#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// e-Layout range mask shader: luminance or colour range coverage of the
// source, in alpha over white (premultiplied). Driven by MaskRasterizer
// (lib/core/develop/mask_raster.dart).
//
// The colour range distance and tolerance are ported from LightCraft
// (MIT OR Apache-2.0), crates/pipeline/src/masks.rs (`shape_alpha`,
// `color_range_tolerance`): OkLab distance with a and b at full weight and L
// at a quarter; full coverage up to half the tolerance, none past it.
// Departures, e-Layout proposals: the source is display-referred sRGB, so
// there is no select tone map, and OkLab is taken from linear sRGB, not
// Rec.2020. Luminance range reads Rec.709 luma of the display-referred sRGB
// source, re-encoded to sRGB (a grey's level is its value), not LightCraft's
// log luminance mapped from -8 to +4 EV; the band edges are LightCraft's
// smoothsteps. OkLab: Bjorn Ottosson (public domain / MIT).
//
// Uniform layout. MaskRasterizer sets these in this exact order; keep the
// copy in mask_raster.dart the same.
//   float index  name     meaning
//    0, 1        uSize    output (= source) size, px
//    2           uMode    0 = luminance range, 1 = colour range
//    3           uLow     luminance: lower end, 0..1
//    4           uHigh    luminance: upper end, 0..1
//    5           uSmooth  luminance: Smooth/100
//    6           uTol     colour: tolerance (OkLab distance)
//    7           uCount   colour: samples in use, 0..5
//    8..22       uS0..uS4 colour: samples in OkLab (L, a, b)
// Samplers: 0 uSrc (a drawn image).

uniform vec2 uSize;
uniform float uMode;
uniform float uLow;
uniform float uHigh;
uniform float uSmooth;
uniform float uTol;
uniform float uCount;
uniform vec3 uS0;
uniform vec3 uS1;
uniform vec3 uS2;
uniform vec3 uS3;
uniform vec3 uS4;

uniform sampler2D uSrc;

out vec4 fragColor;

float toLin(float v) {
  return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
}

vec3 toLin3(vec3 c) {
  return vec3(toLin(c.r), toLin(c.g), toLin(c.b));
}

float toEnc(float v) {
  return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1.0 / 2.4) - 0.055;
}

// LightCraft `smooth`: smoothstep, safe when e1 == e0.
float smoothRamp(float e0, float e1, float x) {
  float t = clamp((x - e0) / max(e1 - e0, 1e-4), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

float cbrtPos(float v) {
  return pow(max(v, 0.0), 1.0 / 3.0);
}

vec3 oklab(vec3 lin) {
  float l = 0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b;
  float m = 0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b;
  float s = 0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b;
  l = cbrtPos(l);
  m = cbrtPos(m);
  s = cbrtPos(s);
  return vec3(
      0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
}

float labDist(vec3 p, vec3 q) {
  vec3 d = p - q;
  return sqrt(d.y * d.y + d.z * d.z + 0.25 * d.x * d.x);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  // Impeller's OpenGL ES backend stores images it drew bottom up; the source
  // is always a drawn image (MaskRasterizer makes sure), so reads flip on
  // GLES (see ImageFilter.shader in dart:ui).
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec4 t = texture(uSrc, uv);
  vec3 e = t.a > 0.0 ? clamp(t.rgb / t.a, 0.0, 1.0) : vec3(0.0);
  vec3 lin = toLin3(e);

  float c = 0.0;
  if (uMode < 0.5) {
    // Luminance on a perceptual 0..1 scale: Rec.709 luma, re-encoded.
    float y = toEnc(dot(lin, vec3(0.2126, 0.7152, 0.0722)));
    float s = max(uSmooth, 1e-3);
    c = smoothRamp(uLow - s, uLow, y) * (1.0 - smoothRamp(uHigh, uHigh + s, y));
  } else if (uCount > 0.5) {
    vec3 p = oklab(lin);
    float d = labDist(p, uS0);
    if (uCount > 1.5) d = min(d, labDist(p, uS1));
    if (uCount > 2.5) d = min(d, labDist(p, uS2));
    if (uCount > 3.5) d = min(d, labDist(p, uS3));
    if (uCount > 4.5) d = min(d, labDist(p, uS4));
    // The max over samples of the similarity is the similarity of the
    // nearest sample.
    c = 1.0 - smoothRamp(uTol * 0.5, uTol, d);
  }
  c = clamp(c, 0.0, 1.0);
  fragColor = vec4(c, c, c, c);
}
