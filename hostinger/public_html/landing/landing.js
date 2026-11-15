/*
 * e-Layout landing page.
 * Part 1 (ported from the old tool's landing.js): draws three sample "photos" (simple drawings,
 * not real photos) and puts the real PIO footer on them with the same render code the old tool
 * uses to save photos.
 * Part 2: the theme override for screenshots, the buttons in the visitor's platform order, and the
 * download buttons filled from download/latest.json. No inline styles (the page's CSP forbids them).
 */
(function (PIO) {
  'use strict';

  const { model, render } = PIO;
  const canvases = [...document.querySelectorAll('.frame canvas')];
  const toggles = [...document.querySelectorAll('[data-footer]')];
  let footer = null;      // { doc, prep } once the PIO footer is ready
  let withFooter = true;

  // ---------- drawing helpers ----------

  // Same numbers every time, so the drawings don't change on resize.
  function seeded(seed) {
    let s = seed >>> 0;
    return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  }

  function vertical(ctx, y0, y1, stops) {
    const g = ctx.createLinearGradient(0, y0, 0, y1);
    stops.forEach((c, i) => g.addColorStop(i / (stops.length - 1), c));
    return g;
  }

  function disc(ctx, x, y, r, color) {
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
  }

  // A soft line of hills or mountains standing on `base`.
  function ridge(ctx, w, h, base, amp, color, seed, from = 0, to = 1) {
    const rnd = seeded(seed);
    const n = 7;
    const pts = [];
    for (let i = 0; i <= n; i++) pts.push([w * (from + ((to - from) * i) / n), base - amp * (0.35 + rnd() * 0.65)]);
    ctx.beginPath();
    ctx.moveTo(w * from, h);
    ctx.lineTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < pts.length; i++) {
      const [px, py] = pts[i - 1];
      const [x, y] = pts[i];
      ctx.quadraticCurveTo(px + (x - px) / 2, Math.min(py, y) - amp * 0.25, x, y);
    }
    ctx.lineTo(w * to, h);
    ctx.closePath();
    ctx.fillStyle = color;
    ctx.fill();
  }

  function cloud(ctx, x, y, s) {
    ctx.fillStyle = 'rgba(255,255,255,0.72)';
    for (const [dx, dy, r] of [[0, 0, 1], [0.9, 0.15, 0.75], [-0.85, 0.2, 0.7], [0.35, -0.35, 0.7]]) {
      ctx.beginPath();
      ctx.ellipse(x + dx * s, y + dy * s, r * s * 1.25, r * s * 0.8, 0, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  // ---------- the three scenes ----------

  // Farm rows at sunrise (organic farming is what the town is known for).
  function field(ctx, w, h) {
    const hz = h * 0.56;
    ctx.fillStyle = vertical(ctx, 0, hz, ['#6EA6D3', '#BCD5E2', '#F3DCAE']);
    ctx.fillRect(0, 0, w, hz + 2);
    const sx = w * 0.7;
    const sy = hz - h * 0.07;
    const glow = ctx.createRadialGradient(sx, sy, h * 0.03, sx, sy, h * 0.36);
    glow.addColorStop(0, 'rgba(255,238,196,0.95)');
    glow.addColorStop(1, 'rgba(255,238,196,0)');
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, w, hz);
    disc(ctx, sx, sy, h * 0.055, '#FFF3D2');
    cloud(ctx, w * 0.2, h * 0.17, h * 0.05);
    ridge(ctx, w, hz + 2, hz, h * 0.13, '#86A0B4', 11);
    ridge(ctx, w, hz + 2, hz, h * 0.06, '#5F806C', 29);
    ctx.fillStyle = vertical(ctx, hz, h, ['#7AA455', '#4F7F35', '#3B6A28']);
    ctx.fillRect(0, hz, w, h - hz);
    // Crop rows running to a point on the horizon
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, hz, w, h - hz);
    ctx.clip();
    const vx = w * 0.44;
    ctx.fillStyle = 'rgba(32,68,22,0.34)';
    for (let i = -16; i <= 16; i++) {
      const x = vx + i * w * 0.1;
      ctx.beginPath();
      ctx.moveTo(vx + i * w * 0.004, hz);
      ctx.lineTo(x - w * 0.022, h);
      ctx.lineTo(x + w * 0.022, h);
      ctx.closePath();
      ctx.fill();
    }
    ctx.restore();
    const rnd = seeded(7);
    for (let i = 0; i < 30; i++) disc(ctx, (i / 29) * w + (rnd() - 0.5) * w * 0.03, hz + h * 0.004, h * (0.01 + rnd() * 0.012), '#42633A');
  }

  // The coast, with a coconut tree.
  function coast(ctx, w, h) {
    const hz = h * 0.47;
    ctx.fillStyle = vertical(ctx, 0, hz, ['#76B0DC', '#B9D6E8', '#E6F0F3']);
    ctx.fillRect(0, 0, w, hz + 2);
    cloud(ctx, w * 0.32, h * 0.13, w * 0.07);
    cloud(ctx, w * 0.82, h * 0.22, w * 0.05);
    ridge(ctx, w, hz + 2, hz, h * 0.05, '#6A8A80', 5, 0, 0.5);
    ctx.fillStyle = vertical(ctx, hz, h * 0.74, ['#4B95C6', '#2F74A3']);
    ctx.fillRect(0, hz, w, h * 0.74 - hz);
    ctx.strokeStyle = 'rgba(255,255,255,0.22)';
    ctx.lineWidth = Math.max(1, h * 0.003);
    const rnd = seeded(3);
    for (let i = 0; i < 14; i++) {
      const y = hz + (h * 0.74 - hz) * (0.1 + rnd() * 0.85);
      const x = rnd() * w;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + w * (0.08 + rnd() * 0.14), y);
      ctx.stroke();
    }
    ctx.fillStyle = vertical(ctx, h * 0.74, h, ['#EFE1BF', '#DCC79B']);
    ctx.fillRect(0, h * 0.74, w, h * 0.26);
    ctx.fillStyle = 'rgba(255,255,255,0.7)';
    ctx.fillRect(0, h * 0.74, w, Math.max(1, h * 0.006));
    // Coconut tree
    const crown = { x: w * 0.42, y: h * 0.27 };
    ctx.lineCap = 'round';
    ctx.strokeStyle = '#6E5137';
    ctx.lineWidth = w * 0.045;
    ctx.beginPath();
    ctx.moveTo(w * 0.86, h * 1.02);
    ctx.quadraticCurveTo(w * 0.6, h * 0.62, crown.x, crown.y);
    ctx.stroke();
    const leaf = (angle, len, color) => {
      const a = (angle * Math.PI) / 180;
      const tx = crown.x + Math.cos(a) * len;
      const ty = crown.y + Math.sin(a) * len;
      const nx = -Math.sin(a) * len * 0.18;
      const ny = Math.cos(a) * len * 0.18;
      const mx = (crown.x + tx) / 2;
      const my = (crown.y + ty) / 2 - len * 0.18;
      ctx.beginPath();
      ctx.moveTo(crown.x, crown.y);
      ctx.quadraticCurveTo(mx + nx, my + ny, tx, ty + len * 0.12);
      ctx.quadraticCurveTo(mx - nx, my - ny, crown.x, crown.y);
      ctx.fillStyle = color;
      ctx.fill();
    };
    for (const [ang, len, c] of [[200, 0.42, '#2E5A31'], [235, 0.36, '#3C7140'], [275, 0.3, '#2E5A31'], [310, 0.38, '#3C7140'],
      [345, 0.44, '#2E5A31'], [20, 0.36, '#3C7140'], [160, 0.36, '#3C7140']]) leaf(ang, w * len, c);
    disc(ctx, crown.x - w * 0.02, crown.y + w * 0.03, w * 0.022, '#5A4526');
    disc(ctx, crown.x + w * 0.025, crown.y + w * 0.035, w * 0.022, '#5A4526');
  }

  // Rice terraces below the mountains.
  function terraces(ctx, w, h) {
    const hz = h * 0.44;
    ctx.fillStyle = vertical(ctx, 0, hz, ['#86BDE3', '#C9DFEC', '#E4EEF2']);
    ctx.fillRect(0, 0, w, hz + 2);
    cloud(ctx, w * 0.7, h * 0.14, w * 0.06);
    ridge(ctx, w, hz + 2, hz, h * 0.26, '#7D97A9', 41);
    ridge(ctx, w, hz + 2, hz, h * 0.11, '#5A7D64', 17);
    const greens = ['#5F8F3F', '#78A84F', '#6A9A46', '#88B65C', '#719F4A', '#8EBA62', '#7AAA52'];
    const rows = greens.length;
    for (let i = 0; i < rows; i++) {
      const y = hz + ((h - hz) * i) / rows - h * 0.01;
      const bend = h * (0.02 + i * 0.006);
      ctx.beginPath();
      ctx.moveTo(0, y + bend);
      ctx.bezierCurveTo(w * 0.3, y - bend, w * 0.65, y + bend * 1.6, w, y);
      ctx.lineTo(w, h);
      ctx.lineTo(0, h);
      ctx.closePath();
      ctx.fillStyle = greens[i];
      ctx.fill();
      ctx.strokeStyle = 'rgba(214,232,180,0.75)';
      ctx.lineWidth = Math.max(1, h * 0.004);
      ctx.stroke();
    }
  }

  const SCENES = { field, coast, terraces };
  const WORDS = {
    field: 'farm rows at sunrise',
    coast: 'the coast with a coconut tree',
    terraces: 'rice terraces below the mountains',
  };

  // ---------- painting ----------

  function paint(canvas) {
    const r = canvas.getBoundingClientRect();
    if (!r.width) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = Math.round(r.width * dpr);
    const h = Math.round(r.height * dpr);
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }
    const ctx = canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, w, h);
    SCENES[canvas.dataset.scene](ctx, w, h);
    const on = withFooter && footer;
    if (on) {
      // Exactly how a photo is saved: the layout scaled to the photo's width, pinned to its edges.
      const g = render.photoGeometry(w, h, footer.doc);
      ctx.save();
      ctx.scale(g.s, g.s);
      render.drawLayout(ctx, footer.doc, footer.prep, g.frameH, g.s);
      ctx.restore();
    }
    canvas.setAttribute('aria-label', `A ${canvas.dataset.shape} photo, a drawing of ${WORDS[canvas.dataset.scene]}, ${on ? 'with the PIO footer along the bottom' : 'without a footer'}`);
    const name = canvas.parentElement.querySelector('.frame-name');
    name.textContent = withFooter ? `${name.dataset.name}_PIO.jpg` : `${name.dataset.name}.JPG`;
  }

  const paintAll = () => canvases.forEach(paint);

  for (const b of toggles) {
    b.addEventListener('click', () => {
      withFooter = b.dataset.footer === 'on';
      for (const t of toggles) t.setAttribute('aria-pressed', String(t === b));
      paintAll();
    });
  }

  let queued = false;
  new ResizeObserver(() => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; paintAll(); });
  }).observe(document.querySelector('.frames'));

  paintAll();

  (async () => {
    const def = (window.PIO_LAYOUTS || []).find((l) => l.id === 'office:pio-footer') || (window.PIO_LAYOUTS || [])[0];
    if (!def) return;
    const doc = model.sanitize(def);
    model.upgradePins(doc);
    footer = { doc, prep: await render.prepare(doc) };
    paintAll();
  })().catch((err) => console.warn('The sample footer could not be drawn.', err));
})(window.PIO = window.PIO || {});

