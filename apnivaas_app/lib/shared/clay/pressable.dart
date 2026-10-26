library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The press every clay surface shares: a small scale-down while a finger is on it.
///
/// It listens to raw pointer events rather than joining the gesture arena, so it never competes
/// with the [InkWell] or button underneath it for the tap — the tap belongs to them, this only
/// draws the press. Under reduce motion it draws nothing at all.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
  });

  final Widget child;

  /// False for a control that cannot be pressed (no handler), so it does not pretend to be.
  final bool enabled;

  /// 0.97 for a card or button, 0.94 for an icon well.
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down == down || !mounted) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || MediaQuery.disableAnimationsOf(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: _down ? Motion.press : Motion.fast,
        curve: Motion.enter,
        child: widget.child,
      ),
    );
  }
}
