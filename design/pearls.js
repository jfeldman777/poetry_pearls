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
})();
