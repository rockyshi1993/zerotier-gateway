const ensurePageLandmarks = () => {
  let main = document.querySelector('main');
  const homeHero = document.querySelector('.rp-home-hero');

  if (homeHero) {
    homeHero.setAttribute('role', 'main');
    homeHero.id = 'main-content';
    main = homeHero;
    if (!homeHero.querySelector('h1')) {
      const heading = document.createElement('h1');
      heading.className = 'ztg-visually-hidden';
      heading.textContent = 'ZeroTier Gateway';
      homeHero.prepend(heading);
    }
  } else if (main) {
    main.id = 'main-content';
  }

  const navigation = document.querySelector('.rp-nav-menu');
  if (navigation) {
    navigation.setAttribute('role', 'navigation');
    navigation.setAttribute('aria-label', '主导航');
  }

  if (main && !document.querySelector('.ztg-skip-link')) {
    const skipLink = document.createElement('a');
    skipLink.className = 'ztg-skip-link';
    skipLink.href = '#main-content';
    skipLink.textContent = '跳到主要内容';
    document.body.prepend(skipLink);
  }
};

const enhanceInteractiveElements = () => {
  ensurePageLandmarks();

  document.querySelectorAll('a[href], button, [role="link"], [role="button"]').forEach((element) => {
    if (element.dataset.enterGuardReady === 'true') return;
    if (element.matches('.rp-home-feature__card--clickable, .rp-nav-hamburger')) return;

    element.dataset.enterGuardReady = 'true';
    element.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter') return;
      event.preventDefault();
      event.stopPropagation();
      element.click();
    });
  });

  document.querySelectorAll('.rp-home-feature__card--clickable').forEach((element) => {
    if (element.dataset.keyboardReady === 'true') return;

    const title = element.querySelector('h2')?.textContent?.trim() || '文档任务';
    element.dataset.keyboardReady = 'true';
    element.setAttribute('role', 'link');
    element.setAttribute('tabindex', '0');
    element.setAttribute('aria-label', `打开任务：${title}`);
    element.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      event.stopPropagation();
      element.click();
    });
  });

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
      element.addEventListener('keydown', (event) => {
        if (event.key !== 'Enter' && event.key !== ' ') return;
        event.preventDefault();
        event.stopPropagation();
        element.click();
      });
    }
    updateState();
  });
};

const startEnhancements = () => {
  enhanceInteractiveElements();
  new MutationObserver(enhanceInteractiveElements).observe(document.documentElement, {
    childList: true,
    subtree: true
  });
};

const scheduleEnhancements = () => {
  requestAnimationFrame(() => requestAnimationFrame(startEnhancements));
};

if (document.readyState === 'complete') {
  scheduleEnhancements();
} else {
  window.addEventListener('load', scheduleEnhancements, { once: true });
}
