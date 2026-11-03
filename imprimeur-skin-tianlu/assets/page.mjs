// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// What a stylesheet cannot do for Tianlu: one fold column for each band, which only the
// page's height can count, outside main and so outside its blocks, and each diagram's
// width, for its plate in whole columns, which the sheet can read from no drawing in WebKit.

export default function mount({ signal }) {
  const root = document.documentElement;
  const main = document.getElementById('imprimeur-main');
  const heading = document.getElementById('imprimeur-title');

  const layer = document.body.appendChild(document.createElement('div'));
  layer.className = 'tianlu-folds';
  layer.setAttribute('aria-hidden', 'true');

  // Everything a band is made of comes from the sheet.  A band's foot lies past the last
  // block by main::after, so that the page's last band ends where the last fold does.
  const lay = () => {
    for (const svg of main.querySelectorAll('.tianlu-slot pre.mermaid > svg')) {
      const width = svg.viewBox.baseVal?.width;
      if (width) svg.closest('.tianlu-slot').style.setProperty('--tianlu-draw-w', `${width}px`);
    }
    const style = getComputedStyle(main);
    const grid = parseFloat(style.height);
    const pitch = grid + parseFloat(style.columnGap);
    const bands = Math.max(1, Math.round((main.scrollHeight - grid) / pitch) + 1);
    const title = heading.textContent;
    if (layer.childElementCount === bands && layer.dataset.tianluTitle === title) return;
    layer.dataset.tianluTitle = title;
    // A document's title reaches the folds as text alone, in attributes that the sheet draws.
    layer.replaceChildren(...Array.from({ length: bands }, () => {
      const fold = document.createElement('i');
      fold.setAttribute('data-tianlu-title', title);
      fold.append(document.createElement('u'), document.createElement('s'));
      fold.firstChild.setAttribute('data-tianlu-ear', [...title].slice(0, 2).join(''));
      return fold;
    }));
  };

  const watcher = new MutationObserver(lay);
  signal.addEventListener('abort', () => {
    watcher.disconnect();
    layer.remove();
    for (const slot of main.querySelectorAll('.tianlu-slot')) slot.style.removeProperty('--tianlu-draw-w');
  });
  watcher.observe(root, { attributes: true, attributeFilter: ['data-tianlu-preset', 'data-tianlu-face', 'lang'] });
  watcher.observe(main, { childList: true, subtree: true });
  watcher.observe(heading, { childList: true });
  window.addEventListener('resize', lay, { signal });
  main.addEventListener('load', lay, { capture: true, signal });
  document.fonts.ready.then(() => {
    if (!signal.aborted) lay();
  });
  lay();
}
