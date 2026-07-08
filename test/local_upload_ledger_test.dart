import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lead_pilot_telecaller/src/models/call_recording.dart';
import 'package:lead_pilot_telecaller/src/services/local_upload_ledger.dart';

// The upload ledger prevents the auto-capture flow from re-uploading the same
// dialer recording after a restart / folder re-scan: a recording that was
// already uploaded resolves straight back to its existing call_id.
void main() {
  CallRecording rec(String path, {int size = 100, int mtimeMs = 1000}) =>
      CallRecording(
        path: path,
        fileName: path.split('/').last,
        sizeBytes: size,
        recordedAt: DateTime.fromMillisecondsSinceEpoch(mtimeMs),
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('unknown recording has no call_id yet', () async {
    final ledger = LocalUploadLedger();
    expect(await ledger.callIdFor(rec('/a/call1.m4a')), isNull);
  });

  test('remembered recording resolves back to its call_id', () async {
    final ledger = LocalUploadLedger();
    final r = rec('/a/call1.m4a');
    await ledger.remember(r, 'call_9876543210_abcd1234');
    expect(await ledger.callIdFor(r), 'call_9876543210_abcd1234');
  });

  test('a different file (same name, different mtime) is treated as new', () async {
    final ledger = LocalUploadLedger();
    await ledger.remember(rec('/a/call1.m4a', mtimeMs: 1000), 'call_old');
    // Same path+size but a newer mtime → a genuinely different recording.
    expect(await ledger.callIdFor(rec('/a/call1.m4a', mtimeMs: 2000)), isNull);
  });

  test('re-remembering the same file does not duplicate and updates call_id', () async {
    final ledger = LocalUploadLedger();
    final r = rec('/a/call1.m4a');
    await ledger.remember(r, 'call_first');
    await ledger.remember(r, 'call_second');
    expect(await ledger.callIdFor(r), 'call_second');

    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList('uploaded_recordings_v1') ?? const [];
    expect(entries.where((e) => e.startsWith(LocalUploadLedger.keyFor(r))).length, 1);
  });
}
