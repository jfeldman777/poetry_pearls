(function () {
  var main = document.querySelector('main.search');
  var data = window.PEARLS_SEARCH;
  if (!main || !data) return;
  var input = main.querySelector('.search-input');
  var out = main.querySelector('.search-results');
  var count = main.querySelector('.search-count');
  var summary = count.textContent;
  var LIMIT = 100;

  function normalize(s) {
    return s.toLowerCase().replace(/ё/g, 'е').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  }
  // Crude stemming: cut the ending so that "зимой" also finds "зима", "clocks" — "clock".
  function stem(w) {
    return w.length >= 5 ? w.slice(0, -2) : w.length === 4 ? w.slice(0, -1) : w;
  }
  function plural(n, one, few, many) {
    var m10 = n % 10, m100 = n % 100;
    return n + ' ' + (m10 === 1 && m100 !== 11 ? one : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? few : many);
  }

  // data: [[page, poetRu, poetEn, [[id, title, enTitle, ru, en], ...]], ...]
  var poems = [];
  var poets = data.map(function (pt) {
    pt[3].forEach(function (s) {
      var lines = [s[1], s[2]].concat(s[3].split('\n'), s[4].split('\n'))
        .map(function (l) { return l.trim(); })
        .filter(Boolean);
      var p = {
        index: poems.length,
        href: pt[0] + '#' + s[0],
        poetRu: pt[1],
        title: s[1] || s[2],
        enTitle: s[1] && s[2] !== s[1] ? s[2] : '',
        lines: lines,
        normLines: lines.map(normalize),
        normAll: '',
        spans: []
      };
      p.normLines.forEach(function (line, li) {
        if (!line) return;
        if (p.normAll) p.normAll += ' ';
        p.spans.push({ li: li, start: p.normAll.length, end: p.normAll.length + line.length });
        p.normAll += line;
      });
      poems.push(p);
    });
    return { href: pt[0], ru: pt[1], en: pt[2], norm: normalize(pt[1] + ' ' + pt[2]) };
  });

  // Matches start at a word boundary ("елка" must not hit "стрелками"), the end may be cut off.
  function at(text, needle) {
    return (' ' + text).indexOf(' ' + needle);
  }
  function has(text, words) {
    return words.every(function (w) { return at(text, w) >= 0; });
  }

  // Levels: 4 — phrase inside one line, 3 — phrase across lines, 2 — all words in one line, 1 — all words in the poem.
  function find(query, words) {
    var results = [];
    poems.forEach(function (p) {
      var match = null;
      var phraseLine = p.normLines.findIndex(function (line) { return at(line, query) >= 0; });
      var start = phraseLine < 0 ? at(p.normAll, query) : -1;
      if (phraseLine >= 0) {
        match = { level: 4, lines: [phraseLine] };
      } else if (start >= 0) {
        var end = start + query.length;
        match = { level: 3, lines: p.spans.filter(function (s) { return s.end > start && s.start < end; }).map(function (s) { return s.li; }) };
      } else {
        var wordsLine = p.normLines.findIndex(function (line) { return has(line, words); });
        if (wordsLine >= 0) {
          match = { level: 2, lines: [wordsLine] };
        } else if (has(p.normAll, words)) {
          var best = 0, bestCount = -1;
          p.normLines.forEach(function (line, li) {
            var c = words.filter(function (w) { return at(line, w) >= 0; }).length;
            if (c > bestCount) { best = li; bestCount = c; }
          });
          match = { level: 1, lines: [best] };
        }
      }
      if (match) results.push({ poem: p, level: match.level, lines: match.lines });
    });
    results.sort(function (a, b) { return b.level - a.level || a.poem.index - b.poem.index; });
    return results;
  }

  function highlight(node, text, words) {
    var long = words.filter(function (w) { return w.length > 1; });
    var pattern = (long.length ? long : words).slice()
      .sort(function (a, b) { return b.length - a.length; })
      .map(function (w) {
        return w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/е/g, '[её]') + '[\\p{L}\\p{N}]*';
      })
      .join('|');
    var re = new RegExp('(^|[^\\p{L}\\p{N}])(' + pattern + ')', 'giu');
    var last = 0, m;
    while ((m = re.exec(text))) {
      var from = m.index + m[1].length;
      node.appendChild(document.createTextNode(text.slice(last, from)));
      var mark = document.createElement('mark');
      mark.textContent = m[2];
      node.appendChild(mark);
      last = from + m[2].length;
    }
    node.appendChild(document.createTextNode(text.slice(last)));
  }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }
  function group(title, items) {
    out.appendChild(el('h3', 'search-group', title));
    var ul = el('ul', 'search-list');
    items.forEach(function (li) { ul.appendChild(li); });
    out.appendChild(ul);
  }

  function render(raw) {
    var query = normalize(raw);
    out.textContent = '';
    if (query.length < 2) {
      count.textContent = summary;
      return;
    }
    var words = query.split(' ').map(stem);
    var poetHits = poets.filter(function (pt) { return pt.norm.indexOf(query) >= 0 || has(pt.norm, words); });
    var results = find(query, words);
    var found = [];
    if (results.length) found.push(plural(results.length, 'стихотворение', 'стихотворения', 'стихотворений'));
    if (poetHits.length) found.push(plural(poetHits.length, 'поэт', 'поэта', 'поэтов'));
    count.textContent = found.length ? 'Найдено: ' + found.join(', ') : '';
    if (!results.length && !poetHits.length) {
      out.appendChild(el('p', 'search-empty', 'Ничего не найдено. Попробуйте оставить только несколько самых запоминающихся слов.'));
      return;
    }

    if (poetHits.length) {
      group('Поэты', poetHits.map(function (pt) {
        var li = el('li');
        var a = el('a', null, pt.ru);
        a.href = pt.href;
        li.appendChild(a);
        if (pt.en !== pt.ru) li.appendChild(el('small', null, pt.en));
        return li;
      }));
    }

    var shown = results.slice(0, LIMIT);
    var item = function (r) {
      var p = r.poem;
      var li = el('li');
      var a = el('a', null, p.title);
      a.href = p.href;
      li.appendChild(a);
      li.appendChild(el('small', null, p.poetRu + (p.enTitle ? ' · ' + p.enTitle : '')));
      var snippet = el('div', 'search-snippet');
      highlight(snippet, r.lines.map(function (li) { return p.lines[li]; }).join(' / '), words);
      li.appendChild(snippet);
      return li;
    };
    var exact = shown.filter(function (r) { return r.level >= 3; });
    var partial = shown.filter(function (r) { return r.level < 3; });
    if (exact.length) group(partial.length ? 'Точное совпадение' : 'Стихотворения', exact.map(item));
    if (partial.length) group('Все слова есть, но не подряд', partial.map(item));
    if (results.length > LIMIT) {
      out.appendChild(el('p', 'search-more', 'Показаны первые ' + LIMIT + '. Уточните запрос, чтобы увидеть остальные.'));
    }
  }

  var timer = null;
  input.addEventListener('input', function () {
    clearTimeout(timer);
    timer = setTimeout(function () {
      var q = input.value.trim();
      history.replaceState(null, '', q ? '?q=' + encodeURIComponent(q) : location.pathname);
      render(q);
    }, 150);
  });
  main.querySelector('.search-form').addEventListener('submit', function (e) {
    e.preventDefault();
    clearTimeout(timer);
    render(input.value);
  });

  var q = new URLSearchParams(location.search).get('q') || '';
  input.value = q;
  render(q);
})();
