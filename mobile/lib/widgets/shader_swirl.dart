import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

// A slowly moving swirl of three colors, like the web's ShaderSwirl.tsx. It fills its parent.
// Until the shader is ready, or if it can't load, it's a solid fill of the middle color, which
// is also the web's fallback. With reduced motion it's one still frame. Its ticker pauses with
// the route (TickerMode) and stops when the widget leaves the tree.

ui.FragmentProgram? _program;
Future<ui.FragmentProgram?>? _loading;

/// Loads the shader once. Later swirls get it synchronously, so a card that's rebuilt (say, after
/// studying, when the deck list reloads) never shows the fallback for a frame.
Future<ui.FragmentProgram?> _loadProgram() =>
    _loading ??= ui.FragmentProgram.fromAsset('shaders/suggestion_swirl.frag')
        .then<ui.FragmentProgram?>((program) => _program = program, onError: (Object _) => null);

class ShaderSwirl extends StatefulWidget {
  const ShaderSwirl({super.key, required this.colors})
    : assert(colors.length == 3, 'The swirl mixes exactly three colors.');

  final List<Color> colors;

  @override
  State<ShaderSwirl> createState() => _ShaderSwirlState();
}

class _ShaderSwirlState extends State<ShaderSwirl> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) => _time.value = elapsed.inMicroseconds / 1e6);
  final _time = ValueNotifier<double>(0);
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    final loaded = _program;
    if (loaded != null) {
      _shader = loaded.fragmentShader();
      return;
    }
    _loadProgram().then((program) {
      if (program == null || !mounted) return;
      setState(() => _shader = program.fragmentShader());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: one frame at time 0, as on the web.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _ticker.isActive) {
      _ticker.stop();
      _time.value = 0;
    } else if (!still && !_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _SwirlPainter(shader: _shader, colors: widget.colors, time: _time),
      child: const SizedBox.expand(),
    ),
  );
}

class _SwirlPainter extends CustomPainter {
  _SwirlPainter({required this.shader, required this.colors, required this.time})
    : super(repaint: time);

  final ui.FragmentShader? shader;
  final List<Color> colors;
  final ValueListenable<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = this.shader;
    if (shader == null) {
      canvas.drawRect(rect, Paint()..color = colors[1]);
      return;
    }
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value);
    var index = 3;
    for (final color in colors) {
      shader
        ..setFloat(index++, color.r)
        ..setFloat(index++, color.g)
        ..setFloat(index++, color.b);
    }
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_SwirlPainter old) => old.shader != shader || !listEquals(old.colors, colors);
}
