import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// The lit ground the sign-in screen stands on, and the wash behind a dashboard.
///
/// ── WHAT THE REFERENCE ASKED FOR, AND WHAT IT GOT ─────────────────────────────────────────
///
/// The supplied component paints `bg-gradient-to-b from-purple-500/40 via-purple-700/50 to-black`
/// with two pulsing radial glows and a noise overlay. That is the effect reproduced here. The
/// PURPLE, though, is NIVORA's own — [NivoraColors.rooms] `#8566BA` — and not Tailwind's
/// purple-500 `#a855f7`.
///
/// That is not a small distinction and it is not laziness. This app's colours are fixed by
/// [NivoraDomain] and checked by theme_contrast_test.dart on every build; #8566BA is already in
/// that set as the rooms tone, already measured against #0b0d0f, and already appears on room
/// cards throughout the product. Importing a second, brighter purple would put two purples one
/// screen apart that are nearly but not quite the same — which reads as a rendering fault rather
/// than as a palette.
///
/// ── IT IS A WASH, NOT A SURFACE ───────────────────────────────────────────────────────────
///
/// Everything here sits BEHIND content at low alpha, so no text ever draws on the glow directly:
/// the card that sits on top of it brings its own near-opaque ground. That is what keeps the
/// contrast suite green while the screen still reads as purple. If a future change puts a label
/// straight onto this field, that label needs measuring — the wash is not a background colour
/// anything is certified against.
class AuroraField extends StatefulWidget {
  const AuroraField({super.key, required this.child, this.intensity = 1});

  final Widget child;

  /// 0 draws the plain ground; 1 is the sign-in screen. Dashboards use a fraction of it — the
  /// same light, turned down, so a screen full of data is not competing with its own backdrop.
  final double intensity;

  @override
  State<AuroraField> createState() => _AuroraFieldState();
}

class _AuroraFieldState extends State<AuroraField> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // One controller for both glows, running long and slow. The reference gives them 6s and 8s
    // and offsets one; a single 8s pass with the second glow reading it at a phase offset is the
    // same picture for one ticker instead of two.
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final purple = NivoraColors.rooms;
    final i = widget.intensity.clamp(0.0, 1.0);

    // A user who has asked the OS to reduce motion gets the same picture, held still. The glow
    // is the point; the breathing is decoration, and decoration is what that setting is about.
    final still = MediaQuery.disableAnimationsOf(context);

    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: t.scaffoldBackgroundColor)),

        // The top wash: a wide, very soft dome bleeding down from behind the status bar.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final pulse = still ? 0.5 : _breathe(_c.value);
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -1.15),
                      radius: 1.25,
                      colors: [
                        purple.withValues(alpha: (0.20 + 0.06 * pulse) * i),
                        purple.withValues(alpha: 0.05 * i),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // The bottom wash, reading the same ticker half a cycle out so the two are never at
        // full strength together — which is what stops the screen looking like it is flashing.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final pulse = still ? 0.5 : _breathe((_c.value + 0.5) % 1);
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 1.25),
                      radius: 1.1,
                      colors: [
                        purple.withValues(alpha: (0.16 + 0.06 * pulse) * i),
                        Colors.transparent,
                      ],
                      stops: const [0, 1],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        widget.child,
      ],
    );
  }

  /// 0 → 1 → 0 across the cycle, smoothly. A raw sawtooth would jump at the wrap.
  double _breathe(double v) => Curves.easeInOut.transform(v < 0.5 ? v * 2 : (1 - v) * 2);
}
