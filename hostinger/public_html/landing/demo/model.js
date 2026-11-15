/*
 * Layout documents.
 *
 * A layout is a list of pieces (text, shapes, images, icons) laid out on a
 * frame 1200 units wide. When the layout is applied to a photo, everything
 * scales with the photo's width, and each piece keeps its distance from the
 * edge it is pinned to (top, bottom, centre, or both for "stretch"). That is
 * how one layout fits landscape and portrait photos alike.
 *
 * A layout can instead crop every photo to a fixed shape (fit: 'crop').
 */
(function (PIO) {
  'use strict';

  const DESIGN_W = 1200;
  const RATIOS = { landscape: 3 / 2, portrait: 3 / 4, square: 1, wide: 16 / 9, tall: 4 / 5 };
  const TYPES = ['text', 'shape', 'image', 'icon'];
  const PINS = ['top', 'center', 'bottom', 'stretch'];
  const SHAPES = ['rect', 'ellipse', 'triangle', 'diamond', 'polygon', 'star', 'arrow', 'torn'];
  const BLENDS = ['source-over', 'multiply', 'screen', 'overlay', 'darken', 'lighten', 'color-dodge', 'color-burn',
    'hard-light', 'soft-light', 'difference', 'exclusion', 'hue', 'saturation', 'color', 'luminosity'];
  const FILL_TYPES = ['none', 'solid', 'linear', 'radial'];
  const IMAGE_DATA = /^data:image\/(png|jpeg|webp|gif|avif);base64,[A-Za-z0-9+/=]+$/;
  const FONT_MIME = /^(font\/(ttf|otf|woff|woff2)|application\/(x-font-ttf|x-font-otf|font-woff|font-sfnt|octet-stream)|)$/;

  let counter = 0;
  function uid(prefix) {
    counter = (counter + 1) % 1e6;
    return `${prefix}_${Date.now().toString(36)}${counter.toString(36)}${Math.random().toString(36).slice(2, 6)}`;
  }

  const clone = (v) => JSON.parse(JSON.stringify(v));

  function newLayout(name) {
    return {
      version: 2, pinsVersion: 2, id: uid('L'), name: name || 'Untitled layout', width: DESIGN_W,
      fit: 'keep', ratio: RATIOS.landscape, elements: [], groups: {}, assets: {}, fonts: {},
      created: Date.now(), updated: Date.now(),
    };
  }

  function baseElement(type) {
    return {
      id: uid('e'), type, name: '', visible: true, locked: false,
      // pinAuto: the pin follows the piece: whichever part of the photo it sits in when moved.
      x: 0, w: 200, h: 100, pin: 'center', pinAuto: true, top: 0, bottom: 0, cy: 0,
      rotation: 0, skewX: 0, skewY: 0, flipX: false, flipY: false,
      opacity: 1, blend: 'source-over',
      fill: { type: 'solid', color: '#2481C3', alpha: 1, angle: 90,
        stops: [{ at: 0, color: '#2481C3', alpha: 0 }, { at: 1, color: '#2481C3', alpha: 1 }] },
      stroke: { width: 0, color: '#14212E', alpha: 1 },
      shadow: { on: false, color: '#000000', alpha: 0.35, blur: 8, x: 0, y: 3 },
      radius: 0,
      effects: { blur: 0, brightness: 100, contrast: 100, saturate: 100, grayscale: 0 },
    };
  }

  function newElement(type, props) {
    const el = baseElement(type);
    if (type === 'text') {
      Object.assign(el, { name: 'Text', text: 'Your text here', font: 'Barlow', weight: 700, italic: false, size: 56,
        align: 'left', letterSpacing: 0, lineHeight: 1.2, upper: false });
      el.fill.color = '#FFFFFF';
      el.shadow = { on: true, color: '#000000', alpha: 0.35, blur: 6, x: 0, y: 2 };
    } else if (type === 'shape') {
      Object.assign(el, { name: 'Shape', shape: 'rect', sides: 6, points: 5, inner: 0.45, seed: 7, rough: 0.5, w: 240, h: 160 });
    } else if (type === 'image') {
      Object.assign(el, { name: 'Image', asset: null, fit: 'contain' });
      el.fill.type = 'none';
      el.stroke.color = '#FFFFFF';
    } else if (type === 'icon') {
      Object.assign(el, { name: 'Icon', icon: 'phone', lineWidth: 2, w: 64, h: 64,
        iconBg: { shape: 'circle', color: '#FFFFFF', alpha: 1 } });
    }
    return Object.assign(el, props || {});
  }

  // ---------- geometry ----------

  function frameHeight(doc, previewRatio) {
    return doc.width / (doc.fit === 'crop' ? doc.ratio : (previewRatio || RATIOS.landscape));
  }

  // The element's box in design units, for a frame of the given height.
  function boxOf(el, frameH) {
    let y;
    let h = el.h;
    if (el.pin === 'top') y = el.top;
    else if (el.pin === 'bottom') y = frameH - el.bottom - el.h;
    else if (el.pin === 'stretch') { y = el.top; h = Math.max(1, frameH - el.top - el.bottom); }
    else y = frameH / 2 + el.cy - el.h / 2;
    return { x: el.x, y, w: el.w, h };
  }

  // Stores a box back into the fields of the element's pin.
  function setBox(el, box, frameH) {
    el.x = box.x;
    el.w = Math.max(1, box.w);
    el.h = Math.max(1, box.h);
    if (el.pin === 'top') el.top = box.y;
    else if (el.pin === 'bottom') el.bottom = frameH - box.y - el.h;
    else if (el.pin === 'stretch') { el.top = box.y; el.bottom = frameH - box.y - el.h; }
    else el.cy = box.y + el.h / 2 - frameH / 2;
  }

  function setPin(el, pin, frameH) {
    const box = boxOf(el, frameH);
    el.pin = pin;
    setBox(el, box, frameH);
  }

  function autoPin(box, frameH) {
    const c = box.y + box.h / 2;
    if (c < frameH * 0.4) return 'top';
    if (c > frameH * 0.6) return 'bottom';
    return 'center';
  }

  // The pin a piece should have where it sits now. A shape running from the top edge to the
  // bottom edge (a side bar) stretches so it keeps doing so on taller photos.
  function pinFor(el, box, frameH) {
    const fullHeight = el.type === 'shape' && box.y <= frameH * 0.05 && box.y + box.h >= frameH * 0.95;
    return fullHeight ? 'stretch' : autoPin(box, frameH);
  }

  function place(el, box, frameH) {
    el.pin = pinFor(el, box, frameH);
    setBox(el, box, frameH);
    return el;
  }

  // After a piece moves: re-pin it to the part of the photo it now sits in (unless the
  // person chose a pin themselves, or it belongs to a group, which pins all its pieces
  // together). Its place in this frame doesn't change.
  function autoRepin(el, frameH) {
    if (el.pinAuto === false || el.group) return;
    const box = boxOf(el, frameH);
    const pin = pinFor(el, box, frameH);
    if (pin !== el.pin) {
      el.pin = pin;
      setBox(el, box, frameH);
    }
  }

  // Layouts made before pins followed their pieces: re-pin every piece once, judging its
  // position in the smallest landscape-or-taller frame that fully shows it.
  function upgradePins(doc) {
    if (doc.pinsVersion >= 2) return false;
    const base = frameHeight(doc);
    for (const el of doc.elements) {
      if (el.pinAuto !== undefined) continue;
      if (el.pin === 'stretch' || doc.fit === 'crop') { el.pinAuto = false; continue; }
      const need = el.pin === 'top' ? el.top + el.h : el.pin === 'bottom' ? el.bottom + el.h : el.h + 2 * Math.abs(el.cy);
      const fh = Math.max(base, need);
      el.pinAuto = true;
      autoRepin(el, fh);
    }
    doc.pinsVersion = 2;
    return true;
  }

  function duplicate(el) {
    const copy = clone(el);
    copy.id = uid('e');
    return copy;
  }

  // ---------- groups ----------
  // A group is a set of pieces handled as one. Its pieces sit next to each other in the
  // layer order and carry the group's id; the group itself only holds a name and its
  // "stays at" setting. All pieces of a group share one pin, so they keep together on
  // taller or wider photos.

  function membersOf(doc, gid) {
    return doc.elements.filter((e) => e.group === gid);
  }

  function unionBox(list, frameH) {
    let l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
    for (const el of list) {
      const x = boxOf(el, frameH);
      l = Math.min(l, x.x); t = Math.min(t, x.y); r = Math.max(r, x.x + x.w); b = Math.max(b, x.y + x.h);
    }
    return { x: l, y: t, w: r - l, h: b - t };
  }

  // Gives every piece of a group the group's pin: chosen by hand, or from where the group sits.
  function groupPin(doc, gid, frameH) {
    const g = doc.groups && doc.groups[gid];
    const members = membersOf(doc, gid);
    if (!g || !members.length) return;
    const pin = g.pinAuto === false ? g.pin : autoPin(unionBox(members, frameH), frameH);
    g.pin = pin;
    for (const el of members) if (el.pin !== pin) setPin(el, pin, frameH);
  }

  function nextGroupName(doc) {
    const used = new Set(Object.values(doc.groups || {}).map((g) => g.name));
    for (let n = 1; ; n++) if (!used.has(`Group ${n}`)) return `Group ${n}`;
  }

  // Puts each group's pieces next to each other (at its topmost piece), drops groups that
  // lost their pieces, and frees the last piece of a group of one.
  function cleanGroups(doc, frameH) {
    doc.groups = doc.groups || {};
    for (const el of doc.elements) if (el.group && !doc.groups[el.group]) delete el.group;
    for (const gid of Object.keys(doc.groups)) {
      const members = membersOf(doc, gid);
      if (members.length < 2) {
        for (const el of members) { delete el.group; el.pinAuto = true; if (frameH) autoRepin(el, frameH); }
        delete doc.groups[gid];
        continue;
      }
      const idx = members.map((m) => doc.elements.indexOf(m));
      const top = Math.max(...idx);
      if (top - Math.min(...idx) + 1 === members.length) continue;   // already together
      const rest = doc.elements.filter((e) => e.group !== gid);
      const below = doc.elements.slice(0, top).filter((e) => e.group !== gid).length;
      rest.splice(below, 0, ...members);
      doc.elements.splice(0, doc.elements.length, ...rest);
    }
  }

  // Groups the given pieces (pieces already in other groups are taken out of those).
  function makeGroup(doc, ids, frameH) {
    const members = doc.elements.filter((e) => ids.includes(e.id));
    if (members.length < 2) return null;
    doc.groups = doc.groups || {};
    const gid = uid('g');
    doc.groups[gid] = { name: nextGroupName(doc), pinAuto: true, pin: 'center' };
    for (const el of members) el.group = gid;
    cleanGroups(doc, frameH);
    // Gather the pieces at the topmost one (cleanGroups did that), then pin them together.
    groupPin(doc, gid, frameH);
    return gid;
  }

  function ungroup(doc, gid, frameH) {
    for (const el of membersOf(doc, gid)) {
      delete el.group;
      el.pinAuto = true;
      autoRepin(el, frameH);
    }
    if (doc.groups) delete doc.groups[gid];
  }

  // ---------- assets ----------

  function addAsset(doc, { name, data, w, h }) {
    for (const [id, a] of Object.entries(doc.assets)) {
      if (a.data === data) return id;      // same picture already in the layout
    }
    const id = uid('a');
    doc.assets[id] = { name: name || 'Image', data, w, h };
    return id;
  }

  function pruneAssets(doc) {
    const used = new Set(doc.elements.filter((e) => e.type === 'image').map((e) => e.asset));
    for (const id of Object.keys(doc.assets)) if (!used.has(id)) delete doc.assets[id];
  }

  // A layout made from one picture, the way version 1 worked.
  function fromImage(name, asset, placement) {
    const doc = newLayout(name);
    const id = addAsset(doc, asset);
    const el = newElement('image', { name, asset: id, fit: 'stretch', x: 0, w: DESIGN_W, pinAuto: false });
    if (placement === 'frame') {
      doc.fit = 'crop';
      doc.ratio = asset.w / asset.h;
      Object.assign(el, { pin: 'stretch', top: 0, bottom: 0, h: DESIGN_W / doc.ratio });
    } else if (placement === 'center') {
      Object.assign(el, { pin: 'center', cy: 0, h: DESIGN_W * asset.h / asset.w });
    } else {
      Object.assign(el, { pin: placement === 'header' ? 'top' : 'bottom', top: 0, bottom: 0, h: DESIGN_W * asset.h / asset.w });
    }
    doc.elements.push(el);
    return doc;
  }

  const PART_NAMES = { top: 'Top part', bottom: 'Bottom part', left: 'Left border', right: 'Right border' };

  // Pieces for the parts of a split frame picture (see render.splitFrame). `box` is where the
  // whole picture sat, in design units, inside a frame of height frameH. Top and bottom parts
  // are pinned to their edges; side borders stretch with the photo's height.
  function partsToElements(doc, name, parts, W, H, box, frameH) {
    const kx = box.w / W;
    const ky = box.h / H;
    return parts.map((p) => {
      const asset = addAsset(doc, { name: `${name}: ${PART_NAMES[p.edge].toLowerCase()}`, data: p.data, w: p.w, h: p.h });
      const el = newElement('image', { name: PART_NAMES[p.edge], asset, fit: 'stretch', pinAuto: false,
        pin: p.edge === 'top' ? 'top' : p.edge === 'bottom' ? 'bottom' : 'stretch' });
      setBox(el, { x: box.x + p.x * kx, y: box.y + p.y * ky, w: p.w * kx, h: p.h * ky }, frameH);
      return el;
    });
  }

  // A layout made from a frame picture that was split into parts.
  function fromParts(name, parts, W, H) {
    const doc = newLayout(name);
    const frameH = DESIGN_W * H / W;
    doc.elements.push(...partsToElements(doc, name, parts, W, H, { x: 0, y: 0, w: DESIGN_W, h: frameH }, frameH));
    return doc;
  }

  // ---------- history ----------

  const snapshot = (doc) => JSON.stringify(doc, (k, v) => (k === 'assets' || k === 'fonts' ? undefined : v));

  function restore(doc, snap) {
    const back = JSON.parse(snap);
    back.assets = doc.assets;
    back.fonts = doc.fonts;
    return back;
  }

  // ---------- reading layout files from other people ----------

  const num = (v, def, min, max) => (typeof v === 'number' && Number.isFinite(v) ? Math.min(max, Math.max(min, v)) : def);
  const str = (v, def, max) => (typeof v === 'string' ? v.slice(0, max) : def);
  const bool = (v, def) => (typeof v === 'boolean' ? v : def);
  const pick = (v, list, def) => (list.includes(v) ? v : def);
  const hex = (v, def) => (typeof v === 'string' && /^#[0-9a-f]{6}$/i.test(v) ? v.toUpperCase() : def);
  const cleanName = (v, def) => str(v, def, 80).replace(/[\u0000-\u001f]/g, '').trim() || def;

  function cleanFill(f, def) {
    if (!f || typeof f !== 'object') return clone(def);
    const stops = Array.isArray(f.stops) ? f.stops.slice(0, 8).map((s) => ({
      at: num(s && s.at, 0, 0, 1), color: hex(s && s.color, '#000000'), alpha: num(s && s.alpha, 1, 0, 1) })) : [];
    return {
      type: pick(f.type, FILL_TYPES, def.type), color: hex(f.color, def.color), alpha: num(f.alpha, def.alpha, 0, 1),
      angle: num(f.angle, 90, -360, 360), stops: stops.length >= 2 ? stops : clone(def.stops),
    };
  }

  function cleanElement(raw, scale, assets) {
    if (!raw || typeof raw !== 'object' || !TYPES.includes(raw.type)) return null;
    const el = newElement(raw.type);
    const d = num;
    Object.assign(el, {
      name: cleanName(raw.name, el.name), visible: bool(raw.visible, true), locked: bool(raw.locked, false),
      x: d(raw.x, 0, -1e5, 1e5) * scale, w: d(raw.w, el.w, 1, 1e5) * scale, h: d(raw.h, el.h, 1, 1e5) * scale,
      pin: pick(raw.pin, PINS, 'center'), pinAuto: typeof raw.pinAuto === 'boolean' ? raw.pinAuto : undefined,
      group: typeof raw.group === 'string' && /^[\w-]{1,64}$/.test(raw.group) ? raw.group : undefined,
      top: d(raw.top, 0, -1e5, 1e5) * scale,
      bottom: d(raw.bottom, 0, -1e5, 1e5) * scale, cy: d(raw.cy, 0, -1e5, 1e5) * scale,
      rotation: d(raw.rotation, 0, -360, 360), skewX: d(raw.skewX, 0, -80, 80), skewY: d(raw.skewY, 0, -80, 80),
      flipX: bool(raw.flipX, false), flipY: bool(raw.flipY, false),
      opacity: d(raw.opacity, 1, 0, 1), blend: pick(raw.blend, BLENDS, 'source-over'),
      fill: cleanFill(raw.fill, el.fill), radius: d(raw.radius, 0, 0, 1e4) * scale,
    });
    const st = raw.stroke || {};
    el.stroke = { width: d(st.width, 0, 0, 500) * scale, color: hex(st.color, el.stroke.color), alpha: d(st.alpha, 1, 0, 1) };
    const sh = raw.shadow || {};
    el.shadow = { on: bool(sh.on, el.shadow.on), color: hex(sh.color, '#000000'), alpha: d(sh.alpha, 0.35, 0, 1),
      blur: d(sh.blur, 8, 0, 500) * scale, x: d(sh.x, 0, -500, 500) * scale, y: d(sh.y, 3, -500, 500) * scale };
    const fx = raw.effects || {};
    el.effects = { blur: d(fx.blur, 0, 0, 100) * scale, brightness: d(fx.brightness, 100, 0, 300),
      contrast: d(fx.contrast, 100, 0, 300), saturate: d(fx.saturate, 100, 0, 300), grayscale: d(fx.grayscale, 0, 0, 100) };

    if (el.type === 'text') {
      Object.assign(el, {
        text: str(raw.text, el.text, 4000), font: cleanName(raw.font, 'Barlow'), weight: Math.round(d(raw.weight, 400, 100, 900) / 100) * 100,
        italic: bool(raw.italic, false), size: d(raw.size, 48, 1, 5000) * scale, align: pick(raw.align, ['left', 'center', 'right'], 'left'),
        letterSpacing: d(raw.letterSpacing, 0, -100, 500) * scale, lineHeight: d(raw.lineHeight, 1.2, 0.5, 4), upper: bool(raw.upper, false),
      });
    } else if (el.type === 'shape') {
      Object.assign(el, {
        shape: pick(raw.shape, SHAPES, 'rect'), sides: Math.round(d(raw.sides, 6, 3, 12)), points: Math.round(d(raw.points, 5, 3, 12)),
        inner: d(raw.inner, 0.45, 0.1, 0.95), seed: Math.round(d(raw.seed, 7, 0, 1e6)), rough: d(raw.rough, 0.5, 0, 1),
      });
    } else if (el.type === 'image') {
      if (typeof raw.asset !== 'string' || !assets[raw.asset]) return null;
      Object.assign(el, { asset: raw.asset, fit: pick(raw.fit, ['contain', 'cover', 'stretch'], 'contain') });
    } else if (el.type === 'icon') {
      const bg = raw.iconBg || {};
      Object.assign(el, {
        icon: PIO.icons && PIO.icons.has(raw.icon) ? raw.icon : 'star', lineWidth: d(raw.lineWidth, 2, 0.5, 4),
        iconBg: { shape: pick(bg.shape, ['none', 'circle', 'square'], 'circle'), color: hex(bg.color, '#FFFFFF'), alpha: d(bg.alpha, 1, 0, 1) },
      });
    }
    return el;
  }

  // Validates a layout read from a file. Throws a readable error when it isn't one.
  function sanitize(input) {
    const raw = input && input.format === 'pio-photo-layout' ? input.layout : input;
    if (!raw || typeof raw !== 'object' || raw.version !== 2 || !Array.isArray(raw.elements)) {
      throw new Error("This file isn't a layout from this tool.");
    }
    const doc = newLayout(cleanName(raw.name, 'Imported layout'));
    const scale = DESIGN_W / num(raw.width, DESIGN_W, 10, 1e5);
    doc.fit = raw.fit === 'crop' ? 'crop' : 'keep';
    doc.ratio = num(raw.ratio, RATIOS.landscape, 0.2, 5);
    doc.pinsVersion = num(raw.pinsVersion, 1, 1, 99);
    const assets = {};
    for (const [id, a] of Object.entries(raw.assets && typeof raw.assets === 'object' ? raw.assets : {})) {
      if (!/^[\w-]{1,64}$/.test(id) || !a || typeof a.data !== 'string' || a.data.length > 40e6 || !IMAGE_DATA.test(a.data)) continue;
      assets[id] = { name: cleanName(a.name, 'Image'), data: a.data, w: num(a.w, 1, 1, 1e5), h: num(a.h, 1, 1, 1e5) };
    }
    doc.assets = assets;
    doc.elements = raw.elements.slice(0, 500).map((e) => cleanElement(e, scale, assets)).filter(Boolean);
    doc.groups = {};
    for (const [gid, g] of Object.entries(raw.groups && typeof raw.groups === 'object' ? raw.groups : {})) {
      if (!/^[\w-]{1,64}$/.test(gid) || !g || typeof g !== 'object') continue;
      doc.groups[gid] = { name: cleanName(g.name, 'Group'), pin: pick(g.pin, ['top', 'center', 'bottom'], 'center'), pinAuto: bool(g.pinAuto, true) };
    }
    for (const el of doc.elements) if (el.group === undefined) delete el.group;
    cleanGroups(doc);
    const fonts = {};
    for (const [family, faces] of Object.entries(raw.fonts && typeof raw.fonts === 'object' ? raw.fonts : {})) {
      const name = cleanName(family, '');
      if (!name || !Array.isArray(faces)) continue;
      fonts[name] = faces.slice(0, 18).filter((f) => f && typeof f.data === 'string' && f.data.length < 15e6 && /^[A-Za-z0-9+/=]+$/.test(f.data))
        .map((f) => ({ weight: Math.round(num(f.weight, 400, 100, 900) / 100) * 100, style: f.style === 'italic' ? 'italic' : 'normal',
          mime: FONT_MIME.test(f.mime || '') ? (f.mime || '') : '', variable: f.variable === true, data: f.data }));
    }
    doc.fonts = fonts;
    return doc;
  }

  PIO.model = {
    DESIGN_W, RATIOS, SHAPES, BLENDS, PINS, uid, clone, newLayout, newElement, frameHeight, boxOf, setBox,
    setPin, autoPin, pinFor, autoRepin, upgradePins, place, duplicate, addAsset, pruneAssets, fromImage, fromParts, partsToElements,
    membersOf, unionBox, groupPin, cleanGroups, makeGroup, ungroup,
    snapshot, restore, sanitize,
  };
})(window.PIO = window.PIO || {});
