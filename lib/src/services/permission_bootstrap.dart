import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests the runtime permissions the app needs up front, so the call
/// overlay, auto-return, and reminders work the first time a user makes a call.
///
/// Only the standard runtime permissions are requested here (phone state +
/// notifications). The "special access" permissions — draw-over-other-apps
/// (`SYSTEM_ALERT_WINDOW`) and all-files access — are settings-page grants that
/// would be too disruptive to force at launch, so they're requested in context
/// (when a call starts / when a recording is read).
class PermissionBootstrap {
  const PermissionBootstrap._();

  /// Safe to call multiple times; already-granted permissions are no-ops.
  /// Never throws — permission failures must not block app startup.
  static Future<void> requestStartup() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await [
        // READ_PHONE_STATE — lets the overlay detect when the call ends and
        // bring the app back to the foreground automatically.
        Permission.phone,
        // POST_NOTIFICATIONS — follow-up reminders + the foreground-service
        // notification on Android 13+.
        Permission.notification,
      ].request();
    } catch (_) {
      // Ignore — the app stays usable; features degrade gracefully.
    }
  }
}
