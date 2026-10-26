/// The lock screen over the whole app while [AppLockState.locked] (core/auth/app_lock.dart).
///
/// A layer above the router rather than a route, so the screen underneath keeps its state and
/// unlocking puts the person back exactly where they were.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_lock.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../shared/wordmark.dart';
import '../common/form_parts.dart';

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => ref.read(appLockProvider.notifier).onHidden(),
      onShow: () => ref.read(appLockProvider.notifier).onShown(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ask as soon as the lock appears, once per lock.
    ref.listen(appLockProvider.select((s) => s.locked), (was, locked) {
      if (locked && was != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(appLockProvider.notifier).unlock();
        });
      }
    });
    final locked = ref.watch(appLockProvider.select((s) => s.locked));
    return Stack(
      children: [
        // Hidden from touch and screen readers while locked, but kept alive.
        ExcludeSemantics(
          excluding: locked,
          child: AbsorbPointer(absorbing: locked, child: widget.child),
        ),
        if (locked) const Positioned.fill(child: AppLockScreen()),
      ],
    );
  }
}

class AppLockScreen extends ConsumerWidget {
  const AppLockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final lock = ref.watch(appLockProvider);
    return Material(
      color: t.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/brand/apnivaas_logo.webp',
                    height: 72,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) =>
                        Icon(Icons.lock_rounded, size: 56, color: t.colorScheme.primary),
                  ),
                  const SizedBox(height: Space.sm),
                  Center(
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: ApnivaasTypeMark(color: t.colorScheme.primary, fontSize: 24),
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                  Semantics(
                    header: true,
                    child: Text('Apnivaas is locked',
                        textAlign: TextAlign.center, style: t.textTheme.headlineSmall),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Use your fingerprint, face or phone PIN to open it.',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  if (lock.message != null) ...[
                    const SizedBox(height: Space.md),
                    FormNote(lock.message!, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: Space.lg),
                  BusyFilledButton(
                    label: 'Unlock',
                    icon: Icons.fingerprint_rounded,
                    busy: lock.prompting,
                    onPressed: () => ref.read(appLockProvider.notifier).unlock(),
                  ),
                  const SizedBox(height: Space.xs),
                  TextButton(
                    onPressed: lock.prompting
                        ? null
                        : () => ref.read(authControllerProvider.notifier).signOut(),
                    child: const Text('Sign out instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
