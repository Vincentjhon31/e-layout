# LightCraft reading notes

Reading notes for the e-Layout photo editor (Phase 0 and 1). They record the formulas, constants,
colour spaces and order of operations that LightCraft uses, so a Dart or GLSL implementer can port
each tool without opening the Rust code. Facts only: no LightCraft source is copied into the
project; formulas are restated here in maths and short pseudocode.

Marks used below:

- **LC** = `storytold/lightcraft` at commit `25252399dbe948c3a1d876aca7dbe63d86a1be20`
  (shallow clone, branch head on 2026-11-23).
- **CL** = `storytold/craft-libs` at commit `2be967ec515a687db6b0abe372d54243ccf124bd`. This is the
  `rev` that LC's `Cargo.toml` (lines 13 to 44) pins, and it holds most of the real formulas (see
  section 1).
- "**proposal, not from LightCraft**" = something LightCraft does not have; a suggestion only.
- "**not implemented in LightCraft**" = checked by search, absent.
- Paths are relative to the repository root of LC or CL. `file:line` ranges were read at those commits.

---

## 1. Source, licence and where the formulas live

**Licence.** LC's `Cargo.toml` line 8 says `license = "MIT OR Apache-2.0"`. LC has `LICENSE-MIT`,
`LICENSE-APACHE` and a `NOTICE` ("Copyright (c) 2026 ArtCraft Team and the LightCraft contributors.
Licensed under the MIT License or the Apache License, Version 2.0, at your option"). CL has the
same two licence files, its own `NOTICE`, and the same `license = "MIT OR Apache-2.0"`
(`Cargo.toml:9`). Confirmed for both.

Things in the NOTICEs that are not covered by that licence and that we must not take: the ArtCraft
name, wordmark and logos (`docs/brand/`, trademarks); the Inter font; showcase photographs; the
camera colour matrices in `crates/raw/src/spectral_table.rs` (derived from rawtoaces-data, Apache-2.0,
and CIE data, CC-BY-4.0); the optional RawNIND denoise checkpoint (GPL-3.0, a separately downloaded
model, never part of the formula path). None of these is on the path of the formulas below.

**Important finding: the formulas are not in the LC repository.** LC's `crates/develop`,
`crates/color` and `crates/raster` are thin. `crates/pipeline` holds the per-pixel loop
(`finish.rs`) and the plane preparation (`local.rs`), but nearly every formula is `pub use`d from the
CL crates `craft-develop`, `craft-develop-model`, `craft-color-transform` and `craft-color`
(for example `LC crates/pipeline/src/tone.rs:3`, `lut.rs:3`, `curve.rs:9`, `local.rs:15-19`,
`finish.rs:17-20`). The brief said to clone only LC; I also cloned CL (same owner, same licence) into
the scratchpad, checked out at the pinned rev, so these notes cite both. Nothing from either clone
goes into the project.

**Third-party code and algorithms behind the formulas I describe** (Step 3 of the brief):

| Item | Source | Licence / status |
|---|---|---|
| Rust crates in the formula path: `serde`, `serde_json`, `rayon`, `miniz_oxide`, `proptest` (tests) | crates.io | MIT/Apache-2.0 family. No GPL or LGPL crate in `craft-develop`, `craft-develop-model`, `craft-color-transform`, `craft-color` or LC `crates/{develop,color,raster,pipeline}` (checked `Cargo.toml` files and grepped for GPL, darktable, RawTherapee, LibRaw, dcraw: only the RawNIND note above, which is not code). |
| OkLab | Bjorn Ottosson, "A perceptual color space for image processing" (2020); matrices at `CL crates/color-transform/src/oklab.rs:11-24` | Published by the author under a permissive licence (MIT). Port with credit. |
| Planckian locus cubic | Kim et al., Journal of the Korean Physical Society 41 (2002) (`CL crates/color-transform/src/cct.rs:1-43`) | Published formula. |
| Guided filter | He et al. (self-guided, `CL crates/develop/src/local.rs:236-324`) | Published algorithm. |
| Dark channel prior (dehaze) | He et al. idea; LC's formula is its own (section 7.3) | Published idea. |
| Monotone cubic | Fritsch and Carlson (1980) (`CL crates/color-transform/src/curve.rs:1-104`) | Published algorithm. |
| Crystal film grain | Aurelien Pierre's 2023 article; LC says "Implemented from the article's description; no code was taken" (`LC docs/grain.md`) | Idea only. I recommend not porting it (section 8.2). |
| Gaussian-region legacy curve, `compat.rs` | "PhotoCraft's Camera Raw Filter", Brandon Thomas, MIT OR Apache-2.0 (`CL crates/develop/src/curve/compat.rs:1-5`) | Not needed. |
| Bradford matrix | Standard published matrix (`CL crates/cms/src/math.rs:117`) | Public. |

**Result: no GPL or LGPL source is in the path. No stop-and-ask is needed.** One credit duty: LC's
NOTICE goes into the app's licences (global constraint, Task 19), and the CL NOTICE should go with it
because the ported formulas live there.

---

## 2. What LightCraft is, and how its pipeline differs from e-Layout's

- LightCraft is a raw developer. Its working space is **scene-referred linear Rec.2020** (D65), as
  floats. The decoded input image is converted to it (`LC crates/pipeline/src/lib.rs:3-5`).
  Output is display-encoded sRGB (or another output space; `lib.rs:4-5`, `finish.rs:531-574`).
- Spatial radii are given **relative to the original image's long edge**, so a 400 px preview and a
  60 MP export match (`lib.rs:16-17`). In the notes, `ppl` (px_per_long) means the number of output
  pixels spanning the original image's long edge (`LC crates/pipeline/src/geometry.rs:221-225`); for
  an uncropped output it is the long side of the output in pixels.
- Per-photo "process versions" (V1 to V10, `LC docs/process-versions.md`) keep old edits rendering
  the same. **e-Layout has no old edits, so port the latest behaviour only** and ignore the V1 to V8
  branches. Where this matters I say which branch is the latest.
- For a **non-RAW** source (JPEG, PNG), `SourceInfo.raw == false` (`LC crates/pipeline/src/lib.rs:88-93`).
  That selects: the "display" tone map (section 5.4), relative white balance around 6500 K / 0 as shot
  (section 5.9), and no camera-curve or V4 "light" operators (those need `raw`).

Porting caveat for e-Layout: LightCraft does its maths in linear Rec.2020 with OkLab built for
Rec.2020. e-Layout's Dart LUT pipeline will most likely work in sRGB primaries. Everything here
ports to linear sRGB by substituting the sRGB matrices (section 3) and Rec.709 luminance weights
`Y = 0.2126 R + 0.7152 G + 0.0722 B`. The 8 hue centres (section 6.4) are the same in both,
because OkLCh hue is defined by the colour, not by the working space. That swap is a **proposal,
not from LightCraft**; LightCraft itself never runs in sRGB primaries.

---

## 3. Shared definitions

```text
smooth(e0, e1, x) = t*t*(3 - 2t),  t = clamp((x - e0)/(e1 - e0), 0, 1)        (smoothstep)
GREY = 0.18                                                                    (CL develop/src/tone.rs:11)
lumaRec2020(c)  = 0.2627 R + 0.6780 G + 0.0593 B   (linear)                    (CL develop/src/colorops.rs:51-53)
log_lum(c)      = log2( max(lumaRec2020(c), 1e-7) / 0.18 )                     (CL develop/src/local.rs:688-690)
srgb_to_linear(v) = v <= 0.04045 ? v/12.92 : ((v+0.055)/1.055)^2.4             (LC crates/color/src/transfer.rs:5-13)
linear_to_srgb(v) = v <= 0.0031308 ? 12.92 v : 1.055 v^(1/2.4) - 0.055
wrap(a) = ((a + PI) mod 2PI) - PI                    (CL develop/src/colorops.rs:71-73; mod = rem_euclid)
```

**OkLab** (`CL crates/color-transform/src/oklab.rs:11-24, 75-86`). For linear sRGB use the published
direct matrices (rows):

```text
SRGB_TO_LMS = [[0.4122214708, 0.5363325363, 0.0514459929],
               [0.2119034982, 0.6806995451, 0.1073969566],
               [0.0883024619, 0.2817188376, 0.6299787005]]
LMS_TO_LAB  = [[0.2104542553,  0.7936177850, -0.0040720468],
               [1.9779984951, -2.4285922050,  0.4505937099],
               [0.0259040371,  0.7827717662, -0.8086757660]]
LAB_TO_LMS  = [[1.0,  0.3963377774,  0.2158037573],
               [1.0, -0.1055613458, -0.0638541728],
               [1.0, -0.0894841775, -1.2914855480]]
LMS_TO_SRGB = [[ 4.0767416621, -3.3077115913,  0.2309699292],
               [-1.2684380046,  2.6097574011, -0.3413193965],
               [-0.0041960863, -0.7034186147,  1.7076147010]]
lab = LMS_TO_LAB * cbrt(SRGB_TO_LMS * rgb)            rgb = LMS_TO_SRGB * (LAB_TO_LMS * lab)^3
L = lab[0]   C = hypot(a, b)   h = atan2(b, a)  (radians, -PI..PI)      lch<->lab as usual
```

LightCraft builds the same thing for Rec.2020 (`OkLab::for_space`, `oklab.rs:95-106`:
`XYZ_TO_LMS * bradford(space.white -> D65) * rgb_to_xyz`; for Rec.2020 the white is D65, so no
adaptation). Chromaticities used: sRGB R(0.64, 0.33) G(0.30, 0.60) B(0.15, 0.06); Rec.2020
R(0.708, 0.292) G(0.170, 0.797) B(0.131, 0.046); both white D65 (0.3127, 0.3290)
(`CL crates/color-transform/src/space.rs:97-118`).

**HSV hue to OkLCh hue** (`CL develop/src/colorops.rs:56-62`): take the pure HSV colour
`hsv_to_rgb(deg, 1, 1)`, treat it as sRGB-encoded, linearise, convert to the working space, take
the OkLab hue. Used for mixer band centres, grading wheel hues and the skin hue.

---

## 4. Which tools are global per-pixel and which are local (neighbourhood)

LightCraft's own split, from `LC crates/pipeline/src/finish.rs` (per-pixel loop) and
`LC crates/pipeline/src/local.rs:186-257` (planes that need neighbours):

| Tool | Class in LightCraft | Why |
|---|---|---|
| White balance (temperature, tint) | Global per-pixel (a 3x3 matrix) | `CL develop/src/local.rs:49-109` |
| Exposure | Global per-pixel (gain `2^ev`) | `LC finish.rs:250-251, 674` |
| Contrast, Whites, Blacks | Global per-pixel (luminance tone map table) | `CL develop/src/tone.rs:291-330` |
| Parametric curve, point curves (master and R, G, B) | Global per-pixel, per channel (1D LUTs on encoded values) | `LC finish.rs:29-51, 575-586` |
| Vibrance, Saturation, HSL mixer, Colour grading, B&W mix, Point colour | Global per-pixel (OkLab/OkLCh) | `CL develop/src/colorops.rs:234-311` |
| Calibration | Global per-pixel (matrix + shadow tint) | `colorops.rs:322-368` |
| Profile table (`lut:` 3D LUT) with Amount | Global per-pixel (display-encoded) | `LC finish.rs:613-625` |
| **Highlights, Shadows** | **Neighbourhood**: weighted by an edge-aware base layer of log luminance (median then guided filter, sigma = 1.5 % of long edge). **Not** a pure per-pixel function. | `LC finish.rs:729-737`, `CL local.rs:422-431` |
| **Texture** | **Local**: log luminance minus Gaussian blur (sigma = 0.18 % of long edge, min 0.6 px) | `finish.rs:755-762`, `local.rs:792-795` |
| **Clarity** | **Local**: log luminance minus guided-filter blur (sigma = 1.2 % of long edge) | `finish.rs:747-754`, `local.rs:851` |
| **Dehaze** | **Local**: dark channel blurred (sigma = 2 % of long edge) plus an image-wide airlight estimate | `finish.rs:694-711` |
| **Sharpening** | **Local**: log luminance minus exact Gaussian at the sharpen radius | `finish.rs:763-776` |
| **Luminance noise reduction** | **Local**: self-guided filter of log luminance | `CL local.rs:575-588` |
| **Colour noise reduction** | **Local**: blurred chromaticity (legacy) or the joint multi-scale filter (V6+) | `CL local.rs:589-604`, `nrc_joint.rs` |
| Vignette | Position-dependent (needs x, y), no neighbours | `finish.rs:501-529` |
| Grain | Position-dependent (hash of x, y), no neighbours | `finish.rs:587-612` |

**Consequence for the brief.** The brief puts Highlights and Shadows in the 3D-LUT global pipeline.
LightCraft does not: its Highlights and Shadows read a blurred neighbourhood. A LUT can only hold the
per-pixel limit of it. Section 5.5 gives LightCraft's weights and a **proposal, not from
LightCraft** for a bakeable version (use the pixel's own log luminance as the base).

Anything marked "Global per-pixel" above is a function of the pixel's (r, g, b) alone and can be
baked into a 3D LUT. Vignette and grain depend on the position and belong in the fragment shader
with the local tools.

---

## 5. Order of operations

### 5.1 Stage order (the whole render)

From `LC crates/pipeline/src/lib.rs:7-14` and `render_impl` (`lib.rs:721-823`):

1. **Geometry**: orientation, lens corrections, perspective, crop and straighten, one resample, defringe.
2. **Scene-linear**: white balance, exposure, dehaze, local tone (highlights/shadows), texture,
   clarity, local adjustments (masks).
3. **Tone map**: contrast, whites, blacks on luminance; highlight desaturation.
4. **Colour**: vibrance, saturation, mixer, grading, B&W (OkLCh).
5. **Display**: vignette (display-linear), gamut map to the output space, sRGB encode, tone curves
   (parametric then point), grain. (The upstream doc comment lists vignette after the curves; the code, and
   the table in 5.2, put it before the encode.)

The docs text in `lib.rs:13-14` lists "tone curves, vignette, grain" at the end, but the code order
is the one in 5.2 and is the one to follow.

Code path inside `render_impl` (`lib.rs:721-823`):

1. `frame.sample` resamples the source to the output size (`lib.rs:748-751`).
2. `lin_cpu` (`lib.rs:645-653`): raw local tone map (raw only), **white balance**
   (`local::white_balance`), defringe, spot removal, red-eye.
3. `local::denoise` (`lib.rs:764`): **luminance noise reduction, then colour noise reduction**
   (`CL local.rs:562-572`). Noise reduction therefore happens before exposure, tone and colour.
4. `lens_blur::apply_with` (`lib.rs:765`), not needed for e-Layout.
5. `local::prepare` (`lib.rs:779`, `LC local.rs:186-257`): builds `log_l` and the blurred planes from
   the image **before exposure** (see 5.3).
6. `finish::finish` (`lib.rs:798`): the per-pixel loop `finish_with` (`LC finish.rs:428-630`),
   order in 5.2.

### 5.2 The per-pixel loop, step by step (`LC crates/pipeline/src/finish.rs`)

For each output pixel (`finish_with`, lines 450-627), with `raw` = the pre-exposure white-balanced,
noise-reduced linear pixel and `ev` = `light.exposure`:

| # | Step | Lines | Space |
|---|---|---|---|
| 1 | `color = raw * 2^ev` (exposure gain) | 674 | linear Rec.2020 |
| 2 | Local mask moire/defringe (skip: masks are out of scope) | 676-692 | linear |
| 3 | **Dehaze** (global slider plus mask term) | 694-711 | linear |
| 4 | Local-mask exposure, temp, tint (skip) | 713-722 | linear |
| 5 | `delta` in stops, summed: highlights+shadows, (mask whites, blacks, contrast), clarity, texture, sharpening, (mask noise); then `color *= 2^delta` | 463-470, 729-784 | log luminance, applied as an RGB gain |
| 6 | Calibration matrix and shadow tint (scene linear) | 472-475 | linear |
| 7 | **Tone map**: `yl = lumaRec2020(color)`, `o = tone(yl)`, `d = color * o / yl`, optional chroma scale, then highlight desaturation | 477-489 | linear to display-linear |
| 8 | V4 calibrated Contrast and Blacks (raw with camera curve only, skip) | 491-492 | n/a |
| 9 | **Colour ops** (`ColorOps::apply`): mixer, point colour, vibrance, saturation, local hue, B&W, grading | 494-495 | OkLab of display-linear |
| 10 | Local colour overlay (skip) | 496-499 | |
| 11 | **Vignette** (display-linear) | 501-529 | display-linear |
| 12 | Gamut map to output primaries (`gamut_map_to`) | 531-556 | linear output |
| 13 | Encode with the sRGB curve (exact or 8-bit table) | 559-574 | encoded 0..1 |
| 14 | **Tone curves**: parametric, then master, then R/G/B point curves, as one 1D LUT per channel; then Refine Saturation | 575-586 | **encoded sRGB** |
| 15 | **Grain** | 587-612 | encoded |
| 16 | **Profile 3D LUT with Amount** (`lut:` profiles) | 613-625 | encoded |
| 17 | Quantise to 8 bit with an 8x8 Bayer dither (`bayer_dither_offset`, `finish():371-379`) | | |

Highlights, Shadows, Contrast, Whites, Blacks: notice that **Highlights and Shadows (step 5) come
before the tone map (step 7)**; Contrast, Whites and Blacks are the tone map itself (step 7).
Exposure is step 1, before everything.

Where the profile table sits (brief item "where the table sits in the order"): in LightCraft's own
`lut:` profiles it is the **last** colour step (16), after grain, working on display-encoded sRGB
clamped to 0..1. Its Amount is `k = clamp(profile.amount/100, 0, 2)` and the result is
`e + (lut(e) - e) * k` (section 9). Built-in non-table profiles are different: they are slider offsets
added **before** rendering (`CL develop/src/profiles.rs:45-52`, section 9).

### 5.3 Why the planes are pre-exposure

Exposure is a pure gain, so LightCraft computes the blurred log-luminance planes once on the
un-exposed image and adds `ev` to values read from them (`LC lib.rs:19-22, 265-268`; `finish.rs:458-465`).
Filters of log luminance are shift-equivariant, so this equals filtering after exposure. A shader that
applies exposure first can blur the exposed image directly.

### 5.4 Global-only order for the e-Layout baked LUT (derived, not a LightCraft function)

For the tools that are global per-pixel, the LightCraft order restricted to them is:

```text
WB matrix (linear)  ->  exposure gain  ->  [Highlights/Shadows: see 5.5]
 ->  tone map on luminance (contrast, whites, blacks)  ->  OkLab colour block
     (mixer, vibrance, saturation, B&W, grading)
 ->  gamut map -> sRGB encode -> tone curves (parametric, master, R/G/B), Refine Saturation
 ->  profile table with Amount.
```

Vignette and grain go in the shader after the LUT (LightCraft applies grain after the curves and
before the profile table; applying the table after grain matters only for strong tables).

---

## 6. Formulas, global per-pixel tools

### 6.1 Exposure

`gain = 2^ev`, `ev = light.exposure` (slider -5..5 EV, step 0.01); every channel of the linear pixel
is multiplied (`LC finish.rs:250-251, 674`). No clamping at that point.

### 6.2 Contrast, Whites, Blacks: the display tone map (non-RAW sources)

For non-RAW sources the latest process uses `ToneMap::display_hdr(contrast, whites, blacks, peak=1)`
(`LC finish.rs:343-346` arm `None => ToneMap::display_hdr(...)`; `CL develop/src/tone.rs:284-330`).
It is a 4096-entry table over `EV = log2(y/0.18)` from -14 to +10 (`tone.rs:12-15`), linear
interpolation, below -14 EV scaled linearly (`tone.rs:357-367`). Underneath, per scene luminance `y`
(sliders divided by 100: `c = Contrast/100`, `w = Whites/100`, `b = Blacks/100`):

```text
m  = 0.18^(1/2.2) = 0.4586564           // the contrast pivot: grey in a gamma-2.2 domain
p  = y^(1/2.2)                           // gamma 2.2, NOT the sRGB curve
if p <= 1:
    p += c * 0.35 * (p - m) * (1 - (2p - 1)^2)         // S-curve anchored at 0, grey (m) and 1
    up = smooth(0.45, 1.0, p);   p += w * 0.12 * up * (1 - 0.5 p)       // whites: upper tones
    lo = 1 - smooth(0.0, 0.45, p);  p += b * 0.07 * lo * min(2p, 1)     // blacks: lower tones
else:
    p += w * 0.12 * 0.5                                  // above white: whites shifts the headroom
o = max(p, 0)^2.2
if neutral (c = w = b = 0): no shoulder (identity up to white)
else if o > 0.95:  d = min(o - 0.95, 0.1);  o = 0.95 + d - d*d/0.2     // short shoulder, slope 1 at 0.95
o = clamp(o, 0, 1)                                       // peak = 1 for SDR
```

Neutral sliders give the identity (`o = y` for `y <= 1`). Then, per pixel (`LC finish.rs:477-489`):

```text
yl = lumaRec2020(color)                    // after exposure, local tone and calibration
o  = tone(yl)
d  = yl > 1e-9 ? color * (o / yl) : (0,0,0)          // colour ratios kept, luminance replaced
k  = chroma_scale(o)  (always 1.0 for display tone maps)   // CL tone.rs:344-353
mx = max(d);  if mx > peak(=1):  t = clamp((mx - 1)/max(mx - o, 1e-6), 0, 1);  d += (o - d) * t
```

The last line desaturates a pixel with a channel above 1 towards its luminance so it fits.

Pivot answer (brief: "contrast pivot"): **0.18 scene linear**, which in the gamma-2.2 domain is
`m = 0.4586564`. Contrast adds `c * 0.35 * (p - m) * (1 - (2p-1)^2)` to `p`: no effect at 0, at `m`
(so grey stays grey) and at 1.

The raw/generic tone map (`ToneMap::generic`, `tone.rs:241-281`) is a different curve (extended
Reinhard with the contrast as an EV-domain slope `1 + 0.55c` for `c >= 0`, `1 + 0.4c` for `c < 0`; white
point `0.18 * 2^(2.9 - 1.6 w)`; blacks toe). It is for scene-referred raw files and **not needed
for e-Layout**.

### 6.3 Highlights and Shadows (neighbourhood in LightCraft; weights below)

Slider values `hl = Highlights/100`, `sh = Shadows/100` (`LC finish.rs:278-279`). In
`local_tone_delta` (`finish.rs:729-737`):

```text
base           = base_plane + ev + shift         // log2(L/0.18) of the edge-aware base layer,
                                                  // after exposure; shift = (log lum after dehaze) - (before)
shadow_weight    = 1 - smooth(-4.8, 0.3, base)
highlight_weight = smooth(-1.0, 2.8, base)
delta += sh * 1.7 * shadow_weight * sqrt(shadow_weight) + hl * 1.7 * highlight_weight       // in stops
```

then (`finish.rs:463-470`) `color *= 2^delta` for all three channels (luminance-ratio-preserving).

The **base plane** (`CL develop/src/local.rs:404-431, 760, 835-867`; `LC local.rs:217-249`), latest
process:

1. `l = log_lum(pixel)` per pixel on the pre-exposure image.
2. `m = detail_free(l, r)`, `r = min(round(0.0015 * ppl), 24)` px (`local.rs:404-411, 445-476`): the
   separable median `median_hv(l, r)` (window `2r+1`, rows then columns, clamped edges), each value
   `l` clamped between that median and the median of a 3x wider neighbourhood
   (`BASE_COARSE_STEP = 3`, computed on a box-downscaled copy and bilinearly enlarged).
3. `base = guided_fast(m, sigma, eps = 0.35)` with `sigma = max(0.015 * ppl, 1)` (capped at 24 for
   draft quality); `guided_fast` is the self-guided filter of section 7.1 computed on a `step`-times
   reduced plane, `step = clamp(floor(sigma/3), 1, 16)` (`local.rs:314-324, 491-493`).
4. If neither Highlights nor Shadows is set (nor a mask's), the base plane is not built and `base = l`.

Per-pixel-bakeable **proposal, not from LightCraft** (chosen for Phase 1): for a 3D LUT, set `base = log2(Ypixel/0.18)`
of the exposed pixel itself (the limit `sigma -> 0`). That keeps LightCraft's weight curves and strengths
but loses the edge-aware halo-free behaviour. The shadow weight spans a very wide range
(`smooth(-4.8, 0.3, base)`, about 5 stops), so a per-pixel bake looks harsher than LightCraft's, where the
blurred base smooths it. Porters should tune the **strength** (the 1.7 factors), not the curve shape.
If a shader later has a spare blurred plane, replace
`Ypixel` by the blurred luminance (a Gaussian approximation of the base).

Whites, Blacks and Contrast also have **local-mask versions** in this function
(`finish.rs:738-746`: `0.8 * smooth(0.5, 3.0, l1)`, `0.8 * (1 - smooth(-6, -1.5, l1))`,
`0.14 * clamp(l1, -6, 4)`) but those only receive the mask sliders (`mask_terms`, `finish.rs:137-167`),
never the global ones. Not needed.

### 6.4 HSL colour mixer (8 bands)

Bands, in order (`CL develop-model/src/settings.rs:417-419`): red, orange, yellow, green, aqua,
blue, purple, magenta, with **HSV hue centres** `[0, 30, 60, 120, 180, 225, 270, 315]` degrees.

The centre of each band in **OkLCh hue** (`band_hues`, `colorops.rs:65-68`) is the HSV colour of
that hue pushed through the OkLab conversion (section 3). Computed for sRGB primaries (the same
values hold for Rec.2020, since OkLab hue depends on the colour):

| Band | HSV deg | OkLCh hue rad | OkLCh hue deg |
|---|---|---|---|
| Red | 0 | 0.5102 | 29.23 |
| Orange | 30 | 0.9211 | 52.78 |
| Yellow | 60 | 1.9158 | 109.77 |
| Green | 120 | 2.4870 | 142.50 |
| Aqua | 180 | -2.8838 | 194.77 |
| Blue | 225 | -1.6785 | 263.83 |
| Purple | 270 | -1.1559 | 293.77 |
| Magenta | 315 | -0.2838 | 343.74 |

**Porters must compute the hue centres at start-up in Dart exactly as the Rust does** (HSV hue to sRGB,
linearise, convert, OkLab hue; section 3). Use this table only as test vectors; it is my computation with
the published OkLab sRGB matrices, **not verified against the Rust** (the Rust computes them at start-up. They are in increasing hue order going round the circle,
which `band_weights` relies on.)

**Falloff** (`band_weights`, `colorops.rs:75-94`): a partition of unity of raised-cosine blends
between neighbouring centres.

```text
for i in 0..8:
    a = hues[i];  b = hues[(i+1) % 8]
    span = wrap(b - a) mod 2PI            // arc from a to b, in (0, 2PI)
    d    = wrap(h - a) mod 2PI            // arc from a to the pixel hue
    if d <= span:
        t = d / span;  s = 0.5 - 0.5*cos(PI * t)
        w[i] += 1 - s;  w[(i+1) % 8] += s
        break                              // exactly two non-zero weights, summing to 1
```

At a centre its band has weight 1. Slider scaling (`ColorOps::new`, `colorops.rs:207-209`; sliders -100..100):

```text
hueShift[i] = Hue_i/100 * 0.5      // radians (so +-100 = +-0.5 rad = +-28.6 deg)
satScale[i] = Sat_i/100
lumShift[i] = Lum_i/100 * 0.18
```

Applied in OkLCh (`colorops.rs:261-273`), only when any band is non-zero:

```text
[L, C, h] = lch(oklab(rgb))
dh = sum_i w_i * hueShift_i;  ds = sum_i w_i * satScale_i;  dl = sum_i w_i * lumShift_i
chroma_w = min(C / 0.12, 1)             // greys keep their value; hue is meaningless near neutral
h += dh * chroma_w
C *= max(1 + ds, 0)
L += dl * chroma_w * sqrt(max(L, 0.05))
```

Test vectors (my Python transliteration, not run against Rust; compute the weights in Dart from the
start-up hue centres): `band_weights(1.2 rad)` =
orange 0.8182, yellow 0.1818, others 0; `band_weights(-2.0 rad)` = aqua 0.1655, blue 0.8345.

### 6.5 Vibrance and Saturation

Both scale OkLab chroma `C` (`colorops.rs:245-252, 277-284`), `vib = Vibrance/100`,
`sat = Saturation/100`, applied after the mixer and Point Color, in this order:

```text
skinHue = oklchHue(HSV hue 25 deg) = 0.7828 rad (sRGB computation)        // colorops.rs:224
if vib != 0:
    low  = 1 - clamp(C / 0.22, 0, 1)                                      // less saturated colours move more
    skin = vib > 0 ? 1 - 0.6 * exp( -( wrap(h - skinHue) / 0.35 )^2 ) : 1 // protects skin tones on increase
    C   *= max(1 + vib * low*low * skin * 1.2, 0)
if sat != 0:   C *= max(1 + sat, 0)
```

`Saturation = -100` gives `C = 0` (grey). Test vector (my transliteration, not verified against Rust): `vib = +0.5`, `C = 0.05`,
`h = 0` gives `C = 0.06784`; at `h = skinHue` `0.05717`; `C = 0.2` gives `0.20099`.

### 6.6 B&W mix and B&W treatment

When the treatment is B&W (`crs:ConvertToGrayscale`) or the profile is monochrome
(`colorops.rs:45-47`), the colour block ends with (`colorops.rs:286-291`):

```text
w   = band_weights(h)                 // h includes any local hue shift
mix = sum_i w_i * (BW_i / 100)         // BW_i = the eight B&W sliders, -100..100
L   = max(L + mix * min(C / 0.2, 1) * 0.25, 0)
C   = 0
```

So the grey value is the pixel's OkLab lightness `L`, brightened or darkened by the band sliders in
proportion to how saturated the colour is. Mixer, vibrance and saturation still run before it
(they are irrelevant once `C` is zeroed except through `h` and the pre-`C` mix weight). Grading
(next) still applies after, so wheels split-tone a B&W image. Point Color is skipped in B&W
(`colorops.rs:211-215`).

### 6.7 Colour grading (3 wheels + global, blending, balance)

Each wheel (`colorops.rs:194-198`): `hue` 0..360 (HSV degrees), `sat` 0..100, `lum` -100..100.

```text
h_ok = oklchHue(HSV hue)            // wheel hue as an OkLCh angle
s    = sat/100 * 0.09
wheel = { a = s*cos(h_ok), b = s*sin(h_ok), lum = lum/100 * 0.12 }
```

Grading is a no-op when every wheel has `sat == 0` and `lum == 0` (`settings.rs:557-561`; hue is
ignored). Blending `Bl = Blending/100` (default 0.5), balance `Ba = Balance/100` (`colorops.rs:219-222`).
In `grade` (`colorops.rs:296-311`), with `L` the pixel's OkLab lightness **after** the colour block
above:

```text
m     = 0.5 - Ba * 0.25                 // where shadows end and highlights begin (balance moves it)
width = 0.15 + Bl * 0.5                 // blending widens the overlap
ws = 1 - smooth(m - width, m + width*0.25, L)           // shadows weight
wh = smooth(m - width*0.25, m + width, L)               // highlights weight
wm = max(1 - ws - wh, 0)                                 // midtones weight
for (wheel, weight) in [(shadows, ws), (midtones, wm), (highlights, wh), (global, 1)]:
    lab.a += wheel.a * weight;  lab.b += wheel.b * weight;  lab.L += wheel.lum * weight
rgb = oklab_to_linear(lab)
```

The wheels add a colour vector to OkLab a and b; they do not rotate the existing hue. Test vectors
(my transliteration, not verified against Rust; blending 0.5, balance 0): at `L` = 0.1, 0.3, 0.5, 0.7, 0.9 the (shadow, mid,
highlight) weights are (1, 0, 0), (0.648, 0.352, 0), (0.104, 0.792, 0.104), (0, 0.352, 0.648), (0, 0, 1).

### 6.8 Point Color (not in the Task 4 list, noted for completeness)

`PointK` (`colorops.rs:107-174`): up to 8 samples; each selects a box in OkLCh around a picked
colour (half-widths `wh = (0.1 + 0.6 hueRange) k`, `wc = (0.02 + 0.12 satRange) k`,
`wl = (0.05 + 0.4 lumRange) k`, `k = max(range/50, 0.05)`), with soft `smooth` edges, and shifts hue
by `0.5 * hueShift`, chroma by `1 + satShift`, lightness by `0.2 * lumShift`, variance `0.8`. Skip
unless the plan asks.

### 6.9 Temperature and tint, non-RAW images

For non-RAW sources (`SourceInfo.raw == false`): as-shot white is `(6500 K, tint 0)`
(`LC lib.rs:114-130`, `CL settings.rs:316-322`), and `wb.temp` / `wb.tint` are "the same model
with an as shot of 6500 K / 0". The UI shows a **relative -100..100** scale for these files. The
mapping from the relative slider `r` to Kelvin (`CL develop-model/src/crs.rs:154-158`):

```text
K(r) = 1e6 / ( 1e6/6500  -  0.8 * clamp(r, -100, 100) )        // a mired shift around 6500 K
r = +50 -> 8783.8 K,   r = -50 -> 5158.7 K                      // higher K = bluer assumed white = warmer correction (derived)
```

(This is the mapping LightCraft uses to read `crs:IncrementalTemperature`; I read no other slider
mapping for the UI's relative scale in the files I cite, so treat K(r) as the documented one. The raw
Kelvin range of `wb.temp` is 2000..50000, tint -150..150: `CL develop-model/src/controls.rs:178-179`.)

White balance is a matrix on **linear** RGB (`CL local.rs:66-91`):

```text
(t, tint)   = (wb.temp, wb.tint)              // effective_wb for non-raw (not As Shot)
white       = temp_tint_to_xy(t, tint)        // chromaticity of the assumed scene illuminant
shot        = temp_tint_to_xy(6500, 0)
W(xy)       = rgb_from_xyz * bradford_adapt(xy -> space white D65) * xyz_from_rgb     // 3x3, linear RGB
M           = W(white) * inverse( W(shot) )
g           = M * (1,1,1);   Y = luma(g);      M = M / Y            // keeps neutral luminance (WB must not change exposure)
pixel       = max(M * pixel, 0)                // before exposure
```

If `(t, tint)` equals the as-shot values (or mode is As Shot), no matrix is applied (`local.rs:73-75`).
Sign reasoning (my derivation from the matrix above, not a citation): the matrix maps the assumed source
white to neutral, so a higher Kelvin value (bluer assumed white) gives a warmer correction, and a positive
tint (assumed white shifted towards green) gives a magenta correction. `settings.rs:329-330` has a help
comment on tint direction; check it against a test image before wiring the slider direction.

`temp_tint_to_xy` (`CL color-transform/src/cct.rs:26-94`):

```text
kim_xy(T):  T = clamp(T, 1667, 25000);  (x from a cubic in 1/T, then y from a cubic in x; constants)
  x = T <= 4000 ? -0.2661239e9/T^3 - 0.2343589e6/T^2 + 0.8776956e3/T + 0.179910
                : -3.0258469e9/T^3 + 2.1070379e6/T^2 + 0.2226347e3/T + 0.240390
  y = T <= 2222 ? -1.1063814 x^3 - 1.34811020 x^2 + 2.18555832 x - 0.20219683
    : T <= 4000 ? -0.9549476 x^3 - 1.37418593 x^2 + 2.09137015 x - 0.16748867
                :  3.0817580 x^3 - 5.87338670 x^2 + 3.75112997 x - 0.37001483
(u, v) = CIE 1960 of kim_xy:   d = -2x + 12y + 3;  u = 4x/d;  v = 6y/d
outside 1667..25000 K the locus continues as a straight line in mired (cct.rs:62-73) -- not needed
normal n = unit normal of the locus at T, pointing to +v (towards green), by finite difference
          of locus_uv at mired +-1 (cct.rs:75-84)
duv = tint / 3000                                  // TINT_SCALE = 3000 tint units per unit Duv
(u', v') = (u, v) + n * duv ;  xy = ( 3u'/(2u' - 8v' + 4), 2v'/(2u' - 8v' + 4) )
```

`bradford_adapt(src -> dst)` is the standard Bradford: `XYZ->cone` matrix
`[[0.8951, 0.2664, -0.1614], [-0.7502, 1.7135, 0.0367], [0.0389, -0.0685, 1.0296]]`
(`CL cms/src/math.rs:117`), scale the cone responses by `cone(dst)/cone(src)` per channel, and go back.
The Process V10 version returns identity when a source cone response is not positive; use that
checked form.

**Not in LightCraft for non-RAW:** there is no separate formula for non-RAW; it reuses the raw path
with an as-shot of 6500 K. A simpler diagonal-gain temperature/tint would be a **proposal, not from
LightCraft**; if used, say so in the Task 4 table.

---

## 7. Tone curves

### 7.1 Parametric curve (four regions)

`ParametricCurve::new` (`CL crates/develop/src/curve.rs:33-64`); amounts in graph order
`[shadows, darks, lights, highlights]` (`curve.rs:13`, sliders -100..100), splits default 25 / 50 / 75 %
(slider ranges 10..70, 20..80, 30..90: `controls.rs`):

```text
s0 = clamp(splitShadows/100, 0, 1)
s1 = clamp(splitMid/100,    s0, 1)
s2 = clamp(splitHighlights/100, s1, 1)
regions = [(0, s0, a0), (s0, s1, a1), (s1, s2, a2), (s2, 1, a3)]      // a_i = region amount, -100..100
prev = 0
for i in 0..=1023:   x = i/1023                  // 1024 entries; i = 0 gives x = 0, y = 0
    d = 0
    for (lo, hi, amt) in regions, amt != 0:
        ctr = (lo+hi)/2;  half = (hi - lo)*0.75 + 0.05
        t   = clamp((x - ctr)/half, -1, 1)
        d  += (amt/100) * 0.22 * (0.5 + 0.5*cos(PI*t))           // one cosine bump per region
    y = clamp(x + d * 4x(1-x), 0, 1)                              // 4x(1-x) pins 0 and 1
    prev   = max(prev, y);  lut[i] = prev                          // forced monotone; at i = 0, prev = 0 so lut[0] = 0
```

Test vectors (my transliteration, not verified against Rust): `shadows = +50`, splits default: at x = 0, 0.1, 0.25, 0.5, 0.75, 1 the
output is 0, 0.13853, 0.28784, 0.5, 0.75, 1. `darks = +30, lights = -50`: 0, 0.1, 0.27271, 0.47982,
0.71216, 1.

### 7.2 Point curves (master, red, green, blue)

`MonotoneCurve` (`CL color-transform/src/curve.rs:65-135`): a monotone cubic Hermite spline
(Fritsch-Carlson) through points in 0..1 x 0..1.

```text
points: drop non-finite, sort by x, merge points closer than 1e-9 in x; fewer than 2 points = identity
d[i]  = (y[i+1]-y[i]) / (x[i+1]-x[i])
m[0] = d[0];  m[n-1] = d[n-2]
m[i] = (d[i-1]*d[i] <= 0) ? 0 : (d[i-1]+d[i])/2           // 0 < i < n-1
for each segment i:  if d[i] == 0:  m[i] = m[i+1] = 0
                     else: r = hypot(m[i], m[i+1]);  lim = 3*|d[i]|;  if r > lim: scale m[i], m[i+1] by lim/r
eval(x): x <= x0 -> y0;  x >= x_last -> y_last;  else
         t = (x-x_i)/h, h = x_{i+1}-x_i
         y = (2t^3-3t^2+1) y_i + (t^3-2t^2+t) h m_i + (-2t^3+3t^2) y_{i+1} + (t^3-t^2) h m_{i+1}
```

A curve counts as the identity when empty or every point has `x == y` within 1e-9
(`settings.rs:396-398`).

### 7.3 How they combine and where they run

`curve_luts` (`LC finish.rs:29-51`) builds three 1024-entry LUTs (R, G, B). Order of application
(`composite = outer ∘ inner`, `CL color-transform/src/curve.rs:243-252`):

```text
base   = parametric LUT                                   (applied first)
if master is not identity:  base = master ∘ base           (master after parametric)
channel c: if its curve is not identity:  lutc = curve_c ∘ base   else  lutc = base
```

So per channel: **parametric, then master, then the channel's own curve**. They run on **display-encoded
sRGB values** (after the sRGB encode, step 14), per channel, `Lut1::eval` clamps the input to 0..1 and
interpolates linearly (`curve.rs:187-199`). When all four are identity the whole stage is skipped
(`finish.rs:33`).

Refine Saturation (`CL develop/src/finish.rs:147-162`, slider 0..100, default 100): after the curves, with
`refine = Refine/100` (`LC finish.rs:272`), applied only if `refine < 1`:

```text
luma(e) = 0.2126 R + 0.7152 G + 0.0722 B  (on encoded values);  chroma(e) = max(e) - min(e)
s0 = chroma(before) / max(luma(before), 1e-4);  s1 = chroma(after) / max(luma(after), 1e-4)
if s1 <= 1e-6 or s0 <= 1e-6: return after
k = clamp( (s0/s1)^(1 - refine), 0, 4 );  out = luma(after) + (after - luma(after)) * k
```

`refine = 1` keeps the curve's own saturation; `0` restores the pre-curve saturation.

---

## 8. Local effects (the GLSL shader candidates)

All of these work on `log_l = log2(Y/0.18)` of the **pre-exposure** image (or, in a shader, the
exposed image with the same formulas, since the filters are shift-equivariant), give a `delta` in
stops, and multiply all three channels by `2^delta` (`LC finish.rs:463-470`). Sliders divided by 100
unless noted (`finish.rs:245-248`: `clar`, `tex`, `dehaze`).

### 8.1 Plane definitions (`CL develop/src/local.rs:792-867`, `LC local.rs:186-257`)

```text
texture band : tex_blur   = gaussian(log_l, sigma = max(0.0018 * ppl, 0.6))
clarity band : clar_blur  = guided_fast(log_l, sigma = max(0.012 * ppl, 1), eps = 0.8)       (CLARITY_EPS)
dehaze       : dark       = gaussian( min(R, G, B) of the pre-exposure image, sigma = max(0.02 * ppl, 1) )
sharpen band : sharp_blur = gaussian_taps(log_l, exact Gaussian taps at sigma_sharp)   (section 8.5)
```

`gaussian` = three successive box blurs approximating a Gaussian (Kovesi/Wells radii, clamped edges;
`CL develop/src/raster/blur.rs:12-27, 122-142`; `LC crates/raster/src/blur.rs` is the same code). A
sigma at or below 0.3 px is no blur. `gauss_taps(sigma)`: `r = ceil(3 sigma)`, weights
`exp(-i^2 / (2 sigma^2))` normalised, sigma clamped to 0.05..64 (`blur.rs:152-160`). In a shader, a true
separable Gaussian is a fine substitute for the box approximation (**proposal, not from LightCraft**).

Self-guided filter, `guided(p, sigma, eps)` (`CL local.rs:236-309`), Gaussian windows of `sigma`:

```text
mean = G(p);  corr = G(p*p);  var = max(corr - mean*mean, 0)
a = var / (var + eps);   b = mean - a*mean
q = G(a) * p + G(b)
```

`guided_fast` computes `a`, `b` on a plane box-downscaled by `step = clamp(floor(sigma/3), 1, 16)`
and samples them bilinearly (`local.rs:314-324`); `step = 1` is the plain filter.

### 8.2 Texture

`LC finish.rs:755-762`:

```text
texture = Texture/100
detail  = log_l - tex_blur                                   // pixel's log luminance minus the fine blur
tame    = 1 - 0.6 * smooth(0.4, 1.6, |detail|)               // strong edges get less boost, limits halos
delta  += texture * 1.1 * clamp(detail, -1, 1) * tame
```

### 8.3 Clarity

`LC finish.rs:747-754`:

```text
clarity  = Clarity/100
detail   = clamp(log_l - clar_blur, -2.5, 2.5)
midtone  = exp( -(base / 3.2)^2 )               // base = the highlights/shadows base plane after exposure
                                                // (= log_l + ev when Highlights and Shadows are 0)
delta   += clarity * 0.85 * detail * (0.35 + 0.65 * midtone)
```

For a shader without a base plane, use `base = log_l + ev` (the exposed pixel's own value).

### 8.4 Dehaze

`LC finish.rs:694-711` (sliders `dehaze = Dehaze/100`), on **linear colour after exposure**, before
the local-tone delta. `air_pre` = airlight of the pre-exposure dark channel; `air = air_pre * 2^ev`.

```text
airlight(dark):  take every 7th value of the dark channel plane, sort, value at the 99.5th percentile,
                 max(value, 0.05); 1.0 if empty                            // CL local.rs:870-886
min_c = min(color.rgb)                                                      // exposed pixel
veil  = clamp( min( dark[i]/air_pre , min_c/air ), 0, 1 )                   // each term 0 if its denominator <= 0
if dehaze > 0:
    t     = max(1 - 0.95 * min(dehaze, 1) * veil, 0.12)                     // transmission
    color = max( (color - air*(1 - t)) / t, 0 )                             // per channel
else:
    amount = min(-dehaze, 1) * 0.7 * (0.35 + 0.65 * veil)
    color += (air*0.9 - color) * amount                                     // adds haze towards 0.9 air
```

After dehaze the pixel's `log_lum` is recomputed for the later tone steps (`finish.rs:724-726`).
The airlight is image-wide: a windowed render fixes it from a 384 px (`AIRLIGHT_PROXY_EDGE = 384`, `lib.rs:475`) proxy
of the whole frame (`lib.rs:508-512`, `local.rs:260-265`); for e-Layout compute it once per photo
from a reduced copy.

### 8.5 Sharpening (latest, "pixel scale", process V3 and later)

`LC finish.rs:763-768` with `CL develop/src/finish.rs:12-43` and `local.rs:800-833`:

```text
Amount, Radius, Detail, Masking = detail.sharpen_amount (0..150), sharpen_radius (0.5..3, default 1),
                                  sharpen_detail (0..100, default 25), sharpen_masking (0..100)
sharpen    = Amount / 150                                    (finish.rs:283)
raw_sigma  = clamp(Radius, 0.1, 10) * ppl / native_long       // output px per original px
sigma      = clamp(raw_sigma, 0.5, 64)
det        = log_l - gaussian_taps(log_l, sigma)             // pixel-scale detail (stops)
limit      = 0.03 * 50^(clamp(Detail/100, 0, 1))             // 0.03 .. 1.5 stops
mask       = Masking/100
m          = mask > 0 ? smooth(mask*0.1, mask*0.1 + 0.06, |det|) : 1   // edge mask: flat areas and noise left alone
term       = 7 * m * det / (1 + |det| / limit)               // 7.0 = SHARPEN_GAIN, a soft clip at `limit`
gain       = sharpen_gain(raw_sigma)                         // 1 when raw_sigma >= 1; below, a Nyquist match:
delta     += sharpen * gain * term
```

`sharpen_gain(raw)` for `raw < 1` (`local.rs:819-833`): build the taps for `sharpen_sigma(raw)`,
`response = sum over taps of (+-1 alternating) * tap`, `desired = 1 - exp(-0.5 * PI^2 * raw^2)`,
`ratio = desired / max(1 - response, 1e-6)`, `blend = clamp((1 - raw)/0.5, 0, 1)`,
`gain = 1 + (ratio - 1) * blend`; 0 when `raw <= 0` or not finite. `native_long` is the original
photo's long edge, so a preview gets the export's sharpening scaled down. If e-Layout edits at one
resolution, `ppl = native_long` and `raw_sigma = Radius`.
Test vector (my transliteration, not verified against Rust): `limit(Detail 25) = 0.07977`; `term(det = 0.1, Detail 25, Masking 0) = 0.3106`.

### 8.6 Luminance noise reduction

`nr_params` and `apply_nr` (`CL local.rs:541-556, 575-588`), `lum = NoiseReduction/100`,
`detail = nr_detail/100`; `scale` = output px per original px, at most 1 (`detail_scale`, `local.rs:512-515`);
at full size `scale = 1`:

```text
sigma = nr_radius((1 + 2.5*lum) * scale)                    // radius in px; below 1 px: sigma = 1 px with blend w
eps   = max((0.002 + lum*lum*0.25*(1 - 0.7*detail)) * scale*scale, 1e-7)
k     = sqrt(lum) * w                                        // w = 1 for sigma >= 1
l     = log2(Y/0.18)  per pixel                              // log_lum
f     = guided(l, sigma, eps)                                // self-guided filter (8.1), plain not fast
gain  = 2^( (f - l) * k );  pixel *= gain                    // in linear light, ratios kept
```

(`nr_radius`: if `sigma >= 1` then `(sigma, 1)` else `(1, min((sigma / box_sigma(1))^2, 1))` and
`box_sigma(1)` = 0.8165 px; if `w < 0.01` it is skipped.) **LuminanceNoiseReductionContrast
(`detail.nr_contrast`) is stored and mapped from `crs:` but never read by the renderer**
(`CL crates/**` search: only `controls.rs:267`, `crs.rs:356`, `settings.rs:647,671`): treat the Contrast
slider as not implemented in LightCraft.

### 8.7 Colour noise reduction

Two methods; LightCraft's latest process (V6+) uses the **joint** one (`CL local.rs:562-572`,
`nrc_joint.rs`, 1194 lines: multi-scale self-guided filtering of R-Y and B-Y with a noise model, a
brake for isolated colour specks, `Y` kept exactly; parameters at `local.rs:632-646`: `sigma = (2 +
10*amount) * (1 + smoothness/100) * scale`, passes at `sigma` and `3*sigma`, `k = 64*amount*(1.5 -
detail)`, offset 0.003). I did not read `nrc_joint.rs` in full and do **not recommend porting it**.
The simpler **legacy method** (used by V1 to V5, `local.rs:589-604`) is portable:

```text
col  = ColorNoiseReduction/100; detail = nr_color_detail/100; smooth = 1 + nr_color_smoothness/100
sigma = nr_radius((1.5 + 6*col) * scale * smooth)
keep  = detail * 0.5;   t = col * (1 - keep) * w
chroma  = rgb / max(Y, 1e-6)  per pixel       // chromaticity
chroma_b = gaussian(chroma, sigma)
out = max( (chroma + (chroma_b - chroma) * t) * Y, 0 )      // original luminance Y re-applied
```

Defaults (Detail 50, Smoothness 50) from `settings.rs:661-679`. Use the legacy method with the label
"LightCraft legacy colour noise reduction, V1 to V5".

### 8.8 Vignette (post-crop)

`CL develop/src/finish.rs:45-72`, applied at `LC finish.rs:501-529` on display-linear colour, in the
coordinates of the **whole output frame** (a windowed render keeps the global frame):

```text
amount  = Vignette/100 (-1..1),  midpoint = Midpoint/100, feather = Feather/100,
roundness r = Roundness/100 (-1..1), highlights = Highlights/100 (0..1), style
start   = 0.15 + midpoint * 0.95
width   = 0.05 + feather * 1.1
aspect_mix = clamp((r + 1)/2, 0, 1)
power   = r >= 0 ? 2 : 2 + (-r) * 6
aspect  = frame_w / frame_h
u = (px + 0.5)/w * 2 - 1;  v = (py + 0.5)/h * 2 - 1                 // -1..1 over the whole frame
sx = 1 + (aspect - 1) * aspect_mix;  sy = 1 + (1/aspect - 1) * aspect_mix
ax = |u * max(sx, 1) / max(sx, sy)|;  ay = |v * max(sy, 1) / max(sx, sy)|
dist = (ax^power + ay^power)^(1/power)
t    = smooth(start, start + width, dist)
if t > 0:
    lum = clamp(lumaRec2020(d), 0, 1)
    if amount < 0 (darken):
        f = 1 + amount * t
        if style == HighlightPriority: f += (1 - f) * highlights * smooth(0.4, 1.0, lum)
        if style == PaintOverlay:  d *= (1 - (-amount) * t)    else  d *= f
        // ColorPriority uses f as is
    else (lighten):  d += (1 - d) * amount * t * 0.85         // toward white, 0.85 strength
```

(ColorPriority and HighlightPriority differ only through the `highlights` term; Paint Overlay uses a
plain multiply.) Imported `crs:PostCropVignetteStyle`: 2 = colorPriority, 3 = paintOverlay, else
highlightPriority (`crs.rs:367-374`). Test vectors (transliteration): amount -0.5, midpoint 50, feather 50,
roundness 0, aspect 1.5: `start = 0.625`, `width = 0.6`; at the corner `dist = 1.2806`, `t = 1`, factor 0.5;
at the middle of the long edge `dist = 1`, `t = 0.6836`, factor 0.6582; at the centre factor 1.

Because `d` is display-linear, the multiplier works in linear light before the sRGB encode.

### 8.9 Grain

Latest LightCraft uses the **crystal grain** (process V7+: `LC crates/pipeline/src/crystal.rs`, CL
`crates/develop/src/crystal.rs`, 1093 lines; `LC docs/grain.md`): a Boolean model of polygonal crystal
layers on two periodic tiles stored as summed-area tables. **Do not port it**; it needs 16 table reads
per pixel and a pre-drawn emulsion. Its calibration (strength at mid-grey, levels of 255 at 6000 px:
`Amount/100 * exp(2.447 + 1.386*exp(-Size/19.88)) * (1 - 0.084d + 1.6384d^2)`, `d = Roughness/100 - 0.5`,
8.55 at 50/25/50) is a useful target. Its application to the encoded colour `e` is
(`CL crystal.rs:1081-1088`): `k_total = K * g * (1 - srgb_to_linear(lum))`, `e += k_total * lift(v)` per
channel (`lift(v) = Y * dv/dY` of the sRGB curve, so the grain keeps hue).

The **portable one is the value-noise grain of V1 to V6** (`CL finish.rs:74-119`, `LC finish.rs:94-109,
587-603`), the best candidate for the shader:

```text
amt   = Amount/100 * 0.13
cell  = max( (0.0006 + Size/100 * 0.0024) * ppl, 0.6 )              // noise cell in output px
rough = Roughness/100;   seed = grain.seed
gx = n.x * ow / long;  gy = n.y * oh / long                           // frame position, 0..1 over the long edge
sc = ppl / cell
v  = grain_noise(gx*sc,      gy*sc,      seed)      * (1 - rough*0.5)
   + grain_noise(gx*sc*2.3,  gy*sc*2.3,  seed ^ 0x55) * rough * 0.7
lum = 0.2126 e0 + 0.7152 e1 + 0.0722 e2                               // encoded values
k   = amt * v * (0.35 + 2.6 * lum * (1 - lum))                        // strongest in midtones
e  += k                                                                // same k to R, G and B (monochrome)
```

`grain_noise(x, y, seed)` (`CL finish.rs:99-119`): value noise in -1..1 with smoothstep fade:

```text
x0 = floor(x), y0 = floor(y);  fx = x - x0, fy = y - y0
h(i, j) = ((i*0x8da6b343) ^ (j*0xd8163841) ^ (seed*0xcb1ab31f)  [uint32 wrap]);
          v ^= v >> 13;  v *= 0x5bd1e995;  v ^= v >> 15;   return (v & 0xffff)/32768 - 1
u = fx*fx*(3 - 2fx);  w = fy*fy*(3 - 2fy)
a = lerp(h(i,j),   h(i+1,j),   u);   b = lerp(h(i,j+1), h(i+1,j+1), u);   return lerp(a, b, w)
```

Porting warning: this hash uses 32-bit integer multiply, xor and shift. **The integer hash needs a float
replacement in Flutter shaders**: Flutter's fragment shaders are compiled for the runtime effect backends and
integer bit operations are not reliably available on all of them; use a float hash with the same shape (**proposal, not from LightCraft**) and do not expect bit-exact
output. Grain is position-based: the shader needs the frame coordinates and `ppl` (the long edge in px).

### 8.10 Calibration (listed for completeness)

`calibration_matrix` and `calibrate` (`CL colorops.rs:314-368`), in scene-linear light before the tone map
(`LC finish.rs:472-475`): each primary rotated in OkLCh hue by `Hue/100 * 0.5` rad and its chroma scaled by
`1 + Sat/100 * 0.6` at constant L, columns rescaled so (1, 1, 1) maps to itself; then a shadows tint on G:
`w = 1 - smooth(-5, -0.5, log2(Y/0.18))`, `G *= max(1 - 0.3 * tint * w, 0)`, luminance restored.

---

## 9. Profiles, LUTs and Amount

**Built-in LightCraft profiles** (`CL develop/src/profiles.rs:1-60`) are not tables: a "profile" is a list of
*deltas on the user's sliders*, each multiplied by `k = clamp(Amount/100, 0, 2)`
(`profile.amount` range 0..200, default 100): contrast, saturation, vibrance, mixer, B&W mix, wheel vectors
added to the user's wheels, and point-curve fades (`y -> b + y*(w - b)`, `b = clamp(black*k, 0, 0.45)`,
`w = clamp(1 - (1 - white)*k, 0.55, 1)`). All looks are LightCraft's own. Not reusable as data.

**`.cube` LUT profiles** (`CL develop/src/lut.rs`): text format `LUT_3D_SIZE n` (2..256), optional
`DOMAIN_MIN` / `DOMAIN_MAX`, `n^3` "r g b" lines with **red changing fastest** (`index = r + n*(g + n*b)`),
1D LUTs rejected, non-finite entries rejected (`lut.rs:21-64`). Lookup is trilinear on the **display-encoded**
colour, input clamped to the domain (`lut.rs:67-87`). Applied last, after grain, with Amount
(`LC finish.rs:613-625`):

```text
m = lut.apply( clamp(e, 0, 1) )          // e = display-encoded colour after curves and grain
k = clamp(profile.amount/100, 0, 2)
out = e + (m - e) * k                     // SDR path, finish.rs:620-622
```

So Amount 100 % is the table, 0 % is no change, 200 % extrapolates. **This is the only table Amount
rule in LightCraft; it is the model for e-Layout's creative profiles.**

---

## 10. Adobe `crs:Table_*` / `RGBTable` decoding

### 10.1 What LightCraft does

**Not implemented in LightCraft.** I searched LC and CL for `RGBTable`, `RGBTables`, `Table_`,
`ProfileLookTable`, base85, ascii85 and zlib use in the develop and import paths:

- The only hits for `RGBTable` are in a skip list: `crs:RequiresRGBTables` is a "does not change the
  rendering" bookkeeping key (`CL develop-model/src/crs.rs:68`, `LC crates/engine/src/crs.rs:88`).
- `crs:Look`, `crs:CameraProfile` and anything holding a table are reported as **unmapped** on import
  (`CL crs.rs:448-512`: "`CameraProfile`, `Look`, `MaskGroupBasedCorrections`..." are listed as not carried
  over; `camera_profile_name` keeps the name only).
- LightCraft decodes a different Adobe table family: the DNG camera-profile **HSV** tables
  `ProfileHueSatMapData1/2`, `ProfileLookTableData` (`CL crates/raw/src/profile.rs:1-123`): HSV of linear
  ProPhoto RGB (D50); value axis indexed through the sRGB curve when the encoding tag is 1. That is the
  nearest reference code but **not** the XMP `crs:Table_*` RGB table, and a Dart decoder must not assume it.

Therefore everything below is what I could establish independently. It is **not** from LightCraft's
source, and parts are unresolved. Task 8 must finish this against the real files.

### 10.2 Facts established from the sample pack (read only, nothing copied)

Read for a manual check, as the global constraints allow. Both XMP files in
`LightroomVintageVibeFree` were parsed; I record structure and the alphabet, never the data.

1. **Where the data sits.** In a pure Look preset, the root `rdf:Description` carries two attributes:
   `crs:RGBTable="<32 hex digits, uppercase>"` and `crs:Table_<same 32 hex digits>="<text>"`. The 32 hex
   digits are the table's fingerprint (an MD5-sized digest). The text is a single XML attribute value
   with no whitespace and no XML entities, of the order of 240,000 characters for a 3D table, plus
   `crs:RequiresRGBTables="False"`. (File 1: `crs:PresetType="Look"`, `crs:SupportsAmount="True"`,
   `crs:ProcessVersion="15.4"`, `crs:Version="18.3.1"`.)
2. **Other `Table_` uses.** The second file (a Camera Raw Filter style packet) has
   `crs:Table_<hash>="..."` too; the same hash is named by `crs:CompressedSettings="<hash>"` inside a
   `crs:Filters` item. So the `Table_<hash>` mechanism carries different payload kinds; the `RGBTable`
   attribute names the one that is a colour table. Decoder: look the table up by the digits in
   `crs:RGBTable`, never by scanning all `Table_` attributes.
3. **Text alphabet.** The text uses exactly **85 distinct characters** in a base-85 style encoding:
   `! # $ % ' ( ) * + - . / 0-9 : = ? @ A-Z [ ] ^ `` ` `` a-z { | }`. These are the printable characters
   `0x21` to `0x7D` except `" & , ; < > \ _` (8 removed: the XML-unsafe ones and a few others).
   Length mod 5 was 2 for the large table and 3 for the small one, so the encoding is a grouping of
   5 characters per 4 bytes with a short last group, as in Ascii85.
4. **The digit order is NOT the plain ASCII order of those characters, and NOT Z85 order with
   `& < >` swapped for `' | `` ` ``.** I tried, for the large table: that ASCII-sorted order and its
   reverse, Z85 order with all 6 substitutions of `' ` |` for `& < >`, digit-first, then
   upper/lower/punctuation orderings (all 24 class orders, ASCII punctuation), each with most-significant
   or least-significant digit first and big- or little-endian bytes. Every one overflows `2^32` in some
   5-character group, so none is the Adobe order. **The real alphabet order, byte order and the framing
   (a length prefix?) are unresolved.** A short run of `0` characters at the start of the text
   (`...00`) suggests the order may start with the digits, as in Z85, with small integers in the header.
5. **Amount.** The Camera Raw Filter style file has a `crs:Look` struct with `crs:Amount="0.5"` next to
   the look's name and UUID; the pure Look preset (file 1) has no Amount attribute, only
   `crs:SupportsAmount="True"`. My reading (an inference, not verified): the Amount is stored outside the
   table, as a fraction (0.5 here) that scales the look's effect, and the application's Amount slider
   shows it as a percentage. The second file also has `crs:SupportsAmount2="True"`; I do not know what
   it adds. LightCraft ignores all of these (`CL crs.rs:51, 67`).

### 10.3 What I recall about the format, unverified

The following is from memory of Adobe's DNG SDK and public discussions of Camera Raw profile tables, and
**I could not verify any of it here**. It is a hypothesis for Task 8 to test against the real files, not
a specification, and none of it comes from LightCraft:

- The decoded bytes are the DNG SDK's `dng_rgb_table` serialisation (a fingerprint-named "big table"):
  a small integer header (a version, the number of dimensions 1 or 3, the number of divisions per axis,
  possibly a gamut and gamma code and a min/max amount), then the sample array, then likely a trailer.
- The table is a **3D RGB to RGB** lattice with `divisions^3` entries, stored with **red varying fastest
  or slowest**: the decoder must test both. The lattice axes are probably indexed in a non-linear
  (gamma) encoding and the colour space probably a wide gamut such as ProPhoto RGB; I could not confirm
  either. The sample values are probably 16-bit integers or floats of the output colour.
- The payload is probably compressed with zlib (deflate); a 4-byte uncompressed length may come first.
- The Amount probably interpolates between the identity lattice and the table: `out = in + (T(in) - in) * amount`,
  possibly with a separate "min amount / max amount" pair giving extrapolation limits. This matches how
  LightCraft treats its own `.cube` tables (section 9), but Adobe's exact rule for amounts above 1 is unknown.

**What the Dart decoder needs, to be established in Task 8 by experiment with the sample files:**
(a) the exact 85-character digit order; (b) byte order of the 4-byte groups; (c) the framing (prefix,
compression, and how the short last group is handled); (d) the header layout; (e) the lattice size,
axis ordering, sample type and **colour space and gamma** of the table; (f) the Amount rule. Useful
checks: a decoded 3D table of divisions `n` has `n^3 * 3` samples; an identity-like or near-identity
table (the first few lattice entries near black) shows the axis order and the gamma; the table
fingerprint in the attribute name is likely a hash of the decoded bytes, which gives an exact
correctness test for the decoder (compute MD5 of the decoded payload and compare with the 32 hex digits;
if it matches under a hypothesis, the hypothesis is right). That fingerprint check is the strongest
verification available and should be Task 8's first test.

I do not give a "proposal" decoder because I have no verified procedure to propose. Task 8 needs more
research (the DNG specification's section on RGB tables for camera profiles, and the XMP "Camera Raw settings"
schema) or must treat tables as an optional extra (decode if the fingerprint
check passes, otherwise ignore the table and apply the slider settings only).

---

## 11. `crs:` name mapping (what LightCraft reads)

From `CL crates/develop-model/src/crs.rs:182-445` (`to_partial`; `LC crates/engine/src/crs.rs` is the
same file). Values are plain numbers (a leading `+` and `a/b` fractions accepted), booleans are
`True`/`False`/`1`.

| `crs:` name | LightCraft setting | Notes |
|---|---|---|
| `Exposure2012` | `light.exposure` | EV |
| `Contrast2012`, `Highlights2012`, `Shadows2012`, `Whites2012`, `Blacks2012` | `light.contrast`, `.highlights`, `.shadows`, `.whites`, `.blacks` | -100..100 |
| `Exposure`, `Contrast`, `HighlightRecovery`, `FillLight`, `Shadows`, `Brightness` (older process) | approximated only if no `*2012` field exists: exposure = v; contrast = v - 25; highlights = -v; shadows = v; blacks = -(v - 5)*4; whites = (v - 50)*0.6 (each clamped to -100..100) | `crs.rs:201-220` |
| `Texture` | `effects.texture` | |
| `Clarity2012` (older: `Clarity`) | `effects.clarity` | |
| `Dehaze` | `effects.dehaze` | |
| `Vibrance`, `Saturation` | `color.vibrance`, `color.saturation` | |
| `WhiteBalance` | `wb.mode` (asShot, auto, daylight, cloudy, shade, tungsten, fluorescent, flash, else custom) | |
| `Temperature`, `Tint` | `wb.temp`, `wb.tint` (Kelvin) | For rendered files with `AsShotTemperature`: `r = (1e6/as_shot - 1e6/t) / 0.8`, then `K(r)` (section 6.9), tint minus `AsShotTint` (`crs.rs:241-263`) |
| `IncrementalTemperature`, `IncrementalTint` | the relative scale `r` for rendered files | `K(r)` |
| `ConvertToGrayscale` | `treatment` = bw / color | |
| `HueAdjustment{Red,Orange,Yellow,Green,Aqua,Blue,Purple,Magenta}` | `mixer.<band>.hue` | -100..100 |
| `SaturationAdjustment<Band>` | `mixer.<band>.sat` | |
| `LuminanceAdjustment<Band>` | `mixer.<band>.lum` | |
| `GrayMixer<Band>` | `bw_mix.<band>` | |
| `ParametricShadows`, `ParametricDarks`, `ParametricLights`, `ParametricHighlights` | `curve.shadows`, `.darks`, `.lights`, `.highlights` | |
| `ParametricShadowSplit`, `ParametricMidtoneSplit`, `ParametricHighlightSplit` | `curve.split_shadows`, `.split_mid`, `.split_highlights` | |
| `ToneCurvePV2012` (+ `Red`, `Green`, `Blue`) | `curve.master`, `.red`, `.green`, `.blue` | An `rdf:Seq` of `"x, y"` strings in 0..255, divided by 255; a straight 0,0 to 255,255 line = no curve; channel curves are read only when the master and all three channels are present (`crs.rs:316-331`). `ToneCurve` (older) used only when no `ToneCurvePV2012` |
| `CurveRefineSaturation` | `curve.refine_saturation` | |
| `SplitToningShadowHue`, `...ShadowSaturation`, `ColorGradeShadowLum` | `grading.shadows.hue/sat/lum` | |
| `SplitToningHighlightHue`, `...HighlightSaturation`, `ColorGradeHighlightLum` | `grading.highlights.hue/sat/lum` | |
| `ColorGradeMidtoneHue`, `ColorGradeMidtoneSat`, `ColorGradeMidtoneLum` | `grading.midtones.*` | |
| `ColorGradeGlobalHue`, `ColorGradeGlobalSat`, `ColorGradeGlobalLum` | `grading.global.*` | |
| `ColorGradeBlending`, `SplitToningBalance` | `grading.blending`, `grading.balance` | |
| `Sharpness`, `SharpenRadius`, `SharpenDetail`, `SharpenEdgeMasking` | `detail.sharpen_amount`, `_radius`, `_detail`, `_masking` | |
| `LuminanceSmoothing`, `LuminanceNoiseReductionDetail`, `LuminanceNoiseReductionContrast` | `detail.nr_luminance`, `_detail`, `_contrast` (the last is unused) | |
| `ColorNoiseReduction`, `ColorNoiseReductionDetail`, `ColorNoiseReductionSmoothness` | `detail.nr_color`, `_color_detail`, `_color_smoothness` | |
| `PostCropVignetteAmount`, `...Midpoint`, `...Roundness`, `...Feather`, `...HighlightContrast`, `...Style` | `vignette.amount`, `.midpoint`, `.roundness`, `.feather`, `.highlights`, `.style` | |
| `GrainAmount`, `GrainSize`, `GrainFrequency` | `grain.amount`, `grain.size`, `grain.roughness` | Note: `GrainFrequency` is the roughness |
| `ShadowTint`, `RedHue`, `RedSaturation`, `GreenHue`, `GreenSaturation`, `BlueHue`, `BlueSaturation` | `calibration.*` | |
| `Look` (struct), `CameraProfile`, `RGBTable`, `Table_*` | **not carried over** (reported as unmapped) | section 10 |

Not adjustments, ignored (`crs.rs:42-82`): `Version`, `ProcessVersion`, `Name`, `ShortName`, `Group`, `UUID`,
`PresetType`, `SupportsAmount`, `SupportsAmount2`, `SupportsColor`, `SupportsMonochrome`, `RequiresRGBTables`,
`Cluster`, `SortName`, `Description`, `AsShotTemperature`, `AsShotTint`, `CameraProfileDigest`, etc.

Control ranges and defaults (`CL develop-model/src/controls.rs:150-300`): exposure -5..5 (0.01);
contrast, highlights, shadows, whites, blacks, texture, clarity, dehaze, vibrance, saturation, all mixer and
B&W sliders, curve region amounts: -100..100, 0; `curve.split*`: 10..70 / 20..80 / 30..90, defaults 25 / 50 /
75; `refineSaturation` 0..100, 100; `grading.*.hue` 0..360, `.sat` 0..100, `.lum` -100..100, blending 0..100 (50),
balance -100..100 (0); `wb.temp` 2000..50000 (6500), `wb.tint` -150..150; vignette amount -100..100,
midpoint 0..100 (50), roundness -100..100, feather 0..100 (50), highlights 0..100; grain amount 0..100,
size 0..100 (25), roughness 0..100 (50); sharpening 0..150 (0), radius 0.5..3 (1.0), detail 0..100 (25),
masking 0..100; noise reduction luminance 0..100, detail 0..100 (50), colour 0..100, colour detail 0..100 (50),
smoothness 0..100 (50); `profile.amount` 0..200 (100).

---

## 12. Gaps and cautions for the implementers

1. **Highlights and Shadows are neighbourhood-dependent in LightCraft** (sections 4, 6.3). A 3D LUT
   cannot reproduce them. Decision needed: bake the pixel-only proposal, or move them to the shader.
2. **Sensitivity to the sRGB port (a judgement, not measured):** the tools that shift most when the
   Rec.2020/OkLab-tuned constants are used in sRGB are those with chroma thresholds, in this order:
   vibrance (`C/0.22`), mixer (`chroma_w = C/0.12`), B&W mix (`C/0.2`), then grading wheel strengths (0.09),
   then the rest. Constants are thresholds on OkLab chroma C, which does not depend on the working space;
   the risk comes from out-of-gamut clipping and from the luma weights and tone-map stage that run before
   OkLab. Do not rescale the constants.
3. **Everything is in linear Rec.2020 with OkLab(Rec.2020)**. If e-Layout works in sRGB primaries, the
   matrices change (section 3) and the ported constants (for example 0.22 and 0.12 in the chroma terms)
   were tuned for LightCraft's space; results will be close but not identical. Tests should compare
   behaviour, not byte equality with LightCraft.
3. **The curves run on encoded values, the colour block and tone map on linear light.** The 3D LUT must
   therefore be indexed in a way that survives the tone map's linear-light domain: sample in sRGB-encoded
   space and decode inside the bake (**proposal, not from LightCraft**), 33 points per axis at least.
4. **Dehaze needs an image-wide airlight** (99.5th percentile of a blurred dark channel): compute it once
   per photo from a reduced copy.
5. **Texture, clarity, sharpening and noise reduction need blurred log-luminance planes** at sigmas that are
   fractions of the long edge (0.18 %, 1.2 %, 2 %, and the sharpening Radius in original pixels): the shader
   needs multi-pass blur or a mip chain.
6. **Grain hash uses 32-bit integer ops**: replace with a float hash in the shader (section 8.9).
7. **Colour noise reduction (latest) is the joint multi-scale method** and is large; use the legacy chroma
   blur (section 8.7).
8. **LuminanceNoiseReductionContrast is not implemented in LightCraft.**
9. **Adobe `RGBTable` decoding is not in LightCraft** (section 10); Task 8 starts from the facts in 10.2 and
   the MD5-fingerprint check in 10.3, and should expect to do original reverse-engineering of the sample
   files (allowed for manual checks; no sample data may enter the repository).
10. Test vectors in this file (sections 6.4 to 8.8) come from a Python transliteration of the Rust
    formulas that I wrote to check the arithmetic. I did not build or run LightCraft. They are consistent
    with my reading of the code, not with an execution of it; a guard test written from them should say
    so.
