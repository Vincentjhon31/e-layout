# Develop spike: shader, blur and LUT (Task 3)

Throwaway spike (branch `spike/develop`, deleted). Flutter 3.44.1. One fragment shader with three samplers (image, blurred copy, 33-size LUT packed `size*size` wide, `size` high), `src + amount*(src-blur)`, then a trilinear LUT lookup (two bilinear lookups on the b slices, mixed). Test image: generated 2048 px gradient plus checker plus lines. Windows machine: the build laptop (integrated GPU). Web: Chrome with the default CanvasKit renderer, run with a GPU (a headless run with software GL also worked, but its timings are meaningless).

## Results

| Question | Result |
|---|---|
| `FragmentProgram.fromAsset` in `flutter test` (widget test, `runAsync`, `toImage`, read pixels) | Works. Loads, renders, pixels non-trivial. Runs in about 2 s. |
| Windows (profile) | Runs. |
| Web (`flutter run -d chrome --profile`, and the release build `flutter build web --release --base-href /app/`) | Runs. `flutter run` printed no console lines, so the profile build was built with `flutter build web --profile` and served locally. Profile and release give the same pixels. No `--wasm` build tried. |
| Android | **Pending.** No phone attached. Owner to try a debug APK later. |
| Pixels, Windows vs web | A 32x32 grid sample (3072 channel values) of the 2048 px output is identical (max difference 0). Whole-image hashes differ (Windows `ba7910f0`, web `97fe7ce0`), so some pixels differ somewhere by a small amount (not located; the tile/blur comparison below shows differences of 1 to 3 levels between blur paths). Not a visible difference. |

## Timings (profile / release)

| Measure | Windows profile | Web (profile, release) |
|---|---|---|
| Bake LUT 17 (40 multiply-adds per colour) | 1.2 ms (+1.5 ms to image) | 0.7 / 1.8 ms (+8 / 18 ms) |
| Bake LUT 33 | 4.7 ms (+7.9 ms) | 4.2 / 11.7 ms (+8 / 16 ms) |
| Bake LUT 65 | 39 ms (+4.8 ms) | 38 / 33 ms (+11 / 9 ms) |
| One shader frame at 2048 px, offscreen `toImage` | 44.6 ms (readback of 16 MB: 20.8 ms) | 49 / 52 ms (readback 13 / 17.5 ms) |
| On-screen slider animation (300 px high strip, 3 s) | 61 fps, raster median 1.2 ms, p90 2.2 ms | 59 fps, raster median 0.8 / 0.9 ms |
| `ImageFilter.blur` 2048 px, sigma 2 / 20 / 80 | 65 / 81 / 64 ms | 56 / 52 / 47 ms, release 72 / 70 / 89 ms |
| Same, downscale 4x, blur at sigma/4, upscale | 93 / 59 / 52 ms | 148 / 95 / 109 ms |
| Difference of downscaled blur from direct blur (mean / max levels) | 0.68 / 42, 0.48 / 6, 0.51 / 3 | similar |
| 6000x4000 whole-image reference (blur 20 + shader) | 720 ms | 2293 / 1503 ms |
| 6000x4000 as 12 tiles of 2048 with 96 px margin (render, then with stitch) | 1105 ms, then 1473 ms | 1614 / 2226 ms, then 2576 / 2949 ms |

Tile seams: stitched result against the whole-image render has a largest difference of 3 levels out of 255 (85808 of 24 million pixels differ by more than 1). The largest difference at the seams (3 columns or rows either side) is also 3, so the seams are no worse than the rest. No visible seam at sigma 20 with a 96 px margin. The margin must stay larger than about 3 sigma (96 px covers sigma up to about 30; larger blur radii need a larger margin or a blur on the downscaled whole image).

The numbers above that use `toImage` include picture recording and texture creation, so they overstate one on-screen frame (the on-screen raster time is 1 to 2 ms for a small preview).

## Decisions

- **Shader test runner: `flutter test`.** It loads the shader and renders it, so Task 9's shader tests use widget tests with `tester.runAsync`, `toImage` and `toByteData`. No `integration_test` needed. Compare with a tolerance (a few levels), not exact hashes, as the test renderer may differ from the GPU.
- **LUT size while dragging: 17. After release: 33.** The 33-size bake alone is 4.7 ms on Windows, below the 16 ms line, but with the upload it is about 13 ms, and a mid-range phone is likely 3 to 5 times slower, which crosses 16 ms. Revisit with the phone numbers (if 33 stays under 16 ms there, drag at 33). 65 is never used (39 ms).
- **Blur: no downscale-blur-upscale for large sigma.** Direct `ImageFilter.blur` on a 2048 px image takes about the same time at sigma 2, 20 and 80 (50 to 90 ms), and the downscale route is slower on the website and mixed on Windows, with extra error. Revisit on the phone: if sigma 80 is much slower than sigma 20 there, add the downscale for sigma above about 40.
- **Web renderer:** the default CanvasKit renderer (what `flutter build web --release --base-href /app/` makes) shows the shader. Nothing extra is needed. Only the plain JavaScript build was tried.
- **Stop condition:** not triggered. Windows and the website both run the shader, so Task 9 can go ahead. Android is pending a phone.
- **Speed against the targets (estimate, not measured on a phone):**
  - Slider preview: on-screen frames cost 1 to 2 ms of raster time on Windows and web, with 60 fps, so a mid-range phone at about 10 times that is still above 20 fps. Lower risk, confirm on the phone.
  - 24 MP save: the GPU part (blur and shader on 12 tiles) was 1.1 to 1.5 s on Windows and 1.6 to 2.2 s on the website. JPEG decode and encode were not measured here. Nothing so far points to a miss by half or double, but a phone with a weaker GPU and 3 to 5 times the cost would reach 5 to 8 s for the GPU part alone. Bring the phone number before Task 4 if the debug APK shows that.

## For the owner

Android is the open item: run the spike on a phone (debug APK) to settle the LUT size while dragging, the blur rule and the two speed targets.
