# Photo editing, Phases 0 and 1 (study, spike, editor, preset import) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Keep the **Handoff notes** at the bottom current after every task: another session resumes from them.

**Goal:** e-Layout 1.1.0. Staff edit JPEG and PNG photos inside e-Layout with Lightroom's main tools, apply a preset to the whole batch, change single photos on top of it, import their Lightroom presets (including creative-profile colour tables), and keep the batch and its edits until they clear it. Everything works offline on Android, Windows and the website.

**Architecture:**
- Edits are data. A `SettingsPatch` (partial settings) is the unit for presets, the shared preset and each photo's own changes. `EditSettings` is the resolved result.
- Every global colour operation is written **once**, in pure Dart (`ColorPipeline`), and baked into a 3D lookup table (LUT).
- One fragment shader (`shaders/develop.frag`) applies the local effects (texture, clarity, dehaze, sharpening, noise reduction), then the LUT, then vignette and grain.
- The same `PhotoDeveloper` draws the editor preview, the Home thumbnails and the full-size save, inside the existing tiled exporter, with overlapping tiles.
- Lightroom files are parsed in Dart and mapped to `SettingsPatch`.
- The batch is kept per platform: files, IndexedDB, or memory in tests.

**Tech Stack:** Flutter 3.44.1 / Dart 3.12.1, `dart:ui` `FragmentProgram` and `ImageFilter.blur`, `package:xml` (new), `archive` (already in), the existing store pattern (`*_io.dart` / `*_web.dart` / `*_memory.dart` chosen by conditional import), REA for the Lightroom Mobile study, LightCraft (Rust, "MIT OR Apache-2.0") as the formula reference.

**Spec:** `docs/superpowers/specs/2026-11-23-photo-editing-design.md`. Read it first. This plan covers its Phase 0 and Phase 1. Crop (Phase 2), RAW (Phase 3) and matching Lightroom (Phase 4) get their own plans after Task 3's results.

## Global Constraints

- Work only inside `C:\Windows_Applications\REA_Projects\Re_Canva\pio_photo_layout\`. Clone LightCraft and keep every REA output in the session scratchpad, never in the project.
- The sample pack `C:\Windows_Applications\REA_Projects\Re_Canva\LightroomVintageVibeFree\` is third-party ("Copyright Presetpro INC"). Read it for manual checks only. Never copy it, or any part of it, into the repository, the app, the tests or the notes. Tests use files the builder writes.
- No Adobe code, shaders, icons, images, preset packs or branding in e-Layout. "Lightroom" appears only where it describes compatibility ("Import a Lightroom preset"). REA findings are facts (names, ranges, behaviour), never copied code or assets.
- Formulas ported from LightCraft are credited: its NOTICE goes into the app's licences (Task 19). The "Lightroom" name and Adobe's file formats are only read, never written.
- No real people's photos, citizens' data, the owner's email, keys or tokens anywhere in the project tree, tests, goldens or notes. Test images are generated in code (gradients, checkerboards, noise, flat patches). The only existing photo asset is `test/assets/exif_rotated_6.jpg`.
- Dart: `dart:io` only in `*_io.dart`; `package:web` and `dart:js_interop` only in `*_web.dart`; choose with conditional imports (Part 3 rule). Add packages with `flutter pub add <name>`, and read a package's source in `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\` before using its API.
- The photo path never imports `lib/online/`. That includes `lib/core/develop/`, `lib/core/presets/`, the stores and `lib/features/develop/`. `test/offline/no_network_imports_test.dart` enforces it (Task 19 adds the new folders).
- Tests first: write the test, run it, see it fail, implement, see it pass. A guard test that passes on its first run is allowed; say so in the notes.
- Every task that changes Dart ends with `flutter analyze` reporting "No issues found!" and `timeout 2400 flutter test --timeout 30s` reporting "All tests passed!".
  - Read the first failure only.
  - Use the `etest`/`ptest` helpers (`test/features/editor/editor_screen_test.dart:78`, `test/features/editor/panels_test.dart:60`) for widget tests that can leave timers.
  - Create futures and decode images inside `tester.runAsync`.
- Screens get goldens: phone 390x844 at DPR 2 and wide 1280x800 at DPR 1, light and dark (`test/ui/golden_helpers.dart`). Open them with the Read tool and judge them as a designer:
  - simple, clean, iOS-like, using the Part 2 tokens (`docs/superpowers/plans/2026-11-15-part2-app.md`, section "Design");
  - nothing clipped, touch targets of 44 pt or more, readable contrast.

  Fix what looks wrong before ticking, and write in the notes what you saw.
- Wording: plain words, sentence case, no exclamation marks, no jargon. Labels use the app's existing British spelling ("Colour", as in the layout editor's tiles). Text shared by every platform says "this {deviceNoun}" (`lib/platform/device_noun.dart`).
- The build laptop has about 1 GB of free RAM. Run one `flutter`, Gradle, MSBuild or headless-Chrome command at a time, with generous timeouts. Run long builds with `run_in_background`. Stop every program you start.
- Shell: `cd` explicitly or use absolute paths, and quote paths (the user folder name has a space). Write files with the Write tool.
- Git: work on branch `feature/photo-editing`, and commit at the end of every task. End every commit message with these two lines:
  ```
  Co-Authored-By: Claude Opus 5.5 (the noreply address Anthropic gives)
  Claude-Session: https://claude.ai/code/session_0173zfBAdymYyN846CJGK4tq
  ```
  Never push. Never touch the Obsidian vault's repository.
- Unattended runs: use only the usage thresholds the owner names for that run (read `C:\Windows_Applications\REA_Projects\Re_Canva\.claude\usage-latest.json`). Over the line: start nothing new, leave the project analyze-clean, write the notes, stop. Never shut down or restart the computer unless the owner asked for it in that run.

## Review Focus

1. **Big photos on a small phone.** A 48 MP JPEG saved with clarity, noise reduction and grain turned on, on the engine-clamped path (`forcePixelPath`). Saving must finish, or stop with the existing memory line, never crash. Test in Task 10.
2. **Presets from other Lightroom versions.** Unknown `crs:` fields are ignored; values like `"+1.0"`, `"-0"` and `"+20"` parse; process version below 10 adds the older-Lightroom line. Tests in Task 11.
3. **A kept photo that vanished.** The OS cleared app storage, or the browser evicted IndexedDB. The cell shows "Can't open this file." and everything else still restores. Test in Task 14.
4. **The same preset imported twice, and a profile imported after its preset.** No duplicates (same UUID replaces), and the waiting preset links to the profile. Tests in Task 11 and Task 14.
5. **EXIF-rotated photos.** Vignette centre, grain and tile origin are in upright coordinates, so preview and save match for `test/assets/exif_rotated_6.jpg`. Test in Task 10.

---

### Task 0: Start

**Files:** none.

- [ ] **Step 1:** `cd` to the project and run `git status --short`. If anything is listed (on 2026-11-23 the owner's unfinished 1.0.1 changes were: `assets/whats_new.md`, `lib/app_info.dart`, `pubspec.yaml`, two tests, a golden), **stop and ask the owner** whether to commit them as 1.0.1 first. Do not commit or discard them yourself.
- [ ] **Step 2:** `git switch -c feature/photo-editing`.
- [ ] **Step 3:** Run `flutter analyze` and the full test suite. Record the baseline counts in the Handoff notes.

### Task 1: LightCraft reading notes

**Files:**
- Create: `docs/superpowers/notes/lightcraft-notes.md`

- [ ] **Step 1:** Shallow-clone `https://github.com/storytold/lightcraft` into the scratchpad (`git clone --depth 1`). Record the commit hash. Read `LICENSE-*` and `NOTICE`, and confirm "MIT OR Apache-2.0".
- [ ] **Step 2:** From the `develop`, `color`, `raster` and `pipeline` crates, write down the following, each with its file and line:
  - the **order of operations**;
  - the working colour space;
  - the **formula** for every tool in Task 4's `Setting` table: exposure, contrast pivot, highlights, shadows, whites, blacks, parametric curve, point curves, temperature and tint for non-RAW images, vibrance, saturation, the HSL mixer (the hue centres of the 8 bands and their falloff), colour grading (including blending and balance), the B&W mix, texture, clarity, dehaze, vignette, grain, sharpening and noise reduction;
  - how it decodes Adobe `crs:Table_*` / `RGBTable` data, and how a profile's `Amount` is applied, including where the table sits in the order;
  - its `crs:` name mapping.
