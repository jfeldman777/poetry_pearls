(function () {
  var root = document.documentElement;
  try { var theme = localStorage.getItem('pearls-theme'); if (theme) root.dataset.theme = theme; } catch (e) {}
  var toggle = document.getElementById('theme');
  if (toggle) {
    toggle.addEventListener('click', function () {
      var dark = root.dataset.theme ? root.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
      root.dataset.theme = dark ? 'light' : 'dark';
      try { localStorage.setItem('pearls-theme', root.dataset.theme); } catch (e) {}
    });
  }

  var cat = document.querySelector('main.catalog');
  if (cat) initCatalog(cat);

  var main = document.querySelector('main[data-mode]');
  if (!main) return;
  var buttons = document.querySelectorAll('.segmented button');
  function setMode(mode) {
    main.dataset.mode = mode;
    buttons.forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.mode === mode)); });
    try { localStorage.setItem('pearls-mode', mode); } catch (e) {}
  }
  buttons.forEach(function (b) { b.addEventListener('click', function () { setMode(b.dataset.mode); }); });
  try { var saved = localStorage.getItem('pearls-mode'); if (saved) setMode(saved); } catch (e) {}

  function initCatalog(cat) {
    var views = cat.querySelectorAll('.cat-view');
    var tabs = cat.querySelectorAll('.cat-tabs button');
    var search = cat.querySelector('.cat-search');
    var empty = cat.querySelector('.cat-empty');
    var current = null;

    function filter() {
      var q = (search.value || '').trim().toLowerCase().replace(/ё/g, 'е');
      var view = cat.querySelector('.cat-view[data-view="' + current + '"]');
      var shown = 0;
      view.querySelectorAll('[data-q]').forEach(function (el) {
        var hit = !q || el.dataset.q.indexOf(q) >= 0;
        el.hidden = !hit;
        if (hit) shown++;
      });
      view.querySelectorAll('.cat-group').forEach(function (g) {
        g.hidden = !!q && !g.querySelector('[data-q]:not([hidden])');
      });
      view.querySelectorAll('.letters').forEach(function (n) { n.hidden = !!q; });
      empty.hidden = shown > 0;
    }

    function show(name, keepHash) {
      if (!cat.querySelector('.cat-view[data-view="' + name + '"]')) name = 'ru';
      current = name;
      views.forEach(function (v) { v.hidden = v.dataset.view !== name; });
      tabs.forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.view === name)); });
      if (!keepHash) history.replaceState(null, '', '#' + name);
      filter();
    }

    tabs.forEach(function (b) { b.addEventListener('click', function () { show(b.dataset.view); }); });
    search.addEventListener('input', filter);

    var now = new Date();
    var md = (now.getMonth() + 1) + '-' + now.getDate();
    var today = cat.querySelectorAll('[data-md="' + md + '"]');
    if (today.length) {
      var banner = cat.querySelector('.cat-today');
      var links = [];
      today.forEach(function (li) {
        li.classList.add('today');
        var a = li.querySelector('a');
        links.push('<a href="' + a.getAttribute('href') + '">' + a.textContent + '</a>');
      });
      banner.innerHTML = '<span class="pearl" aria-hidden="true"></span><span>Сегодня день рождения: ' + links.join(', ') + '</span>';
      banner.hidden = false;
    }

    var hash = decodeURIComponent(location.hash.slice(1));
    var target = hash && document.getElementById(hash);
    var owner = target && target.closest('.cat-view');
    if (owner) {
      show(owner.dataset.view, true);
      target.scrollIntoView();
    } else {
      show(hash || 'ru', !hash);
    }
  }
})();
