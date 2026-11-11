import 'package:flutter/material.dart';

import '../theme.dart';

// The web app's motion (frontend/src/styles/index.css): things arrive by fading and rising a
// few pixels, and leave faster than they came. Nothing bounces, loops or moves on its own, and
// with reduced motion nothing moves at all.

/// Rises in once when first built: a page, a new review card, a revealed answer. Give it a new
/// key to play it again.
class RiseIn extends StatefulWidget {
  const RiseIn({super.key, required this.child, this.duration = Motion.base, this.offset = 6});

  final Widget child;
  final Duration duration;
  final double offset;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: widget.duration);
  late final _curve = CurvedAnimation(parent: _controller, curve: Motion.ease);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isDismissed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _Rise(animation: _curve, offset: widget.offset, child: widget.child);
}

class _Rise extends AnimatedWidget {
  const _Rise({required Animation<double> animation, required this.offset, required this.child})
    : super(listenable: animation);

  final double offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Opacity(
      opacity: t.clamp(0, 1),
      child: Transform.translate(offset: Offset(0, offset * (1 - t)), child: child),
    );
  }
}

/// Page transitions to match the web: the new page rises in over 200 ms; going back, the page
/// fades and sinks away in 120 ms.
class RiseInPageTransitionsBuilder extends PageTransitionsBuilder {
  const RiseInPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Motion.base;

  @override
  Duration get reverseTransitionDuration => Motion.fast;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return _Rise(
      animation: CurvedAnimation(
        parent: animation,
        curve: Motion.ease,
        reverseCurve: Motion.ease.flipped,
      ),
      offset: 6,
      child: child,
    );
  }
}

/// Dialog and sheet motion: in over 280 ms from 8 px lower at 98 %, out in 120 ms.
Widget dialogTransition(
  Animation<double> animation,
  Widget child, {
  Alignment origin = Alignment.center,
  double fromScale = 0.98,
  double rise = 8,
}) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Motion.ease,
    reverseCurve: Motion.ease.flipped,
  );
  return AnimatedBuilder(
    animation: curved,
    child: child,
    builder: (context, child) {
      final t = curved.value;
      return Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, rise * (1 - t)),
          child: Transform.scale(
            scale: fromScale + (1 - fromScale) * t,
            alignment: origin,
            child: child,
          ),
        ),
      );
    },
  );
}

/// Rises in again whenever [value] changes, keeping [child]'s state: the home shell's tabs, which
/// must not be rebuilt when switching, but should arrive like a page.
class RiseOnChange extends StatefulWidget {
  const RiseOnChange({super.key, required this.value, required this.child});

  final Object value;
  final Widget child;

  @override
  State<RiseOnChange> createState() => _RiseOnChangeState();
}

class _RiseOnChangeState extends State<RiseOnChange> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: Motion.base, value: 1);
  late final _curve = CurvedAnimation(parent: _controller, curve: Motion.ease);

  @override
  void didUpdateWidget(RiseOnChange old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Rise(animation: _curve, offset: 6, child: widget.child);
}
