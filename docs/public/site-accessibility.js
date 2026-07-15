const enhanceInteractiveElements = () => {
  document.querySelectorAll('.rp-switch-appearance').forEach((element) => {
    if (element.dataset.keyboardReady === 'true') return;

    element.dataset.keyboardReady = 'true';
    element.setAttribute('role', 'button');
    element.setAttribute('tabindex', '0');
    element.setAttribute('aria-label', '切换明暗主题');
    element.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      event.stopPropagation();
      element.click();
    });
  });

  document.querySelectorAll('.rp-social-links__item[href*="github.com"]').forEach((element) => {
    element.setAttribute('aria-label', '打开 GitHub 仓库');
  });

  document.querySelectorAll('.rp-nav-hamburger').forEach((element) => {
    const updateState = () => {
      const expanded = element.classList.contains('rp-nav-hamburger--active');
      element.setAttribute('aria-expanded', String(expanded));
      element.setAttribute('aria-label', expanded ? '关闭导航菜单' : '打开导航菜单');
    };

    if (element.dataset.menuReady !== 'true') {
      element.dataset.menuReady = 'true';
      element.addEventListener('click', () => requestAnimationFrame(updateState));
    }
    updateState();
  });
};

enhanceInteractiveElements();
new MutationObserver(enhanceInteractiveElements).observe(document.documentElement, {
  childList: true,
  subtree: true
});
