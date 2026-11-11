// Light-touch accessibility enhancements for Rspress pages.
// Do NOT intercept Enter for native <a> or <button>: browsers already implement their keyboard behavior.
(() => {
  function ensureMainAndSkipLink() {
    const main = document.querySelector('main, .rp-home-hero');
    if (!main) return;
    if (!main.id) main.id = 'main-content';

    const hero = document.querySelector('.rp-home-hero');
    if (hero && !hero.querySelector('h1')) {
      const heading = document.createElement('h1');
      heading.className = 'ztg-visually-hidden';
      heading.textContent = 'ZeroTier Gateway';
      hero.prepend(heading);
    }

    if (!document.querySelector('.ztg-skip-link')) {
      const link = document.createElement('a');
      link.href = `#${main.id}`;
      link.textContent = '跳到主要内容';
      link.className = 'ztg-skip-link';
      document.body.prepend(link);
    }
  }

  function enhanceCustomCards() {
    document.querySelectorAll('.rp-home-feature__card--clickable').forEach((card) => {
      // Prefer existing accessible native links. Only upgrade non-native clickable cards.
      if (card.matches('a[href], button') || card.querySelector('a[href]')) return;
      if (card.dataset.ztgKeyboardReady === 'true') return;
      card.dataset.ztgKeyboardReady = 'true';
      card.setAttribute('role', 'link');
      card.setAttribute('tabindex', '0');
      const title = card.querySelector('h2')?.textContent?.trim() || '任务文档';
      card.setAttribute('aria-label', `打开：${title}`);
      card.addEventListener('keydown', (event) => {
        if (event.key !== 'Enter' && event.key !== ' ') return;
        event.preventDefault();
        card.click();
      });
    });
  }

  let scheduled = false;
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => {
      scheduled = false;
      ensureMainAndSkipLink();
      enhanceCustomCards();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', schedule, { once: true });
  } else schedule();

  // Rspress route transitions may replace page content. This observer is coalesced per animation frame.
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
})();