(function () {
  'use strict';

  var $ = function (id) { return document.getElementById(id); };

  var theme = /[?&]theme=(light|dark)\b/.exec(location.search);
  if (theme) document.documentElement.setAttribute('data-theme', theme[1]);

  function platform() {
    var ua = navigator.userAgent || '';
    if (/Android/i.test(ua)) return 'android';
    if (/iPhone|iPad|iPod/i.test(ua) || (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1)) return 'other';
    if (/Windows/i.test(ua)) return 'windows';
    return 'other';
  }
  var forced = /[?&]as=(android|windows|other)\b/.exec(location.search);
  var mine = forced ? forced[1] : platform();

  // The visitor's own platform first and filled; iPhone, Mac and others get the browser button first.
  var first = mine === 'android' || mine === 'windows' ? mine : 'browser';
  var box = $('buttons');
  ['android', 'windows', 'browser'].filter(function (p) { return p !== first; })
    .forEach(function (p) { box.appendChild($('btn-' + p)); });
  $('btn-' + first).classList.add('primary');
  box.insertBefore($('btn-' + first), box.firstChild);

  function size(bytes) {
    return (bytes / 1048576).toFixed(bytes >= 10485760 ? 0 : 1) + ' MB';
  }

  // Without a list (404, offline, an error) the buttons keep pointing to /download/.
  fetch('download/latest.json', { cache: 'no-cache' })
    .then(function (res) { return res.ok ? res.json() : null; })
    .then(function (latest) {
      if (!latest) return;
      ['android', 'windows'].forEach(function (p) {
        var entry = latest[p];
        if (!entry || !entry.download) return;
        var b = $('btn-' + p);
        b.href = entry.download;
        b.querySelector('.btn-sub').textContent = 'Version ' + entry.version + ' · ' + size(entry.size);
      });
    })
    .catch(function () { /* offline: the buttons already lead to the download page */ });
}());
