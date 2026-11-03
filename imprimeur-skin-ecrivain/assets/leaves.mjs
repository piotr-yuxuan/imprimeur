// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// The supply of leaves.  The leaves are pure CSS, a stack of floats that the sheet draws
// from one empty element per leaf and cuts where the document ends (see the end of
// skin.css), so nothing here decides how many show, and the toggle runs no script.  All
// this does is keep more elements than any hand or variant can need, beside main and never
// in it: so it stays out of the block diff, which reads main's children alone, and out of
// the scroll map, which reads main's elements.

export default function mount({ signal }) {
  const root = document.documentElement;
  const main = document.getElementById('imprimeur-main');
  const stack = document.createElement('div');
  stack.className = 'ecrivain-feuilles';
  stack.setAttribute('aria-hidden', 'true');
  document.body.prepend(stack);

  // Two leaves running hold more than one leaf's writing, or the second's first block would
  // have stayed on the first: so a text of n leaves' writing takes at most 2n + 1.  A third
  // more covers a text that a pageless sheet sets wider than a leaf does.
  const compose = () => {
    const line = parseFloat(getComputedStyle(document.body).lineHeight);
    const lines = parseFloat(getComputedStyle(root).getPropertyValue('--ecrivain-feuille-lignes'));
    const end = main.lastElementChild?.getBoundingClientRect().bottom ?? 0;
    const text = end - document.body.getBoundingClientRect().top;
    const count = 3 * Math.ceil(Math.max(0, text) / (lines * line)) + 2;
    while (stack.children.length < count) {
      stack.append(document.createElement('i'));
      stack.lastChild.append(document.createElement('b'));
    }
    while (stack.children.length > count) stack.lastChild.remove();
  };
  compose();

  const sizes = new ResizeObserver(compose);
  sizes.observe(main);
  const choices = new MutationObserver(compose);
  choices.observe(root, {
    attributes: true,
    attributeFilter: ['data-ecrivain-sheet', 'data-ecrivain-variant', 'data-ecrivain-hand'],
  });
  signal.addEventListener('abort', () => {
    sizes.disconnect();
    choices.disconnect();
    stack.remove();
  });
}
