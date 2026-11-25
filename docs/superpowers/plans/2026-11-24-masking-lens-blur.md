# Masking, lens blur and built-in presets (e-Layout 1.2.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Keep the **Handoff notes** at the bottom current.

**Goal:** e-Layout 1.2.0 adds Lightroom's premium-style tools, all offline and with no AI model:
- built-in presets (e-Layout's own looks), so no download is needed;
- masks: Brush, Linear, Radial, Brightness range, Colour range, and automatic Subject, Sky and Background;
- each mask has its own light, colour and effects sliders;
- lens blur: keeps the subject sharp and blurs the rest with bokeh.

**Why (the owner, 2026-11-24):**
- Lightroom keeps masking and lens blur behind its paid tier, and the owner wants them in e-Layout. "Hand-drawn masks are enough, but if you can do automatic, please do it."
- On filters: "there are already built-in preset filters, so there is no need to download if the same filter is in the app."
- The owner asked to "just dive in" (no design questions). Every product decision below is Claude's call.

**Architecture:**
- **Masks and lens blur are data:** they're stored in `SettingsPatch` under a new tool group, `masks`.
- **Rendering:** `ShaderDeveloper.develop` keeps its current pass, then runs one extra GPU pass per active mask (`shaders/mask_apply.frag`), then one lens blur pass (`shaders/lens_blur.frag`).
- **Mask coverage** is rasterised per render region:
  - shapes and brush strokes are drawn with `dart:ui` Canvas (gradients, stroked paths, `MaskFilter.blur`);
  - brightness and colour ranges come from a small shader, `shaders/mask_range.frag`;
  - Subject and Sky come from low-resolution maps computed once per photo in pure Dart (LightCraft's heuristics plus a guided filter) and drawn scaled into the region.
- **Components** combine with Add (lighten), Subtract and Intersect, using canvas blend modes.
- **Everything uses whole-photo coordinates** (normalised 0–1 of the upright photo), so preview, 100 % zoom and tiled saves match.

**Tech Stack:** Flutter 3.44.1, `dart:ui` (Canvas, `FragmentProgram`, `ImageFilter`, `MaskFilter`), pure-Dart image maths. No new packages.

**Reference:** LightCraft (MIT OR Apache-2.0), cloned in the earlier scratchpad: `…\912c2bc3-…\scratchpad\lightcraft`.
- `crates/pipeline/src/masks.rs`: Sky at lines 274–288, Subject at 300–313, Background at 315, the guided filter `guided_cross` at 750–800, brush dabs at 568–700, colour-range tolerance at 503.
- `crates/pipeline/src/lens_blur.rs`: the disc blur, focus, transition, boost, and `subject_estimate` at 272.
- `crates/develop/src/settings.rs:900–960`: lens-blur fields.

Port the ideas and maths, credit them in comments (the licence is already in the app's Licences).

## Global Constraints

- Every rule in `.superpowers/sdd/2026-11-23-photo-editing-phase0-1/global-constraints.md` still applies:
  - offline photo path; `*_io`/`*_web` split; tests first;
  - analyze clean and per-area test runs; goldens opened and judged;
  - plain sentence-case wording with British "Colour";
  - about 1 GB of free RAM, so one heavy process at a time;
  - format only the files you change; the single Co-Authored-By trailer;
  - never push, tag or merge.
- Branch: `feature/masking` (created from `main` at v1.1.0+3).
- **The OpenGL ES rule (learned in 1.1.0):** every photo texture a shader samples is a *drawn* image, made with `toImage`, never a decoded or uploaded one. On GLES, reads of them flip `uv.y` under `#ifdef IMPELLER_TARGET_OPENGLES`. Colour tables made with `imageFromRgba` are uploaded and are not flipped. Mask coverage images are drawn with Canvas and `toImage`, so they are drawn images and their reads flip like the photo's. Add a guard test per new shader, like `test/core/develop/shader_gles_test.dart`.
- **The tile rule (learned in 1.1.0):** every texture sent to a shader must be at most 2048 px on each side. The exporter's edited step is `tileSize - 2 × margin`, and `margin()` must now also cover local clarity radii and the lens blur's largest radius.
- **Limits:**
  - at most **8 masks** per photo;
  - at most **4 components** per mask;
  - brush strokes: at most **64 strokes** per mask and **2000 points** per stroke, with points stored as normalised `(x, y)` and doubles rounded to 4 decimals in JSON;
  - colour range: at most **5 samples**.

  Imports and JSON reads clamp to these limits.
- Presets never carry masks or lens blur. `saveAsPreset` and imported presets drop the `masks` group.
- No AI model, no download, nothing online.

## Review Focus

1. **A photo saved with a brush mask and lens blur in tiles has no seams or shifted masks.** The coverage per tile must line up with the whole photo. Test in Task 7.
2. **Very small or very large brushes, and strokes off the photo's edge, are safe.** Size is clamped to 0.5–50 % of the long edge, and points outside 0–1 are clipped. No crash, nothing drawn outside. Test in Task 3.
3. **A mask on an EXIF-rotated photo lands where it was drawn.** Coordinates are in upright-photo space. Test in Task 7.
4. **Copy to all with "Masks & blur" off leaves other photos' masks alone, and with it on, copies them.** Subject and Sky masks recompute on each photo; drawn shapes copy as drawn. Test in Task 8.
5. **The Subject and Sky maps on a plain, flat or tiny photo (1×1, all white, all black) give a valid map** (all 0, or smooth) and never NaN. Test in Task 4.

---

### Task 1: Built-in presets

**Files:**
- Create: `assets/presets/builtin.json` (add `assets/presets/` to pubspec), `lib/core/presets/builtin_presets.dart`
- Modify: `lib/core/presets/preset.dart` (`enum PresetKind { builtin, user, imported }`), `lib/features/home/home_controller.dart` (load the built-ins at start, before stored presets), `lib/features/home/preset_picker.dart` and `lib/features/develop/panels/panel_presets.dart` (a "Built-in" section first; built-ins can't be deleted or shared)
- Test: `test/core/presets/builtin_presets_test.dart`, plus additions to `test/features/home/preset_ui_test.dart`

**Interfaces:**
- Produces: `Future<List<Preset>> loadBuiltinPresets()`, ids `builtin:<slug>`, kind `builtin`, `created` = epoch 0.
- `builtin.json` holds `{"version":1,"presets":[{"id":"builtin:warm","name":"Warm","patch":{…SettingsPatch json…}}, …]}`.

**The 16 looks, in this order:**

| Name | Look |
|---|---|
| Warm | warmer temperature |
| Cool | cooler temperature |
| Vivid | vibrance and saturation up, a little contrast |
| Soft | lower contrast and clarity, lifted shadows |
| Matte | lifted blacks, a faded curve |
| Fade | lower saturation, lifted blacks, softened highlights |
| Film | a gentle S-curve, warm highlights, cool shadows (grading), light grain |
| Vintage | warm, faded, low saturation, grain, a vignette |
| Teal & orange | orange skin hues, teal shadows and sky (mixer plus grading) |
| Golden hour | warm, extra yellow and orange, soft contrast |
| Moody | darker, lower saturation, a deep vignette, more clarity |
| Bright & airy | brighter, lifted shadows, lower contrast, cool tint |
| Crisp | texture, clarity and sharpening up, slight contrast |
| Black & white | B&W with a balanced mix |
| B&W contrast | B&W with strong contrast and clarity |
| Sepia | B&W plus warm grading |

The values are the implementer's design: moderate, flattering on outdoor event photos, and nothing extreme. Never copy a commercial pack.

- [ ] **Step 1: Write the failing tests.**
  - 16 presets in that order, with unique ids and names;
  - each is non-neutral;
  - exactly the three B&W ones have `grayscale: true`;
  - none has a profile or masks;
  - every value is inside its `Setting` range.

  UI tests:
  - the picker shows "Built-in" first;
  - a built-in can't be deleted, so its long-press menu has no Delete;
  - choosing "Warm" sets the shared preset with sharedId `builtin:warm`.
- [ ] **Step 2:** Run the tests and see them fail.
- [ ] **Step 3:** Implement. Make the 16 patches and render one golden, `test/core/presets/goldens/builtin_grid.png`: a 4×4 contact sheet of the generated landscape scene with each preset applied through `CpuDeveloper`. Open it, judge every look, and adjust any that is harsh or broken.
- [ ] **Step 4:** Run `flutter analyze` and `flutter test test/core/presets test/features/home`. Commit (`feat(presets): built-in looks`).

### Task 2: The masks and lens blur model

**Files:**
- Create: `lib/core/develop/masks.dart`
- Modify: `lib/core/develop/settings.dart`:
  - `enum ToolGroup { light, colour, effects, detail, masks }`;
  - `SettingsPatch` gets `List<Mask>? masks` and `LensBlur? lensBlur` (group `masks`), included in `over`, `only`, `without`, JSON and `isEmpty`;
  - `EditSettings` gets `List<Mask> masks` (default empty) and `LensBlur lensBlur` (default off), included in `toPatch` and `key`.
- Test: `test/core/develop/masks_test.dart`, plus additions to `settings_test.dart`

**Interfaces:**
- Produces:
  - `enum MaskOp { add, subtract, intersect }`.
  - `sealed class MaskShape` with these subclasses, all values clamped on construction and in `fromJson`:
    - `BrushShape(List<BrushStroke> strokes)`; `BrushStroke(List<(double, double)> points, {double size = 0.05, double feather = 50, double flow = 100, bool erase = false})`;
    - `LinearShape(double x0, double y0, double x1, double y1)` (full effect at `(x0, y0)`, none at `(x1, y1)`);
    - `RadialShape({double cx = .5, double cy = .5, double rx = .25, double ry = .25, double angle = 0, double feather = 50, bool invert = false})`;
    - `LuminanceRangeShape({double low = .5, double high = 1, double smooth = 20})`;
    - `ColourRangeShape(List<(double, double, double)> samples, {double refine = 50})`;
    - `SubjectShape()`, `SkyShape()`, `BackgroundShape()`.
  - `class MaskComponent(MaskShape shape, {MaskOp op = MaskOp.add})`.
  - `class Mask({required String id, String name, List<MaskComponent> components, Map<Setting, double> adjust, bool visible = true})`.
    - `adjust` only accepts the **local settings**: exposure, contrast, highlights, shadows, whites, blacks, temperature, tint, vibrance, saturation, texture, clarity, dehaze. Any other key is dropped. Values are deltas within each `Setting`'s range.
  - `class LensBlur({double amount = 0, LensFocus focus = LensFocus.subject, double fx = .5, double fy = .5, String? maskId, double transition = 50, double boost = 0})`, with `enum LensFocus { subject, point, mask }`.
    - `amount` is 0–100, where 100 is a disc radius of 2 % of the long edge.
    - `bool get isOn => amount > 0`.
  - Value equality and `toJson`/`fromJson` for all of them, with the Global Constraints limits enforced in `fromJson`.

- [ ] **Step 1: Write the failing tests.**
  - a JSON round trip of every shape;
  - limits clamp (9 masks become 8, 6 components become 4, 70 strokes become 64, 2500 points become 2000, 7 samples become 5);
  - a non-local setting key in `adjust` is dropped;
  - `over`/`only`/`without` include `masks` and `lensBlur` in `ToolGroup.masks`;
  - `EditSettings.key` changes when a brush point moves;
  - old JSON with no masks loads with empty masks.
- [ ] **Step 2:** Run the tests and see them fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter analyze` and `flutter test test/core`. Commit (`feat(develop): masks and lens blur model`).

### Task 3: Mask coverage rasteriser

**Files:**
- Create: `lib/core/develop/mask_raster.dart`, `shaders/mask_range.frag` (add it to pubspec)
- Test: `test/core/develop/mask_raster_test.dart`, plus the GLES guard in `test/core/develop/shader_gles_test.dart`

**Interfaces:**
- Consumes: Task 2; `recordImage` and `copyImage` from `photo_developer.dart`.
- Produces: `class MaskRasterizer`:
  - `static Future<MaskRasterizer> load()`;
  - `Future<ui.Image> coverage(Mask m, {required ui.Image src, required ui.Offset origin, required ui.Size fullSize, required double scale, AutoMaps? auto})`.
    - It returns a drawn image the size of `src`, with coverage 0–1 in its alpha and white RGB.
    - `src` is the render-region image at `scale`.
    - `origin` is its top-left in render pixels of the whole photo; `fullSize` is the whole photo in render pixels.

**How each part is drawn:**
- **Components:** each one is drawn into a `saveLayer` and combined.
  - **Add:** `BlendMode.lighten`.
  - **Subtract:** coverage `a·(1−c)` via `BlendMode.dstOut`.
  - **Intersect:** `BlendMode.dstIn`.
- **Radial:** an oval at `(cx·W, cy·H)` with radii `(rx·W, ry·H)`, rotated by `angle`. A `RadialGradient` gives full coverage inside `1 − feather/100`, falling to 0 at the edge; `invert` flips it.
- **Linear:** a `LinearGradient` from `(x0, y0)` (1) to `(x1, y1)` (0), clamped beyond both ends.
- **Brush:**
  - each stroke is a stroked `Path` with radius = `size × long edge`;
  - feather is a `MaskFilter.blur` with sigma `feather/100 × radius / 2`;
  - flow is the paint alpha;
  - `erase` uses `BlendMode.dstOut`.
- **Luminance and colour range:** draw `mask_range.frag` over the region, sampling `src`.
  - **Luminance:** smoothstep from `low − smooth/100` to `low`, times one minus a smoothstep from `high` to `high + smooth/100`.
  - **Colour:** the max over samples of a similarity in OkLab chroma and lightness, with tolerance from `refine` (LightCraft `color_range_tolerance`, masks.rs:503).
- **Subject, Sky, Background:** draw `auto.subject` or `auto.sky` (Task 4), stretched over the whole photo, through `drawImageRect` with `FilterQuality.high`. Background is `1 − subject`.

- [ ] **Step 1: Write the failing tests** (a 64×64 region; read the alpha back):
  - a radial with feather 0 has its centre at 1 and its corner at 0;
  - with feather 50, a point halfway out is between 0.2 and 0.8;
  - invert flips it;
  - linear: the `(x0, y0)` side is 1 and the `(x1, y1)` side is 0;
  - brush: pixels on the path are covered, far pixels are 0, and an erase stroke clears its pixels;
  - subtract and intersect give the expected coverage;
  - luminance range on a grey gradient covers only its band;
  - colour range picks the sampled red and not blue;
  - **region consistency:** coverage of the full 64×64 equals the two 32×64 halves stitched (`origin` (0,0) and (32,0)), within 2/255;
  - **Review Focus 2:** size 0.0001 is clamped and doesn't throw; points at (−5, 7) draw nothing outside and don't throw.
- [ ] **Step 2:** Run the tests and see them fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run analyze and tests. Commit (`feat(develop): mask coverage`).

### Task 4: Automatic Subject and Sky maps

**Files:**
- Create: `lib/core/develop/auto_masks.dart`
- Test: `test/core/develop/auto_masks_test.dart`

**Interfaces:**
- Produces:
  - `class AutoMaps { final ui.Image subject, sky; final (double, double) subjectPoint; void dispose(); }`;
  - `Future<AutoMaps> computeAutoMaps(ui.Image photo)`:
    - downscale to at most 384 px on the long edge;
    - read RGBA and compute in pure Dart: log luminance, then **Sky** (masks.rs:274–288) and **Subject** (masks.rs:300–313);
    - refine both with a guided filter whose guide is luminance (masks.rs:750–800: radius 2 % of the long edge, eps 1e-3);
    - upload both as drawn images, with coverage in alpha.
  - `subjectPoint` is the normalised centroid of the subject map's top 10 % (`lens_blur.rs:272` `subject_estimate`).
- HomeController/PhotoEditorController cache one `AutoMaps` per photo (Task 7 wires it).

- [ ] **Step 1: Write the failing tests:**
  - a generated photo with a blue gradient top half and green bottom: sky mean in the top quarter is over 0.6, in the bottom quarter under 0.1;
  - a grey photo with a textured central square: subject mean in the centre is more than twice the corner mean;
  - `subjectPoint` is within 0.15 of (0.5, 0.5);
  - **Review Focus 5:** 1×1, all-white and all-black photos give finite maps, values in 0–1, and no throw.
- [ ] **Step 2:** Run the tests and see them fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run analyze and tests. Commit (`feat(develop): automatic subject and sky`).

### Task 5: The mask apply pass

**Files:**
- Create: `shaders/mask_apply.frag` (in pubspec)
- Modify: `lib/core/develop/shader_developer.dart`, `lib/core/develop/photo_developer.dart` (`develop` gets `AutoMaps? auto`; `CpuDeveloper` applies masks with the same maths per pixel, for tests)
- Test: `test/core/develop/mask_apply_test.dart`, plus the GLES guard

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces: masks applied inside `develop()`:
  - after the main pass, for each visible mask with a non-empty `adjust`, in order:
    1. rasterise its coverage for this region;
    2. bake a LUT from a `ColorPipeline` of the mask's tone and colour deltas (as `EditSettings` applied to the developed sRGB);
    3. blur the current image for the mask's texture, clarity and dehaze;
    4. run `mask_apply.frag`: `out = mix(base, local(base), coverage)`.
  - `margin()` also covers the largest local clarity radius.

- [ ] **Step 1: Write the failing tests:**
  - a radial mask with exposure +1 brightens inside and leaves outside unchanged (within 1/255);
  - a mask with no `adjust` changes nothing;
  - two masks apply in order;
  - shader and `CpuDeveloper` agree on tone and colour deltas within 2/255 mean;
  - a hidden mask (`visible: false`) does nothing.
- [ ] **Step 2:** Run the tests and see them fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run analyze and tests. Commit (`feat(develop): masks in the developer`).

### Task 6: The lens blur pass

**Files:**
- Create: `shaders/lens_blur.frag` (in pubspec)
- Modify: `shader_developer.dart`, `photo_developer.dart`
- Test: `test/core/develop/lens_blur_test.dart`, plus the GLES guard

**Interfaces:**
- Produces: when `lensBlur.isOn`, a final pass in `develop()` runs.
- **Focus map** (in focus = 1):
  - `subject`: the AutoMaps subject coverage;
  - `point`: a radial falloff around `(fx, fy)` whose width follows `transition`;
  - `mask`: the coverage of `maskId`, or the subject if that mask is missing.
- **Disc blur:** a golden-angle disc of 48 taps.
  - Radius per pixel = `amount/100 × 0.02 × long edge × scale × (1 − focus)^(1 + transition/50)`.
  - Highlight boost: weight = `1 + boost/25 × max(0, luminance − 0.75) × 4`.
  - Taps that are more in focus than the centre are down-weighted, so sharp edges don't bleed.
  - Port from `lens_blur.rs` and credit it.
- `margin()` also covers the largest radius.

- [ ] **Step 1: Write the failing tests:**
  - amount 0 changes nothing;
  - with point focus at the centre and amount 100, the centre keeps its local variance and the corners lose more than 60 % of theirs;
  - boost makes a bright dot in the blurred area spread brighter than with boost 0;
  - **tiles:** two tiles with `margin()` stitched equal one whole render within 2/255.
- [ ] **Step 2:** Run the tests and see them fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run analyze and tests. Commit (`feat(develop): lens blur`).

### Task 7: Wiring: AutoMaps cache, exporter and preview

**Files:**
- Modify: `lib/features/home/home_controller.dart` (compute and cache AutoMaps per photo lazily, only when a photo's settings use Subject, Sky or Background, or lens blur focuses on the subject; freed on remove and clear), `lib/core/export/photo_exporter.dart` (compute AutoMaps from the 512 px copy once per photo and pass it to every tile), `lib/features/develop/develop_canvas.dart` and `lib/features/viewer/photo_viewer.dart` (pass the cached AutoMaps)
- Test: additions to `test/core/export/photo_exporter_test.dart` and `test/features/home/home_develop_test.dart`

- [ ] **Step 1: Write the failing tests:**
  - **Review Focus 1:** a brush mask plus lens blur, saved in 64 px tiles, matches a single whole render within 2/255 and has no visible seam;
  - **Review Focus 3:** `exif_rotated_6.jpg` with a radial mask in its upright top-left corner: the saved upright top-left is the changed one;
  - AutoMaps is computed once per photo for a 4-tile save;
  - a photo without auto masks never computes AutoMaps.
- [ ] **Step 2:** Run the tests and see them fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run analyze and tests (core, home, viewer, develop). Commit (`feat: masks and lens blur in previews and saves`).

### Task 8: Copy to all and presets

**Files:**
- Modify: `lib/core/develop/batch_look.dart` (copyToAll accepts `ToolGroup.masks`), `lib/features/develop/copy_sheet.dart` (a fifth checkbox, "Masks & blur", **off** by default), preset save and import (drop `masks` and `lensBlur`)
- Test: additions to `batch_look_test.dart`, `presets_panel_test.dart`, `import_test.dart`

- [ ] **Step 1: Write the failing tests** (**Review Focus 4**):
  - with "Masks & blur" off, others' masks are unchanged;
  - with it on, they get the source photo's masks and lens blur;
  - saving a preset drops masks;
  - the copy sheet shows five groups with masks unchecked.
- [ ] **Step 2:** Run the tests and see them fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run analyze and tests. Commit (`feat: copy masks and blur to other photos`).

### Task 9: The Masking panel

**Files:**
- Create: `lib/features/develop/panels/panel_masks.dart`
- Modify: `photo_editor_controller.dart` (`ToolPanel.masks` after `detail`, plus mask operations as one-step undoable changes), `photo_editor_screen.dart` (tool tile "Masking", icon `CupertinoIcons.circle_lefthalf_fill`)
- Test: `test/features/develop/masks_panel_test.dart`, plus goldens

**Interfaces (controller):**
- `Future<void> addMask(MaskShape first)` (selects the new mask, named "Mask 1", "Mask 2"…)
- `selectMask(String? id)`, `deleteMask(id)`, `renameMask(id, name)`, `setMaskVisible(id, bool)`
- `addComponent(id, MaskShape, MaskOp)`, `updateShape(id, index, MaskShape)` (gesture-aware: `beginChange`/`previewShape`/`endChange`, so one drag is one step), `removeComponent(id, index)`
- `setMaskValue(id, Setting, double)`
- `String? selectedMaskId`, `bool showOverlay`

**UI:**
- **No mask selected:** the panel shows the mask list (name, a small coverage thumbnail, eye) and a "+" button with an action sheet:
  - "Subject", "Sky", "Background", "Brush", "Linear gradient", "Radial gradient", "Brightness range", "Colour range".
- **A mask selected:** the panel shows tabs:
  - "Adjust": the 13 local sliders in pairs, using `DevelopSlider`;
  - "Mask": the shape controls for each component, plus "Add" and "Subtract" buttons to combine shapes;
  - "Show mask": a switch for a red 50 % overlay on the canvas.
- At most 8 masks; when full, "+" is disabled with the caption "8 masks is the most for one photo."

- [ ] **Step 1: Write the failing tests:**
  - adding "Radial gradient" creates "Mask 1", selected;
  - an Adjust slider drag is one undo step;
  - delete, rename and hide each work and undo;
  - the 9th mask is refused;
  - Subtract adds a component with `op` subtract.

  Goldens: the mask list, Adjust, the Mask tab, the add sheet; light, dark and 320.
- [ ] **Step 2:** Run the tests and see them fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run analyze and tests (develop). Open the goldens. Commit (`feat(develop): masking panel`).

### Task 10: Editing masks on the photo

**Files:**
- Create: `lib/features/develop/mask_handles.dart` (an overlay painter plus gestures)
- Modify: `develop_canvas.dart` (with the Masking panel open and a mask selected, the canvas shows the overlay and handles; one-finger gestures go to the mask, and two-finger pinch still zooms)
- Test: `test/features/develop/mask_handles_test.dart`, plus goldens

**Behaviour:**
- **Radial:** drag the centre dot to move; drag the 4 edge dots to resize the axes; drag the rotation dot to rotate; a "Feather" slider sits in the Mask tab.
- **Linear:** drag either end line, or the middle to move both.
- **Brush:**
  - the Mask tab has "Brush" / "Erase" chips and Size, Feather and Flow sliders;
  - one finger paints a stroke, recorded in normalised photo coordinates through the canvas's view transform;
  - points are thinned to at least 0.002 apart;
  - one stroke is one undo step.
- **Colour range:** tap the photo to add a sample (at most 5), with a "Refine" slider.
- **Brightness range:** no handles; Low, High and Smooth sliders.
- **Subject, Sky, Background:** no handles; a note says "Found automatically. Brush or subtract to fix it."
- **Overlay:** when "Show mask" is on, the coverage is shown red at 50 %; it is on while a handle is dragged.

- [ ] **Step 1: Write the failing tests:**
  - dragging the radial centre by (+40, +20) screen px moves `cx`/`cy` by the matching normalised amount at the fit zoom and at 2× zoom;
  - a brush drag produces one stroke with thinned points inside 0–1;
  - erase records `erase: true`;
  - a tap with Colour range adds one sample with the tapped pixel's colour;
  - a pinch still zooms and draws nothing.

  Goldens: radial and linear handles, and the brush overlay.
- [ ] **Step 2:** Run the tests and see them fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run analyze and tests. Open the goldens. Commit (`feat(develop): edit masks on the photo`).

### Task 11: Lens blur tool

**Files:**
- Create: `lib/features/develop/panels/panel_blur.dart`
- Modify: the controller (`ToolPanel.blur` after `masks`, plus one-step setters), the screen (tile "Lens blur", icon `CupertinoIcons.camera_filters`), and `develop_canvas.dart` (with focus "Point", a tap sets the focus; "Show focus" overlays the in-focus area in green at 40 %)
- Test: `test/features/develop/blur_panel_test.dart`, plus goldens

**Panel:**
- an "Amount" slider (0–100), with the tab "Focus" segmented: "Subject" / "Point" / "Mask" (Mask is disabled without masks; it then picks a mask from the list);
- "Transition" and "Bokeh highlights" sliders;
- a "Show focus" switch.

- [ ] **Step 1: Write the failing tests:**
  - an Amount drag is one undo step;
  - Point focus plus a tap at the photo centre sets `fx`/`fy` to about (0.5, 0.5);
  - choosing Mask with no masks is disabled.

  Goldens: the panel light and dark at 320, and the focus overlay.
- [ ] **Step 2:** Run the tests and see them fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run analyze and tests. Open the goldens. Commit (`feat(develop): lens blur tool`).

### Task 12: e-Layout 1.2.0 test build

- [ ] **Step 1:** Run `python scripts/bump_version.py 1.2.0`. Add a `## 1.2.0` section at the top of `assets/whats_new.md`:

```markdown
## 1.2.0

- Built-in looks: 16 ready presets such as Warm, Film, Vintage, Teal & orange and Black & white, with nothing to download.
- Masks: change just part of a photo with a brush, a gradient, a brightness or colour range, or the subject, sky and background found for you.
- Lens blur: keep the subject sharp and blur the rest, with soft bokeh highlights.
```

- [ ] **Step 2:** Run `flutter analyze`. Then run the tests in pieces: `test/core`, `test/features/develop`, `test/features/home test/features/viewer test/features/about test/features/layouts test/features/fonts`, the editor tests except `panels_test.dart`, and `test/ui test/offline test/online test/platform`. Also run `python tool/check_tree.py` and `python scripts/test_release_scripts.py`.
- [ ] **Step 3:** Build the APK with TEMP set to `C:\Temp\gradle-tmp` (the long-TEMP Gradle loopback trap). Copy it to `dist/e-layout-1.2.0-local.apk`. Commit (`release: e-Layout 1.2.0 masking and lens blur`). **Do not tag, push or merge**: the owner tries it on a phone first.

---

## Handoff notes

- 2026-11-24: plan written; the owner opted out of design questions. Branch `feature/masking` from `main` (v1.1.0+3, released). Website upload of the 1.1.0 web zip into `app/` is still a manual owner step.
