import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'motion.dart';

// Glass and the page behind it, as in frontend/src/styles/index.css. Glass only goes on what
// floats over content: the top bar, menus and sheets, and the review card.

/// CSS saturate(140%).
const _saturate = ColorFilter.matrix(<double>[
  1.3148, -0.2860, -0.0288, 0, 0, //
  -0.0852, 1.1140, -0.0288, 0, 0, //
  -0.0852, -0.2860, 1.3712, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// Whether glass should be a solid surface instead: the system asks for more contrast, which
/// is where the web app also drops transparency.
bool solidGlass(BuildContext context) => MediaQuery.highContrastOf(context);

/// A frosted panel: strong blur, one edge with a faint highlight along the top, no shadow.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.thin = false,
    this.borderRadius = BorderRadius.zero,
    this.edges = const {
      AxisDirection.up,
      AxisDirection.down,
      AxisDirection.left,
      AxisDirection.right,
    },
  });

  final Widget child;

  /// The review card's lighter fill, for glass that only ever has the page behind it.
  final bool thin;
  final BorderRadius borderRadius;

  /// Which sides draw the edge. The top bar only has its bottom one.
  final Set<AxisDirection> edges;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final solid = solidGlass(context);
    final edge = BorderSide(color: solid ? c.lineStrong : c.glassEdge);
    final border = Border(
      top: edges.contains(AxisDirection.up) ? edge : BorderSide.none,
      bottom: edges.contains(AxisDirection.down) ? edge : BorderSide.none,
      left: edges.contains(AxisDirection.left) ? edge : BorderSide.none,
      right: edges.contains(AxisDirection.right) ? edge : BorderSide.none,
    );
    final panel = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: border.isUniform ? borderRadius : null,
        border: border,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: solid ? c.surface : (thin ? c.glassFillThin : c.glassFill),
          borderRadius: borderRadius,
        ),
        // The highlight along the top edge (an inset shadow on the web).
        child: Stack(
          children: [
            child,
            if (!solid)
              Positioned(
                top: edges.contains(AxisDirection.up) ? 1 : 0,
                left: borderRadius.topLeft.x,
                right: borderRadius.topRight.x,
                height: 1,
                child: IgnorePointer(child: ColoredBox(color: c.glassHighlight)),
              ),
          ],
        ),
      ),
    );
    if (solid) return ClipRRect(borderRadius: borderRadius, child: panel);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.compose(
          outer: _saturate,
          inner: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur, tileMode: TileMode.mirror),
        ),
        child: panel,
      ),
    );
  }
}

enum Scene {
  /// Pine light from the top left, warm sand from the bottom right.
  page,

  /// While studying, the pine light sits behind the review card so its glass has something to
  /// frost.
  study,
}

/// The page: a low-contrast vertical gradient with two soft glows.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, this.scene = Scene.page, this.child});

  final Scene scene;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BackdropPainter(context.colors, scene),
    child: child ?? const SizedBox.expand(),
  );
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.colors, this.scene);

  final EngramColors colors;
  final Scene scene;

  // radial-gradient(<rx> <ry> at <x> <y>, glow, transparent 70%), in fractions of the page.
  void _glow(Canvas canvas, Size size, Color color, Offset center, double rx, double ry) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
        stops: const [0, 0.7],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1));
    canvas
      ..save()
      ..translate(center.dx * size.width, center.dy * size.height)
      ..scale(rx * size.width, ry * size.height)
      ..drawCircle(Offset.zero, 1, paint)
      ..restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.paperTop, colors.paperBottom],
        ).createShader(rect),
    );
    switch (scene) {
      case Scene.page:
        _glow(canvas, size, colors.glowPine, Offset.zero, 0.7, 0.55);
      case Scene.study:
        _glow(canvas, size, colors.glowPine, const Offset(0.5, 0.3), 0.6, 0.45);
    }
    _glow(canvas, size, colors.glowWarm, const Offset(1, 1), 0.6, 0.5);
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.colors != colors || old.scene != scene;
}

/// A screen: the backdrop, a glass top bar that content scrolls under, and the body.
class GlassScaffold extends StatelessWidget {
  const GlassScaffold({
    super.key,
    required this.body,
    this.title,
    this.leading,
    this.actions,
    this.scene = Scene.page,
    this.automaticallyImplyLeading = true,
  });

  final Widget body;
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final Scene scene;
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    return Backdrop(
      scene: scene,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Glass(
            edges: const {AxisDirection.down},
            child: AppBar(
              title: title,
              leading: leading,
              actions: actions,
              automaticallyImplyLeading: automaticallyImplyLeading,
              shape: const Border(),
              titleSpacing: leading == null && !automaticallyImplyLeading ? 16 : null,
            ),
          ),
        ),
        body: body,
      ),
    );
  }
}

/// Padding that keeps content clear of the glass bars it scrolls under: the top bar, and the
/// bottom navigation bar on the home shell's tabs. Inside a [GlassScaffold] the padding from
/// [MediaQuery] already includes both.
EdgeInsets underBars(BuildContext context, EdgeInsets padding) {
  final insets = MediaQuery.paddingOf(context);
  return padding + EdgeInsets.only(top: insets.top, bottom: insets.bottom);
}

/// A glass menu anchored under [anchor], growing from its top-right corner, like the web's
/// dropdown menus.
Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required BuildContext anchor,
  required WidgetBuilder builder,
  double width = 240,
}) {
  final box = anchor.findRenderObject()! as RenderBox;
  final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
  return Navigator.of(context).push(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: Motion.of(context, Motion.fast),
      reverseTransitionDuration: Motion.of(context, Motion.fast),
      pageBuilder: (context, animation, secondary) => Stack(
        children: [
          Positioned(
            top: bottomRight.dy + 4,
            right: overlay.size.width - bottomRight.dx,
            width: width,
            child: Glass(
              borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
              child: Material(
                type: MaterialType.transparency,
                child: Padding(padding: const EdgeInsets.all(4), child: builder(context)),
              ),
            ),
          ),
        ],
      ),
      transitionsBuilder: (context, animation, secondary, child) =>
          dialogTransition(animation, child, origin: Alignment.topRight, fromScale: 0.96, rise: 0),
    ),
  );
}

/// A glass sheet from the bottom, over a blurred scrim, for short forms and confirmations.
Future<T?> showGlassSheet<T>({required BuildContext context, required WidgetBuilder builder}) {
  final c = context.colors;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: c.scrim,
    transitionDuration: Motion.of(context, Motion.slow),
    pageBuilder: (context, animation, secondary) => SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: 12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Glass(
              borderRadius: const BorderRadius.all(Radius.circular(Radii.lg)),
              child: Material(
                type: MaterialType.transparency,
                child: Padding(padding: const EdgeInsets.all(24), child: builder(context)),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondary, child) => Stack(
      children: [
        // The web's scrim blurs what's behind it a little (--scrim-blur).
        if (!solidGlass(context))
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) => BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 6 * animation.value,
                    sigmaY: 6 * animation.value,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        dialogTransition(animation, child),
      ],
    ),
  );
}
