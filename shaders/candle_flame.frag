#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform vec2 uWick;
uniform float uLean;
uniform float uPressure;
uniform float uWarmth;
uniform float uSharedGlow;
uniform float uLit;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
             f.y);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 p = frag - uWick;
  float rise = -p.y;
  float height = mix(57.0, 32.0, clamp(uPressure, 0.0, 1.0));
  float vertical = smoothstep(0.0, 5.0, rise) *
      (1.0 - smoothstep(height - 8.0, height + 4.0, rise));

  float gust = uLean * (0.25 + uPressure * 0.18) * rise;
  float living = (noise(vec2(rise * 0.075, uTime * 1.8)) - 0.5) *
      (2.4 + uPressure * 6.0) * (rise / max(height, 1.0));
  float centerX = gust + living;
  float taper = pow(clamp(1.0 - rise / max(height, 1.0), 0.0, 1.0), 0.58);
  float halfWidth = mix(3.0, 16.5 + uPressure * 4.0, taper);
  float edge = abs(p.x - centerX) / max(halfWidth, 0.1);
  float body = (1.0 - smoothstep(0.72, 1.04, edge)) * vertical * uLit;

  float core = (1.0 - smoothstep(0.08, 0.52, edge)) *
      smoothstep(2.0, 10.0, rise) *
      (1.0 - smoothstep(height * 0.52, height * 0.76, rise));
  vec3 outer = mix(vec3(1.0, 0.28, 0.055), vec3(0.72, 0.25, 1.0),
      (1.0 - uWarmth) * 0.55);
  vec3 middle = mix(outer, vec3(1.0, 0.72, 0.18), 0.64);
  vec3 flame = mix(outer, middle, clamp(1.0 - edge, 0.0, 1.0));
  flame = mix(flame, vec3(1.0, 0.98, 0.72), core);

  vec2 glowDelta = frag - (uWick + vec2(centerX * 0.35, -height * 0.42));
  float glowRadius = 74.0 + uSharedGlow * 24.0;
  float glow = exp(-dot(glowDelta, glowDelta) / (glowRadius * glowRadius)) *
      (0.20 + uSharedGlow * 0.12) * uLit;
  vec3 glowColor = mix(vec3(1.0, 0.38, 0.08), vec3(0.72, 0.32, 1.0),
      (1.0 - uWarmth) * 0.5);
  float alpha = clamp(body + glow * 0.52, 0.0, 1.0);
  vec3 color = flame * body + glowColor * glow;
  fragColor = vec4(color, alpha);
}
