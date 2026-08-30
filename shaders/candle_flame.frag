#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform vec2 uWick;
uniform float uLean;
uniform float uPressure;
uniform float uWarmth;
uniform float uSharedGlow;
uniform float uLit;
uniform sampler2D uFlameTexture;

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

  float gust = uLean * (0.25 + uPressure * 0.18) * rise;
  float living = (noise(vec2(rise * 0.075, uTime * 1.8)) - 0.5) *
      (2.4 + uPressure * 6.0) * (rise / max(height, 1.0));
  float centerX = gust + living;

  // A flame grows out of a narrow root, swells above the wick and returns to
  // a single point at its tip. The former separable vertical mask created a
  // visibly flat lower edge, making the flame look pasted onto the candle.
  float along = clamp((rise + 3.5) / (height + 3.5), 0.0, 1.0);
  float envelope = pow(max(along, 0.0001), 0.72) *
      pow(max(1.0 - along, 0.0001), 1.40) * 3.82;
  float asymmetricSwell = mix(0.70, 1.0, smoothstep(0.0, 0.26, along));
  float halfWidth = 0.18 +
      (14.6 + uPressure * 3.6) * envelope * asymmetricSwell;
  float sideNoise = noise(vec2(rise * 0.11 + 7.0, uTime * 1.35)) - 0.5;
  float leftWidth = halfWidth * (0.92 + sideNoise * 0.18);
  float rightWidth = halfWidth * (1.04 - sideNoise * 0.14);
  float lateral = p.x - centerX;
  float edge = lateral < 0.0
      ? -lateral / max(leftWidth, 0.1)
      : lateral / max(rightWidth, 0.1);
  float vertical = smoothstep(-3.5, 1.5, rise) *
      (1.0 - smoothstep(height - 2.5, height + 0.5, rise));
  float shell = (1.0 - smoothstep(0.76, 1.03, edge)) * vertical;

  // The root is an organic bulb around the glowing tip of the wick. It removes
  // the last possible seam even when the outer shell leans in a strong gust.
  vec2 rootPoint = vec2(
      (p.x - centerX * 0.08) / (4.6 + uPressure * 1.2),
      (rise - 1.0) / 5.4);
  float root = 1.0 - smoothstep(0.72, 1.08, length(rootPoint));

  // A photographed flame supplies the fine internal filaments, but it is
  // sampled through the procedural bend field so it remains physically tied
  // to breath, turbulence and the wick instead of being a static overlay.
  float textureWidth = 25.0 + uPressure * 4.0;
  float textureHeight = height + 7.0;
  vec2 flameUv = vec2(
      0.5 + (p.x - centerX * 0.72) / textureWidth,
      1.0 - (rise + 3.0) / textureHeight);
  float inTexture = step(0.0, flameUv.x) * step(flameUv.x, 1.0) *
      step(0.0, flameUv.y) * step(flameUv.y, 1.0);
  vec4 photographed = texture(uFlameTexture, clamp(flameUv, 0.0, 1.0));
  float photographedBody = photographed.a * inTexture;
  float body = max(max(shell * 0.24, photographedBody), root) * uLit;

  // Temperature is continuous across the same shell distance field. There
  // is no separate inner silhouette, so the eye reads one volume rather than
  // a yellow drop pasted inside an orange one.
  float centerHeat = pow(clamp(1.0 - edge, 0.0, 1.0), 1.35) * body;
  float hottest = pow(clamp(1.0 - edge, 0.0, 1.0), 4.2) *
      smoothstep(0.0, 5.0, rise) *
      (1.0 - smoothstep(height * 0.16, height * 0.34, rise)) * body;

  vec2 bluePoint = vec2(
      (p.x - centerX * 0.10) / (6.2 + uPressure * 1.4),
      (rise - 1.5) / 5.0);
  float blueBase =
      (1.0 - smoothstep(0.68, 1.08, length(bluePoint))) * body;

  vec3 outer = mix(vec3(1.0, 0.28, 0.055), vec3(0.72, 0.25, 1.0),
      (1.0 - uWarmth) * 0.55);
  vec3 middle = mix(outer, vec3(1.0, 0.72, 0.18), 0.64);
  vec3 flame = mix(outer, middle, clamp(0.18 + centerHeat * 0.68, 0.0, 1.0));
  flame = mix(flame, vec3(1.0, 0.86, 0.32), hottest * 0.16);
  flame = mix(flame, vec3(0.32, 0.48, 0.94), blueBase * 0.34);
  vec3 photographedColor = photographed.a > 0.001
      ? photographed.rgb / photographed.a
      : vec3(0.0);
  float textureMix = smoothstep(0.015, 0.42, photographedBody) * 0.72;
  flame = mix(flame, photographedColor, textureMix);

  vec2 glowDelta = frag - (uWick + vec2(centerX * 0.35, -height * 0.42));
  float glowRadius = 74.0 + uSharedGlow * 24.0;
  float glow = exp(-dot(glowDelta, glowDelta) / (glowRadius * glowRadius)) *
      (0.20 + uSharedGlow * 0.12) * uLit;
  vec3 glowColor = mix(vec3(1.0, 0.38, 0.08), vec3(0.72, 0.32, 1.0),
      (1.0 - uWarmth) * 0.5);
  float contactGlow = exp(-dot(p / vec2(18.0, 9.0), p / vec2(18.0, 9.0))) *
      0.24 * uLit;
  float alpha = clamp(body + glow * 0.52 + contactGlow * 0.35, 0.0, 1.0);
  vec3 color = flame * body + glowColor * glow;
  color += vec3(1.0, 0.34, 0.08) * contactGlow;
  fragColor = vec4(color, alpha);
}
