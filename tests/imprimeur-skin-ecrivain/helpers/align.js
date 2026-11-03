// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// What the check of the alignment needs from the page: where each letter is, by the DOM;
// the pixels decide the rest (align-check.py).  The same script in both engines.  A
// letter's rectangle runs the strut's ascent and descent about the baseline, so its middle
// is that line's baseline, as the DOM has it.
window.ecrivainAlign = (() => {
  const sitters = new Set('acemnorsuvwx');
  const skipped = 'svg, math, kbd, sup, sub, figure a, .task, .imprimeur-diagram-error, code:not(pre code)';
  const colour = (name) => {
    const probe = document.body.appendChild(document.createElement('span'));
    probe.style.color = `var(${name})`;
    const text = getComputedStyle(probe).color;
    probe.remove();
    const pen = Object.assign(document.createElement('canvas'), { width: 1, height: 1 }).getContext('2d');
    pen.fillStyle = text;
    pen.fillRect(0, 0, 1, 1);
    return [...pen.getImageData(0, 0, 1, 1).data].slice(0, 3);
  };
  const kindOf = (element) => {
    if (element.closest('blockquote, aside.footnotes, caption, figcaption, .caption')) return 'note';
    if (element.closest('#imprimeur-title, h1, h2, h3, h4, h5, h6')) return 'heading';
    return element.closest('td, th') ? 'table' : 'body';
  };
  const range = document.createRange();
  const add = (lines, node, at, parent, style) => {
    range.setStart(node, at);
    range.setEnd(node, at + 1);
    const rect = range.getClientRects()[0];
    if (!rect || rect.width < 1) return;
    const y = rect.top + rect.height / 2 + window.scrollY;
    const key = `${y}|${style.fontFamily}|${style.fontSize}`;
    if (!lines.has(key)) {
      lines.set(key, { y, size: parseFloat(style.fontSize), kind: kindOf(parent), text: '',
                       code: Boolean(parent.closest('pre')), letters: [] });
    }
    const line = lines.get(key);
    line.text += node.data[at];
    if (sitters.has(node.data[at])) {
      line.letters.push([node.data[at], rect.left + window.scrollX, rect.right + window.scrollX]);
    }
  };
  function probe(slice) {
    const lines = new Map();
    for (const root of [document.getElementById('imprimeur-title'), document.getElementById('imprimeur-main')]) {
      if (root.hidden) continue;
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      while (walker.nextNode()) {
        const node = walker.currentNode;
        if (node.parentElement.closest(skipped)) continue;
        const style = getComputedStyle(node.parentElement);
        for (let at = 0; at < node.length; at += 1) {
          if (!/\s/.test(node.data[at])) add(lines, node, at, node.parentElement, style);
        }
      }
    }
    const rootStyle = getComputedStyle(document.documentElement);
    const body = document.body.getBoundingClientRect();
    return JSON.stringify({
      slice,
      dpr: window.devicePixelRatio,
      width: document.documentElement.clientWidth,
      height: document.documentElement.scrollHeight,
      bodyLeft: body.left + window.scrollX,
      line: parseFloat(getComputedStyle(document.body).lineHeight),
      fontSize: parseFloat(getComputedStyle(document.body).fontSize),
      interline: parseFloat(rootStyle.getPropertyValue('--ecrivain-i')),
      paper: colour('--imp-background'),
      ink: colour('--imp-foreground'),
      thick: colour('--ecrivain-rule-strong-ink'),
      thin: colour('--ecrivain-rule-ink'),
      lines: [...lines.values()].sort((a, b) => a.y - b.y),
      blocks: [...document.getElementById('imprimeur-main').children]
        .map((element) => element.getBoundingClientRect().top + window.scrollY - body.top - window.scrollY),
    });
  }
  const sheet = new CSSStyleSheet();
  sheet.replaceSync(`
    html body { background-image: none !important; }
    .ecrivain-feuilles b::after { background: none !important; color: transparent !important; }
    * { text-decoration: none !important; }
    mark { background: none !important; }
    thead th { background-image: none !important; }
    hr, pre::after, table::after, blockquote::before,
    .note::before, .tip::before, .warning::before, .caution::before, .important::before { visibility: hidden !important; }
    ::selection { background: none !important; }
  `);
  function inkOnly(on) {
    document.adoptedStyleSheets = on ? [sheet] : [];
  }
  return { probe, inkOnly };
})();
'ready';
