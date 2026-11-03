// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// What a stylesheet cannot do for Briefing: the memo's Skim link, a test of the font's
// figures, details on paper, and a diagram's natural size.

// Each designed figure is about 0.73 as wide as the plain one in Inter and Adwaita
// Sans, in both engines; a font with none stays at 1.
const designedFigures = 0.85;

export default function mount({ signal, option }) {
  const root = document.documentElement;
  const main = document.getElementById('imprimeur-main');

  // What a new render or a drawing brings, and the skim view's word on its link.
  const follow = () => {
    for (const link of main.querySelectorAll('.briefing-skim')) {
      link.setAttribute('aria-pressed', String(option('skim') === 'on'));
    }
    for (const svg of main.querySelectorAll('pre.mermaid > svg')) {
      const width = svg.viewBox.baseVal?.width;
      if (width) svg.style.setProperty('--briefing-natural', `${width}px`);
    }
  };
  const watcher = new MutationObserver(follow);
  watcher.observe(root, { attributes: true, attributeFilter: ['data-briefing-skim'] });
  watcher.observe(main, { childList: true, subtree: true });
  follow();

  // The link flips this page, at once: the next option that Emacs sets speaks for the
  // session again, skim with it.
  document.addEventListener('click', (event) => {
    if (!(event.target instanceof Element && event.target.closest('.briefing-skim'))) return;
    if (option('skim') === 'on') root.removeAttribute('data-briefing-skim');
    else root.setAttribute('data-briefing-skim', 'on');
  }, { capture: true, signal });

  // On paper, nothing stays folded, and what the reader had open stays open after.
  let opened = [];
  window.addEventListener('beforeprint', () => {
    opened = [...main.querySelectorAll('details:not([open])')];
    for (const details of opened) details.open = true;
  }, { signal });
  window.addEventListener('afterprint', () => {
    for (const details of opened) details.open = false;
  }, { signal });

  signal.addEventListener('abort', () => {
    watcher.disconnect();
    root.classList.remove('briefing-plain-figures');
    for (const svg of main.querySelectorAll('pre.mermaid > svg')) svg.style.removeProperty('--briefing-natural');
  });

  document.fonts.ready.then(() => {
    if (signal.aborted) return;
    const span = document.body.appendChild(document.createElement('span'));
    span.style.cssText = 'position:absolute;visibility:hidden;white-space:nowrap;';
    const widthOf = (digit, position) => {
      span.textContent = digit;
      span.style.fontVariantPosition = position;
      return span.getBoundingClientRect().width;
    };
    const designed = [...'0123456789'].every((digit) => widthOf(digit, 'super') < widthOf(digit, 'normal') * designedFigures);
    span.remove();
    root.classList.toggle('briefing-plain-figures', !designed);
  });
}
