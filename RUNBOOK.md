# LeadPilot — Run Both (Flutter app + FastAPI backend)

How to run the **Flutter telecaller app** (`lead_pilot_telecaller`) against the
**FastAPI "AI layer" backend** (`voicesummary-main`). Verified on macOS
(Darwin), Flutter 3.41, Postgres 14, Python 3.10.

```
lead_pilot_telecaller/   ← this folder (Flutter app)
voicesummary-main/        ← ../voicesummary-main (FastAPI backend, port 8000)
```

The app talks to the backend over HTTP. **Start the backend first**, then the app.
If the backend is unreachable the app automatically falls back to mock data, so
it never crashes — but you won't see live data until the backend is up.

---

## 0. One-time prerequisites

| Tool | Check | Install (macOS / Homebrew) |
|---|---|---|
| Flutter 3.x | `flutter --version` | https://docs.flutter.dev/get-started |
| Python 3.10+ | `python3 --version` | `brew install python@3.11` |
| PostgreSQL 14 | `psql --version` | `brew install postgresql@14` |
| ffmpeg | `ffmpeg -version` | `brew install ffmpeg` |
| A Groq API key | — | free at https://console.groq.com/keys |

---

## 1. Backend — `../voicesummary-main` (port 8000)

### 1a. Start PostgreSQL and create the database (once)
```bash
# start the server
pg_ctl -D /opt/homebrew/var/postgresql@14 -l /tmp/pg14.log start
# or:  brew services start postgresql@14

# create the database (safe to re-run)
createdb voicesummary 2>/dev/null || echo "already exists"
```

### 1b. Python env + dependencies (once)
```bash
cd "../voicesummary-main"
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install matplotlib            # NEEDED at startup, missing from requirements.txt
pip install openai-whisper        # ONLY for recording upload → transcription
```
> ⚠️ `matplotlib` is imported transitively at startup (`audio_processor` →
> `improved_voice_analyzer`). Without it `uvicorn` fails with
> `ModuleNotFoundError: No module named 'matplotlib'`.
> `openai-whisper` is only needed for the upload/transcribe flow; the inbox,
> lead detail, memory, and telecaller endpoints work without it.

### 1c. `.env` (once)
A `.env` already exists in `voicesummary-main`. It must contain at least:
```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/voicesummary
GROQ_API_KEY=gsk_...your_key...
STORAGE_MODE=local
APP_PORT=8000
```

### 1d. Create the tables (once, idempotent)
```bash
source .venv/bin/activate
python -c "from app.database import engine, Base; import app.models; Base.metadata.create_all(bind=engine); print('tables ready')"
```

### 1e. Run the backend (every time)
```bash
cd "../voicesummary-main"
source .venv/bin/activate
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```
- `--host 0.0.0.0` is required so a **physical phone** on your Wi-Fi can reach it.
- API docs: http://localhost:8000/docs

### 1f. Smoke-test it works
```bash
curl http://localhost:8000/health
curl http://localhost:8000/api/inbox
# create a demo lead so the inbox isn't empty:
curl -X POST http://localhost:8000/api/leads -H 'Content-Type: application/json' \
  -d '{"name":"Sneha Reddy","phone":"+919876543210","source":"google","reason":"Wants 3BHK"}'
curl http://localhost:8000/api/inbox        # now shows 1 lead
```

> **Want real AI-analysed leads (scores, memory bubble)?** Import the sample
> audio once (needs `openai-whisper` + `GROQ_API_KEY`):
> ```bash
> python import_audio.py      # transcribes + analyses the 9 sample calls
> ```

---

## 2. Flutter app — this folder

### 2a. Point the app at your backend
Edit [`lib/src/core/api/api_config.dart`](lib/src/core/api/api_config.dart) →
`ApiEnvironment.dev.baseUrl`:

| Target | baseUrl |
|---|---|
| **Android emulator** | `http://10.0.2.2:8000`  (host loopback) |
| **Physical phone (Xiaomi)** | `http://<your-mac-LAN-IP>:8000` |
| **iOS simulator / desktop / web** | `http://localhost:8000` |

Find your Mac's LAN IP (phone + Mac must be on the **same Wi-Fi**):
```bash
ipconfig getifaddr en0      # e.g. 192.168.31.132  → http://192.168.31.132:8000
```
> Currently set to `http://192.168.31.132:8000`. Update the one line if your
> network/IP changed.
>
> `ApiConfig.useMockData` is already `false` (live backend). Set it back to
> `true` to demo the UI offline with no backend running.

### 2b. Run it
```bash
cd "<this folder>"
flutter pub get
flutter devices            # list connected phones / emulators
flutter run                # pick a device, or: flutter run -d <deviceId>
```

The home/inbox, lead detail (memory + history), and telecaller score now load
from the backend. Live-call recording upload requires `openai-whisper` on the
backend (step 1b).

---

## 3. Run both quickly

Two terminals:

```bash
# Terminal 1 — backend
cd "../voicesummary-main" && source .venv/bin/activate && \
  python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# Terminal 2 — app
cd "<this folder>" && flutter run
```

---

## 4. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| App shows mock leads, not real data | Backend unreachable. Check it's running and the `baseUrl` host/port + Wi-Fi. |
| `ModuleNotFoundError: matplotlib` on `uvicorn` start | `pip install matplotlib` (step 1b). |
| Phone can't connect, emulator can | Use the **LAN IP** (not `localhost`) for a physical device; phone + Mac on same Wi-Fi; backend started with `--host 0.0.0.0`. |
| Android: `CLEARTEXT ... not permitted` | Plain-http to a LAN IP is blocked by default on release builds. Use a debug build, or add a network-security-config / `usesCleartextTraffic` for the dev host. |
| `connection refused :5432` | Postgres not running — `brew services start postgresql@14`. |
| Inbox empty (`leads: []`) | No leads yet. `POST /api/leads` (step 1f) or run `python import_audio.py`. |
| Upload/transcribe fails | `pip install openai-whisper` and ensure `ffmpeg` is on PATH. |
| Verify which env the app uses | `ApiConfig.environment` in `api_config.dart` (dev / staging / prod). |

---

## 5. What's wired vs. still mock

- **Live from backend:** lead inbox (`/api/inbox`), lead detail + memory bubble
  (`/api/leads/{contact_key}`), telecaller score (`/api/telecaller/score`),
  dedup (`/api/leads/dedupe`), recording upload pipeline (`/api/calls/*`).
- **Still mock (no backend endpoint yet):** Follow-ups list, global Call Log.
- **Ready but not yet bound to a button:** `LeadRepository.createLead` /
  `uploadRecording` — wire these into the Add-Outbound "Save" action to make
  that screen fully live.
