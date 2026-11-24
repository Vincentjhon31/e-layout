#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// e-Layout develop shader: the local tools, the baked global colour table,
// vignette and grain, in one pass. Driven by ShaderDeveloper
// (lib/core/develop/shader_developer.dart).
//
// Formulas are ported from LightCraft / craft-libs (MIT OR Apache-2.0), as
// restated in docs/superpowers/notes/lightcraft-notes.md section 8, in linear
// sRGB (Rec.709 luma). Departures, all e-Layout proposals, not LightCraft:
//  - blurred planes are Gaussian blurs of the sRGB-encoded image
//    (ui.ImageFilter.blur), read back as log luminance (log of the blur, not
//    blur of the log);
//  - luminance noise reduction uses a per-pixel guided-filter weight
//    a = d^2 / (d^2 + eps) instead of the windowed guided filter;
//  - colour noise reduction is LightCraft's legacy chroma blur (V1 to V5);
//  - clarity uses a Gaussian instead of the guided filter;
//  - dehaze's dark channel is the darkest channel of the clarity blur;
//  - grain is LightCraft's V1 to V6 value noise with a float hash
//    ("Hash without Sine", Dave Hoskins, MIT) instead of the integer hash.
//
// Uniform layout. ShaderDeveloper sets these in this exact order; keep the
// copy at the top of shader_developer.dart the same.
//   float index  name          meaning
//    0, 1        uSize         output (= source) size, render px
//    2, 3        uOrigin       source top-left in the whole photo, render px
//    4, 5        uFull         whole photo size, render px
//    6           uScale        render px per full-resolution px
//    7           uLutSize      colour table nodes per side
//    8           uLutOn        1 = apply the colour table, 0 = skip it
//    9           uEv           Exposure (stops), for clarity's midtone weight
//   10           uNrLum        luminance noise reduction strength k (0 = off)
//   11           uNrEps        luminance noise reduction epsilon (stops^2)
//   12           uNrCol        colour noise reduction blend t (0 = off)
//   13           uSharpAmt     Amount/150 x Nyquist gain (0 = off)
//   14           uSharpLimit   soft-clip limit (stops), from Detail
//   15           uSharpMask    Masking/100
//   16           uTexture      Texture/100
//   17           uClarity      Clarity/100
//   18           uDehaze       Dehaze/100
//   19           uAir          airlight (linear, whole photo)
//   20           uVigAmount    Vignette/100
//   21           uVigStart     0.15 + Midpoint/100 x 0.95
//   22           uVigWidth     0.05 + Feather/100 x 1.1
//   23           uVigMix       (Roundness/100 + 1) / 2
//   24           uVigPower     2, or 2 + 6 x -Roundness/100 below 0
//   25           uVigHigh      Highlights/100
//   26           uGrainAmt     Amount/100 x 0.13 (0 = off)
//   27           uGrainCell    grain cell, full-resolution px
//   28           uGrainRough   Roughness/100
// Samplers: 0 uSrc, 1 uBlurNrLum, 2 uBlurNrCol, 3 uBlurSharp, 4 uBlurTex,
// 5 uBlurClar, 6 uLut. An unused blur is bound to the source.

uniform vec2 uSize;
uniform vec2 uOrigin;
uniform vec2 uFull;
uniform float uScale;
uniform float uLutSize;
uniform float uLutOn;
uniform float uEv;
uniform float uNrLum;
uniform float uNrEps;
uniform float uNrCol;
uniform float uSharpAmt;
uniform float uSharpLimit;
uniform float uSharpMask;
uniform float uTexture;
uniform float uClarity;
uniform float uDehaze;
uniform float uAir;
uniform float uVigAmount;
uniform float uVigStart;
uniform float uVigWidth;
uniform float uVigMix;
uniform float uVigPower;
uniform float uVigHigh;
uniform float uGrainAmt;
uniform float uGrainCell;
uniform float uGrainRough;

uniform sampler2D uSrc;
uniform sampler2D uBlurNrLum;
uniform sampler2D uBlurNrCol;
uniform sampler2D uBlurSharp;
uniform sampler2D uBlurTex;
uniform sampler2D uBlurClar;
uniform sampler2D uLut;

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

