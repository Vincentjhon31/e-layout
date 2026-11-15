/*
 * Fonts: the typefaces bundled in fonts/, fonts already installed on this
 * computer, and fonts people upload (kept in this browser, and embedded in
 * exported layout files so they work on other computers too).
 */
(function (PIO) {
  'use strict';

  const BUILT_IN = [
    { family: 'Barlow', weights: [400, 500, 600, 700, 800], group: 'Sans serif' },
    { family: 'Barlow Condensed', weights: [400, 600, 800], group: 'Sans serif' },
    { family: 'Montserrat', weights: [400, 700, 800], group: 'Sans serif' },
    { family: 'Poppins', weights: [400, 600, 800], group: 'Sans serif' },
    { family: 'Open Sans', weights: [400, 700, 800], group: 'Sans serif' },
    { family: 'Fira Sans Condensed', weights: [400, 600, 800], group: 'Sans serif' },
    { family: 'Nunito', weights: [400, 800], group: 'Sans serif' },
    { family: 'Oswald', weights: [400, 600], group: 'Headline' },
    { family: 'Anton', weights: [400], group: 'Headline' },
    { family: 'Bebas Neue', weights: [400], group: 'Headline' },
    { family: 'Playfair Display', weights: [400, 700, 900], group: 'Serif' },
    { family: 'Libre Baskerville', weights: [400, 700], group: 'Serif' },
    { family: 'Cinzel', weights: [400, 700], group: 'Serif' },
    { family: 'Dancing Script', weights: [400, 700], group: 'Script' },
    { family: 'Great Vibes', weights: [400], group: 'Script' },
    { family: 'Pacifico', weights: [400], group: 'Script' },
  ];

  // Common Windows fonts. Only the ones actually installed are offered.
  const SYSTEM = ['Arial', 'Arial Black', 'Times New Roman', 'Georgia', 'Segoe UI', 'Verdana',
    'Tahoma', 'Trebuchet MS', 'Impact', 'Courier New', 'Segoe Script', 'Calibri', 'Cambria'];

  const WEIGHT_NAMES = { 100: 'Thin', 200: 'Extra light', 300: 'Light', 400: 'Regular', 500: 'Medium',
    600: 'Semibold', 700: 'Bold', 800: 'Extra bold', 900: 'Black' };

  const uploaded = new Map();        // family -> [{ weight, style, mime, data(ArrayBuffer), variable, source, face }]
  const installedCache = new Map();

  function quote(family) {
    return `"${String(family).replace(/["\\]/g, '')}"`;
  }

  function cssFont(family, weight, italic, sizePx) {
    return `${italic ? 'italic ' : ''}${weight || 400} ${sizePx}px ${quote(family)}, sans-serif`;
  }

  function builtIn(family) {
    return BUILT_IN.find((f) => f.family === family) || null;
  }

  // A font is installed if text drawn with it measures differently from the fallbacks.
  function isInstalled(family) {
    if (installedCache.has(family)) return installedCache.get(family);
    const ctx = document.createElement('canvas').getContext('2d');
    const sample = 'mmmmmmmmmmlli WQ@#0123';
    let found = false;
    for (const fallback of ['monospace', 'serif', 'sans-serif']) {
      ctx.font = `72px ${fallback}`;
      const base = ctx.measureText(sample).width;
      ctx.font = `72px ${quote(family)}, ${fallback}`;
      if (Math.abs(ctx.measureText(sample).width - base) > 0.5) { found = true; break; }
    }
    installedCache.set(family, found);
    return found;
  }

  function kind(family) {
    if (builtIn(family)) return 'built-in';
    if (uploaded.has(family)) return 'uploaded';
    if (SYSTEM.includes(family)) return 'system';
    return 'unknown';
  }

  function weightsFor(family) {
    const b = builtIn(family);
    const faces = uploaded.has(family) ? uploaded.get(family) : [];
    const mine = faces.some((f) => f.variable) ? [100, 200, 300, 400, 500, 600, 700, 800, 900] : faces.map((f) => f.weight);
    if (!b && !mine.length) return [400, 700];
    return [...new Set([...(b ? b.weights : []), ...mine])].sort((x, y) => x - y);
  }

  function nearestWeight(family, weight) {
    const ws = weightsFor(family);
    return ws.reduce((best, w) => (Math.abs(w - weight) < Math.abs(best - weight) ? w : best), ws[0]);
  }

  // Grouped list for the font picker.
  function catalog() {
    const groups = [];
    const byGroup = new Map();
    for (const f of BUILT_IN) {
      if (!byGroup.has(f.group)) byGroup.set(f.group, []);
      byGroup.get(f.group).push(f.family);
    }
    for (const [label, families] of byGroup) groups.push({ label, families });
    const mine = [...uploaded.keys()].filter((f) => !builtIn(f)).sort();
    if (mine.length) groups.unshift({ label: 'Fonts you added', families: mine });
    const system = SYSTEM.filter(isInstalled);
    if (system.length) groups.push({ label: 'On this computer', families: system });
    return groups;
  }

  // Makes a font file usable on the page. Variable fonts cover every weight from one file.
  async function register(family, weight, style, data, mime, opts = {}) {
    const face = new FontFace(family, data, { weight: opts.variable ? '100 900' : String(weight), style });
    await face.load();
    document.fonts.add(face);
    if (!uploaded.has(family)) uploaded.set(family, []);
    const list = uploaded.get(family);
    const old = list.findIndex((f) => f.weight === weight && f.style === style && !!f.variable === !!opts.variable);
    if (old >= 0) {
      document.fonts.delete(list[old].face);
      list.splice(old, 1);
    }
    list.push({ weight, style, mime, data, variable: !!opts.variable, source: opts.source || 'file', face });
  }

  function unregister(family) {
    for (const f of uploaded.get(family) || []) document.fonts.delete(f.face);
    uploaded.delete(family);
  }

  // Fonts people added, for the "Your fonts" list.
  function added() {
    return [...uploaded.entries()].map(([family, faces]) => ({
      family,
      source: faces.some((f) => f.source === 'library') ? 'library' : 'file',
      styles: faces.length,
      weights: weightsFor(family).filter((w) => faces.some((f) => f.variable || f.weight === w)),
    })).sort((a, b) => a.family.localeCompare(b.family));
  }

  // Turns "Montserrat-BoldItalic.ttf" into { family: 'Montserrat', weight: 700, style: 'italic' }.
  function describeFile(fileName) {
    const stem = fileName.replace(/\.[^.]+$/, '');
    const lower = stem.toLowerCase().replace(/[\s_-]/g, '');
    const weights = [['extrablack', 900], ['black', 900], ['heavy', 900], ['extrabold', 800], ['ultrabold', 800],
      ['semibold', 600], ['demibold', 600], ['bold', 700], ['medium', 500], ['extralight', 200], ['ultralight', 200],
      ['light', 300], ['thin', 100], ['hairline', 100], ['regular', 400], ['book', 400], ['normal', 400]];
    let weight = 400;
    for (const [word, w] of weights) {
      if (lower.includes(word)) { weight = w; break; }
    }
    const style = /italic|oblique/i.test(stem) ? 'italic' : 'normal';
    const family = stem
      .replace(/[-_]?(extra|ultra|semi|demi)?(black|heavy|bold|medium|light|thin|hairline|regular|book|normal)?(italic|oblique)?$/i, '')
      .replace(/[-_]+/g, ' ')
      .replace(/([a-z])([A-Z])/g, '$1 $2')
      .trim() || stem;
    return { family, weight, style };
  }

  // Waits until every font a layout uses is ready, so canvas text never falls back silently.
  async function ensure(doc) {
    const wanted = new Set();
    for (const el of doc.elements) {
      if (el.type === 'text') wanted.add(cssFont(el.font, el.weight, el.italic, 40));
    }
    await Promise.all([...wanted].map((f) => document.fonts.load(f).catch(() => null)));
  }

  // Families used by a layout that this computer can't draw.
  function missing(doc) {
    const out = new Set();
    for (const el of doc.elements) {
      if (el.type !== 'text') continue;
      const k = kind(el.font);
      if (k === 'unknown' || (k === 'system' && !isInstalled(el.font))) out.add(el.font);
    }
    return [...out];
  }

  function toBase64(buffer) {
    const bytes = new Uint8Array(buffer);
    let s = '';
    for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return btoa(s);
  }

  function fromBase64(b64) {
    const s = atob(b64);
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out.buffer;
  }

  // Uploaded fonts a layout uses, packed for a layout file.
  function embedFor(doc) {
    const out = {};
    for (const el of doc.elements) {
      if (el.type !== 'text' || !uploaded.has(el.font) || out[el.font]) continue;
      out[el.font] = uploaded.get(el.font).map((f) => ({ weight: f.weight, style: f.style, mime: f.mime, variable: f.variable, data: toBase64(f.data) }));
    }
    return out;
  }

  PIO.fonts = {
    BUILT_IN, WEIGHT_NAMES, cssFont, kind, isInstalled, weightsFor, nearestWeight, catalog, register, unregister, added,
    describeFile, ensure, missing, embedFor, toBase64, fromBase64,
    isUploaded: (family) => uploaded.has(family),
  };
})(window.PIO = window.PIO || {});
