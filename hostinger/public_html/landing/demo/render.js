/*
 * Draws layouts. The editor preview, the thumbnails and the full-size saved
 * photos all go through these same functions, so what you see is what you get.
 */
(function (PIO) {
  'use strict';

  const { model, fonts, icons } = PIO;
  const RAD = Math.PI / 180;
  const bitmapCache = new Map();
  const measureCtx = document.createElement('canvas').getContext('2d');
  const HAS_SPACING = 'letterSpacing' in measureCtx;

  // ---------- small helpers ----------

  function rgba(hex, a) {
    const n = parseInt(String(hex).slice(1), 16) || 0;
    return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a == null ? 1 : a})`;
  }

  function dataToBlob(dataUrl) {
    const comma = dataUrl.indexOf(',');
    const mime = dataUrl.slice(5, dataUrl.indexOf(';'));
    const bin = atob(dataUrl.slice(comma + 1));
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new Blob([bytes], { type: mime });
  }

  function blobToDataUrl(blob) {
    return new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(r.result);
      r.onerror = () => reject(r.error);
      r.readAsDataURL(blob);
    });
  }

  function bitmapFor(asset) {
    let p = bitmapCache.get(asset.data);
    if (!p) {
      p = createImageBitmap(dataToBlob(asset.data));
      bitmapCache.set(asset.data, p);
      p.catch(() => bitmapCache.delete(asset.data));
    }
    return p;
  }

  // Decodes the layout's pictures and waits for its fonts.
  async function prepare(doc) {
    const bitmaps = new Map();
    await Promise.all([
      fonts.ensure(doc),
      ...Object.entries(doc.assets).map(async ([id, a]) => {
        try {
          bitmaps.set(id, await bitmapFor(a));
        } catch (err) {
          console.warn(`Picture "${a.name}" could not be read.`, err);
        }
      }),
    ]);
    return { bitmaps };
  }

  function mulberry(seed) {
    let a = seed >>> 0;
    return () => {
      a = (a + 0x6D2B79F5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function roundRect(p, x, y, w, h, r) {
    r = Math.max(0, Math.min(r || 0, w / 2, h / 2));
    if (!r) { p.rect(x, y, w, h); return p; }
    p.moveTo(x + r, y);
    p.arcTo(x + w, y, x + w, y + h, r);
    p.arcTo(x + w, y + h, x, y + h, r);
    p.arcTo(x, y + h, x, y, r);
    p.arcTo(x, y, x + w, y, r);
    p.closePath();
    return p;
  }

  function poly(p, pts) {
    pts.forEach(([x, y], i) => (i ? p.lineTo(x, y) : p.moveTo(x, y)));
    p.closePath();
    return p;
  }

  function shapePath(el, w, h) {
    const p = new Path2D();
    const ring = (n, radiusAt) => {
      const pts = [];
      for (let i = 0; i < n; i++) {
        const a = (-90 + (i * 360) / n) * RAD;
        const r = radiusAt(i);
        pts.push([w / 2 + (w / 2) * r * Math.cos(a), h / 2 + (h / 2) * r * Math.sin(a)]);
      }
      return poly(p, pts);
    };
    switch (el.shape) {
      case 'ellipse': p.ellipse(w / 2, h / 2, w / 2, h / 2, 0, 0, Math.PI * 2); return p;
      case 'triangle': return poly(p, [[w / 2, 0], [w, h], [0, h]]);
      case 'diamond': return poly(p, [[w / 2, 0], [w, h / 2], [w / 2, h], [0, h / 2]]);
      case 'polygon': return ring(el.sides || 6, () => 1);
      case 'star': return ring((el.points || 5) * 2, (i) => (i % 2 ? el.inner || 0.45 : 1));
      case 'arrow': return poly(p, [[0, h * 0.32], [w * 0.62, h * 0.32], [w * 0.62, 0], [w, h / 2], [w * 0.62, h], [w * 0.62, h * 0.68], [0, h * 0.68]]);
      case 'torn': {
        // A band with a ragged top edge, like torn paper.
        const rand = mulberry(el.seed || 7);
        const amp = (el.rough == null ? 0.5 : el.rough) * Math.min(h * 0.45, 70);
        const steps = Math.max(12, Math.round(w / 16));
        p.moveTo(0, amp * rand());
        for (let i = 1; i <= steps; i++) p.lineTo((w * i) / steps, amp * (i % 2 ? 0.55 + 0.45 * rand() : 0.35 * rand()));
        p.lineTo(w, h);
        p.lineTo(0, h);
        p.closePath();
        return p;
      }
      default: return roundRect(p, 0, 0, w, h, el.radius);
    }
  }

  function paint(ctx, fill, w, h) {
    if (!fill || fill.type === 'none') return null;
    if (fill.type === 'solid') return rgba(fill.color, fill.alpha);
    const stops = [...fill.stops].sort((a, b) => a.at - b.at);
    let g;
    if (fill.type === 'radial') {
      g = ctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, Math.hypot(w, h) / 2);
    } else {
      const a = (fill.angle || 0) * RAD;
      const dx = Math.cos(a);
      const dy = Math.sin(a);
      const half = Math.abs((w / 2) * dx) + Math.abs((h / 2) * dy) || 1;
      g = ctx.createLinearGradient(w / 2 - dx * half, h / 2 - dy * half, w / 2 + dx * half, h / 2 + dy * half);
    }
    for (const s of stops) g.addColorStop(Math.min(1, Math.max(0, s.at)), rgba(s.color, s.alpha));
    return g;
  }

  function shadowOn(ctx, sh, px) {
    if (sh && sh.on && sh.alpha > 0) {
      ctx.shadowColor = rgba(sh.color, sh.alpha);
      ctx.shadowBlur = sh.blur * px;
      ctx.shadowOffsetX = sh.x * px;
      ctx.shadowOffsetY = sh.y * px;
    } else {
      shadowOff(ctx);
    }
  }

  function shadowOff(ctx) {
    ctx.shadowColor = 'rgba(0,0,0,0)';
    ctx.shadowBlur = 0;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 0;
  }

  function filterOf(fx, px) {
    if (!fx) return 'none';
    const parts = [];
    if (fx.blur > 0) parts.push(`blur(${(fx.blur * px).toFixed(2)}px)`);
    if (fx.brightness !== 100) parts.push(`brightness(${fx.brightness}%)`);
    if (fx.contrast !== 100) parts.push(`contrast(${fx.contrast}%)`);
    if (fx.saturate !== 100) parts.push(`saturate(${fx.saturate}%)`);
    if (fx.grayscale > 0) parts.push(`grayscale(${fx.grayscale}%)`);
    return parts.length ? parts.join(' ') : 'none';
  }

  // ---------- text ----------

  function setSpacing(ctx, ls) {
    if (HAS_SPACING) ctx.letterSpacing = `${ls || 0}px`;
  }

  function lineWidth(ctx, line, ls) {
    if (!line) return 0;
    if (HAS_SPACING) return ctx.measureText(line).width - (ls || 0);
    if (!ls) return ctx.measureText(line).width;
    let w = 0;
    for (const ch of line) w += ctx.measureText(ch).width + ls;
    return w - ls;
  }

  function fillLine(ctx, line, x, y, ls, stroke) {
    if (HAS_SPACING || !ls) {
      if (stroke) ctx.strokeText(line, x, y); else ctx.fillText(line, x, y);
      return;
    }
    for (const ch of line) {
      if (stroke) ctx.strokeText(ch, x, y); else ctx.fillText(ch, x, y);
      x += ctx.measureText(ch).width + ls;
    }
  }

  // Lines, widths and the box size of a text element, in design units.
  function textLayout(el, ctx) {
    ctx = ctx || measureCtx;
    ctx.save();
    ctx.font = fonts.cssFont(el.font, el.weight, el.italic, el.size);
    setSpacing(ctx, el.letterSpacing);
    const lines = (el.upper ? el.text.toUpperCase() : el.text).split('\n');
    const widths = lines.map((l) => lineWidth(ctx, l, el.letterSpacing));
    const m = ctx.measureText('Hg');
    const asc = m.fontBoundingBoxAscent || el.size * 0.9;
    const desc = m.fontBoundingBoxDescent || el.size * 0.25;
    ctx.restore();
    const lh = el.size * el.lineHeight;
    return { lines, widths, lh, asc, desc, w: Math.max(1, ...widths), h: Math.max(1, lh * lines.length) };
  }

  function drawText(ctx, el, box, px) {
    const L = textLayout(el, ctx);
    ctx.font = fonts.cssFont(el.font, el.weight, el.italic, el.size);
    setSpacing(ctx, el.letterSpacing);
    ctx.textBaseline = 'alphabetic';
    ctx.textAlign = 'left';
    const style = paint(ctx, el.fill, box.w, box.h);
    const pos = L.lines.map((line, i) => {
      const free = box.w - L.widths[i];
      const x = el.align === 'center' ? free / 2 : el.align === 'right' ? free : 0;
      return [line, x, i * L.lh + (L.lh - (L.asc + L.desc)) / 2 + L.asc];
    });
    const outline = el.stroke && el.stroke.width > 0;
    if (outline) {
      ctx.lineWidth = el.stroke.width * 2;
      ctx.lineJoin = 'round';
      ctx.miterLimit = 2;
      ctx.strokeStyle = rgba(el.stroke.color, el.stroke.alpha);
      for (const [line, x, y] of pos) fillLine(ctx, line, x, y, el.letterSpacing, true);
      shadowOff(ctx);
    }
    if (style) {
      ctx.fillStyle = style;
      for (const [line, x, y] of pos) fillLine(ctx, line, x, y, el.letterSpacing, false);
    }
  }

  // ---------- pieces ----------

  function drawShape(ctx, el, box) {
    const p = shapePath(el, box.w, box.h);
    const style = paint(ctx, el.fill, box.w, box.h);
    if (style) {
      ctx.fillStyle = style;
      ctx.fill(p);
      shadowOff(ctx);
    }
    if (el.stroke && el.stroke.width > 0) {
      ctx.lineWidth = el.stroke.width;
      ctx.lineJoin = 'round';
      ctx.strokeStyle = rgba(el.stroke.color, el.stroke.alpha);
      ctx.stroke(p);
    }
  }

  function drawImage(ctx, el, box, bmp) {
    if (!bmp) return;
    const { w, h } = box;
    const clip = roundRect(new Path2D(), 0, 0, w, h, el.radius);
    let dx = 0, dy = 0, dw = w, dh = h;
    let clipped = el.radius > 0;
    if (el.fit === 'contain') {
      const k = Math.min(w / bmp.width, h / bmp.height);
      dw = bmp.width * k; dh = bmp.height * k; dx = (w - dw) / 2; dy = (h - dh) / 2;
    } else if (el.fit === 'cover') {
      const k = Math.max(w / bmp.width, h / bmp.height);
      dw = bmp.width * k; dh = bmp.height * k; dx = (w - dw) / 2; dy = (h - dh) / 2;
      clipped = true;
    }
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    if (clipped) {
      if (el.shadow && el.shadow.on && el.shadow.alpha > 0) {
        ctx.fillStyle = '#000';
        ctx.fill(clip);         // casts the shadow; the picture covers it
        shadowOff(ctx);
      }
      ctx.save();
      ctx.clip(clip);
      ctx.drawImage(bmp, dx, dy, dw, dh);
      ctx.restore();
    } else {
      ctx.drawImage(bmp, dx, dy, dw, dh);
    }
    shadowOff(ctx);
    if (el.stroke && el.stroke.width > 0) {
      ctx.lineWidth = el.stroke.width;
      ctx.strokeStyle = rgba(el.stroke.color, el.stroke.alpha);
      ctx.stroke(clip);
    }
  }

  function drawIcon(ctx, el, box) {
    const { w, h } = box;
    const bg = el.iconBg && el.iconBg.shape !== 'none' ? el.iconBg : null;
    if (bg) {
      const p = new Path2D();
      if (bg.shape === 'circle') p.ellipse(w / 2, h / 2, w / 2, h / 2, 0, 0, Math.PI * 2);
      else roundRect(p, 0, 0, w, h, Math.min(w, h) * 0.22);
      ctx.fillStyle = rgba(bg.color, bg.alpha);
      ctx.fill(p);
      shadowOff(ctx);
      if (el.stroke && el.stroke.width > 0) {
        ctx.lineWidth = el.stroke.width;
        ctx.strokeStyle = rgba(el.stroke.color, el.stroke.alpha);
        ctx.stroke(p);
      }
    }
    const k = (Math.min(w, h) * (bg ? 0.6 : 1)) / 24;
    ctx.save();
    ctx.translate(w / 2 - 12 * k, h / 2 - 12 * k);
    ctx.scale(k, k);
    const style = paint(ctx, el.fill, 24, 24) || '#000';
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.lineWidth = el.lineWidth || 2;
    for (const part of icons.parts(el.icon)) {
      if (part.fill) { ctx.fillStyle = style; ctx.fill(part.path, part.rule || 'nonzero'); }
      else { ctx.strokeStyle = style; ctx.stroke(part.path); }
    }
    ctx.restore();
  }

  // The element's transform, from its own 0..w / 0..h space to design units.
  function matrixOf(el, box) {
    const m = new DOMMatrix().translate(box.x + box.w / 2, box.y + box.h / 2);
    if (el.rotation) m.rotateSelf(el.rotation);
    if (el.skewX || el.skewY) m.multiplySelf(new DOMMatrix([1, Math.tan(el.skewY * RAD), Math.tan(el.skewX * RAD), 1, 0, 0]));
    if (el.flipX || el.flipY) m.scaleSelf(el.flipX ? -1 : 1, el.flipY ? -1 : 1);
    return m.translateSelf(-box.w / 2, -box.h / 2);
  }

  function drawElement(ctx, el, prep, frameH, px) {
    const box = model.boxOf(el, frameH);
    if (box.w <= 0 || box.h <= 0) return;
    ctx.save();
    const m = matrixOf(el, box);
    ctx.transform(m.a, m.b, m.c, m.d, m.e, m.f);
    ctx.globalAlpha *= el.opacity;
    ctx.globalCompositeOperation = el.blend || 'source-over';
    const filter = filterOf(el.effects, px);
    if (filter !== 'none') ctx.filter = filter;
    shadowOn(ctx, el.shadow, px);
    if (el.type === 'text') drawText(ctx, el, box, px);
    else if (el.type === 'shape') drawShape(ctx, el, box);
    else if (el.type === 'image') drawImage(ctx, el, box, prep && prep.bitmaps.get(el.asset));
    else if (el.type === 'icon') drawIcon(ctx, el, box);
    ctx.restore();
  }

  // Draws every visible piece. ctx must already be scaled so 1 unit = 1 design unit;
  // px is how many device pixels one design unit covers (for shadows and blur).
  function drawLayout(ctx, doc, prep, frameH, px) {
    for (const el of doc.elements) {
      if (el.visible) drawElement(ctx, el, prep, frameH, px);
    }
  }

  // ---------- photos ----------

  // Output size, photo crop and layout scale for a photo of pw x ph pixels.
  function photoGeometry(pw, ph, doc) {
    if (doc && doc.fit === 'crop') {
      const r = doc.ratio;
      let w = pw;
      let h = ph;
      if (pw / ph > r) w = Math.round(ph * r); else h = Math.round(pw / r);
      return { w, h, crop: { x: Math.round((pw - w) / 2), y: Math.round((ph - h) / 2), w, h }, s: w / doc.width, frameH: doc.width / r };
    }
    const width = doc ? doc.width : model.DESIGN_W;
    return { w: pw, h: ph, crop: { x: 0, y: 0, w: pw, h: ph }, s: pw / width, frameH: (width * ph) / pw };
  }

  // Draws a photo (src may be a reduced copy: k = src pixels per photo pixel) with
  // the layout on top. out = output pixels per photo pixel.
  function compose(ctx, src, k, g, doc, prep, out) {
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    const c = g.crop;
    ctx.drawImage(src, c.x * k, c.y * k, c.w * k, c.h * k, 0, 0, g.w * out, g.h * out);
    if (!doc) return;
    const px = g.s * out;
    ctx.save();
    ctx.scale(px, px);
    drawLayout(ctx, doc, prep, g.frameH, px);
    ctx.restore();
  }

  // The layout alone on a transparent background, widthPx wide.
  function layoutCanvas(doc, prep, widthPx, previewRatio, canvas) {
    const frameH = model.frameHeight(doc, previewRatio);
    const px = widthPx / doc.width;
    canvas = canvas || document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(widthPx));
    canvas.height = Math.max(1, Math.round(frameH * px));
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.save();
    ctx.scale(px, px);
    drawLayout(ctx, doc, prep, frameH, px);
    ctx.restore();
    return canvas;
  }

  // Pictures that get stretched past `limit` times their real size on a photo `photoW` pixels wide.
  function softPictures(doc, prep, photoW, limit) {
    const s = photoW / doc.width;
    const out = [];
    for (const el of doc.elements) {
      if (!el.visible || el.type !== 'image') continue;
      const bmp = prep.bitmaps.get(el.asset);
      if (!bmp) continue;
      const k = el.fit === 'cover' ? Math.max(el.w / bmp.width, el.h / bmp.height) : Math.min(el.w / bmp.width, el.h / bmp.height);
      const shown = bmp.width * k * s;
      if (shown / bmp.width > limit) out.push({ name: el.name || 'Picture', natural: bmp.width, shown: Math.round(shown) });
    }
    return out;
  }

  // Checks a picture for transparency and guesses where it belongs (used for imports).
  function analyseAlpha(bitmap) {
    const w = Math.min(200, bitmap.width);
    const h = Math.max(2, Math.round((bitmap.height * w) / bitmap.width));
    const c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    const ctx = c.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(bitmap, 0, 0, w, h);
    const px = ctx.getImageData(0, 0, w, h).data;
    let hasAlpha = false;
    let topClear = true;
    let bottomClear = true;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const a = px[(y * w + x) * 4 + 3];
        if (a < 250) hasAlpha = true;
        if (a > 8) {
          if (y < h * 0.45) topClear = false;
          else if (y >= h * 0.55) bottomClear = false;
        }
      }
    }
    let placement = 'frame';
    if (bitmap.width / bitmap.height >= 2.2 || (topClear && !bottomClear)) placement = 'footer';
    else if (bottomClear && !topClear) placement = 'header';
    else if (topClear && bottomClear) placement = 'center';
    return { hasAlpha, placement };
  }

  // A layout picture that covers the whole frame (header, footer, side borders) can be cut
  // along its see-through middle. Each part then gets pinned to its own edge and the side
  // borders stretch, so the layout fits photos of any shape instead of cropping them.
  // Returns the parts in the picture's pixels, or null when the middle isn't see-through.
  function splitFrame(bitmap) {
    const W = bitmap.width;
    const H = bitmap.height;
    const k = Math.min(1, 640 / W);
    const w = Math.max(1, Math.round(W * k));
    const h = Math.max(1, Math.round(H * k));
    const c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    const ctx = c.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(bitmap, 0, 0, w, h);
    const px = ctx.getImageData(0, 0, w, h).data;
    const on = (x, y) => px[(y * w + x) * 4 + 3] > 12;
    const side = Math.max(1, Math.round(w * 0.15));

    // The longest run of rows with nothing in the middle 70% of the width.
    let best = null;
    let start = -1;
    for (let y = 0; y <= h; y++) {
      let empty = y < h;
      for (let x = side; empty && x < w - side; x++) if (on(x, y)) empty = false;
      if (empty && start < 0) start = y;
      if (!empty && start >= 0) {
        if (!best || y - start > best.end - best.start) best = { start, end: y };
        start = -1;
      }
    }
    if (!best || best.end - best.start < h * 0.2) return null;
    let r0 = best.start;
    let r1 = best.end;

    // How far side content reaches in from each edge on one row (-1 = none).
    const reach = (y, left) => {
      for (let i = side - 1; i >= 0; i--) if (on(left ? i : w - 1 - i, y)) return i;
      return -1;
    };
    // A border runs down (almost) the whole middle. Anything sticking out past it near the
    // top or bottom belongs to the header or footer, so the middle shrinks to leave it out.
    const borders = { left: -1, right: -1 };
    for (let pass = 0; pass < 4; pass++) {
      let n0 = r0;
      let n1 = r1;
      for (const left of [true, false]) {
        const ext = [];
        for (let y = r0; y < r1; y++) ext.push(reach(y, left));
        const hits = ext.filter((e) => e >= 0).sort((a, b) => a - b);
        const border = hits.length >= ext.length * 0.8 ? hits[Math.floor(hits.length * 0.2)] : -1;
        borders[left ? 'left' : 'right'] = border;
        const middle = (r0 + r1) / 2;
        ext.forEach((e, i) => {
          if (e <= border + 1) return;
          const y = r0 + i;
          if (y < middle) n0 = Math.max(n0, y + 1); else n1 = Math.min(n1, y);
        });
      }
      if (n0 === r0 && n1 === r1) break;
      r0 = n0;
      r1 = n1;
      if (r1 - r0 < h * 0.2) return null;
    }

    const Y0 = Math.min(H, Math.floor(r0 / k));
    const Y1 = Math.max(Y0, Math.min(H, Math.ceil(r1 / k)));
    const parts = [];
    if (Y0 > 0) parts.push({ edge: 'top', x: 0, y: 0, w: W, h: Y0 });
    if (Y1 < H) parts.push({ edge: 'bottom', x: 0, y: Y1, w: W, h: H - Y1 });
    if (borders.left >= 0) parts.push({ edge: 'left', x: 0, y: Y0, w: Math.min(W, Math.ceil((borders.left + 1) / k)), h: Y1 - Y0 });
    if (borders.right >= 0) {
      const bw = Math.min(W, Math.ceil((borders.right + 1) / k));
      parts.push({ edge: 'right', x: W - bw, y: Y0, w: bw, h: Y1 - Y0 });
    }
    return parts.length ? { W, H, parts } : null;
  }

  // Where a picture actually shows inside its box, in design units.
  function shownRect(el, box, bmp) {
    if (el.fit !== 'contain') return box;
    const k = Math.min(box.w / bmp.width, box.h / bmp.height);
    const w = bmp.width * k;
    const h = bmp.height * k;
    return { x: box.x + (box.w - w) / 2, y: box.y + (box.h - h) / 2, w, h };
  }

  // Splits full-frame pictures in a layout into parts pinned to their edges (see splitFrame).
  // With `ids`, only those pictures; otherwise every picture that covers the frame.
  // Returns { split: number of pictures split, failed: the first picture that couldn't be }.
  async function fitAnyShape(doc, prep, frameH, ids) {
    let split = 0;
    for (const el of [...doc.elements]) {
      if (el.type !== 'image' || (ids && !ids.includes(el.id))) continue;
      const box = model.boxOf(el, frameH);
      if (!ids && !(box.w >= doc.width * 0.9 && box.h >= frameH * 0.9)) continue;
      const bmp = prep.bitmaps.get(el.asset);
      const s = bmp && el.fit !== 'cover' && !el.rotation && !el.skewX && !el.skewY ? splitFrame(bmp) : null;
      if (!s) return { split, failed: el };
      const parts = await cutParts(bmp, s);
      const pieces = model.partsToElements(doc, el.name, parts, s.W, s.H, shownRect(el, box, bmp), frameH);
      for (const p of pieces) Object.assign(p, { opacity: el.opacity, blend: el.blend, visible: el.visible, effects: { ...el.effects } });
      for (const p of pieces) prep.bitmaps.set(p.asset, await bitmapFor(doc.assets[p.asset]));
      doc.elements.splice(doc.elements.indexOf(el), 1, ...pieces);
      split++;
    }
    return { split, failed: null };
  }

  // Whether a layout crops photos only because of a full-frame picture (which could be split).
  function hasFramePicture(doc) {
    const fh = model.frameHeight(doc);
    return doc.elements.some((el) => {
      if (el.type !== 'image') return false;
      const b = model.boxOf(el, fh);
      return b.w >= doc.width * 0.9 && b.h >= fh * 0.9;
    });
  }

  // Cuts the parts out of the picture as PNG data URLs.
  async function cutParts(bitmap, split) {
    const out = [];
    for (const p of split.parts) {
      const c = document.createElement('canvas');
      c.width = p.w;
      c.height = p.h;
      c.getContext('2d').drawImage(bitmap, p.x, p.y, p.w, p.h, 0, 0, p.w, p.h);
      const blob = await new Promise((res) => c.toBlob(res, 'image/png'));
      out.push({ ...p, data: await blobToDataUrl(blob) });
    }
    return out;
  }

  PIO.render = {
    rgba, dataToBlob, blobToDataUrl, bitmapFor, prepare, textLayout, shapePath, matrixOf, drawElement, drawLayout,
    photoGeometry, compose, layoutCanvas, softPictures, analyseAlpha, splitFrame, cutParts, fitAnyShape,
    hasFramePicture, roundRect,
  };
})(window.PIO = window.PIO || {});
