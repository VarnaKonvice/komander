/* Platform selection never hides shared product sections. */
(() => {
  function selectPlatform(scope, platform, moveFocus = false) {
    const list = document.querySelector(`[data-platform-tabs="${scope}"]`);
    if (!list) return;
    list.querySelectorAll('[role="tab"]').forEach(tab => {
      const selected = tab.dataset.platform === platform;
      tab.setAttribute('aria-selected', String(selected));
      tab.tabIndex = selected ? 0 : -1;
      const panel = document.getElementById(tab.getAttribute('aria-controls'));
      if (panel) panel.hidden = !selected;
      if (selected && moveFocus) tab.focus();
    });
  }

  document.querySelectorAll('[data-platform-tabs]').forEach(list => {
    const scope = list.dataset.platformTabs;
    const tabs = [...list.querySelectorAll('[role="tab"]')];
    tabs.forEach((tab, index) => {
      tab.addEventListener('click', () => selectPlatform(scope, tab.dataset.platform));
      tab.addEventListener('keydown', event => {
        let next;
        if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
        if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
        if (event.key === 'Home') next = 0;
        if (event.key === 'End') next = tabs.length - 1;
        if (next === undefined) return;
        event.preventDefault();
        selectPlatform(scope, tabs[next].dataset.platform, true);
      });
    });
  });

  document.querySelectorAll('[data-platform-link],[data-platform-open]').forEach(link => {
    link.addEventListener('click', () => {
      selectPlatform('application', link.dataset.platformLink || 'android');
      link.closest('details')?.removeAttribute('open');
      if (link.tagName === 'BUTTON') {
        document.getElementById('commander')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });
})();
