import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lead_pilot_telecaller/src/services/local_upload_outbox.dart';

// The upload outbox is the retry half of the upload story: a recording whose
// upload failed is queued here and retried on the next app resume, so a call
// recorded while offline isn't lost. Keyed by file path (no duplicates), with a
// max-attempts cap so a permanently-bad file can't wedge the queue forever.
void main() {
  OutboxEntry entry(String path) => OutboxEntry(
        leadId: 'lead-1',
        path: path,
        phone: '9876543210',
        contactKey: 'lead-1',
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('empty outbox returns no entries', () async {
    expect(await LocalUploadOutbox().all(), isEmpty);
  });

  test('enqueue persists an entry and re-enqueue does not duplicate', () async {
    final box = LocalUploadOutbox();
    await box.enqueue(entry('/a/call1.m4a'));
    await box.enqueue(entry('/a/call1.m4a')); // same path again
    final all = await box.all();
    expect(all, hasLength(1));
    expect(all.first.phone, '9876543210');
  });

  test('remove drops the entry once uploaded', () async {
    final box = LocalUploadOutbox();
    await box.enqueue(entry('/a/call1.m4a'));
    await box.remove('/a/call1.m4a');
    expect(await box.all(), isEmpty);
  });

  test('markFailure bumps attempts and drops after max attempts', () async {
    final box = LocalUploadOutbox();
    await box.enqueue(entry('/a/call1.m4a'));

    // 5 failures = _maxAttempts; the 5th drops it from the queue.
    bool stillQueued = true;
    for (var i = 0; i < 5; i++) {
      stillQueued = await box.markFailure('/a/call1.m4a', 'network');
    }
    expect(stillQueued, isFalse);
    expect(await box.all(), isEmpty);
  });

  test('markFailure keeps the entry while under the attempt cap', () async {
    final box = LocalUploadOutbox();
    await box.enqueue(entry('/a/call1.m4a'));
    final stillQueued = await box.markFailure('/a/call1.m4a', 'network');
    expect(stillQueued, isTrue);
    final all = await box.all();
    expect(all, hasLength(1));
    expect(all.first.attempts, 1);
    expect(all.first.lastError, 'network');
  });
}