vec3 toEnc3(vec3 c) {
  return vec3(toEnc(c.r), toEnc(c.g), toEnc(c.b));
}

float luma(vec3 c) {
  return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// log2(Y / 0.18), notes section 3.
float logLum(vec3 lin) {
  return log2(max(luma(lin), 1e-7) / 0.18);
}

// Straight (not premultiplied) linear colour of a texel. (SkSL does not
// allow sampler parameters, so callers pass the texel.)
vec3 linOf(vec4 t) {
  return t.a > 0.0 ? toLin3(clamp(t.rgb / t.a, 0.0, 1.0)) : vec3(0.0);
}

// One texel of the colour table: node (r, g, b) at x = r + b*n, y = g.
vec3 lutTexel(float r, float g, float b) {
  float n = uLutSize;
  return texture(uLut, vec2((r + b * n + 0.5) / (n * n), (g + 0.5) / n)).rgb;
}

vec3 lutSlice(float r0, float g0, float b, vec2 t) {
  vec3 top = mix(lutTexel(r0, g0, b), lutTexel(r0 + 1.0, g0, b), t.x);
  vec3 bot = mix(lutTexel(r0, g0 + 1.0, b), lutTexel(r0 + 1.0, g0 + 1.0, b), t.x);
  return mix(top, bot, t.y);
}

// Lut3d.sample: bilinear in r and g within the two neighbouring b slices,
// then linear between the slices.
vec3 lutSample(vec3 c) {
  float n1 = uLutSize - 1.0;
  vec3 f = clamp(c, 0.0, 1.0) * n1;
  vec3 i0 = min(floor(f), vec3(n1 - 1.0));
  vec3 t = f - i0;
  vec3 a = lutSlice(i0.r, i0.g, i0.b, t.xy);
  vec3 z = lutSlice(i0.r, i0.g, i0.b + 1.0, t.xy);
  return mix(a, z, t.z);
}

// "Hash without Sine" (Dave Hoskins, MIT): 0..1 from a lattice point.
float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Value noise in -1..1 with a smoothstep fade (CL finish.rs:99-119 shape).
float valueNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = p - i;
  float a = hash12(i);
  float b = hash12(i + vec2(1.0, 0.0));
  float c = hash12(i + vec2(0.0, 1.0));
  float d = hash12(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  // Impeller's OpenGL ES backend stores images it drew bottom up, and the
  // photo and its blurs are always drawn images (ShaderDeveloper makes sure),
  // so reads of them flip on GLES (see ImageFilter.shader in dart:ui). The
  // position itself (vignette, grain, tile origin) and the colour table,
  // which is uploaded, are not flipped.
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec4 s0 = texture(uSrc, uv);
  float alpha = s0.a;
  vec3 e = alpha > 0.0 ? clamp(s0.rgb / alpha, 0.0, 1.0) : vec3(0.0);

  bool local = uNrLum > 0.0 || uNrCol > 0.0 || uSharpAmt != 0.0 ||
      uTexture != 0.0 || uClarity != 0.0 || uDehaze != 0.0;
  if (local) {
    vec3 c = toLin3(e);

    // Luminance noise reduction (notes 8.6): f = a*l + (1-a)*mean,
    // gain = 2^((f - l) * k).
    if (uNrLum > 0.0) {
      float l = logLum(c);
      float d = logLum(linOf(texture(uBlurNrLum, uv))) - l;
      float a = d * d / (d * d + uNrEps);
      c *= exp2((1.0 - a) * d * uNrLum);
    }

    // Colour noise reduction, legacy method (notes 8.7): blend the
    // chromaticity toward the blurred one, keep the luminance.
    if (uNrCol > 0.0) {
      float y = luma(c);
      vec3 bc = linOf(texture(uBlurNrCol, uv));
      float yb = luma(bc);
      if (y > 1e-6 && yb > 1e-6) {
        vec3 ch = c / y;
        c = max((ch + (bc / yb - ch) * uNrCol) * y, 0.0);
      }
    }

    float l = logLum(c);
    float delta = 0.0;

    // Sharpening (notes 8.5): soft-clipped unsharp mask with edge masking.
    if (uSharpAmt != 0.0) {
      float det = l - logLum(linOf(texture(uBlurSharp, uv)));
      float m = uSharpMask > 0.0
          ? smoothstep(uSharpMask * 0.1, uSharpMask * 0.1 + 0.06, abs(det))
          : 1.0;
      delta += uSharpAmt * 7.0 * m * det / (1.0 + abs(det) / uSharpLimit);
    }

    // Texture (notes 8.2).
    if (uTexture != 0.0) {
      float det = l - logLum(linOf(texture(uBlurTex, uv)));
      float tame = 1.0 - 0.6 * smoothstep(0.4, 1.6, abs(det));
      delta += uTexture * 1.1 * clamp(det, -1.0, 1.0) * tame;
    }

    vec3 clar = vec3(0.0);
    if (uClarity != 0.0 || uDehaze != 0.0) {
      clar = linOf(texture(uBlurClar, uv));
    }

    // Clarity (notes 8.3), base = the exposed pixel's own log luminance.
    if (uClarity != 0.0) {
      float det = clamp(l - logLum(clar), -2.5, 2.5);
      float base = (l + uEv) / 3.2;
      float mid = exp(-base * base);
      delta += uClarity * 0.85 * det * (0.35 + 0.65 * mid);
    }

    c *= exp2(delta);

    // Dehaze (notes 8.4), with the whole-photo airlight.
    if (uDehaze != 0.0) {
      float dark = min(clar.r, min(clar.g, clar.b));
      float minC = min(c.r, min(c.g, c.b));
      float veil = clamp(min(dark / uAir, minC / uAir), 0.0, 1.0);
      if (uDehaze > 0.0) {
        float t = max(1.0 - 0.95 * min(uDehaze, 1.0) * veil, 0.12);
        c = max((c - uAir * (1.0 - t)) / t, 0.0);
      } else {
        float amt = min(-uDehaze, 1.0) * 0.7 * (0.35 + 0.65 * veil);
        c += (uAir * 0.9 - c) * amt;
      }
    }

    e = toEnc3(clamp(c, 0.0, 1.0));
  }

  // Global colour: exposure, tone, colour, curves and profile, baked.
  if (uLutOn > 0.5) {
    e = lutSample(e);
  }

  // Global position in the whole photo, render px (pixel centre).
  vec2 g = uOrigin + frag;

  // Vignette (notes 8.8, highlight priority), on linear light.
  if (uVigAmount != 0.0) {
    float aspect = uFull.x / uFull.y;
    float u = g.x / uFull.x * 2.0 - 1.0;
    float v = g.y / uFull.y * 2.0 - 1.0;
    float sx = 1.0 + (aspect - 1.0) * uVigMix;
    float sy = 1.0 + (1.0 / aspect - 1.0) * uVigMix;
    float sm = max(sx, sy);
    float ax = abs(u * max(sx, 1.0) / sm);
    float ay = abs(v * max(sy, 1.0) / sm);
    float dist = pow(pow(ax, uVigPower) + pow(ay, uVigPower), 1.0 / uVigPower);
    float t = smoothstep(uVigStart, uVigStart + uVigWidth, dist);
    if (t > 0.0) {
      vec3 d = toLin3(e);
      if (uVigAmount < 0.0) {
        float lum = clamp(luma(d), 0.0, 1.0);
        float f = 1.0 + uVigAmount * t;
        f += (1.0 - f) * uVigHigh * smoothstep(0.4, 1.0, lum);
        d *= f;
      } else {
        d += (1.0 - d) * uVigAmount * t * 0.85;
      }
      e = toEnc3(clamp(d, 0.0, 1.0));
    }
  }

  // Grain (notes 8.9, value noise), keyed on full-resolution position.
  if (uGrainAmt > 0.0) {
    vec2 p = g / uScale / uGrainCell;
    float n = valueNoise(p) * (1.0 - uGrainRough * 0.5) +
        valueNoise(p * 2.3 + vec2(57.0, 113.0)) * uGrainRough * 0.7;
    float lum = luma(e);
    e += uGrainAmt * n * (0.35 + 2.6 * lum * (1.0 - lum));
  }

  e = clamp(e, 0.0, 1.0);
  fragColor = vec4(e * alpha, alpha);
}
