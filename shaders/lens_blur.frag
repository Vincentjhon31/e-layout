#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// e-Layout lens blur shader: a shallow depth of field, the last pass of the
// develop. Driven by ShaderDeveloper (lib/core/develop/shader_developer.dart).
//
// The idea is ported from LightCraft (MIT OR Apache-2.0),
// crates/pipeline/src/lens_blur.rs: a pixel's circle of confusion grows as it
// leaves the focus, pixels more in focus than the one being blurred are left
// out so a sharp subject does not bleed into the blur around it, and Boost
// weights highlights up before they are spread, so they turn into bright
// discs. e-Layout departures (proposals, not LightCraft's):
//  - one gather pass of 48 golden-angle taps on the disc at each pixel,
//    instead of LightCraft's four coarse disc levels blended by the circle of
//    confusion. The taps are about 0.26 x the radius apart, so each reads a
//    mix of the image and a focus-weighted Gaussian prefilter (sigma 0.13 x
//    the largest radius), by 0.128 x radius / sigma: large discs are filled,
//    not offset copies, and small ones stay crisp. The prefilter is an
//    8-bit Gaussian of the encoded colour weighted by (1 - focus) and
//    Boost, so a small highlight loses some of its light at large radii
//    unless Boost is up;
//  - the transition is an exponent on the focus, (1 - focus)^(1 + t/50),
//    not a distance ramp from the focus edge;
//  - colours are averaged in linear light, but the image is the developed,
//    display-referred one (sRGB encoded), not scene-linear;
//  - Boost's highlight test is the Rec.709 luma of the encoded colour above
//    0.75, not a smoothstep of scene-linear luminance.
//
// Uniform layout. ShaderDeveloper sets these in this exact order; keep the
// copy in shader_developer.dart the same.
//   float index  name     meaning
//    0, 1        uSize    output (= source) size, px
//    2           uRadius  disc radius at focus 0, px
//    3           uCap     largest radius allowed (tile budget), px
//    4           uPower   1 + Transition/50
//    5           uBoost   Boost/25
//    6           uPreK    0.128 / prefilter sigma (0 = no prefilter)
//    7           uMode    0 = the blur, 1 = the prefilter's weighted input
// Samplers: 0 uSrc (the image so far), 1 uFocus (focus 0 to 1 in alpha),
// 2 uPre (a Gaussian blur of the weighted input, or uSrc when uPreK is 0).
// All are drawn images of the output's size.

uniform vec2 uSize;
uniform float uRadius;
uniform float uCap;
uniform float uPower;
uniform float uBoost;
uniform float uPreK;
uniform float uMode;

uniform sampler2D uSrc;
uniform sampler2D uFocus;
uniform sampler2D uPre;

out vec4 fragColor;

const int kTaps = 48;
const float kGoldenAngle = 2.39996323;

// Texture coordinates of the position p (px). Impeller's OpenGL ES backend
// stores images it drew bottom up; all inputs are drawn images, so every
// read flips on GLES (see develop.frag).
vec2 uvOf(vec2 p) {
  vec2 uv = p / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return uv;
}

vec3 toLinear(vec3 c) {
  vec3 lo = c / 12.92;
  vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
  // step(c, edge) is 1 where c <= edge.
  return mix(hi, lo, step(c, vec3(0.04045)));
}

vec3 toSrgb(vec3 c) {
  c = clamp(c, 0.0, 1.0);
  vec3 lo = c * 12.92;
  vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
  return mix(hi, lo, step(c, vec3(0.0031308)));
}

// Boost's weight for a straight encoded colour: 1, up to 1 + uBoost for
// white.
float gain(vec3 s) {
  float lum = dot(s, vec3(0.2126, 0.7152, 0.0722));
  return 1.0 + uBoost * max(0.0, lum - 0.75) * 4.0;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec4 c0 = texture(uSrc, uvOf(p));
  float f0 = clamp(texture(uFocus, uvOf(p)).a, 0.0, 1.0);
  vec3 s0 = c0.a > 0.0 ? c0.rgb / c0.a : vec3(0.0);
  // The largest Boost weight, so the prefilter's weights fit in 0..1.
  float gmax = 1.0 + uBoost;
  if (uMode > 0.5) {
    // The prefilter's input: each pixel premultiplied by its weight, how far
    // out of focus it is times its Boost weight (over gmax). Blurred, its
    // rgb / a is the weighted mean colour and a x gmax the mean weight.
    float wt = (1.0 - f0) * gain(s0) / gmax * c0.a;
    fragColor = vec4(s0 * wt, wt);
    return;
  }
  float blur = 1.0 - f0;
  float r = blur <= 0.0 ? 0.0 : min(uRadius * pow(blur, uPower), uCap);
  if (r <= 0.0) {
    fragColor = c0;
    return;
  }
  // How much each tap reads the prefilter: none for a small disc.
  float k = clamp(r * uPreK, 0.0, 1.0);
  vec4 acc = vec4(0.0);
  float wsum = 0.0;
  for (int i = 0; i < kTaps; i++) {
    float fi = float(i);
    // Even area per tap: radius grows with the square root of the index.
    float rr = r * sqrt((fi + 0.5) / float(kTaps));
    float th = fi * kGoldenAngle;
    vec2 q = clamp(p + rr * vec2(cos(th), sin(th)), vec2(0.5), uSize - 0.5);
    vec4 c = texture(uSrc, uvOf(q));
    float f = clamp(texture(uFocus, uvOf(q)).a, 0.0, 1.0);
    vec3 s = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);
    // Taps more in focus than this pixel count less: no sharp bleed.
    float w = (1.0 - max(0.0, f - f0)) * gain(s);
    vec4 tap = vec4(toLinear(s) * c.a, c.a) * w;
    if (k > 0.0) {
      vec4 pre = texture(uPre, uvOf(q));
      // Where almost all of the prefilter's area was in focus (pre.a near
      // 0), its 8 bits say little, so the tap keeps to the image.
      float kk = k * smoothstep(0.0, 0.0625, pre.a);
      if (kk > 0.0) {
        float wp = pre.a * gmax;
        vec4 ptap = vec4(toLinear(pre.rgb / pre.a) * wp, wp);
        tap = mix(tap, ptap, kk);
        w = mix(w, wp, kk);
      }
    }
    acc += tap;
    wsum += w;
  }
  if (wsum <= 1e-5) {
    fragColor = c0;
    return;
  }
  // Photos are opaque, so a is 1 there.
  float a = clamp(acc.a / wsum, 0.0, 1.0);
  vec3 lin = acc.a > 0.0 ? acc.rgb / acc.a : vec3(0.0);
  fragColor = vec4(toSrgb(lin) * a, a);
}
