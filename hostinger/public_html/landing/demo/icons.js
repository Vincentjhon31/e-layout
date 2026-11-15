/*
 * Icon set for layouts, drawn on a 24 x 24 grid. Each icon is a list of path
 * parts that are either stroked (line icons) or filled.
 */
(function (PIO) {
  'use strict';

  const DEFS = {
    phone: { label: 'Phone', parts: [
      { d: 'M5.2 3.5h3.2l1.6 4.2-2.1 1.3a11.2 11.2 0 0 0 7.1 7.1l1.3-2.1 4.2 1.6v3.2a1.9 1.9 0 0 1-2.1 1.9A16.3 16.3 0 0 1 3.3 5.6a1.9 1.9 0 0 1 1.9-2.1z' }] },
    mobile: { label: 'Mobile', parts: [
      { d: 'M8 2.5h8a2 2 0 0 1 2 2v15a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2v-15a2 2 0 0 1 2-2z' }, { d: 'M11 18.5h2' }] },
    mail: { label: 'Email', parts: [
      { d: 'M4.5 5h15A2.5 2.5 0 0 1 22 7.5v9a2.5 2.5 0 0 1-2.5 2.5h-15A2.5 2.5 0 0 1 2 16.5v-9A2.5 2.5 0 0 1 4.5 5z' },
      { d: 'M2.8 6.8 12 13l9.2-6.2' }] },
    facebook: { label: 'Facebook', parts: [
      { fill: true, d: 'M13.6 22v-8.6h2.9l.45-3.4H13.6V7.9c0-1 .3-1.6 1.7-1.6h1.8V3.3a24 24 0 0 0-2.6-.13c-2.6 0-4.4 1.6-4.4 4.5V10H7.2v3.4h2.9V22z' }] },
    instagram: { label: 'Instagram', parts: [
      { d: 'M7.2 2.5h9.6a4.7 4.7 0 0 1 4.7 4.7v9.6a4.7 4.7 0 0 1-4.7 4.7H7.2a4.7 4.7 0 0 1-4.7-4.7V7.2a4.7 4.7 0 0 1 4.7-4.7z' },
      { d: 'M12 8a4 4 0 1 0 0 8a4 4 0 1 0 0-8z' },
      { fill: true, d: 'M17.4 5.4a1.2 1.2 0 1 0 0 2.4a1.2 1.2 0 1 0 0-2.4z' }] },
    youtube: { label: 'YouTube', parts: [
      { fill: true, rule: 'evenodd', d: 'M4.6 5h14.8a3.1 3.1 0 0 1 3.1 3.1v7.8a3.1 3.1 0 0 1-3.1 3.1H4.6a3.1 3.1 0 0 1-3.1-3.1V8.1A3.1 3.1 0 0 1 4.6 5zM10 8.8v6.4l5.4-3.2z' }] },
    globe: { label: 'Website', parts: [
      { d: 'M12 2.5a9.5 9.5 0 1 0 0 19a9.5 9.5 0 1 0 0-19z' }, { d: 'M2.5 12h19' },
      { d: 'M12 2.5c2.6 2.7 3.9 5.9 3.9 9.5s-1.3 6.8-3.9 9.5c-2.6-2.7-3.9-5.9-3.9-9.5s1.3-6.8 3.9-9.5z' }] },
    location: { label: 'Location', parts: [
      { d: 'M12 21.5s-7-6-7-11.6a7 7 0 0 1 14 0c0 5.6-7 11.6-7 11.6z' }, { d: 'M12 7.3a2.6 2.6 0 1 0 0 5.2a2.6 2.6 0 1 0 0-5.2z' }] },
    clock: { label: 'Time', parts: [
      { d: 'M12 2.5a9.5 9.5 0 1 0 0 19a9.5 9.5 0 1 0 0-19z' }, { d: 'M12 6.8V12l3.6 2.1' }] },
    calendar: { label: 'Date', parts: [
      { d: 'M5.5 4.5h13a2 2 0 0 1 2 2V19a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2V6.5a2 2 0 0 1 2-2z' }, { d: 'M3.5 9.5h17' },
      { d: 'M8 2.8v3.4M16 2.8v3.4' }] },
    megaphone: { label: 'Announcement', parts: [
      { d: 'M3.5 9.8v4.4a1 1 0 0 0 1 1h2.2l5.3 4V4.8l-5.3 4H4.5a1 1 0 0 0-1 1z' }, { d: 'M15.5 9.3a3.8 3.8 0 0 1 0 5.4' },
      { d: 'M18.3 6.6a7.6 7.6 0 0 1 0 10.8' }] },
    warning: { label: 'Warning', parts: [
      { d: 'M10.3 3.9 2.6 17.4a2 2 0 0 0 1.7 3h15.4a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z' }, { d: 'M12 9v4.6' },
      { fill: true, d: 'M12 16.3a1.15 1.15 0 1 0 0 2.3a1.15 1.15 0 1 0 0-2.3z' }] },
    info: { label: 'Information', parts: [
      { d: 'M12 2.5a9.5 9.5 0 1 0 0 19a9.5 9.5 0 1 0 0-19z' }, { d: 'M12 11v5.8' },
      { fill: true, d: 'M12 6.5a1.15 1.15 0 1 0 0 2.3a1.15 1.15 0 1 0 0-2.3z' }] },
    check: { label: 'Check', parts: [{ d: 'M4.5 12.8l4.6 4.6L19.5 7' }] },
    star: { label: 'Star', parts: [
      { fill: true, d: 'M12 2.6l2.47 6.6 7.04.31-5.52 4.39 1.89 6.79L12 16.8l-5.88 3.89 1.89-6.79-5.52-4.39 7.04-.31z' }] },
    heart: { label: 'Heart', parts: [
      { fill: true, d: 'M12 20.6s-8.3-5.2-8.3-11.1A4.6 4.6 0 0 1 12 6.6a4.6 4.6 0 0 1 8.3 2.9c0 5.9-8.3 11.1-8.3 11.1z' }] },
    user: { label: 'Person', parts: [
      { d: 'M12 3.3a4.2 4.2 0 1 0 0 8.4a4.2 4.2 0 1 0 0-8.4z' }, { d: 'M4.2 20.7c.6-4 3.9-6.6 7.8-6.6s7.2 2.6 7.8 6.6' }] },
    home: { label: 'Office', parts: [
      { d: 'M3.5 11.2 12 3.8l8.5 7.4' }, { d: 'M5.8 9.4v11.1h12.4V9.4' }, { d: 'M10 20.5v-5.6h4v5.6' }] },
    hashtag: { label: 'Hashtag', parts: [{ d: 'M9.6 3.5 7.8 20.5M16.2 3.5l-1.8 17M4.2 8.8h16M3.8 15.2h16' }] },
    leaf: { label: 'Leaf', parts: [
      { d: 'M4.8 19.2C4.8 10.6 10.2 5 19.6 4.4c-.6 9.4-6.2 14.8-14.8 14.8z' }, { d: 'M4.8 19.2 12.6 11.4' }] },
    shield: { label: 'Shield', parts: [
      { d: 'M12 2.7 19.6 5.9v5.6c0 4.9-3.2 8.4-7.6 9.8-4.4-1.4-7.6-4.9-7.6-9.8V5.9z' }] },
    camera: { label: 'Camera', parts: [
      { d: 'M4.3 7.3h3.1l1.7-2.6h5.8l1.7 2.6h3.1a1.6 1.6 0 0 1 1.6 1.6v9.9a1.6 1.6 0 0 1-1.6 1.6H4.3a1.6 1.6 0 0 1-1.6-1.6V8.9a1.6 1.6 0 0 1 1.6-1.6z' },
      { d: 'M12 9.6a3.6 3.6 0 1 0 0 7.2a3.6 3.6 0 1 0 0-7.2z' }] },
  };

  const cache = new Map();

  function parts(name) {
    const def = DEFS[name] || DEFS.star;
    if (!cache.has(name)) cache.set(name, def.parts.map((p) => ({ ...p, path: new Path2D(p.d) })));
    return cache.get(name);
  }

  PIO.icons = {
    names: Object.keys(DEFS),
    label: (name) => (DEFS[name] || DEFS.star).label,
    has: (name) => Object.prototype.hasOwnProperty.call(DEFS, name),
    parts,
  };
})(window.PIO = window.PIO || {});
