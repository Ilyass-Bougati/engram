#version 460 core

// The study suggestion's background: frontend/src/components/ShaderSwirl.tsx's fragment shader,
// in Flutter's dialect. It folds the plane over itself a few times, which turns two plain sine
// waves into slow swirls. The color is only ever a mix of the three uniforms, so text contrast
// holds for every pixel.

#include <flutter/runtime_effect.glsl>

uniform vec2 resolution;
uniform float time;
uniform vec3 color1;
uniform vec3 color2;
uniform vec3 color3;

out vec4 fragColor;

void main() {
  // WebGL's gl_FragCoord starts at the bottom left, Flutter's at the top left: flip y so the
  // swirl moves the same way as on the web.
  vec2 frag = FlutterFragCoord().xy;
  vec2 p = vec2(frag.x, resolution.y - frag.y) / resolution.y * 0.9;
  for (int i = 1; i < 5; i++) {
    float s = float(i);
    p += 0.55 / s * vec2(
      sin(s * 1.5 * p.y + time * 0.21 + s),
      cos(s * 1.5 * p.x - time * 0.17 + s * 1.7)
    );
  }
  float swirl = 0.5 + 0.5 * sin(p.x * 2.2 + p.y * 1.3);
  float highlight = 0.5 + 0.5 * sin(p.y * 2.6 - p.x * 1.1 + time * 0.13);
  vec3 color = mix(color1, color2, smoothstep(0.0, 1.0, swirl));
  color = mix(color, color3, smoothstep(0.15, 1.0, highlight));
  fragColor = vec4(color, 1.0);
}
