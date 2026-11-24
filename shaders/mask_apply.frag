#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// e-Layout mask apply shader: mixes the image before a mask (base) with the
// same image developed with the mask's settings (local) by the mask's
// coverage. Driven by ShaderDeveloper (lib/core/develop/shader_developer.dart).
//
// Uniform layout. ShaderDeveloper sets these in this exact order; keep the
// copy in shader_developer.dart the same.
//   float index  name    meaning
//    0, 1        uSize   output (= base) size, px
// Samplers: 0 uBase, 1 uLocal, 2 uCov (coverage 0 to 1 in alpha). All three
// are drawn images of the output's size.

uniform vec2 uSize;

uniform sampler2D uBase;
uniform sampler2D uLocal;
uniform sampler2D uCov;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  // Impeller's OpenGL ES backend stores images it drew bottom up; all three
  // inputs are drawn images, so their reads flip on GLES (see develop.frag).
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec4 base = texture(uBase, uv);
  vec4 local = texture(uLocal, uv);
  float cov = clamp(texture(uCov, uv).a, 0.0, 1.0);
  // Both are premultiplied with the same alpha, so mixing them is exact.
  fragColor = mix(base, local, cov);
}