- [ ] **Step 3:** Note any third-party crate that a formula you will port came from, and its licence. Stop and ask the owner if one is GPL or LGPL.
- [ ] **Step 4:** Commit the notes (`docs: LightCraft formula notes`).

### Task 2: Lightroom Mobile study (REA; does not block later tasks)

**Files:**
- Create: `docs/superpowers/notes/lightroom-study.md`

- [ ] **Step 1:** Get the APK.
  - If `mcp__rea__list_adb_devices` shows a phone with Lightroom installed (`com.adobe.lrmobile`): `pull_adb_package` into the scratchpad.
  - Else, if the owner has put an APK file somewhere, use it.
  - Else write "Not done: no phone or APK" in the notes, skip to Step 4, and carry on with Task 3.
- [ ] **Step 2:** Use the `reverse-engineer-anything` skill. With `inspect_android_package`, `decode_android_resources`, `search_android_classes` and `inspect_android_method`, record:
  - the edit tool list and its order, and the panel groups;
  - each slider's label, range, default and step (compare with Task 4's table);
  - the gestures: double-tap to reset, hold to compare;
  - the groups in the copy-settings dialog;
  - how presets and profiles are imported, and which `crs:` fields Lightroom writes.

  If the phone is attached, also take `capture_adb_screen` screenshots of the edit panels. Keep them in the scratchpad only.
- [ ] **Step 3:** Write the facts only, plus a "Differences from Task 4's table" list. Any range that differs gets fixed in Task 4 (or in a follow-up commit, if Task 4 is already done).
- [ ] **Step 4:** Commit (`docs: Lightroom Mobile study notes`).

### Task 3: Spike: shader, blur and LUT on Windows, the website and Android (throwaway)

**Files:** a throwaway branch `spike/develop` off `feature/photo-editing`. Only `docs/superpowers/notes/develop-spike.md` is kept, committed on `feature/photo-editing`.

- [ ] **Step 1:** On the spike branch, write a minimal `shaders/develop.frag`:
  - one sampler for the image, one for a 33-size LUT laid out as in Task 7, and one for a blurred copy;
  - it adds `amount * (src - blur)` and then looks the result up in the LUT.

  Declare it under `flutter: shaders:` in `pubspec.yaml`. Write a screen that shows a generated 2048 px gradient-plus-checker image through it, with one slider.
