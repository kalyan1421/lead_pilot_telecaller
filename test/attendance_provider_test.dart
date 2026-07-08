import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lead_pilot_telecaller/src/state/providers.dart';

// Regression test for: AttendanceController.build() used to call _load()
// un-deferred, and _load()'s first statement read `state` before any `await`
// — which ran synchronously inside build(), before Riverpod finished
// initializing the provider, throwing "Bad state: Tried to read the state of
// an uninitialized provider." Fixed via Future.microtask(_load) in build().
//
// Deliberately avoids pumpAndSettle(): this widget's dependency graph pulls in
// session/secure-storage plugin channels that never resolve under plain
// `flutter test` (no platform), so pumpAndSettle hangs for unrelated reasons.
// A couple of bounded pumps is enough to prove build() itself doesn't crash.
void main() {
  testWidgets('attendanceProvider initializes without throwing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: _AttendanceWatcher(),
        ),
      ),
    );

    // First frame: build() runs, state starts at loading:true. This is where
    // the original bug threw synchronously.
    expect(tester.takeException(), isNull);

    // Give the deferred _load() microtask + its (mocked-400-in-tests) network
    // attempt a couple of turns to run; still no exception expected.
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });
}

class _AttendanceWatcher extends ConsumerWidget {
  const _AttendanceWatcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(attendanceProvider);
    return Text(state.loading ? 'loading' : 'loaded');
  }
}
