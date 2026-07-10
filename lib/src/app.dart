import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_router.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';
import 'widgets/leadpilot_widgets.dart';

class LeadPilotApp extends ConsumerWidget {
  const LeadPilotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'LeadPilot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      // App-wide "can't reach server" banner, layered above whatever screen
      // is currently routed to — every screen gets it for free, none of them
      // need to check connectivity themselves.
      builder: (context, child) => _ConnectivityBanner(child: child),
    );
  }
}

class _ConnectivityBanner extends ConsumerWidget {
  const _ConnectivityBanner({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reachable = ref.watch(serverReachableProvider);
    if (child == null) return const SizedBox.shrink();
    if (reachable) return child!;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          LpFallbackBanner(
            message: "Can't reach the server — retrying…",
            onRetry: () => ref.read(serverReachableProvider.notifier).retryNow(),
          ),
          Expanded(child: child!),
        ],
      ),
    );
  }
}
