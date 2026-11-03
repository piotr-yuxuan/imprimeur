# Zoom the page

The page in an Emacs window zooms as Emacs's text scales say. These steps change its size. A real
wheel was checked here on an X server of its own, with a program turning it: a person's hand has not
tried it, and a Wayland session has not been tried.

1. Make the page larger or smaller: press `+` or `-` in its Emacs window, or `C-x C-+` and `C-x C--`,
   as anywhere in Emacs. With a prefix, they go that many steps. The page stays at its place.
2. Use the mouse: hold Control and turn the wheel over the page.
3. Give the page its size back: press `0` in its Emacs window, or `C-x C-0`.
4. Scale everything, and the page with it: press `C-x C-M-+` or `C-x C-M--`, or hold Control and
   Alt and turn the wheel. `C-x C-M-0` undoes it.
5. Scale the source alone: the same keys and the same wheel, over the source.
6. Change what a step is worth: set `text-scale-mode-step`, Emacs's own option.

A popover that is open, or a skin that takes those keys, has them first: Minitel's digits do while
SOMMAIRE waits for a choice. In a browser, Control and the wheel are the browser's own, and these
keys of Emacs have no part in it. [The reference](../reference/commands-and-keys.md#what-zooms-the-page)
says how far a zoom goes, and what it keeps.
