# Photo editing in e-Layout (Lightroom-style) — design

**Date:** 2026-11-23
**Status:** draft, waiting for the owner's approval
**Applies to:** `pio_photo_layout/` (e-Layout 1.0.1 and later)

## Intent and why

The office's staff edit their photos in Adobe Lightroom Mobile, then bring them into e-Layout to put the office layout on them. The owner wants e-Layout to do the editing too, so staff use one app instead of two and e-Layout becomes "more flexible". Nothing is wrong with the photos today. This is about replacing the Lightroom step.

How staff work in Lightroom today (from the owner):

- They use **presets**.
- They apply a preset to one photo and **copy the edits to all photos** in the set.
- After copying, they **still change single photos** when one needs it (for example, one shot is darker).
- They work from both **RAW camera files and JPEGs** (they shoot with a camera).

Two references, chosen by the owner:

- **Lightroom Mobile** (Adobe), studied with REA (Reverse Engineering Anything) to learn its tools, slider ranges, behaviour and preset format.
- **LightCraft** (ArtCraft team, https://github.com/storytold/lightcraft), an open-source Lightroom clone in Rust, licensed "MIT OR Apache-2.0". Its formulas are borrowed and ported. Its code is not linked into the app.

## What exists today

- e-Layout never changes the photo itself. `lib/core/export/photo_exporter.dart` decodes the photo with the engine (or with `package:image` when the engine clamps a big picture), draws it plus the layout in 2048 px tiles with `Picture.toImage`, and encodes JPEG/PNG in an isolate. The output is 8-bit RGBA.
- The Home grid previews come from `HomeController._loadPreview` (a small decode, `kPreviewEdge`). The viewer decodes a 2048 px copy (`kViewerEdge`).
- Pictures inside a layout already have filters (brightness, contrast, saturate, grayscale, blur in `layout_doc.dart`). Photos have none.
- Photos live in memory for the current batch only. Layouts are stored per platform (`layout_store_io/web/memory`).
- Only JPEG and PNG photos open today.
- Design rules for every screen: the "Design" section of `docs/superpowers/plans/2026-11-15-part2-app.md` (colours, Inter, CupertinoIcons, plain sentence-case wording, 44 pt touch targets, light and dark).

## Goals

1. Edit photos inside e-Layout with Lightroom's main tools, offline, on Android, Windows and the website.
2. Presets: apply one to the whole batch, apply one to a single photo, save your own, and **import the presets staff already have from Lightroom**.
3. "Copy to all", plus changes on single photos that stay on top of the shared preset.
4. Open **RAW files** from the office's cameras as well as JPEG and PNG.
5. The saved photo is full resolution, with the edits and the layout, through the existing save flow.
6. Edits look the same in the preview and in the saved file. A Lightroom preset looks close to how it looks in Lightroom.

## Non-goals (not in this project)

- AI tools: select subject or sky, people masks, remove/heal, generative remove, AI denoise. They need large AI models and would make the app heavy and slow on phones. They may be a later project.
- Brush, linear and radial masks (local adjustments). Possible later; the design must not rule them out. If an imported preset uses masks, the masked part is skipped and the import says so. If the office's real presets turn out to depend on masks for their look, this comes back to the owner before Phase 1 is planned.
- Lens profile corrections, Upright and geometry correction (they need Adobe's lens database).
- A photo library or catalog (albums, ratings, keywords) and cloud sync.
- Video.
- Sharing presets through the online template gallery. It fits the gallery later, but it isn't part of this project.

## Anti-goals (failure even if it "works")

- Anything that needs the internet to edit or save.
- Moving a slider that visibly lags on an ordinary Android phone.
- A saved photo that doesn't match what the preview showed.
- An imported office preset that looks clearly different from Lightroom. Staff would go back to Lightroom.
- A cluttered screen. It must stay simple, clean and iOS-like, like the rest of e-Layout.
- Any Adobe code, shaders, icons, images, preset packs or branding inside e-Layout. The word "Lightroom" appears only where it describes compatibility ("Import a Lightroom preset").
- Real people's photos committed to the repository. The repository is public.

## Constraints

- Flutter 3.44.1 / Dart 3.12.1. One codebase for Android, Windows and web. `dart:io` only in `*_io.dart`, web-only code only in `*_web.dart` (Part 3 rule).
- The build laptop has about 1 GB of free RAM: one Flutter, Gradle, MSBuild or native build at a time.
- Project rules from the earlier plans still apply: tests first; `flutter analyze` clean and `flutter test` passing at the end of every task; goldens for screens (phone 390x844 at DPR 2, wide 1280x800 at DPR 1, light and dark).
- Releases go through the existing pipeline (tags, GitHub Actions, `assets/whats_new.md`, `download/latest.json`). Each phase below ships as a normal release.
- The working tree has uncommitted 1.0.1 changes (version, what's new, a golden). Commit or release them before this work starts, so the two don't mix.
- LibRaw's licence (CDDL-1.0 or LGPL-2.1, our choice) needs credit and a way to get its source. LightCraft's Apache-2.0 licence needs its NOTICE carried. Both go on the About screen's licences page.

## Approaches

1. **Our own editor that borrows LightCraft's math (chosen by the owner).** Adjustments run as GPU fragment shaders inside Flutter, so the same code draws the live preview and the full-size save on all three platforms. Formulas are ported from LightCraft. REA on Lightroom Mobile gives the tool list, ranges and behaviour. RAW files open through LibRaw, the long-established C library that uses Adobe-derived colour matrices for each camera. Lightroom presets are parsed in Dart. Trade-off: the most building work, but e-Layout controls it, it stays offline everywhere, and masking can be added later.
2. **LightCraft's whole Rust engine inside e-Layout** (through Rust FFI and WASM). Most features already exist. Rejected: it is alpha and changes weekly, it has no Android target, it isn't built as a library, every slider move would copy pixels between Rust and Flutter (lag on phones), and building Rust with wgpu on a 1 GB-free laptop and in CI is heavy.
3. **Edit only the JPEG preview embedded in RAW files.** Dropped: it throws away the highlight and shadow detail that is the reason staff shoot RAW.

## How editing behaves

The words below are what users see. "Preset" is the staff's own word.

- **Preset for all photos.** Home gets a row under the Layout section: "Preset: None ›". It opens the preset picker (office presets, your presets, imported ones), with each preset previewed on the first photo. Choosing one sets the **shared preset** for every photo in the batch. The grid shows every photo with its edits and the layout.
- **Editing one photo.** Tap a photo, then "Edit" (in the viewer), to open the photo editor. Moving a slider changes **this photo only**. Each slider you move on a photo **replaces** the shared value for that slider on that photo. These are per-setting overrides, not offsets: if the shared preset's exposure later changes, the photo you set to +0.3 stays at +0.3. Every setting you didn't touch on that photo follows the shared preset.
- Photos with their own changes show a small dot on their grid cell. "Reset this photo" removes its own changes. Reset doesn't affect crop; crop has its own reset.
- **Applying a preset inside the editor** applies it to this photo only. Every setting the preset contains becomes an override on this photo.
- **Copy to all** (in the editor) opens a small sheet, like Lightroom's copy-settings dialog:
  - checkboxes for Light, Color, Effects and Detail, all on;
  - a switch, "Keep changes made on single photos", on by default.

  Confirming makes this photo's checked settings the shared preset. With the switch on, other photos keep their own overrides. With it off, their overrides in the checked groups are cleared. Crop and straighten are never copied.
- **Save as preset**, from the editor: a name, then it appears under "Your presets". Presets never include crop.
- **Before and after:** press and hold the photo to see the original.
- **Reset one slider:** double-tap it, as in Lightroom.
- **Undo and redo** in the editor.
- **The batch is kept until staff clear it (decided by the owner).**
  - The photos, the shared preset and every photo's own changes survive closing the app, Android killing it in the background, and a restart.
  - "Clear" on Home (with a confirmation) is the only thing that drops them.
  - How the photos are kept is left to the builder: e-Layout's own copies in app storage (IndexedDB on the website), or lasting file permissions where the platform allows.
  - A batch of RAW files can take a lot of space, so Home shows how much the kept batch uses.
  - When the device can't keep it (website storage refused, disk full), the app says so in a warning note, the same way it handles layouts today (`storageOk`).
- Presets are stored on the device.

## Tools in this project

Ranges follow Lightroom. Phase 0 confirms or corrects every range, default and step from Lightroom Mobile itself.

| Group | Tools |
|---|---|
| Light | Exposure (−5 to +5), Contrast, Highlights, Shadows, Whites, Blacks (−100 to +100); Curve: parametric (highlights, lights, darks, shadows, with split points) and point curves for RGB, red, green and blue |
| Profile | Creative profiles (colour tables) that come with imported presets, with an Amount slider (0 to 200, as Lightroom) |
| Color | Temperature and Tint (kelvin for RAW, −100 to +100 for JPEG, as Lightroom does); Vibrance, Saturation; Color mixer (8 hues × hue, saturation, luminance); Color grading (shadows, midtones, highlights, global; blending, balance); a B&W switch with its grey mix |
| Effects | Texture, Clarity, Dehaze; Vignette (amount, midpoint, roundness, feather, highlights); Grain (amount, size, roughness) |
| Detail | Sharpening (amount, radius, detail, masking); Noise reduction (luminance with detail and contrast; colour with detail and smoothness) |
| Crop | Crop with free and fixed ratios, straighten (angle slider plus a level guide), rotate 90°, flip |

Later, not in this project: Auto, histogram, Point Color, the AI tools, local masks, and optics.

## Screens

- **Home:** the "Preset" row described above. Grid cells show edited photos and an override dot. The "Add" picker accepts RAW files.
- **Viewer:** an "Edit" button next to "Save this photo" and "Share".
- **Photo editor (phone):** the photo fills the top, drawn with its edits and the layout. A "Layout" toggle hides the layout while editing. A filmstrip of the batch sits under the photo, for moving between photos without leaving the editor. At the bottom is a strip of tool tiles in the style of the existing layout editor: Presets, Crop, Light, Color, Effects, Detail. Tapping one opens a panel of about 280 pt with its sliders, and the photo stays visible. The top bar has Done, undo, redo, and "..." (Copy to all, Save as preset, Reset this photo).
- **Zoom in the editor:** pinch, or Ctrl+scroll on wide screens, up to 100%. When zoomed in, the visible region is rendered from the full-resolution photo, so sharpening, noise reduction, texture and grain can be judged. For a RAW photo this uses the full decode of that one photo.
- **Photo editor (wide, Windows and web):** the photo in the middle, the tools as a panel on the right (as in Lightroom on a computer), the filmstrip at the bottom.
- **Preset picker:** a sheet with sections Your presets and Imported. Each is a thumbnail of the current photo with the preset applied. "Import a Lightroom preset" accepts `.xmp`, `.dng`, `.lrtemplate` and `.zip`.

The phone layout and tool order may change after Phase 0, if Lightroom Mobile's own arrangement would be more familiar to staff.

## How it is built

**Settings model (pure Dart, `lib/core/`).** An immutable `EditSettings` holds every tool's values and serialises to JSON. A `PhotoEdit` holds per-photo overrides plus crop. `resolve(sharedPreset, photoEdit)` gives the final settings for a photo. Presets are stored like layouts (io, web and memory stores), in e-Layout's own JSON format (`.preset.json`, with any colour table stored next to it).
- Staff make and save their own presets in e-Layout (owner).
- A preset can be shared to another device as a file through the share sheet or "Save to file", and opened there with the same import.
- No presets are bundled for now. The picker's sections are "Your presets" and "Imported". An "Office presets" section is added only if the office later supplies presets it owns.

**Rendering.** One `EditRenderer` turns a source image plus final settings into pixels at any size. The preview uses it at screen size, and the save uses it at full size inside the existing tiled exporter, before the layout is drawn. Requirements:

- The preview and the save use the same code and the same parameters.
- Filters that look at neighbouring pixels (clarity, texture, sharpening, noise reduction, dehaze, grain) render tiles with enough overlap that tile seams can't be seen.
- Anything measured over the whole photo (dehaze's haze level, for example) is measured once on a small copy and passed to every tile, so tiles agree.
- The order of operations follows Lightroom's (white balance, exposure and tone, curve, colour mixer, grading, effects, detail), confirmed from LightCraft's develop code.
- A test checks that a scaled-down save matches the preview within a small tolerance.

**Precision.** The RAW advantage lives in highlights and shadows beyond 8 bits. RAW data enters the pipeline as linear 16-bit or float. Phase 0's spike decides where that stage runs:

- (a) on the GPU, if Flutter can hold float images (`PixelFormat.rgbaFloat32`) and run shaders on them at full size on all three platforms; or
- (b) on the CPU or native side, after LibRaw. White balance, exposure, highlight recovery and the base tone curve run there, and the 8-bit result goes to the shaders.

JPEG and PNG start in 8-bit, as Lightroom's do.

**RAW (LibRaw).**
- Build LibRaw from source (latest stable release, core only, none of the old GPL demosaic packs): Android NDK, Windows MSVC, and Emscripten (WASM) for the website.
- Call it through `dart:ffi` on Android and Windows and JS interop on the web. The web module loads only when a RAW file is opened, so the website stays fast for everyone else.
- The grid uses the JPEG preview embedded in the RAW file (fast). The editor uses a half-size decode. The save uses a full decode.
- One RAW file in memory at a time on phones.
- Accepted extensions: `.cr2 .cr3 .nef .arw .raf .rw2 .orf .pef .srw .dng`.
- A RAW photo with no edits should look close to Lightroom's default rendering, so e-Layout's base tone curve for RAW is tuned in Phase 5.
- The website may get RAW last. Android and Windows can ship RAW first.

**Lightroom preset import (pure Dart).**
- Formats:
  - `.xmp`: the `crs:` develop settings in an `rdf:Description`, process version 2012 and later.
  - `.dng`: the XMP packet inside the file, which is how Lightroom Mobile users usually pass presets around.
  - `.lrtemplate`: the older Lightroom Classic format, a Lua-style `s = { ... value = { settings = { ... } } }` text file. Packs still ship it.
  - `.zip` of those (`archive` is already a dependency), or several files picked at once. macOS leftovers (`__MACOSX/`, `.DS_Store`, `._*`) are ignored.
- **Creative profiles (colour tables) are required.** They are what the sample pack the owner supplied ("Presetpro – Vintage Vibe", process version 15.4, Lightroom 18.3.1) is built on:
  - Its preset (`crs:PresetType="Normal"`) refers through `<crs:Look>` to a profile by name and UUID, with `crs:Amount="0.5"` and `crs:Stubbed="true"`.
  - The pack's second file is that profile (`crs:PresetType="Look"`). It carries `crs:RGBTable="<id>"` and the table itself as a compressed `crs:Table_<id>` attribute (about 240 KB).
  - The preset also carries a `crs:FilterList` whose entry points at a compressed `crs:Table_<id>` through `crs:CompressedSettings`.

  Import must decode these tables, store each profile, link a preset to its profile by UUID (falling back to the name), and apply the table as a 3D lookup in the shader at the given amount. Importing a preset whose profile isn't present yet works too: the app says which profile is missing, and picks it up when the profile file is imported later. How the tables are encoded is for the builder to find out: Adobe's DNG SDK source is public, and LightCraft may already decode them.
- The sample pack also uses parametric and point curves (RGB, red, green and blue), the colour mixer, grain, sharpening and colour noise reduction. All are in this project's tools. It uses no masks. Its `crs:PointColors` entries are all −1, meaning unused.
- Each `crs:` field maps to an e-Layout setting, including the RAW-kelvin versus JPEG-relative white balance rule.
- Settings e-Layout can't do (masks, lens corrections, Upright, camera profiles it doesn't know) are skipped. After import the app says so in one plain line, for example: "Imported "Office warm". Not carried over: masks, lens corrections."
- **The sample pack is third-party** ("Copyright Presetpro INC", downloaded free by the owner). It lives at `C:\Windows_Applications\REA_Projects\Re_Canva\LightroomVintageVibeFree\` for testing by hand only. It is never copied into the repository, the app or the tests. Tests use small XMP, DNG and lrtemplate files the builder writes, and a colour table the builder generates.

## Phases (in this order; each ends in a release)

0. **Study and spike.**
   - REA on Lightroom Mobile. The APK comes from a staff phone over USB with debugging on (REA `pull_adb_package`), or the owner provides the APK file; it is used for analysis only and never redistributed. Record:
     - the tool list and order, and each slider's label, range, default and step;
     - gestures, and the copy-settings dialog;
     - how presets import, and which XMP fields it writes.

     Findings go in `docs/superpowers/notes/lightroom-study.md`: facts only, no copied code or assets.
   - Read LightCraft's `develop`, `color` and `raw` crates for formulas and the order of operations.
   - Spike: float images and multi-pass shaders at full size, tiled, on Android, Windows and web. Measure slider speed on a real Android phone. Decide precision option (a) or (b).
1. **Editing engine, photo editor and Lightroom preset import, for JPEG and PNG.**
   - Settings model, shaders, Light, Color, Effects, Detail.
   - Presets: save, apply and share as a file, plus importing Lightroom presets (`.xmp`, `.dng`, `.lrtemplate`, `.zip`) with their creative-profile colour tables.
   - The Home preset row, per-photo overrides, copy to all, before/after, zoom to 100%, undo, and saving with edits.
   - Keeping the batch and its edits across restarts.

   Import is in this first release because applying their presets is the main thing staff do. The sample pack must import and apply.
2. **Crop and straighten.**
3. **RAW:** Android and Windows, then the website.
4. **Matching Lightroom.**
   - The office provides a tuning set: a few photos (RAW and JPEG), each exported from Lightroom with each office preset and with single sliders moved, following a checklist the builder writes. The set is kept **outside the repository**.
   - The builder adjusts the formulas until differences are hard to see side by side at normal size.

## Needed from the office

- A sample preset pack: received (see above).
- An Android phone, any staff phone, for speed tests (Phase 0). Lightroom Mobile on it, or its APK file, for REA.
- A few sample photos from the office camera, RAW and JPEG (Phase 3), and the tuning set (Phase 4). The camera model isn't needed up front. If a camera's RAW files can't be read, the app says so and staff use that camera's JPEGs.

## Left to the builder

- Shader pass structure, the exact formulas, tile size and overlap, and data structures and file layout inside the project rules.
- How LibRaw is built and bundled per platform (Flutter native-asset build hooks, or CMake in `android/` and `windows/`), and the web loading mechanism.
- Speed targets, measured and reported in Phase 0. Suggested starting points:
  - slider preview at 20 fps or better on a mid-range Android phone;
  - a full-size 24 MP JPEG save with every tool on in about 4 s;
  - a 24 MP RAW save in about 8 s.

  If the phone misses these badly, bring it back to the owner before Phase 1.
- Choosing CDDL or LGPL for LibRaw.

## Calls made by Claude (the owner has not confirmed these)

1. Per-photo changes are overrides that replace the shared value, not offsets added to it.
2. "Copy to all" keeps single-photo changes by default, with a switch to clear them, and never copies crop.
3. Home shows a "Preset" row (the staff's word) rather than a new screen. Editing opens from the viewer's "Edit" button.
4. e-Layout's own preset format is JSON (`.preset.json`). Lightroom files are import-only.
5. Phase order: editor with preset import, then crop, then RAW, then tuning. The website gets RAW last.
6. `.lrtemplate` import is included, because packs still ship it.
7. The editor zooms to 100%, rendering the visible region at full resolution.
8. If a preset uses masks, the masked part is skipped and the import says so.

## Decided by the owner

- Option 1 (our own editor borrowing LightCraft's math, LibRaw for RAW).
- Presets, copy to all, and single-photo changes after copying.
- RAW and JPEG both.
- The batch and its edits are kept until staff clear it.
- Staff make and save their own presets in e-Layout.
- AI tools, masks and healing were proposed as "later" and not objected to.
7. Auto, histogram, Point Color, masks, healing and AI tools are left out of this project.
