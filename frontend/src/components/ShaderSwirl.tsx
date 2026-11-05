import { useEffect, useRef } from "react";

import { cn } from "@/lib/cn";

const VERTEX_SHADER = `
attribute vec2 position;
void main() {
  gl_Position = vec4(position, 0.0, 1.0);
}`;

// Folds the plane over itself a few times, which turns two plain sine waves into slow swirls.
// The color is only ever a mix of the three tokens, so text contrast holds for every pixel.
const FRAGMENT_SHADER = `
precision mediump float;
uniform vec2 resolution;
uniform float time;
uniform vec3 colors[3];
void main() {
  vec2 p = gl_FragCoord.xy / resolution.y * 0.9;
  for (int i = 1; i < 5; i++) {
    float s = float(i);
    p += 0.55 / s * vec2(
      sin(s * 1.5 * p.y + time * 0.21 + s),
      cos(s * 1.5 * p.x - time * 0.17 + s * 1.7)
    );
  }
  float swirl = 0.5 + 0.5 * sin(p.x * 2.2 + p.y * 1.3);
  float highlight = 0.5 + 0.5 * sin(p.y * 2.6 - p.x * 1.1 + time * 0.13);
  vec3 color = mix(colors[0], colors[1], smoothstep(0.0, 1.0, swirl));
  color = mix(color, colors[2], smoothstep(0.15, 1.0, highlight));
  gl_FragColor = vec4(color, 1.0);
}`;

// Sharp enough for soft shapes, and much cheaper than drawing every pixel of a 2x or 3x screen.
const MAX_PIXEL_RATIO = 1.5;
const REDUCED_MOTION = "(prefers-reduced-motion: reduce)";
const DARK_SCHEME = "(prefers-color-scheme: dark)";

function compile(gl: WebGLRenderingContext, type: number, source: string): WebGLShader | null {
  const shader = gl.createShader(type);
  if (!shader) return null;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  return shader;
}

function createProgram(gl: WebGLRenderingContext): WebGLProgram | null {
  const vertex = compile(gl, gl.VERTEX_SHADER, VERTEX_SHADER);
  const fragment = compile(gl, gl.FRAGMENT_SHADER, FRAGMENT_SHADER);
  const program = gl.createProgram();
  if (!vertex || !fragment) return null;
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  return gl.getProgramParameter(program, gl.LINK_STATUS) === true ? program : null;
}

// Tokens hold light-dark() values, which only the browser can resolve for the current theme.
function readColors(canvas: HTMLCanvasElement, tokens: string[]): number[] {
  const channels = tokens.flatMap((token) => {
    canvas.style.color = `var(${token})`;
    const [r = 0, g = 0, b = 0] = getComputedStyle(canvas).color.match(/[\d.]+/g) ?? [];
    return [Number(r) / 255, Number(g) / 255, Number(b) / 255];
  });
  canvas.style.color = "";
  return channels;
}

// A slowly moving swirl of three color tokens. It fills its positioned parent, which should
// have a solid background: that's what shows without WebGL, or if the context is ever lost.
// With reduced motion it's one still frame. It stops drawing while it's off screen.
export function ShaderSwirl({ tokens, className }: { tokens: string[]; className?: string }) {
  const ref = useRef<HTMLCanvasElement>(null);
  const tokenList = tokens.join(" ");

  useEffect(() => {
    const canvas = ref.current;
    const gl = canvas?.getContext("webgl", { antialias: false, powerPreference: "low-power" });
    if (!canvas || !gl) return;
    const program = createProgram(gl);
    if (!program) return;
    gl.useProgram(program);

    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const position = gl.getAttribLocation(program, "position");
    gl.enableVertexAttribArray(position);
    gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);

    const resolution = gl.getUniformLocation(program, "resolution");
    const time = gl.getUniformLocation(program, "time");
    const colors = gl.getUniformLocation(program, "colors");
    const motion = matchMedia(REDUCED_MOTION);
    const scheme = matchMedia(DARK_SCHEME);
    let frame = 0;
    let visible = true;

    const draw = (now: number) => {
      gl.uniform1f(time, motion.matches ? 0 : now / 1000);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    };
    const tick = (now: number) => {
      draw(now);
      frame = requestAnimationFrame(tick);
    };
    const restart = () => {
      cancelAnimationFrame(frame);
      if (!visible) return;
      if (motion.matches) draw(0);
      else frame = requestAnimationFrame(tick);
    };
    const resize = () => {
      const ratio = Math.min(devicePixelRatio, MAX_PIXEL_RATIO);
      canvas.width = Math.round(canvas.clientWidth * ratio);
      canvas.height = Math.round(canvas.clientHeight * ratio);
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.uniform2f(resolution, canvas.width, canvas.height);
      restart();
    };
    const applyTheme = () => {
      gl.uniform3fv(colors, readColors(canvas, tokenList.split(" ")));
      restart();
    };

    const sized = new ResizeObserver(resize);
    sized.observe(canvas);
    const seen = new IntersectionObserver(([entry]) => {
      visible = entry?.isIntersecting ?? true;
      restart();
    });
    seen.observe(canvas);
    const theme = new MutationObserver(applyTheme);
    theme.observe(document.documentElement, { attributeFilter: ["data-theme"] });
    motion.addEventListener("change", restart);
    scheme.addEventListener("change", applyTheme);
    applyTheme();

    return () => {
      cancelAnimationFrame(frame);
      sized.disconnect();
      seen.disconnect();
      theme.disconnect();
      motion.removeEventListener("change", restart);
      scheme.removeEventListener("change", applyTheme);
      gl.deleteBuffer(buffer);
      gl.deleteProgram(program);
    };
  }, [tokenList]);

  return <canvas ref={ref} aria-hidden className={cn("absolute inset-0 size-full", className)} />;
}
