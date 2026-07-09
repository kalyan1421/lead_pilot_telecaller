# LeadPilot — Run Backend + Flutter App

How to start the **FastAPI backend** (`telecaller-main`) and the **Flutter app**
(`lead_pilot_flutter`) together on macOS.

```
Client-project/Lead Pilot/
  telecaller-main/       ← FastAPI backend (Python, port 8000)
  lead_pilot_flutter/    ← Flutter app (this folder)
```

Start the backend first. If it's unreachable the app falls back to mock data
automatically — the UI stays up but you won't see live leads or call scores.

---

## Prerequisites (one-time)

| Tool | Check | Install |
|---|---|---|
| Flutter 3.x | `flutter --version` | https://docs.flutter.dev/get-started |
| Python 3.11+ | `python3 --version` | `brew install python@3.11` |
| PostgreSQL 14 | `psql --version` | `brew install postgresql@14` |
| ffmpeg | `ffmpeg -version` | `brew install ffmpeg` |
| Sarvam API key | — | https://dashboard.sarvam.ai |

---

## 1. Backend — `telecaller-main/` (port 8000)

### 1a. Start PostgreSQL and create the database (once)

```bash
brew services start postgresql@14
createdb voicesummary 2>/dev/null || echo "already exists"
```

### 1b. Python environment (once)

```bash
cd "../telecaller-main"
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install matplotlib        # needed at startup (transitive dep, missing from requirements.txt)
pip install openai-whisper    # only needed for upload → transcribe flow
```

> `matplotlib` is imported at startup via `audio_processor → improved_voice_analyzer`.
> Without it uvicorn exits immediately with `ModuleNotFoundError`.
>
> `openai-whisper` is only needed for recording upload/transcription. Inbox, lead
> detail, memory, and telecaller score all work without it.

### 1c. `.env` file (once)

```bash
cd "../telecaller-main"
cp env.example .env
```

Edit `.env` — minimum required values:

```env
DATABASE_URL=postgresql://kalyan@localhost:5432/voicesummary
SARVAM_API_KEYS=your_key_here
SARVAM_CHAT_MODEL=sarvam-105b
SARVAM_STT_MODEL=saaras:v3
SARVAM_STT_MODE=transcribe
STORAGE_MODE=local
LOCAL_STORAGE_PATH=./local_storage
AUDIO_SOURCE_PATH=./Audio
APP_HOST=0.0.0.0
APP_PORT=8000
DEBUG=true
```

### 1d. Start the backend

```bash
cd "../telecaller-main"
source .venv/bin/activate
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

`--host 0.0.0.0` is required so a physical phone on your Wi-Fi can reach it.
Tables are created automatically on first startup.

API docs: http://localhost:8000/docs

### 1e. Smoke-test

```bash
curl http://localhost:8000/health
curl http://localhost:8000/api/inbox

# Create a demo lead (appears in inbox immediately):
curl -X POST http://localhost:8000/api/leads \
  -H 'Content-Type: application/json' \
  -d '{"name":"Sneha Reddy","phone":"+919876543210","source":"google","reason":"Wants 3BHK"}'

# Load the sample audio + run full AI analysis (needs openai-whisper + SARVAM_API_KEYS):
python import_audio.py
```

---

## 2. Flutter app — `lead_pilot_flutter/`

### 2a. Point the app at your backend

Edit [`lib/src/core/api/api_config.dart`](lib/src/core/api/api_config.dart),
`ApiEnvironment.dev.baseUrl`:

| Target | Value |
|---|---|
| Android emulator | `http://10.0.2.2:8000` |
| Physical phone (same Wi-Fi as Mac) | `http://<mac-LAN-IP>:8000` |
| iOS simulator / macOS desktop | `http://localhost:8000` |

Find your Mac's LAN IP:
```bash
ipconfig getifaddr en0      # e.g. 192.168.31.132
```

Currently set to `http://192.168.31.132:8000`. Change the one line if your
network or IP has changed.

`ApiConfig.useMockData` is `false` (live backend). Set it back to `true` to run
the UI fully offline.

### 2b. Run

```bash
flutter pub get
flutter devices
flutter run                 # or: flutter run -d <deviceId>
```

---

## 3. Quick-start (both together)

**Terminal 1 — backend:**
```bash
cd "/Users/kalyan/Client-project/Lead Pilot/telecaller-main"
source .venv/bin/activate
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

**Terminal 2 — Flutter:**
```bash
cd "/Users/kalyan/Client-project/Lead Pilot/lead_pilot_flutter"
flutter run
```

---

## 4. Backend module layout

`app/api/` is split into four focused modules (all wired in `app/main.py`):

| File | Responsibility | Key routes |
|---|---|---|
| `calls.py` | Raw call CRUD, audio, transcript | `GET/PUT/DELETE /api/calls/*` |
| `upload.py` | Upload pipeline + crash recovery | `POST /api/calls/upload`, `/processing-status` |
| `analysis.py` | Per-call AI + Score tab | `/api/calls/{id}/lead-analysis`, `/score` |
| `intelligence.py` | Inbox, leads, memory, telecaller | `/api/inbox`, `/api/leads/*`, `/api/memory/*` |
| `_shared.py` | Shared DB helpers | (imported, no routes) |

---

## 5. What's live vs. still local

| Feature | Status | Endpoint |
|---|---|---|
| Lead inbox | Live | `GET /api/inbox` |
| Lead detail + memory bubble | Live | `GET /api/leads/{contact_key}` |
| Save outbound lead | Live | `POST /api/leads` |
| Dedup check | Live | `GET /api/leads/dedupe` |
| Recording upload + pipeline | Live | `POST /api/calls/upload` |
| Processing stepper | Live | `GET /api/calls/{id}/processing-status` |
| Transcript (diarized turns) | Live | `GET /api/calls/{id}/transcript` |
| Score tab (4 rings + notes + trends) | Live | `GET /api/calls/{id}/score` |
| Summary + key points + next steps | Live | `GET /api/calls/{id}/lead-analysis` |
| Telecaller rolling score | Live | `GET /api/telecaller/score` |
| Follow-ups list | Local only | No endpoint yet |
| Pre-call checklist | Local only | No endpoint yet |

---

## 6. Troubleshooting

| Symptom | Fix |
|---|---|
| App shows mock data | Backend unreachable — check it's running and `baseUrl` LAN IP is correct. Phone + Mac must be on same Wi-Fi. |
| `ModuleNotFoundError: matplotlib` | `pip install matplotlib` |
| `connection refused :5432` | PostgreSQL not running — `brew services start postgresql@14` |
| `connection refused :8000` from phone | Start backend with `--host 0.0.0.0` not `127.0.0.1` |
| "can't connect to server" / network error to `127.0.0.1:8000` | `adb reverse` tunnel dropped (happens on every ADB/USB reconnect). Run `adb reverse tcp:8000 tcp:8000`, or keep it alive with `./tool/keep-adb-reverse.sh` in a spare terminal. Check `adb reverse --list` first. |
| Android CLEARTEXT error | Use a debug build; release blocks plain HTTP by default |
| Inbox empty | Run `python import_audio.py` or `POST /api/leads` (step 1e) |
| Upload/transcribe fails | `pip install openai-whisper` and ensure `ffmpeg` is on PATH |
| Score tab shows `--` | Analysis not complete — wait ~60 s after upload then re-open the lead |
| Wrong LAN IP | Re-run `ipconfig getifaddr en0` and update `ApiEnvironment.dev.baseUrl` |
