import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Held only while the persisted session is restored — typically a frame or two on a warm
/// start. Deliberately not an animation: the brief asked for a fast launch and a brand
/// impression, and the honest way to get both is to make this seam disappear rather than
/// perform. The native window background (see Android styles.xml) is the same colour, so
/// there is no flash between the two.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('NIVORA',
                style: t.textTheme.titleLarge?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w600)),
            const SizedBox(height: Space.md),
            SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}