- [ ] **Step 2:** Answer each question below with a measured fact:
  1. Does `ui.FragmentProgram.fromAsset` load and render inside `flutter test` (widget test, `toImage`, read pixels)? If not, does it under `flutter test integration_test -d windows`?
  2. Do the output pixels match across Windows (`flutter run -d windows --profile`), the website (`flutter run -d chrome --profile` and the release web build with Part 3's flags) and Android? Android needs a phone; if none is attached, write "pending" and ask the owner to try the debug APK.
  3. Timing, in profile mode:
     - baking a 17-, 33- and 65-size LUT in Dart (with a `ColorPipeline` stand-in that does 40 multiply-adds per colour);
     - one shader frame at 2048 px;
     - `ImageFilter.blur` at sigma 2, 20 and 80 on a 2048 px image;
     - rendering a 6000x4000 image as 2048 px tiles with a 96 px margin.
  4. Can tiles with a margin be stitched without a visible seam?
- [ ] **Step 3:** Write `develop-spike.md` with the numbers and these decisions, which later tasks read:
  - **Shader test runner:** `flutter test` or `integration_test`.
  - **LUT size while dragging** (17 if a 33-size bake takes more than 16 ms) and after release (33).
  - **Blur:** whether large sigma needs a downscale-blur-upscale.
  - **Web renderer:** what the website needs to show the shader.
  - **Stop condition:** if Windows or the website can't run the shader at all, stop and bring it to the owner before Task 9.
  - **Speed against the spec's targets:**
    - slider preview at 20 fps or better on a mid-range Android phone;
    - a full-size 24 MP JPEG save with every tool on in about 4 s.

    Estimate from the spike's timings. If the phone numbers miss these badly (half the frame rate, or double the save time), bring it to the owner before Task 4.
- [ ] **Step 4:** Delete the spike branch's code (`git switch feature/photo-editing`, keep only the notes), commit the notes (`docs: develop spike results`), and delete branch `spike/develop`.

### Task 4: Settings model

**Files:**
- Create: `lib/core/develop/settings.dart`
- Test: `test/core/develop/settings_test.dart`

**Interfaces:**
- Produces:
  - `enum ToolGroup { light, colour, effects, detail }`
  - `enum Setting` with fields `ToolGroup group`, `double min`, `double max`, `double neutral` and `String crs`
  - `enum CurveChannel { master, red, green, blue }` with `String crs`
  - `class CurvePoint { final int x, y; }` (0–255)
  - `class ProfileRef { final String id; final String name; final double amount; static const none; bool get isNone; }` (`amount` 0–2, 1 = 100 %; `none` has `id == ''`)
  - `class SettingsPatch` with:
    - fields `Map<Setting, double> values`, `Map<CurveChannel, List<CurvePoint>> curves`, `ProfileRef? profile`, `bool? grayscale`, `Map<String, String> extras` (unparsed `crs:` values kept for later phases, e.g. `Temperature`, `Tint`, `WhiteBalance`);
    - methods `SettingsPatch over(SettingsPatch top)` (top wins per key), `SettingsPatch only(Set<ToolGroup> g)`, `SettingsPatch without(Set<ToolGroup> g)`, `bool get isEmpty`, `Map<String, dynamic> toJson()`, `factory SettingsPatch.fromJson(Map<String, dynamic>)`.
  - `class EditSettings` with `factory EditSettings.resolve(List<SettingsPatch> layers)` (neutral first, then each layer), `double operator [](Setting s)`, `List<CurvePoint> curve(CurveChannel c)` (default `[(0,0),(255,255)]`), `ProfileRef profile`, `bool grayscale`, `bool get isNeutral`, `SettingsPatch toPatch()` (every setting explicit), `String get key` (a stable hash string for caches).
  - Group membership: curves are in `light`; `profile` and `grayscale` are in `colour`.

The `Setting` values (exact; Task 2 may correct a range):

| Group | name (crs) min..max neutral |
|---|---|
| light | `exposure` (Exposure2012) −5..5 0; `contrast` (Contrast2012), `highlights` (Highlights2012), `shadows` (Shadows2012), `whites` (Whites2012), `blacks` (Blacks2012) −100..100 0; `curveHighlights` (ParametricHighlights), `curveLights` (ParametricLights), `curveDarks` (ParametricDarks), `curveShadows` (ParametricShadows) −100..100 0; `curveShadowSplit` (ParametricShadowSplit) 5..95 25; `curveMidtoneSplit` (ParametricMidtoneSplit) 5..95 50; `curveHighlightSplit` (ParametricHighlightSplit) 5..95 75 |
| colour | `temperature` (IncrementalTemperature), `tint` (IncrementalTint), `vibrance` (Vibrance), `saturation` (Saturation) −100..100 0; for each of Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta: `hueRed` (HueAdjustmentRed), `satRed` (SaturationAdjustmentRed), `lumRed` (LuminanceAdjustmentRed), `grayRed` (GrayMixerRed) −100..100 0 (32 settings); `gradeShadowHue` (SplitToningShadowHue) 0..360 0; `gradeShadowSat` (SplitToningShadowSaturation) 0..100 0; `gradeShadowLum` (ColorGradeShadowLum) −100..100 0; `gradeMidHue` (ColorGradeMidtoneHue) 0..360 0; `gradeMidSat` (ColorGradeMidtoneSat) 0..100 0; `gradeMidLum` (ColorGradeMidtoneLum) −100..100 0; `gradeHighHue` (SplitToningHighlightHue) 0..360 0; `gradeHighSat` (SplitToningHighlightSaturation) 0..100 0; `gradeHighLum` (ColorGradeHighlightLum) −100..100 0; `gradeGlobalHue` (ColorGradeGlobalHue) 0..360 0; `gradeGlobalSat` (ColorGradeGlobalSat) 0..100 0; `gradeGlobalLum` (ColorGradeGlobalLum) −100..100 0; `gradeBlending` (ColorGradeBlending) 0..100 50; `gradeBalance` (SplitToningBalance) −100..100 0 |
| effects | `texture` (Texture), `clarity` (Clarity2012), `dehaze` (Dehaze) −100..100 0; `vignetteAmount` (PostCropVignetteAmount) −100..100 0; `vignetteMidpoint` (PostCropVignetteMidpoint) 0..100 50; `vignetteRoundness` (PostCropVignetteRoundness) −100..100 0; `vignetteFeather` (PostCropVignetteFeather) 0..100 50; `vignetteHighlights` (PostCropVignetteHighlightContrast) 0..100 0; `grainAmount` (GrainAmount) 0..100 0; `grainSize` (GrainSize) 0..100 25; `grainRoughness` (GrainFrequency) 0..100 50 |
| detail | `sharpenAmount` (Sharpness) 0..150 0; `sharpenRadius` (SharpenRadius) 0.5..3 1; `sharpenDetail` (SharpenDetail) 0..100 25; `sharpenMasking` (SharpenEdgeMasking) 0..100 0; `noiseLuminance` (LuminanceSmoothing) 0..100 0; `noiseDetail` (LuminanceNoiseReductionDetail) 0..100 50; `noiseContrast` (LuminanceNoiseReductionContrast) 0..100 0; `noiseColour` (ColorNoiseReduction) 0..100 0; `noiseColourDetail` (ColorNoiseReductionDetail) 0..100 50; `noiseColourSmoothness` (ColorNoiseReductionSmoothness) 0..100 50 |

`CurveChannel.crs`: `ToneCurvePV2012`, `ToneCurvePV2012Red`, `ToneCurvePV2012Green`, `ToneCurvePV2012Blue`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('84 settings, every neutral inside its range, crs names unique', () {
  expect(Setting.values.length, 84);
  for (final s in Setting.values) {
    expect(s.neutral, inInclusiveRange(s.min, s.max));
  }
  expect(Setting.values.map((s) => s.crs).toSet().length, 84);
});
test('resolve: neutral, then layers in order, top wins', () {
  final a = SettingsPatch(values: {Setting.exposure: 1, Setting.contrast: 20});
  final b = SettingsPatch(values: {Setting.exposure: -0.5});
  final s = EditSettings.resolve([a, b]);
  expect(s[Setting.exposure], -0.5);
  expect(s[Setting.contrast], 20);
  expect(s[Setting.gradeBlending], 50);
});
test('only/without split by group; curves are light, profile and grayscale are colour', () {
  final p = SettingsPatch(
      values: {Setting.exposure: 1, Setting.vibrance: 10},
      curves: {CurveChannel.red: [CurvePoint(0, 0), CurvePoint(255, 250)]},
      profile: ProfileRef('u1', 'Look', 0.5),
      grayscale: true);
  final light = p.only({ToolGroup.light});
  expect(light.values.keys, [Setting.exposure]);
  expect(light.curves.keys, [CurveChannel.red]);
  expect(light.profile, isNull);
  expect(p.without({ToolGroup.light}).grayscale, true);
});
test('JSON round trip keeps everything, including extras and ProfileRef.none', () { ... expect(back.toJson(), p.toJson()); });
test('unknown setting names in JSON are skipped, values are clamped to range', () { ... });
test('isNeutral and key', () {
  expect(EditSettings.resolve([]).isNeutral, true);
  expect(EditSettings.resolve([SettingsPatch(values: {Setting.exposure: 0.1})]).key,
      isNot(EditSettings.resolve([]).key));
});
```

- [ ] **Step 2:** Run `flutter test test/core/develop/settings_test.dart`. Expected: FAIL (file not found).
- [ ] **Step 3:** Implement `lib/core/develop/settings.dart`. JSON uses the `Setting` enum names as keys: `{"values": {"exposure": 1.0}, "curves": {"red": [[0,0],[255,250]]}, "profile": {"id":"…","name":"…","amount":0.5} | null, "grayscale": true | null, "extras": {}}`.
- [ ] **Step 4:** Run the test. Expected: PASS. Then run analyze and the full suite.
- [ ] **Step 5:** Commit (`feat(develop): settings model`).

### Task 5: Batch look (shared preset, per-photo changes, copy to all)

**Files:**
- Create: `lib/core/develop/batch_look.dart`
- Test: `test/core/develop/batch_look_test.dart`

**Interfaces:**
- Consumes: Task 4.
- Produces: `class BatchLook` (immutable) with:
  - fields `SettingsPatch shared`, `String? sharedName`, `Map<int, SettingsPatch> photos`;
  - `EditSettings settingsFor(int id)`, `bool hasOwnChanges(int id)`;
  - `BatchLook withPresetForAll(SettingsPatch? patch, String? name)`;
  - `BatchLook withPhotoPatch(int id, SettingsPatch p)` (merges `p` over that photo's overrides);
  - `BatchLook resetPhoto(int id)`, `BatchLook withoutPhoto(int id)`;
  - `BatchLook copyToAll(int fromId, Set<ToolGroup> groups, {required bool keepSingle})`;
  - `Map<String, dynamic> toJson()`, `factory BatchLook.fromJson(...)`.

Rules (from the spec):
- Overrides **replace** the shared value per setting.
- `withPresetForAll` replaces `shared` entirely (a `null` patch means "None") and keeps every photo's overrides.
- `copyToAll`:
  - the shared preset becomes `shared.over(settingsFor(fromId).toPatch().only(groups))`, and `sharedName` becomes `null` (Home then shows "Custom");
  - the source photo's overrides lose those groups;
  - other photos keep their overrides when `keepSingle`, and lose those groups when it's off.
- Empty patches are removed from `photos`.

- [ ] **Step 1: Write the failing tests.**

```dart
test('an override survives a later change of the shared preset', () {
  var look = const BatchLook().withPresetForAll(SettingsPatch(values: {Setting.exposure: 0}), 'A');
  look = look.withPhotoPatch(7, SettingsPatch(values: {Setting.exposure: 0.3}));
  look = look.withPresetForAll(SettingsPatch(values: {Setting.exposure: 0.5}), 'B');
  expect(look.settingsFor(7)[Setting.exposure], 0.3);
  expect(look.settingsFor(8)[Setting.exposure], 0.5);
  expect(look.hasOwnChanges(7), true);
  expect(look.hasOwnChanges(8), false);
});
test('copy to all, keeping single-photo changes', () {
  var look = const BatchLook()
      .withPhotoPatch(1, SettingsPatch(values: {Setting.exposure: 1, Setting.sharpenAmount: 40}))
      .withPhotoPatch(2, SettingsPatch(values: {Setting.exposure: -1}));
  look = look.copyToAll(1, {ToolGroup.light}, keepSingle: true);
  expect(look.settingsFor(3)[Setting.exposure], 1);
  expect(look.settingsFor(3)[Setting.sharpenAmount], 0); // detail not copied
  expect(look.settingsFor(2)[Setting.exposure], -1);
  expect(look.settingsFor(1)[Setting.sharpenAmount], 40);
  expect(look.photos[1]!.values.containsKey(Setting.exposure), false);
  expect(look.sharedName, isNull);
});
test('copy to all with the switch off clears other photos in the copied groups only', () { ... });
test('reset removes only that photo\'s overrides', () { ... });
test('JSON round trip', () { ... });
```

- [ ] **Step 2:** Run the test. Expected: FAIL.
- [ ] **Step 3:** Implement `batch_look.dart`.
- [ ] **Step 4:** Run the test. Expected: PASS. Then run analyze and the suite.
- [ ] **Step 5:** Commit (`feat(develop): batch look`).

### Task 6: Colour pipeline (the global tools, in Dart)

**Files:**
- Create: `lib/core/develop/color_pipeline.dart`, `lib/core/develop/profile_table.dart`
- Test: `test/core/develop/color_pipeline_test.dart`

**Interfaces:**
- Consumes: Task 4; Task 1's formulas and order.
- Produces:
  - `class ProfileTable` with `final int size`, `final Float32List rgb` (`size³ × 3`, index `((b*size + g)*size + r)*3`, sRGB-encoded 0–1 in and out), `(double, double, double) sample(double r, double g, double b)` (trilinear) and `static ProfileTable identity(int size)`.
  - `class ColorPipeline` with `ColorPipeline(EditSettings s, {ProfileTable? profile})`, `bool get isIdentity` and `(double, double, double) apply(double r, double g, double b)` (sRGB-encoded 0–1 in and out, clamped).
  - `const double kContrastPivot` (linear; from Task 1).
  - Helpers `double srgbToLinear(double v)`, `double linearToSrgb(double v)`, `double hueOf(double r, double g, double b)` (degrees).
- The pipeline covers every `light` and `colour` setting plus the profile. `effects` and `detail` are the shader's job (Task 9), except where Task 1 shows one is global.
- Profile amount: `out = in + amount × (table(in) − in)`, clamped. Amount 2 exaggerates, as Lightroom does. The table's position in the order comes from Task 1.

- [ ] **Step 1: Write the failing tests** (`rng = Random(1)`; tolerance `t = 0.5/255` unless stated):

```dart
test('neutral changes nothing', ...);              // 1000 random colours, |out-in| <= t
test('exposure +1 doubles linear light', ...);      // grey 0.4: srgbToLinear(out) ≈ 2*srgbToLinear(0.4) within 1 %
test('exposure -1 halves it', ...);
test('contrast keeps the pivot', ...);              // linearToSrgb(kContrastPivot) unchanged within 1/255 at ±100
test('contrast +100 darkens 0.2 and lifts 0.8', ...);
test('highlights -100 pulls 0.9 down more than 0.5', ...);
test('shadows +100 lifts 0.1 more than 0.5', ...);
test('whites -10 lowers white; blacks +25 lifts black', ...);
test('point curve passes through its points', ...); // master [(0,0),(115,126),(255,255)]: grey 115/255 -> 126/255 within t
test('red curve moves only red', ...);
test('parametric shadows -41 darkens 0.15 and leaves 1.0', ...);
test('temperature +50 warms grey; tint +50 turns grey magenta', ...); // r>in>b; g<r && g<b
test('saturation -100 and grayscale give grey', ...); // r==g==b within t
test('vibrance +100 boosts a dull colour more than a vivid one', ...);
test('mixer: red hue +100 turns red toward orange, blue untouched', ...); // hueOf in (5°,40°), blue within t
test('mixer: green saturation -100 greys green only', ...);
test('mixer: blue luminance +100 brightens blue', ...);
test('grading: shadows hue 240 sat 100 tints 0.1 grey blue, leaves 0.95 grey nearly neutral', ...);
test('profile: identity table at any amount changes nothing', ...);
test('profile: amount 0 changes nothing; amount 1 equals the table; amount 2 doubles the change', ...); // a test table that adds 0.1 to red
```

- [ ] **Step 2:** Run the test. Expected: FAIL.
- [ ] **Step 3:** Implement, following Task 1's order and formulas. Cite the LightCraft file in a one-line comment above each ported formula.
- [ ] **Step 4:** Run the test. Expected: PASS. Then run analyze and the suite.
- [ ] **Step 5:** Commit (`feat(develop): colour pipeline`).

### Task 7: LUT baking

**Files:**
- Create: `lib/core/develop/lut.dart`
- Test: `test/core/develop/lut_test.dart`

**Interfaces:**
- Consumes: `ColorPipeline` (Task 6).
- Produces: `class Lut3d` with `final int size` and `final Uint8List rgba` (image `size*size` wide and `size` high; the texel for indices r, g, b is at `x = r + b*size, y = g`; alpha 255), `(double, double, double) sample(double r, double g, double b)` (trilinear, the same maths as the shader), and `Lut3d bakeLut(ColorPipeline p, int size)`.

- [ ] **Step 1: Write the failing tests.** Identity bakes identity (each node within 1/255). Texel layout as above (check a few known nodes of a pipeline that zeroes green). Size-33 table vs pipeline within 2/255 on 500 random colours, with exposure 0.7, contrast 30, `hueRed` 40, `gradeShadowSat` 50 and a master curve.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS. Then run analyze and the suite.
- [ ] **Step 5:** Commit (`feat(develop): LUT baking`).

### Task 8: Adobe colour tables

**Files:**
- Create: `lib/core/presets/adobe_table.dart`
- Test: `test/core/presets/adobe_table_test.dart`, `test/core/presets/adobe_table_encoder.dart` (a test-only encoder, the inverse of the decoder)

**Interfaces:**
- Consumes: `ProfileTable` (Task 6); Task 1's notes on the encoding. If LightCraft doesn't decode tables, read Adobe's DNG SDK source (`dng_big_table.cpp`) and note its licence before porting.
- Produces: `ProfileTable decodeAdobeTable(String encoded)`. It converts the table to sRGB-encoded in and out if the data declares another space or gamma (note which in the notes). Bad input throws `FormatException("This colour table can't be read.")`.

- [ ] **Step 1: Write the failing tests.**
  - Encode an identity table and a "red +0.1" table of size 32 with the test encoder; decoding returns size 32 and values within 1/65535 of the originals.
  - Truncated or garbage text throws a `FormatException` with that exact message.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement the decoder, then the test encoder.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5: Manual check (not a test, nothing copied).** Write a throwaway script in the scratchpad that reads `crs:Table_<id>` from the sample pack's profile file (`…\Presetpro - Vintage Vibe 1.xmp`) and decodes it. Record in the notes the size, value range, declared space, and whether the result looks like a warm, faded "vintage" mapping (sample a few colours).
- [ ] **Step 6:** Commit (`feat(presets): decode Adobe colour tables`).

### Task 9: Develop shader and renderer

**Files:**
- Create: `shaders/develop.frag`, `lib/core/develop/photo_developer.dart` (the interface plus `CpuDeveloper`), `lib/core/develop/shader_developer.dart`
- Modify: `pubspec.yaml` (`flutter: shaders: - shaders/develop.frag`)
- Test: `test/core/develop/shader_developer_test.dart` (or `integration_test/`, per Task 3's runner decision), `test/core/develop/cpu_developer_test.dart`

**Interfaces:**
- Consumes: `EditSettings`, `ColorPipeline`, `bakeLut`, `ProfileTable`.
- Produces:
  - `abstract class PhotoDeveloper` with:
    - `Future<ui.Image> develop(ui.Image src, EditSettings s, {ProfileTable? profile, double scale = 1, ui.Offset origin = ui.Offset.zero, ui.Size? fullSize, int lutSize = 33})`
      - `scale`: render pixels per full-resolution photo pixel;
      - `origin`: where `src`'s top-left sits in the whole photo, in render pixels;
      - `fullSize`: the whole photo, in render pixels (defaults to `src`'s size).
    - `int margin(EditSettings s, double scale)`: the tile overlap, in render pixels.
  - `class ShaderDeveloper implements PhotoDeveloper` with `static Future<ShaderDeveloper> load()`.
  - `class CpuDeveloper implements PhotoDeveloper`: global colour only, through `ColorPipeline` per pixel, for tests; `margin` returns 0.
- Shader stages, in order: noise reduction (luminance and colour), sharpening (unsharp mask with Detail and Masking), texture, clarity, dehaze, then the LUT lookup, then vignette (centred on `fullSize`, using `origin`), then grain (hash noise keyed on full-resolution coordinates, `(origin + fragCoord) / scale`, so tiles and preview agree).
- Radii are in full-resolution pixels × `scale`. Blurred inputs come from `ui.ImageFilter.blur` (with the Task 3 downscale rule). Whole-photo values, such as dehaze's haze level, are measured once by the caller on a small copy and passed in through `EditSettings`-derived uniforms. Document the uniform layout in a comment at the top of both files, in the same order.

- [ ] **Step 1: Write the failing tests** (generated 256x256 images):

```dart
test('neutral settings return the input', ...);            // max |diff| <= 1/255
test('global tools match ColorPipeline', ...);             // exposure 0.7, contrast 30, hueRed 40: mean |shader - pipeline| <= 1.5/255
test('clarity +100 raises local contrast at a soft edge', ...);  // std-dev of a 32 px band around the edge goes up
test('sharpening raises the edge gradient', ...);
test('noise reduction lowers variance on a noise patch', ...);
test('vignette -100 darkens corners, not the centre', ...);
test('grain changes pixels but keeps the mean within 2/255', ...);
test('two tiles with margin() overlap equal one whole render', ...); // clarity 60, noiseLuminance 40, grain 30, vignette -40: max diff <= 2/255
test('CpuDeveloper equals ColorPipeline exactly on global tools', ...);
```

- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement the shader and `ShaderDeveloper`. Cache blurred inputs per (image identity, scale, sharpen radius), last two entries.
- [ ] **Step 4:** Run. Expected: PASS. Then run analyze and the suite.
- [ ] **Step 5:** Commit (`feat(develop): shader developer`).

### Task 10: Saving with edits

**Files:**
- Modify: `lib/core/export/photo_exporter.dart`
- Test: `test/core/export/photo_exporter_test.dart` (add)

**Interfaces:**
- Consumes: `PhotoDeveloper`.
- Produces: `PhotoExporter({this.tileSize = 2048, this.forcePixelPath = false, this.developer})`, plus `render(..., ExportSettings settings, {EditSettings? edit, ProfileTable? profile})`.
  - When `edit` is null or neutral, the output is byte-identical to today's.
  - Otherwise each tile is cut from the upright photo with `developer.margin(edit, 1)` extra on every side and developed with `origin` = the tile's position. The margin is cropped off, then the layout is drawn on top exactly as today. The `paintComposite` path and the clamped `forcePixelPath` path both go through this.
  - Dehaze's whole-photo value comes from a 512 px copy, measured once per photo.

- [ ] **Step 1: Write the failing tests.**
  - `edit: null` and neutral both give the same bytes as before (compare with an existing expected output).
  - Exposure +1 makes the saved centre pixel brighter.
  - **WYSIWYG:** the save, scaled down to 480 px, is within a mean of 3/255 of `developer.develop` on the 480 px preview, with `scale = 480 / longEdge`.
  - **EXIF:** `exif_rotated_6.jpg` with vignette −80. Corner pixels of the upright output are darker than its centre, in both the preview and the save.
  - **Big photo:** a 7200x4800 generated JPEG with `forcePixelPath: true`, clarity 50, noise 40, grain 30. The render completes. A thrown out-of-memory error still reaches `isMemoryFailure`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS. Then run analyze and the suite.
- [ ] **Step 5:** Commit (`feat(export): save photos with their edits`).

### Task 11: Lightroom preset import

**Files:**
- Create: `lib/core/presets/preset.dart`, `lib/core/presets/crs_map.dart`, `lib/core/presets/xmp_preset.dart`, `lib/core/presets/lrtemplate_preset.dart`, `lib/core/presets/dng_xmp.dart`, `lib/core/presets/preset_import.dart`
- Modify: `pubspec.yaml` (`flutter pub add xml`)
- Test: `test/core/presets/import_test.dart`, `test/core/presets/fixtures.dart` (builds the test files as strings and bytes)

**Interfaces:**
- Consumes: Task 4 (`Setting.crs`, `CurveChannel.crs`), Task 8.
- Produces:
  - `enum PresetKind { user, imported }`.
  - `class Preset` with `id`, `name`, `kind`, `DateTime created` and `SettingsPatch patch`. The id is `crs:UUID` when present, else 32 random hex characters.
  - `class Profile` with `id` (its `crs:UUID`), `name` and `ProfileTable table`.
  - `class ImportResult` with `List<Preset> presets`, `List<Profile> profiles` and `String line`.
  - `ImportResult importPresetFiles(List<(String name, Uint8List bytes)> files, {Map<String, Profile> known = const {}})`.

**What import does:**
- Files ending `.xmp`, `.dng`, `.lrtemplate` or `.zip` are read; anything else is ignored. Zips are opened, skipping `__MACOSX/`, `.DS_Store` and `._*`.
  - `.dng`: the first `<x:xmpmeta` … `</x:xmpmeta>` byte range is scanned for.
  - `.lrtemplate`: the Lua-style table `s = { … value = { settings = { … } } }` is parsed (strings, numbers, booleans, nested tables, flat number lists for curves).
- An `.xmp` with `crs:PresetType="Look"` is a profile: its UUID, its `crs:Name` alt text, and `crs:RGBTable` pointing to `crs:Table_<id>`. Anything else with `crs:HasSettings="True"` is a preset.
- Values come from attributes and from `crs:` child elements (`rdf:Seq` curves, `"x, y"` items). Numbers may carry `+`. Values are clamped to the `Setting` range.
- `<crs:Look><rdf:Description crs:UUID crs:Name crs:Amount>` becomes `patch.profile`. A non-stubbed Look that carries its own table also yields a `Profile`. Linking is by UUID first, then name, across this import and `known`.
- `crs:Temperature`, `crs:Tint` and `crs:WhiteBalance` go to `patch.extras`, unparsed.
- **Not carried over**, in this order and with these words:
  - "masks": any of `MaskGroupBasedCorrections`, `GradientBasedCorrections`, `CircularGradientBasedCorrections`, `PaintBasedCorrections` with entries;
  - "lens corrections": `LensProfileEnable="1"`, `AutoLateralCA="1"`, non-zero `LensManualDistortionAmount`, `VignetteAmount` or `Defringe`;
  - "perspective": non-zero `PerspectiveUpright`, `PerspectiveVertical`, `PerspectiveHorizontal` or `PerspectiveRotate`;
  - "calibration": non-zero `ShadowTint`, `RedHue`, `RedSaturation`, `GreenHue`, `GreenSaturation`, `BlueHue` or `BlueSaturation`;
  - "point colour": a `crs:PointColors` item that is not all −1;
  - "camera profile": a `CameraProfile` other than "Adobe Standard" or "Adobe Color";
  - "crop": `HasCrop="True"`.
- `crs:FilterList` / `crs:CompressedSettings`: decode or identify the referenced table and write what it is in the notes. If it changes how the photo looks, add it to the list above under a plain name; otherwise ignore it.
- A preset whose profile isn't found keeps `patch.profile` and is reported as missing.

**The result `line`, exact copy:**
- `Imported "<name>".` / `Imported <n> presets.` / `Imported the profile "<name>".`
- If nothing was found: `No Lightroom presets found in these files.`
- Then, appended as they apply:
  - ` Not carried over: <list joined with ", ">.`
  - ` "<preset>" needs the profile "<profile>". Import that file too, and it will be picked up.`
  - ` Made for an older Lightroom, so it may look a little different.` (when `crs:ProcessVersion` < 10)

- [ ] **Step 1: Write the failing tests.** The fixtures mirror the sample pack's *structure* with made-up values and names: a "Normal" preset, process version 15.4, a stubbed Look with a UUID and Amount 0.5, curves, mixer, grain, a FilterList, all-−1 PointColors; a Look file whose table comes from the Task 8 test encoder; an lrtemplate; a fake DNG (TIFF header bytes + an XMP packet + trailing bytes); a zip with `__MACOSX` entries.

```dart
test('xmp preset maps values, curves and the profile reference', ...);  // e.g. Shadows2012 "+20" -> 20, ToneCurvePV2012Red points
test('preset and its profile in one import link by UUID', ...);
test('profile imported later links to the waiting preset by UUID, then by name', ...);
test('missing profile line', ...);
test('lrtemplate maps the same fields', ...);
test('dng: settings come from the embedded packet', ...);
test('zip: macOS leftovers ignored', ...);
test('unknown crs fields ignored; "+1.0" and "-0" parse', ...);
test('not carried over lists masks and lens corrections in order', ...);
test('process version 6.7 adds the older-Lightroom line', ...);
test('same UUID twice gives one preset', ...);
test('a text file gives "No Lightroom presets found in these files."', ...);
```

- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS. Then run analyze and the suite.
- [ ] **Step 5: Manual check.** Import the real sample pack's folder (both `.xmp` files and the `.lrtemplate`) through a throwaway test run pointed at the outside folder (don't commit it). Record the line it produces and any field that surprised you.
- [ ] **Step 6:** Commit (`feat(presets): import Lightroom presets and profiles`).

### Task 12: Preset store and preset files

**Files:**
- Create: `lib/core/presets/preset_codec.dart`, `lib/core/store/preset_store.dart`, `preset_store_io.dart`, `preset_store_web.dart`, `preset_store_memory.dart`
- Modify: `lib/core/presets/preset_import.dart` (also accept `.json` files that are e-Layout presets)
- Test: `test/core/presets/preset_store_test.dart`

**Interfaces:**
- Produces:
  - `abstract class PresetStore` with `Future<List<Preset>> loadPresets()` (oldest first, damaged entries skipped), `Future<void> savePreset(Preset p)`, `Future<void> removePreset(String id)`, `Future<List<Profile>> loadProfiles()`, `Future<void> saveProfile(Profile p)` and `PresetStore createPresetStore()`.
    - io: `<app support>/presets/<id>.preset.json` and `<app support>/presets/profiles/<id>.profile.json`, written atomically (tmp + rename, as `layout_store_io.dart`).
    - web: `IdbBox('e-layout-presets')` with keys `preset:<id>` and `profile:<id>`.
    - memory: maps.
  - `Map<String, dynamic> writePreset(Preset)` / `Preset readPreset(Map)`, and `writeProfile` / `readProfile`. The table is stored as base64 of little-endian `Uint16` (value × 65535).
  - `Uint8List encodePresetFile(Preset p, Profile? profile)`, the share file `{"type":"e-layout-preset","version":1,"preset":{…},"profile":{…}|null}`, and `(Preset, Profile?) decodePresetFile(Uint8List)`. Import of such a file gives `Imported "<name>".`

- [ ] **Step 1: Write the failing tests.** Round trip through each store (io in a temp folder, memory); a damaged file is skipped; a share file round-trips through `importPresetFiles`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS. Then run analyze and the suite.
- [ ] **Step 5:** Commit (`feat(presets): store and share files`).

### Task 13: Keeping the batch

**Files:**
- Create: `lib/core/store/batch_store.dart`, `batch_store_io.dart`, `batch_store_web.dart`, `batch_store_memory.dart`
- Test: `test/core/store/batch_store_test.dart`

**Interfaces:**
- Produces:
  - `class BatchPhoto` with `int id`, `String name`, `String key`, `int? size` and `DateTime? modified`.
  - `class BatchManifest` with `List<BatchPhoto> photos` and `BatchLook look`, plus JSON.
  - `abstract class BatchStore` with:
    - `Future<BatchManifest?> load()`, `Future<void> saveManifest(BatchManifest m)`;
    - `Future<String> putPhoto(String name, Uint8List bytes)` (returns a new key);
    - `Future<Uint8List> readPhoto(String key)` (throws when gone);
    - `Future<void> removePhoto(String key)`, `Future<void> clear()`, `Future<int> usedBytes()`;
    - `BatchStore createBatchStore()`.
  - io: `<app support>/batch/manifest.json` (atomic) and `<app support>/batch/photos/<key><ext>`.
  - web: `IdbBox('e-layout-batch')` with keys `manifest` and `photo:<key>` (bytes as `JSUint8Array`).
  - memory: maps.

- [ ] **Step 1: Write the failing tests.** Put, read and remove; manifest round trip; `clear` empties everything and `usedBytes` returns 0; reading a removed key throws; a damaged manifest makes `load` return null.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS. Then run analyze and the suite.
- [ ] **Step 5:** Commit (`feat(store): keep the batch`).

### Task 14: Home controller: looks, presets and the kept batch

**Files:**
- Modify: `lib/features/home/home_controller.dart`, `lib/features/home/home_wiring.dart`, `lib/main.dart` (create the stores and load the developer)
- Test: `test/features/home/home_controller_test.dart` (add), `test/features/home/home_develop_test.dart`

**Interfaces:**
- Consumes: Tasks 5, 9 to 13.
- Produces, on `HomeController`:
  - Constructor parameters `PresetStore presetStore`, `BatchStore batchStore`, `PhotoDeveloper? developer`.
  - Fields `List<Preset> presets`, `Map<String, Profile> profiles`, `BatchLook look`, `int keptBytes`, `bool batchOk`, `bool editingAvailable` (false when the developer failed to load).
  - `PhotoItem` gains `String? key`, `ui.Image? developed` and `String? developedKey`.
  - Methods:
    - `EditSettings settingsFor(PhotoItem p)`, `ProfileTable? profileFor(EditSettings s)`, `bool hasOwnChanges(PhotoItem p)`;
    - `Future<void> setLook(BatchLook next)` (saves the manifest at once, re-develops changed thumbnails);
    - `Future<void> choosePresetForAll(Preset? p)`;
    - `Future<String> importPresets(List<PickedPhoto> files)` (returns the line; stores presets and profiles);
    - `Future<Preset> savePreset(String name, EditSettings s)` (`kind: user`, full `toPatch()`);
    - `Future<void> removePreset(Preset p)`, `Future<void> sharePreset(Preset p)` (`<name>.preset.json`, through the existing temp and share pattern of `exportLayout`).
  - `clearPhotos()` becomes `Future<void>` and empties the batch store.
  - Changed behaviour:
    - `init()` restores the batch: one `PhotoItem` per `BatchPhoto`, whose `PickedPhoto.readBytes` reads from the store.
    - `addPhotos()` copies each photo's bytes into the store, then saves the manifest.
    - `removePhoto()` removes its bytes, its overrides (`withoutPhoto`) and saves.
    - `saveAll()`, `saveOne()` and `shareOne()` pass `edit: settingsFor(p)` and `profile:` to the exporter.
    - Thumbnails: after a preview loads or the look changes, `developed` is made from `preview` with `developer.develop(..., scale: preview.width / p.width)`, queued like `_loadPreview`. The grid then uses `developed ?? preview`.
    - A store failure sets `batchOk = false`.
  - `notices` adds, when `!batchOk`: `Photos can't be kept on this $deviceNoun, so they will be gone when the app closes.` When `!editingAvailable`: `Photo editing isn't available on this $deviceNoun.`

- [ ] **Step 1: Write the failing tests** (`MemoryBatchStore`, `MemoryPresetStore`, `CpuDeveloper`):

```dart
test('photos and edits come back after a restart', ...);   // add 2, edit photo 1, new controller on the same stores -> same names, same look
test('a kept photo whose bytes are gone shows the error, the rest restore', ...); // "Can't open this file."
test('clear empties the store and the look', ...);
test('choosing a preset for all keeps single-photo changes', ...);
test('importing a profile after its preset links them', ...);
test('saving uses each photo\'s own settings', ...);        // exposure override on photo 1 only: photo 1 saved brighter than photo 2
test('removing a photo drops its overrides', ...);
test('batch store failure shows the note', ...);
```

- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. Update the existing tests that construct `HomeController` to pass memory stores.
- [ ] **Step 4:** Run. Expected: PASS. Then run analyze and the suite.
- [ ] **Step 5:** Commit (`feat(home): looks, presets and the kept batch`).

### Task 15: Home screen: preset row, preset picker, grid, clear

**Files:**
- Create: `lib/features/home/preset_row.dart`, `lib/features/home/preset_picker.dart`
- Modify: `lib/features/home/home_screen.dart`, `lib/features/home/photo_grid.dart`
- Test: `test/features/home/preset_ui_test.dart`, goldens in `test/features/home/goldens/`

**Exact UI:**
- **Preset row**, under the Layout notes and above the Photos title, shown only when `editingAvailable`: a card row 50 pt tall, "Preset" on the left; on the right the shared name, "Custom" (`shared` not empty, `sharedName` null) or "None"; then a chevron.
- **Picker sheet**, titled "Presets":
  - first row "None";
  - sections "Your presets" and "Imported"; each row is a 56 pt thumbnail of the first ready photo (or the sample scene) with that preset applied, plus the name, with a check on the current one;
  - long-press or swipe for "Share" and "Delete";
  - bottom button "Import a Lightroom preset" (`pickFiles(extensions: ['xmp','dng','lrtemplate','zip','json'])`), whose result line shows as a toast;
  - empty state: "No presets yet. Import a Lightroom preset, or make one in the photo editor with Save as preset."
- **Grid:** a cell draws `developed ?? preview`. A photo with its own changes gets an 8 pt accent dot at its top-left.
- **Photos title:** the caption `Kept on this $deviceNoun: <formatBytes(keptBytes)>` under the title when there are photos.
- **Clear** asks first, with title "Clear all photos?", text "The photos and their edits are removed from e-Layout. Your original photos are not touched.", and buttons "Clear" (destructive) and "Cancel".

- [ ] **Step 1: Write the failing tests.** The row shows None, then a name, then Custom; choosing in the picker sets the shared preset; import shows the line; the dot appears only on the overridden photo; Clear asks and then empties. Add goldens: `home_preset_light`/`dark` (phone), `home_preset_wide`, `preset_picker_light`, `preset_picker_empty_dark`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement, following `layout_strip.dart` and `options_sheet.dart` patterns and `sheet_scaffold.dart`.
- [ ] **Step 4:** Run. Expected: PASS. Look at every golden and fix what's wrong. Then run analyze and the suite.
- [ ] **Step 5:** Commit (`feat(home): preset row and picker`).

### Task 16: Photo editor screen (frame, canvas, filmstrip, history)

**Files:**
- Create: `lib/features/develop/photo_editor_controller.dart`, `lib/features/develop/photo_editor_screen.dart`, `lib/features/develop/develop_canvas.dart`, `lib/features/develop/filmstrip.dart`, `lib/features/develop/open_photo_editor.dart`
- Modify: `lib/features/viewer/photo_viewer.dart` (an "Edit" button next to "Save this photo" and "Share", shown when `editingAvailable`)
- Test: `test/features/develop/photo_editor_test.dart`, goldens in `test/features/develop/goldens/`

**Interfaces:**
- Consumes: `HomeController` (Task 14), `PhotoDeveloper`.
- Produces:
  - `enum ToolPanel { presets, light, colour, effects, detail }`.
  - `class PhotoEditorController extends ChangeNotifier`:
    - Constructor `PhotoEditorController({required HomeController home, required int photoId, required PhotoDeveloper developer})`.
    - Getters `PhotoItem photo`, `EditSettings settings` (includes a value being dragged), `ToolPanel? panel`, `bool comparing`, `bool showLayout`, `bool canUndo`, `bool canRedo`.
    - Slider gestures: `void beginChange()`, `void preview(Setting s, double v)`, `Future<void> endChange()`. One gesture is one undo step; `home.setLook` is called only at the end.
    - One-step changes: `Future<void> setValue(Setting s, double v)` (also used by the double-tap reset), `Future<void> setCurve(CurveChannel c, List<CurvePoint> pts)`, `Future<void> setGrayscale(bool on)`, `Future<void> setProfileAmount(double a)`.
    - `Future<void> applyPreset(Preset p)` (to this photo: `withPhotoPatch`).
    - `Future<void> copyToAll(Set<ToolGroup> groups, {required bool keepSingle})`, `Future<void> resetPhoto()`, `Future<Preset> saveAsPreset(String name)`.
    - `Future<void> undo()`, `Future<void> redo()` (history of `BatchLook` snapshots, at most 100).
    - `Future<void> showPhoto(int index)`, `void setPanel(ToolPanel? p)`, `void setComparing(bool on)`, `void toggleLayout()`.
- **Canvas:**
  - It draws the photo developed at the canvas's device-pixel size (one render in flight at a time; a newer request replaces a waiting one), from a decode at `kViewerEdge`, with the layout through `paintComposite` when `showLayout`.
  - Press and hold shows the original, with a small "Original" label at the top.
  - Pinch, or Ctrl+scroll on wide screens, zooms between fit and 100 %. Past the point where one preview pixel covers more than one screen pixel, the visible region (plus `margin`) is cut from a full-size decode of this photo (one kept at a time), developed with `origin` and `scale = 1 × zoom`, and drawn in place.
- **Phone layout:**
  - top bar: "Done" (left), undo, redo, and "..." (Copy to all, Save as preset, Reset this photo);
  - the canvas, then the filmstrip (thumbnails 56 pt, current one ringed, tap to switch);
  - then the tool strip: tiles 64 wide labelled "Presets", "Light", "Colour", "Effects", "Detail", as in the layout editor;
  - tapping a tile swaps the strip for that tool's panel (Task 17/18), half the screen height clamped to 250–320, with a title and "Done".
- **Wide layout** (the breakpoint the Home screen uses): the canvas in the middle, a 360 pt panel on the right that always shows the current tool with the tool tiles as a segmented row at its top, and the filmstrip at the bottom.

- [ ] **Step 1: Write the failing tests** (`etest`; `CpuDeveloper`):

```dart
etest('Edit in the viewer opens the editor on that photo', ...);
etest('a slider drag is one undo step and saves once at the end', ...);
etest('undo after copy to all restores every photo', ...);
etest('hold shows the original and the "Original" label', ...);
etest('filmstrip switches photos and keeps the open panel', ...);
etest('zoom to 100 % shows full-resolution pixels', ...); // 4000x3000 1-px checker photo: the screen shows alternating pixels, not grey
etest('Done returns to Home and the grid cell shows the edit', ...);
```

  Goldens: `photo_editor_light`/`dark` (phone, no panel), `photo_editor_wide`, `photo_editor_compare`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS. Look at the goldens. Then run analyze and the suite.
- [ ] **Step 5:** Commit (`feat(develop): photo editor screen`).

### Task 17: Editor panels: Light, Colour, Effects, Detail

**Files:**
- Create: `lib/features/develop/panels/develop_slider.dart`, `panel_light.dart`, `curve_editor.dart`, `panel_colour.dart`, `panel_effects.dart`, `panel_detail.dart`
- Test: `test/features/develop/panels_test.dart`, goldens

**Exact UI:**
- `DevelopSlider` wraps `LabeledSlider` (`sliderHeight` 36). A double-tap anywhere on its row resets the value to `Setting.neutral`. The value text has a sign for ranges that cross zero ("+20"), two decimals for exposure ("+0.70"), and one decimal for `sharpenRadius`.
- Panels use `PanelTabs` (from `lib/features/editor/panels/panel_widgets.dart`):
  - **Light:** "Basic" (Exposure, Contrast, Highlights, Shadows, Whites, Blacks) and "Curve".
    - Curve has chips "Parametric", "RGB", "Red", "Green", "Blue".
    - Parametric: Highlights, Lights, Darks and Shadows sliders, plus three split sliders that keep shadow < midtone < highlight with gaps of at least 5.
    - The point editor is a square `CurveEditor`: tap adds a point, drag moves it, double-tap removes it. The end points can't be removed and move only vertically.
  - **Colour:** "Basic", "Mixer" and "Grading".
    - Basic: a "Black & white" switch; when a profile is set, a "Profile" line with its name and an "Amount" slider 0–200 %; then Temperature, Tint, Vibrance and Saturation.
    - Mixer: 8 colour dots (Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta) and Hue, Saturation and Luminance sliders for the chosen colour. In black & white it shows the 8 grey-mix sliders instead, titled "Black & white mix".
    - Grading: chips "Shadows", "Midtones", "Highlights" and "Global", each with Hue (0–360), Saturation and Luminance sliders; then Blending and Balance. These are sliders; there are no colour wheels in this release.
  - **Effects:** "Basic" (Texture, Clarity, Dehaze), "Vignette" (Amount, Midpoint, Roundness, Feather, Highlights) and "Grain" (Amount, Size, Roughness).
  - **Detail:** "Sharpening" (Amount, Radius, Detail, Masking) and "Noise" (Luminance, Detail, Contrast, then Colour, Colour detail, Smoothness).
- Every panel must fit without scrolling at 390x844 and 320x568. If a tab doesn't fit, split it into another tab. The test checks scroll extent 0, as the Font panel test does.

- [ ] **Step 1: Write the failing tests** (`ptest`):
  - each slider writes its `Setting`;
  - a double-tap resets it;
  - the curve editor adds, moves and removes points, and keeps its end points;
  - split sliders keep their order;
  - the Mixer switches to the grey mix in black & white;
  - Amount shows only with a profile;
  - nothing scrolls at 390 or 320.

  Goldens for every tab in light mode at 390, the busiest two tabs at 320, and Curve and Grading in dark mode.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS. Look at the goldens. Then run analyze and the suite.
- [ ] **Step 5:** Commit (`feat(develop): editing panels`).

### Task 18: Presets panel, Copy to all, Save as preset, Reset

**Files:**
- Create: `lib/features/develop/panels/panel_presets.dart`, `lib/features/develop/copy_sheet.dart`, `lib/features/develop/save_preset_sheet.dart`
- Test: `test/features/develop/presets_panel_test.dart`, goldens

**Exact UI:**
- **Presets panel:** a horizontal row of preset cards (thumbnail of this photo with the preset, then its name), in "Your presets" then "Imported" order, then an "Import" card. Tapping a card applies the preset to **this photo only** and shows the toast `"<name>" is on this photo.`
- **"..." → Copy to all:** a sheet titled "Copy to all photos" with:
  - checkboxes "Light", "Colour", "Effects" and "Detail", all on;
  - a switch "Keep changes made on single photos", on;
  - a primary button "Copy to <n> photos" (n = the other ready photos), disabled when no group is checked.

  It is one undo step, followed by the toast `Copied to <n> photos.`
- **"..." → Save as preset:** a sheet titled "Save as preset" with a text field (placeholder "Preset name", 80 characters at most) and a "Save" button, followed by the toast `Saved "<name>".` An empty name keeps the button disabled.
- **"..." → Reset this photo:** one undo step, followed by the toast `This photo is back to the shared preset.` Disabled when the photo has no changes of its own.

- [ ] **Step 1: Write the failing tests.** Applying from the panel changes only this photo; Copy to all respects the groups and the switch; the button is disabled with no groups; Save adds a preset to "Your presets"; Reset is disabled without changes; each toast's text is exact. Goldens: `presets_panel`, `copy_sheet_light`/`dark`, `save_preset_sheet`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS. Look at the goldens. Then run analyze and the suite.
- [ ] **Step 5:** Commit (`feat(develop): presets panel, copy to all, save and reset`).

### Task 19: Release 1.1.0

**Files:**
- Modify: `test/offline/no_network_imports_test.dart` (add `lib/core/develop`, `lib/core/presets`, `lib/core/store/preset_store*`, `lib/core/store/batch_store*`, `lib/features/develop`), the About licences (the same place the font licences are listed: add LightCraft's NOTICE and licence text as an asset under `assets/licenses/`), `assets/whats_new.md`, version via `python scripts/bump_version.py 1.1.0`
- Test: the existing what's-new, version and offline tests

- [ ] **Step 1:** Extend the offline guard test. Run it. Expected: PASS (a guard test; note that it passed at once).
- [ ] **Step 2:** Add the licence asset and its About entry. Add a test that the About licences list shows "LightCraft". Run it: fail, then implement, then pass.
- [ ] **Step 3:** Bump to 1.1.0. Add this at the top of `assets/whats_new.md`:

```markdown
## 1.1.0

- Edit your photos inside e-Layout: light, colour, curves, effects, sharpening and noise reduction.
- Put one preset on every photo, then change single photos when one needs it.
- Import your Lightroom presets (.xmp, .dng, .lrtemplate), including their profiles, and share your own presets as a file.
- Your photos and their edits stay in e-Layout until you clear them.
```

- [ ] **Step 4:** Run the full analyze and test suite. Then, one at a time:
  - `flutter build apk --release`;
  - `flutter build windows --release`, then run it for 20 s, screenshot it and stop it;
  - `flutter build web --release --base-href /app/` (with Part 3's flags).

  Copy the APK to `dist/e-layout-1.1.0-local.apk`.
- [ ] **Step 5: Manual check on Windows**, using the outside sample pack and generated photos:
  1. Import the pack. Record the line it shows.
  2. Choose "Presetpro - Vintage Vibe" for all photos.
  3. Change one photo's exposure.
  4. Copy to all.
  5. Save.
  6. Close and reopen the app: the batch and its edits are back.

  Record what you saw. If an Android phone is attached, repeat on it and record the slider speed.
- [ ] **Step 6:** Commit (`release: e-Layout 1.1.0 photo editing`). Do not tag or push: releasing is the owner's call (`RELEASE_GUIDE.md`).

---

## Handoff notes

- 2026-11-23: plan written after the owner approved the design. Not started. The owner also asked for an image converter ("jpg to png, png to jpeg, and more"). It is being designed separately and is **not** part of this plan.
- **2026-11-24: Phases 0 and 1 DONE** on branch `feature/photo-editing` (40 commits after `e-Layout 1.0.1` = 7cfdb92, ending 702b536).
  - Every task got its own review, then a whole-branch review on the most capable model and one fix wave.
  - Not pushed, tagged or merged; the owner decides.
  - Version 1.1.0+3 with its what's-new. Local builds: `dist/e-layout-1.1.0-local.apk` (57.2 MB), Windows release build, web build (`--base-href /app/`).
  - Tests, run in pieces because of memory: core 252, develop 85, home/viewer/offline 54, ui/online/platform 57, about/fonts/layouts all pass.
  - Manual check: with the real sample pack (outside the repo), import gives `Imported "Presetpro - Vintage Vibe". Imported the profile "Presetpro - Vintage Vibe".` Preset for all, a single-photo change, copy to all, save, and the batch and edits coming back after a restart all worked through HomeController on real file stores.
  - Notes written: `docs/superpowers/notes/lightcraft-notes.md`, `develop-spike.md`, `lightroom-study.md` (REA study **not done**: no phone).
- **Owner to-dos before release:**
  1. Re-run `flutter test test/features/editor/panels_test.dart` on an idle machine. "goldens 2 picture tools" timed out here: it waits for real file saves while memory was low. This branch didn't change layout-editor code, but this wasn't confirmed on main.
  2. Plug in an Android phone, then measure slider speed and the 24 MP save time. The spike estimates the save may be about twice the 4 s target. Run the Lightroom Mobile REA study (Task 2).
  3. Try the editor by hand on Windows and the website. Here it was only built, launched and screenshotted.
- **Known simplifications (Phase 4 tuning):**
  - Highlights and Shadows are global, not local.
  - Several local effects are simplified compared with LightCraft.
  - Positive Blacks lifts the black point with a constant chosen here.
- **Parked minors:** see the final ledger summary in the session.
  - Viewer: dispose during a develop in flight; a stale developed image when a develop fails.
  - Picker: swipe labels; an old sharedName without an id shows no check.
  - Imports run on the UI isolate.
  - Orphan bytes are left after a kill (Clear reclaims them).
  - Lossy fileSafe ids.
- **Next:** Phase 2 (crop), Phase 3 (RAW with LibRaw), Phase 4 (matching Lightroom). Each needs its own plan. The converter request is still waiting for the owner's answer about what it's for.
