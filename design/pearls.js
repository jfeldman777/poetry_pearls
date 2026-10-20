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
  initSelection();
  initQr();

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
    var poet = poetNames();

    function colText(article, col) {
      var t = titles(article);
      var link = '\n\n' + poemUrl(article);
      if (col.classList.contains('col-en')) {
        return (t.en || t.ru) + '\n' + poet.en + '\n\n' + verseText(col) + link;
      }
      var credit = col.querySelector('.credit');
      return t.ru + '\n' + poet.ru + '\n\n' + verseText(col) + (credit ? '\n\n' + credit.textContent.trim() : '') + link;
    }

    document.querySelectorAll('article.poem .col').forEach(function (col) {
      var article = col.closest('article.poem');
      var label = col.querySelector('.label');
      if (!label || !col.querySelector('.verse')) return;
      var name = col.classList.contains('col-en') ? 'Скопировать оригинал' : 'Скопировать перевод';
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'poem-copy';
      btn.setAttribute('aria-label', name);
      btn.innerHTML = copyIcon;
      btn.addEventListener('click', function () {
        copy(colText(article, col)).then(function () {
          btn.innerHTML = doneIcon;
          btn.classList.add('done');
          btn.setAttribute('aria-label', 'Скопировано');
          setTimeout(function () {
            btn.innerHTML = copyIcon;
            btn.classList.remove('done');
            btn.setAttribute('aria-label', name);
          }, 1600);
        });
      });
      label.appendChild(btn);
    });
  }

  function verseText(col) {
    var stanzas = col.querySelectorAll('.verse .stanza');
    var parts = stanzas.length ? Array.prototype.map.call(stanzas, function (p) { return p.textContent.trim(); }) : [col.querySelector('.verse').textContent.trim()];
    return parts.join('\n\n');
  }
  // Pages that collect one poet's poems under another heading name the poet on <main>.
  function poetNames() {
    var main = document.querySelector('main[data-mode]');
    var h1 = document.querySelector('h1');
    var alt = h1 && h1.nextElementSibling && h1.nextElementSibling.classList.contains('alt') ? h1.nextElementSibling : null;
    var ru = main && main.dataset.poetRu || (h1 ? h1.textContent.trim() : '');
    return { ru: ru, en: main && main.dataset.poetEn || (alt ? alt.textContent.trim() : ru) };
  }
  // On a sonnet page the heading names the translator; the title and the original live in data attributes.
  function titles(article) {
    var h2 = article.querySelector('.poem-head h2');
    var enTitle = article.querySelector('.poem-head .en-title');
    return {
      ru: article.dataset.title || (h2 ? headingText(h2) : ''),
      en: article.dataset.enTitle || (enTitle ? enTitle.textContent.trim() : '')
    };
  }
  function originalCol(article) {
    var src = article.dataset.en ? document.getElementById(article.dataset.en) : article;
    return src && src.querySelector('.col-en');
  }
  function headingText(h2) {
    var c = h2.cloneNode(true);
    c.querySelectorAll('a, button').forEach(function (n) { n.remove(); });
    return c.textContent.trim();
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
  function siteBase() {
    var local = !/^https?:$/.test(location.protocol) || /^(localhost|127\.|\[::1\])/.test(location.hostname);
    return local ? 'https://jfeldman777.github.io/poetry_pearls/design/' : new URL('./', location.href).href;
  }
  function pageFile() {
    var file = decodeURIComponent(location.pathname.split('/').pop() || '');
    if (!file || file === 'index.html' || file === 'index') return 'index.html';
    if (!/\.[a-z0-9]+$/i.test(file)) file += '.html';
    return file;
  }
  function poemUrl(article) {
    return siteBase() + pageFile() + '#' + encodeURIComponent(article.id);
  }
  function initQr() {
    var tools = document.querySelector('.site-header .tools');
    if (!tools) return;
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'chip';
    btn.textContent = 'QR';
    btn.title = 'QR-код сайта';
    tools.insertBefore(btn, tools.firstChild);
    btn.addEventListener('click', function () {
      var show = function () {
        var site = siteBase();
        var file = pageFile();
        var targets = [{ label: 'Сайт', url: site }];
        if (file && file !== 'index.html') targets.push({ label: 'Эта страница', url: site + file + location.hash });
        window.QR.show('Жемчужины английской поэзии', targets);
      };
      if (window.QR) return show();
      var s = document.createElement('script');
      s.src = 'qr.js?v=2';
      s.onload = show;
      document.head.appendChild(s);
    });
  }
  function plural(n, one, few, many) {
    var m10 = n % 10, m100 = n % 100;
    return n + ' ' + (m10 === 1 && m100 !== 11 ? one : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? few : many);
  }

  // Selection: poems are stored with their texts, so the selection page needs no other data.
  function initSelection() {
    var KEY = 'pearls-selection';
    var SITE = 'Жемчужины английской поэзии';
    var page = decodeURIComponent(location.pathname.split('/').pop() || 'index.html');
    var picks = [];
    var selPage = document.querySelector('main.selection');
    var listEl, modeButtons, titleInput;

    function load() {
      try { var v = JSON.parse(localStorage.getItem(KEY)); return Array.isArray(v) ? v : []; } catch (e) { return []; }
    }
    function save(list) {
      try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) { alert('Не удалось сохранить подборку: ' + e.message); }
      refresh(list);
    }
    function keyOf(item) { return item.page + '#' + item.slug; }
    function refresh(list) {
      document.querySelectorAll('.nav a[href="selection.html"]').forEach(function (a) {
        var badge = a.querySelector('.nav-count');
        if (!list.length) { if (badge) badge.remove(); return; }
        if (!badge) { badge = document.createElement('span'); badge.className = 'nav-count'; a.appendChild(badge); }
        badge.textContent = list.length;
      });
      var keys = list.map(keyOf);
      picks.forEach(function (p) { paintPick(p.btn, keys.indexOf(p.key) >= 0); });
      if (selPage) renderPage(list);
    }

    function paintPick(btn, on) {
      btn.setAttribute('aria-pressed', String(on));
      btn.textContent = on ? '✓ В подборке' : '+ В подборку';
      btn.title = on ? 'Убрать из подборки' : 'Добавить в подборку';
    }
    function capture(article) {
      var poet = poetNames();
      var t = titles(article);
      var ruCol = article.querySelector('.col-ru');
      var enCol = originalCol(article);
      var credit = ruCol && ruCol.querySelector('.credit');
      var ru = ruCol && ruCol.querySelector('.verse') ? verseText(ruCol) : '';
      var en = enCol && enCol.querySelector('.verse') ? verseText(enCol) : '';
      return {
        page: page,
        slug: article.id,
        poetRu: poet.ru,
        poetEn: poet.en,
        titleRu: ru ? t.ru : '',
        titleEn: t.en || (en ? t.ru : ''),
        ru: ru,
        en: en,
        credit: credit ? credit.textContent.trim() : ''
      };
    }
    document.querySelectorAll('main[data-mode] article.poem[id]').forEach(function (article) {
      var head = article.querySelector('.poem-head');
      if (!head || !article.querySelector('.verse')) return;
      var pick = { key: page + '#' + article.id, btn: document.createElement('button') };
      pick.btn.type = 'button';
      pick.btn.className = 'poem-pick';
      pick.btn.addEventListener('click', function () {
        var list = load();
        var keys = list.map(keyOf);
        var i = keys.indexOf(pick.key);
        if (i >= 0) list.splice(i, 1); else list.push(capture(article));
        save(list);
      });
      head.appendChild(pick.btn);
      picks.push(pick);

      var linkBtn = document.createElement('button');
      linkBtn.type = 'button';
      linkBtn.className = 'poem-link';
      linkBtn.textContent = 'Скопировать ссылку';
      linkBtn.title = 'Ссылка откроет это стихотворение';
      linkBtn.addEventListener('click', function () {
        copy(poemUrl(article)).then(function () {
          linkBtn.textContent = 'Ссылка скопирована';
          setTimeout(function () { linkBtn.textContent = 'Скопировать ссылку'; }, 1600);
        });
      });
      head.appendChild(linkBtn);
    });

    if (selPage) initPage();
    refresh(load());
    window.addEventListener('storage', function (e) { if (e.key === KEY) refresh(load()); });

    function initPage() {
      listEl = selPage.querySelector('.sel-list');
      modeButtons = selPage.querySelectorAll('.sel-mode button');
      titleInput = selPage.querySelector('.sel-title');
      var mode = 'both';
      try {
        mode = localStorage.getItem('pearls-sel-mode') || mode;
        titleInput.value = localStorage.getItem('pearls-sel-title') || titleInput.value;
      } catch (e) {}
      function setMode(m) {
        mode = m;
        modeButtons.forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.mode === m)); });
        try { localStorage.setItem('pearls-sel-mode', m); } catch (e) {}
      }
      setMode(mode);
      modeButtons.forEach(function (b) { b.addEventListener('click', function () { setMode(b.dataset.mode); }); });
      titleInput.addEventListener('input', function () {
        try { localStorage.setItem('pearls-sel-title', titleInput.value); } catch (e) {}
      });

      selPage.querySelectorAll('[data-sort]').forEach(function (b) {
        b.addEventListener('click', function () {
          var list = load();
          var name = function (it) { return it.titleRu || it.titleEn; };
          if (b.dataset.sort === 'reverse') list.reverse();
          else if (b.dataset.sort === 'title') list.sort(function (a, c) { return name(a).localeCompare(name(c), 'ru'); });
          else list.sort(function (a, c) { return a.poetRu.localeCompare(c.poetRu, 'ru') || name(a).localeCompare(name(c), 'ru'); });
          save(list);
        });
      });

      var dragFrom = null;
      function clearMarks() {
        listEl.querySelectorAll('.drop-target, .dragging').forEach(function (li) { li.classList.remove('drop-target', 'dragging'); });
      }
      listEl.addEventListener('dragstart', function (e) {
        var li = e.target.closest('li');
        if (!li) return;
        dragFrom = +li.dataset.pos;
        li.classList.add('dragging');
        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.setData('text/plain', li.dataset.pos);
      });
      listEl.addEventListener('dragover', function (e) {
        var li = e.target.closest('li');
        if (dragFrom === null || !li) return;
        e.preventDefault();
        listEl.querySelectorAll('.drop-target').forEach(function (x) { x.classList.remove('drop-target'); });
        li.classList.add('drop-target');
      });
      listEl.addEventListener('drop', function (e) {
        var li = e.target.closest('li');
        if (dragFrom === null || !li) return;
        e.preventDefault();
        move(dragFrom, +li.dataset.pos);
        dragFrom = null;
      });
      listEl.addEventListener('dragend', function () { dragFrom = null; clearMarks(); });

      function current() {
        return { title: titleInput.value.trim() || 'Подборка стихов', poems: feedPoems(load(), mode) };
      }
      function file() {
        var c = current();
        var name = c.title.replace(/[\\\/:*?"<>|]+/g, ' ').replace(/\s+/g, ' ').trim() + '.docx';
        return new File([window.PearlsDocx.build(c.poems, { title: c.title, site: SITE })], name, { type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' });
      }
      function download(f) {
        var a = document.createElement('a');
        a.href = URL.createObjectURL(f);
        a.download = f.name;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(function () { URL.revokeObjectURL(a.href); }, 10000);
      }
      selPage.querySelector('.sel-download').addEventListener('click', function () { download(file()); });

      var share = selPage.querySelector('.sel-share');
      var canShare = false;
      try {
        canShare = !!(navigator.canShare && navigator.canShare({ files: [new File([''], 'test.docx', { type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' })] }));
      } catch (e) {}
      share.hidden = !canShare;
      share.addEventListener('click', function () {
        var f = file();
        navigator.share({ files: [f], title: current().title, text: current().title + ' — ' + SITE }).catch(function (e) {
          if (e.name !== 'AbortError') download(f);
        });
      });

      var copyBtn = selPage.querySelector('.sel-copy');
      var copyLabel = copyBtn.textContent;
      copyBtn.addEventListener('click', function () {
        var c = current();
        copy(feedText(c.poems, c.title)).then(function () {
          copyBtn.textContent = 'Скопировано';
          setTimeout(function () { copyBtn.textContent = copyLabel; }, 1600);
        });
      });

      selPage.querySelector('.sel-clear').addEventListener('click', function () {
        if (confirm('Убрать все стихотворения из подборки?')) save([]);
      });
    }

    function move(from, to) {
      var list = load();
      if (to < 0 || to >= list.length || from === to) return;
      list.splice(to, 0, list.splice(from, 1)[0]);
      save(list);
    }

    function renderPage(list) {
      selPage.querySelector('.sel-count').textContent = list.length ? plural(list.length, 'стихотворение', 'стихотворения', 'стихотворений') : '';
      selPage.querySelector('.sel-empty').hidden = list.length > 0;
      selPage.querySelector('.sel-body').hidden = !list.length;
      listEl.textContent = '';
      list.forEach(function (it, i) {
        var li = document.createElement('li');
        li.draggable = true;
        li.dataset.pos = i;
        var handle = document.createElement('span');
        handle.className = 'sel-handle';
        handle.title = 'Перетащите, чтобы поменять порядок';
        handle.textContent = '⋮⋮';
        var num = document.createElement('span');
        num.className = 'sel-num';
        num.textContent = i + 1;
        var text = document.createElement('div');
        text.className = 'sel-item';
        var a = document.createElement('a');
        a.href = it.page + '#' + it.slug;
        a.textContent = it.titleRu || it.titleEn;
        var small = document.createElement('small');
        small.textContent = it.poetRu + (it.titleRu && it.titleEn ? ' · ' + it.titleEn : '');
        text.appendChild(a);
        text.appendChild(small);
        li.appendChild(handle);
        li.appendChild(num);
        li.appendChild(text);
        [['↑', 'Выше', i - 1, i === 0], ['↓', 'Ниже', i + 1, i === list.length - 1], ['✕', 'Убрать из подборки', -1, false]].forEach(function (op) {
          var b = document.createElement('button');
          b.type = 'button';
          b.className = 'sel-op';
          b.textContent = op[0];
          b.title = op[1];
          b.setAttribute('aria-label', op[1]);
          b.disabled = op[3];
          b.addEventListener('click', function () {
            if (op[2] >= 0) move(i, op[2]);
            else { var l = load(); l.splice(i, 1); save(l); }
          });
          li.appendChild(b);
        });
        listEl.appendChild(li);
      });
    }

    // mode: both — translation, then original; ru / en — one text (falls back to the other if missing).
    function feedPoems(list, mode) {
      return list.map(function (it) {
        var useRu = !!it.ru && (mode !== 'en' || !it.en);
        var useEn = !!it.en && (mode !== 'ru' || !it.ru);
        var parts = [];
        if (useRu) parts.push({ title: it.titleRu, poet: it.poetRu, text: it.ru, credit: it.credit });
        if (useEn) parts.push({ title: it.titleEn || it.titleRu, poet: it.poetEn, text: it.en, en: true });
        if (!parts.length) return null;
        return {
          title: parts[0].title,
          poet: parts[0].poet,
          url: new URL(it.page + '#' + it.slug, location.href).href,
          parts: parts
        };
      }).filter(Boolean);
    }
    function feedText(poems, title) {
      return title + '\n' + SITE + '\n\n\n' + poems.map(function (p) {
        var blocks = [];
        p.parts.forEach(function (part, i) {
          blocks.push((i ? part.title + '\n' + part.poet : p.title + '\n' + p.poet) + '\n\n' + part.text);
          if (part.credit) blocks.push(part.credit);
        });
        blocks.push(p.url);
        return blocks.join('\n\n');
      }).join('\n\n* * *\n\n');
    }
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
