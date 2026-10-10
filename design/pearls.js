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
  initCopy();

  function initCopy() {
    var copyIcon = '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/></svg>';
    var doneIcon = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12l5 5L20 7"/></svg>';
    var h1 = document.querySelector('h1');
    var alt = h1 && h1.nextElementSibling && h1.nextElementSibling.classList.contains('alt') ? h1.nextElementSibling : null;
    var poetRu = h1 ? h1.textContent.trim() : '';
    var poetEn = alt ? alt.textContent.trim() : poetRu;

    function verseText(col) {
      var stanzas = col.querySelectorAll('.verse .stanza');
      var parts = stanzas.length ? Array.prototype.map.call(stanzas, function (p) { return p.textContent.trim(); }) : [col.querySelector('.verse').textContent.trim()];
      return parts.join('\n\n');
    }
    function headingText(h2) {
      var c = h2.cloneNode(true);
      c.querySelectorAll('a, button').forEach(function (n) { n.remove(); });
      return c.textContent.trim();
    }
    function poemText(article) {
      var mode = main.dataset.mode;
      var ru = article.querySelector('.col-ru .verse') && article.querySelector('.col-ru');
      var en = article.querySelector('.col-en .verse') && article.querySelector('.col-en');
      var ruTitle = headingText(article.querySelector('.poem-head h2'));
      var enTitleEl = article.querySelector('.poem-head .en-title');
      var enTitle = enTitleEl ? enTitleEl.textContent.trim() : ruTitle;
      var blocks = [];
      if (ru && mode !== 'en') {
        var credit = ru.querySelector('.credit');
        blocks.push(ruTitle + '\n' + poetRu + '\n\n' + verseText(ru) + (credit ? '\n\n' + credit.textContent.trim() : ''));
      }
      if (en && (mode !== 'ru' || !ru)) blocks.push(enTitle + '\n' + poetEn + '\n\n' + verseText(en));
      if (!blocks.length && ru) blocks.push(ruTitle + '\n' + poetRu + '\n\n' + verseText(ru));
      return blocks.join('\n\n———\n\n') + '\n\n' + location.origin + location.pathname + '#' + article.id;
    }
    function copy(text) {
      if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
      return new Promise(function (resolve, reject) {
        var ta = document.createElement('textarea');
        ta.value = text; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.opacity = '0';
        document.body.appendChild(ta); ta.select();
        try { document.execCommand('copy') ? resolve() : reject(); } catch (e) { reject(e); }
        ta.remove();
      });
    }

    document.querySelectorAll('article.poem').forEach(function (article) {
      var h2 = article.querySelector('.poem-head h2');
      if (!h2 || !article.querySelector('.verse')) return;
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'poem-copy';
      btn.setAttribute('aria-label', 'Скопировать стихотворение');
      btn.innerHTML = copyIcon;
      btn.addEventListener('click', function () {
        copy(poemText(article)).then(function () {
          btn.innerHTML = doneIcon;
          btn.classList.add('done');
          btn.setAttribute('aria-label', 'Скопировано');
          setTimeout(function () {
            btn.innerHTML = copyIcon;
            btn.classList.remove('done');
            btn.setAttribute('aria-label', 'Скопировать стихотворение');
          }, 1600);
        });
      });
      h2.appendChild(btn);
    });
  }

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
