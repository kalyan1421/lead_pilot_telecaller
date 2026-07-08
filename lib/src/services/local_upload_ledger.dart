import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/call_recording.dart';

/// Remembers which recording files have already been uploaded, so the
/// auto-capture flow never re-uploads the same dialer file after an app
/// restart or a re-scan of the same folder.
///
/// The backend also dedupes by content hash (unbounded window), so this is a
/// client-side optimisation — it avoids the redundant upload + re-processing
/// round-trip entirely, and lets the app resolve straight back to the existing
/// `call_id`. Keyed by `path|size|mtimeMs`, which uniquely identifies a saved
/// recording file without having to read and hash its bytes on device.
class LocalUploadLedger {
  static const _key = 'uploaded_recordings_v1';

  static String keyFor(CallRecording r) =>
      '${r.path}|${r.sizeBytes}|${r.recordedAt.millisecondsSinceEpoch}';

  /// Returns the previously-assigned call_id for this recording, or null if it
  /// has never been uploaded.
  Future<String?> callIdFor(CallRecording recording) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(_key) ?? const [];
    final needle = keyFor(recording);
    for (final e in entries) {
      final sep = e.lastIndexOf('=>');
      if (sep != -1 && e.substring(0, sep) == needle) {
        return e.substring(sep + 2);
      }
    }
    return null;
  }

  /// Records that [recording] was uploaded and produced [callId].
  Future<void> remember(CallRecording recording, String callId) async {
    final prefs = await SharedPreferences.getInstance();
    final needle = keyFor(recording);
    final entries = (prefs.getStringList(_key) ?? const <String>[])
        // Drop any stale mapping for the same file, then re-add.
        .where((e) {
          final sep = e.lastIndexOf('=>');
          return sep == -1 || e.substring(0, sep) != needle;
        })
        .toList()
      ..add('$needle=>$callId');
    // Cap the ledger so it can't grow without bound on a heavy-use device.
    final capped = entries.length > 500
        ? entries.sublist(entries.length - 500)
        : entries;
    await prefs.setStringList(_key, capped);
  }
}

final localUploadLedgerProvider = Provider<LocalUploadLedger>(
  (_) => LocalUploadLedger(),
);
