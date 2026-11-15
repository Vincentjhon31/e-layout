/* e-Layout download page. Reads releases.json (every version) and fills the page.
   Every text goes in with textContent, never innerHTML. No inline styles (CSP). */
(function () {
  'use strict';

  var API = '/api/download.php?file=';
  var $ = function (id) { return document.getElementById(id); };

  function theme() {
    var m = /[?&]theme=(light|dark)\b/.exec(location.search);
    if (m) document.documentElement.setAttribute('data-theme', m[1]);
  }

  function platform() {
    var ua = navigator.userAgent || '';
    if (/Android/i.test(ua)) return 'android';
    if (/iPhone|iPad|iPod/i.test(ua) || (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1)) return 'other';
    if (/Windows/i.test(ua)) return 'windows';
    return 'other';
  }
  var forced = /[?&]as=(android|windows|other)\b/.exec(location.search);
  var mine = forced ? forced[1] : platform();

  function size(bytes) {
    return (bytes / 1048576).toFixed(bytes >= 10485760 ? 0 : 1) + ' MB';
  }
  function day(iso) {
    if (!iso) return '';
    var d = new Date(iso + 'T00:00:00Z');
    if (isNaN(d.getTime())) return '';
    return d.toLocaleDateString('en-PH', { timeZone: 'UTC', year: 'numeric', month: 'long', day: 'numeric' });
  }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }
  var NAMES = { android: 'Android', windows: 'Windows' };

  // The visitor's own platform first and filled; iPhone, Mac and others get the browser button first.
  function order() {
    var first = mine === 'android' || mine === 'windows' ? mine : 'browser';
    var rest = ['android', 'windows', 'browser'].filter(function (p) { return p !== first; });
    var box = $('buttons');
    [first].concat(rest).forEach(function (p, i) {
      var b = $('btn-' + p);
      if (i === 0) b.classList.add('primary');
      box.appendChild(b);
    });
    if (mine === 'other') {
      var note = $('note');
      note.textContent = 'Using an iPhone or a Mac? Open e-Layout in your browser instead.';
      note.hidden = false;
    }
  }

  function enable(p, file, version) {
    var b = $('btn-' + p);
    b.href = API + encodeURIComponent(file.name);
    b.removeAttribute('aria-disabled');
    b.querySelector('.btn-sub').textContent = 'Version ' + version + ' · ' + size(file.size);
  }

  function render(data) {
    var list = (data && data.releases) || [];
    var withFiles = list.filter(function (r) { return r.files && Object.keys(r.files).length; });
    var newest = withFiles[0];
    if (!newest) {
      $('meta').textContent = 'The first download will appear here soon.';
      $('empty').hidden = list.length > 0;
    } else {
      var when = day(newest.date);
      $('meta').textContent = 'Version ' + newest.version + (when ? ' · Released ' + when : '');
      Object.keys(newest.files).forEach(function (p) {
        if (NAMES[p] && newest.files[p] && newest.files[p].name) enable(p, newest.files[p], newest.version);
      });
    }
    var host = $('releases');
    list.forEach(function (r, i) {
      var d = el('details');
      if (i === 0) d.open = true;
      var s = el('summary');
      s.appendChild(el('span', '', 'Version ' + r.version));
      if (i === 0) s.appendChild(el('span', 'tag', 'Latest'));
      var when = day(r.date);
      if (when) s.appendChild(el('span', 'date', when));
      d.appendChild(s);
      var notes = r.whats_new || [];
      if (notes.length) {
        var ul = el('ul');
        notes.forEach(function (n) { ul.appendChild(el('li', '', n)); });
        d.appendChild(ul);
      }
      var names = Object.keys(r.files || {}).filter(function (p) { return NAMES[p] && r.files[p] && r.files[p].name; });
      if (names.length) {
        var files = el('div', 'files');
        names.forEach(function (p) {
          var a = el('a', '', NAMES[p] + ' · ' + size(r.files[p].size));
          a.href = API + encodeURIComponent(r.files[p].name);
          files.appendChild(a);
        });
        d.appendChild(files);
      } else if (i > 0) {
        d.appendChild(el('p', 'nofiles', 'The files for this older version are no longer kept. Please use the newest one.'));
      }
      host.appendChild(d);
    });
    if (location.hash === '#changes') $('changes').scrollIntoView();
  }

  theme();
  order();
  fetch('releases.json', { cache: 'no-store' })
    .then(function (res) {
      if (res.status === 404) return { releases: [] };
      if (!res.ok) throw new Error('status ' + res.status);
      return res.json();
    })
    .then(render)
    .catch(function () {
      $('meta').textContent = 'The download list couldn’t be loaded.';
      $('error').hidden = false;
    });
}());
