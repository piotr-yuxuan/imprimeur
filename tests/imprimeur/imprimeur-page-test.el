;;; imprimeur-page-test.el --- Tests of the page, in headless Chromium  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements (plan 002, acceptance 2, 7 and 8): the first load shows the
;; document, reports the server's revision and sends ready, with no console
;; error and no policy violation; a hostile document, on first load or
;; inserted by an edit, runs nothing, navigates nowhere, leaves none of the
;; forbidden elements or attributes and sends no request off the loopback
;; address; video, details, kbd, MathML and cell styles survive; a remote
;; image is a link naming its host in an untrusted document and loads in a
;; trusted one; a render failure shows its text in the banner as text,
;; and pandoc's warnings as a notice; a link followed by click, middle
;; click or from an image map reaches Emacs or nothing, opening no window
;; and changing no location.  Headless Chromium never navigates on a
;; dropped link, so the page's guard against drops is checked by hand.
;;
;; Plan 003, acceptance 3 and "Palette to the page": a change of theme in
;; Emacs gives the page the new palette in place of the last, in its one
;; style element, the new background and the new data-appearance, with no
;; navigation: the location and a property set on window survive, and there
;; is no console error and no policy violation.  "Minitel on the palette":
;; each Minitel colour is the palette's, the background --emacs-bg, the
;; code panes' --emacs-code-bg, the foreground --emacs-fg, the muted text
;; and the rules --emacs-muted, links --emacs-link, and the code's
;; keywords, strings, comments, constants, functions and types --emacs-kw,
;; -str, -com, -const, -fn and -type, and the background of its alerts
;; --emacs-warn; where the palette gives no colour, Minitel's own light or
;; dark one stands in, a code pane's even when the palette gives a
;; background, chosen by the palette's appearance whatever the
;; reader prefers, or by prefers-color-scheme before a palette arrives, and
;; an alert takes the base's error colour.  Acceptance 5: in Minitel, in an
;; Org document as in a Markdown one, h1 to h6, p, li, pre and code share
;; one font list, the default face's family then monospace, which stands in
;; for a family the browser lacks, and one size; the headings' colours are
;; --emacs-h1 to --emacs-h6, the first level's as its chip's background,
;; and a keyword's the keyword colour.
;;
;; Acceptance 3 and "Block diff": in an Org document as in a Markdown one,
;; whose data-pos attributes an edit above shifts, a property set on an
;; untouched node survives an edit elsewhere; a WebM made by ffmpeg reports
;; a duration above 1.5 s and keeps its currentTime across an unrelated
;; edit; neither leaves the page meanwhile, and the page then holds what a
;; fresh load of the same revision shows.  A Markdown block kept by an edit
;; above has the lines of the new text in its data-pos and in those of the
;; elements it holds.  The blocks of a hostile document that an edit above
;; leaves in place stay as harmless as on first load.  A deletion, a move, a
;; duplicate, an insertion and the removal of every block show the new text
;; in its order, keeping the nodes of the blocks that the diff reuses, and
;; the page
;; ends as a fresh load shows it, even when a block that stays loses a
;; data-pos of its own.  A block changed since it was shown, details that
;; the reader opened, is still the block that the document holds, and stays
;; as it is.  A picture or a video that failed to load is tried again at the
;; next edit, which keeps the blocks around it; a video that plays stays,
;; though a track or a source with another after it failed.  An edit of a
;; block's markup alone, its words unchanged, shows as any other.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-cdp)
(require 'imprimeur-test-themes)
(require 'imprimeur)

(defvar imprimeur-page-test-followed nil
  "The links that reached Emacs, newest first: (browse URL) or (visit FILE).")

(defmacro imprimeur-page-test-with (spec &rest body)
  "Run BODY with the page of a scratch document open in a browser.
SPEC is (BUFFER BROWSER FILE TEXT): BUFFER visits FILE, holding TEXT,
in a scratch git repository that also holds pic.png and other.md, in
`imprimeur-mode'; BROWSER has loaded its page.  `browse-url' and
`find-file-other-window' only record into `imprimeur-page-test-followed'."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,browser ,file ,text) spec))
    `(let* ((imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
            (imprimeur-browser-program imprimeur-test-fake-browser)
            (imprimeur-page-test-followed nil)
            (root (repo-test-git-tree (list (cons ,file ,text) (cons "pic.png" "PNG!")
                                            (cons "other.md" "# Other\n"))))
            (,buffer (find-file-noselect (expand-file-name ,file root))))
       (unwind-protect
           (cl-letf (((symbol-function 'browse-url)
                      (lambda (url &rest _) (push (list 'browse url) imprimeur-page-test-followed)))
                     ((symbol-function 'find-file-other-window)
                      (lambda (file &rest _) (push (list 'visit file) imprimeur-page-test-followed))))
             (imprimeur-test-cdp-with-browser ,browser
               (with-current-buffer ,buffer (imprimeur-mode 1))
               (imprimeur-test-cdp-navigate ,browser (imprimeur-url ,buffer))
               ,@body))
         (with-current-buffer ,buffer (set-buffer-modified-p nil))
         (kill-buffer ,buffer)))))

(defun imprimeur-page-test-wait-shown (browser revision)
  "Wait until BROWSER's page shows REVISION or a later one."
  (imprimeur-test-wait-for
   (lambda () (>= (string-to-number (or (imprimeur-test-cdp-eval
                                          browser "document.documentElement.dataset.revision")
                                         "0"))
                  revision))))

(defconst imprimeur-page-test-inspect
  "(() => {
  const main = document.getElementById('imprimeur-main');
  const tags = ['script', 'iframe', 'frame', 'object', 'embed', 'form', 'input', 'button', 'select',
                'textarea', 'style', 'template', 'map', 'area', 'base', 'meta', 'link'];
  const found = tags.filter((tag) => main.getElementsByTagName(tag).length > 0);
  for (const element of main.querySelectorAll('*'))
    for (const attribute of element.attributes)
      if (/^on/i.test(attribute.name)
          || ['target', 'ping', 'download', 'srcdoc', 'formaction'].includes(attribute.name)
          || /^\\s*javascript:/i.test(attribute.value))
        found.push(element.localName + '[' + attribute.name + ']');
  if (document.getElementById('location') || document.getElementsByName('location').length > 0)
    found.push('location');
  return [found, typeof window.__pwned, location.href, document.baseURI];
})()"
  "What the page holds that a hostile document must not have put there.
The value is [FOUND PWNED HREF BASE]: the forbidden elements and
attributes found in main, the type of window.__pwned, the location and
the base URL.")

(defun imprimeur-page-test-hostile (format clean hostile)
  "Check that HOSTILE, text in FORMAT, harms neither the page nor Emacs.
The document starts as CLEAN, then an edit appends HOSTILE, another
adds a paragraph above it, which leaves in place HOSTILE's blocks where
nothing failed to load, the link named run among them, and makes the
others anew, then the page is loaded again."
  (imprimeur-page-test-with (buffer browser (concat "doc." format) clean)
    (let ((url (imprimeur-url buffer))
          (run "[...document.querySelectorAll('main a')].find((a) => a.textContent === 'run')"))
      (imprimeur-page-test-wait-shown browser 1)
      (with-current-buffer buffer (goto-char (point-max)) (insert hostile))
      (imprimeur-page-test-wait-shown browser 2)
      (should (imprimeur-test-cdp-eval browser "document.querySelector('main').textContent.includes('Hostile end')"))
      (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-inspect) (vector [] "undefined" url url)))
      (imprimeur-test-cdp-eval browser (concat run ".__kept = 'kept'"))
      (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
      (imprimeur-page-test-wait-shown browser 3)
      (should (equal (imprimeur-test-cdp-eval browser (concat run ".__kept")) "kept"))
      (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-inspect) (vector [] "undefined" url url)))
      (imprimeur-test-cdp-click browser run)
      (accept-process-output nil 0.5)
      (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-inspect) (vector [] "undefined" url url)))
      (imprimeur-test-cdp-navigate browser url)
      (imprimeur-page-test-wait-shown browser 3)
      (accept-process-output nil 0.5)
      (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-inspect) (vector [] "undefined" url url)))
      (should-not (imprimeur-test-cdp-escaped browser))
      (should-not imprimeur-page-test-followed))))

(defun imprimeur-page-test-fixture (name)
  "Return the contents of the page fixture NAME."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (concat "tests/fixtures/page/" name) repo-test-root))
    (buffer-string)))

(ert-deftest imprimeur-page-shows-the-first-revision-cleanly ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.org"
                                    "#+TITLE: The title\n#+LANGUAGE: fr\n* Heading\nSome text.\n")
    (imprimeur-page-test-wait-shown browser 1)
    (let ((session (buffer-local-value 'imprimeur--session buffer)))
      (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('main h1').textContent")
                     "Heading"))
      (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.revision")
                     (number-to-string (imprimeur--session-revision session))))
      (imprimeur-test-wait-for (lambda () (eql (imprimeur--session-ready session)
                                               (imprimeur--session-revision session)))))
    (should (equal (imprimeur-test-cdp-eval
                    browser "[document.title, document.documentElement.lang,
document.documentElement.dataset.format, document.getElementById('imprimeur-title').textContent]")
                   ["The title" "fr" "org" "The title"]))
    (should (equal (imprimeur-test-cdp-eval browser "window.__violations") []))
    (should-not (imprimeur-test-cdp-errors browser))
    (should-not (imprimeur-test-cdp-escaped browser))))

(ert-deftest imprimeur-page-resists-a-hostile-org-document ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-hostile
   "org" "* Start\n"
   (concat "* Hostile\n#+begin_export html\n" (imprimeur-page-test-fixture "hostile.html")
           "#+end_export\n\n#+ATTR_HTML: :onerror window.__pwned=1 :onclick window.__pwned=1\n"
           "[[file:missing.png]]\n\n[[javascript:window.__pwned=1][run]]\n\n"
           "[[https://example.invalid/remote.png]]\n")))

(ert-deftest imprimeur-page-resists-a-hostile-markdown-document ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-hostile
   "md" "# Start\n"
   (concat "\n# Hostile\n\n" (imprimeur-page-test-fixture "hostile.html")
           "\n[run](javascript:window.__pwned=1)\n\n![remote](https://example.invalid/remote.png)\n")))

(ert-deftest imprimeur-page-keeps-rich-markup ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.md"
                                    (concat "# Rich\n\n<details><summary>More</summary>Hidden</details>\n\n"
                                            "Press <kbd>C-x</kbd> for $x^2$.\n\n"
                                            "| a | b |\n|:--|--:|\n| 1 | 2 |\n\n![clip](clip.webm)\n\n"
                                            "- [ ] tight\n- [x] list\n\nThen:\n\n- [ ] loose\n\n- [x] list\n"))
    (imprimeur-page-test-wait-shown browser 1)
    (should (equal (imprimeur-test-cdp-eval
                    browser "['video', 'details', 'kbd', 'math', 'td[style]']
.filter((selector) => !document.querySelector('main ' + selector))")
                   []))
    ;; A task item shows its box, not a bullet, in tight and loose lists.
    (should (equal (imprimeur-test-cdp-eval
                    browser "[...document.querySelectorAll('main li')]
.map((li) => [li.textContent.trim(), getComputedStyle(li).listStyleType])")
                   [["☐ tight" "none"] ["☑ list" "none"] ["☐ loose" "none"] ["☑ list" "none"]]))
    (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.format") "gfm"))))

(ert-deftest imprimeur-page-loads-remote-images-for-trusted-documents-only ()
  (imprimeur-test-require "pandoc")
  (let ((text "# Badge\n\n![badge](https://example.invalid/badge.svg)\n")
        (image "https://example.invalid/badge.svg"))
    (imprimeur-page-test-with (buffer browser "doc.md" text)
      (imprimeur-page-test-wait-shown browser 1)
      (should (equal (imprimeur-test-cdp-eval
                      browser "[document.querySelectorAll('main img').length,
document.querySelector('main a.imprimeur-remote').textContent]")
                     [0 "badge (example.invalid)"]))
      (accept-process-output nil 0.5)
      (should-not (imprimeur-test-cdp-escaped browser)))
    (let ((trusted-content :all))
      (imprimeur-page-test-with (buffer browser "doc.md" text)
        (imprimeur-page-test-wait-shown browser 1)
        (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('main img').getAttribute('src')")
                       image))
        (imprimeur-test-wait-for (lambda () (member image (imprimeur-test-cdp-escaped browser))))
        (should (equal (imprimeur-test-cdp-eval browser "window.__violations") []))))))

(ert-deftest imprimeur-page-shows-a-failure-as-text ()
  (let* ((meta "<meta http-equiv=refresh content=0;url=http://example.invalid>")
         (imprimeur-pandoc-program imprimeur-test-fake-pandoc)
         (process-environment (append (list "IMPRIMEUR_FAKE_PANDOC=fail"
                                            (concat "IMPRIMEUR_FAKE_PANDOC_MESSAGE=" meta))
                                      process-environment)))
    (imprimeur-page-test-with (buffer browser "doc.org" "* A\n")
      (let ((url (imprimeur-url buffer)))
        (imprimeur-test-cdp-wait browser "!document.getElementById('imprimeur-banner').hidden")
        (accept-process-output nil 1)
        (should (equal (imprimeur-test-cdp-eval
                        browser "(() => { const banner = document.getElementById('imprimeur-banner');
return [banner.dataset.kind, banner.textContent.trim(), banner.children.length,
        document.querySelectorAll('meta[http-equiv=\"refresh\" i]').length, location.href]; })()")
                       (vector "error" meta 0 0 url)))))))

(ert-deftest imprimeur-page-shows-warnings-as-a-notice ()
  (let ((imprimeur-pandoc-program imprimeur-test-fake-pandoc)
        (process-environment (cons "IMPRIMEUR_FAKE_PANDOC=warn" process-environment)))
    (imprimeur-page-test-with (buffer browser "doc.org" "* A\n")
      (imprimeur-page-test-wait-shown browser 1)
      (should (equal (imprimeur-test-cdp-eval
                      browser "(() => { const banner = document.getElementById('imprimeur-banner');
return [banner.hidden, banner.dataset.kind, banner.textContent.trim()]; })()")
                     (vector nil "notice" "[WARNING] Could not fetch resource"))))))

(ert-deftest imprimeur-page-hands-links-to-emacs ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.org"
                                    (concat "* Links\n[[https://example.invalid/plain][plain]]\n\n"
                                            "#+begin_export html\n"
                                            "<p><img id=\"mapped\" src=\"pic.png\" usemap=\"#m\" width=\"100\""
                                            " height=\"100\"><map name=\"m\"><area shape=\"rect\""
                                            " coords=\"0,0,100,100\" href=\"https://example.invalid/area\">"
                                            "</map></p>\n<p><a id=\"blank\" href=\"https://example.invalid/blank\""
                                            " target=\"_blank\">blank</a></p>\n#+end_export\n\n"
                                            "[[file:other.md][other]]\n"))
    (imprimeur-page-test-wait-shown browser 1)
    (let ((url (imprimeur-url buffer))
          (pages (imprimeur-test-cdp-pages browser))
          (buffers (buffer-list))
          (plain "document.querySelector('main a[href$=\"/plain\"]')")
          (prompts nil))
      (cl-letf (((symbol-function 'read-from-minibuffer) (lambda (&rest _) (push 'read prompts) ""))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) (push 'yes-or-no prompts) nil))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) (push 'y-or-n prompts) nil)))
        (imprimeur-test-cdp-click browser plain)
        (imprimeur-test-wait-for (lambda () (= (length imprimeur-page-test-followed) 1)))
        (imprimeur-test-cdp-click browser "document.getElementById('mapped')")
        (accept-process-output nil 0.5)
        (imprimeur-test-cdp-click browser plain "middle")
        (imprimeur-test-wait-for (lambda () (= (length imprimeur-page-test-followed) 2)))
        (imprimeur-test-cdp-click browser "document.getElementById('blank')")
        (imprimeur-test-wait-for (lambda () (= (length imprimeur-page-test-followed) 3)))
        (imprimeur-test-cdp-click browser "document.querySelector('main a[href=\"other.md\"]')")
        (imprimeur-test-wait-for (lambda () (= (length imprimeur-page-test-followed) 4)))
        (accept-process-output nil 0.5))
      (should (equal (reverse imprimeur-page-test-followed)
                     `((browse "https://example.invalid/plain") (browse "https://example.invalid/plain")
                       (browse "https://example.invalid/blank")
                       (visit ,(file-truename (expand-file-name "other.md" (file-name-directory
                                                                            (buffer-file-name buffer))))))))
      (should (equal (imprimeur-test-cdp-eval browser "location.href") url))
      (should (= (imprimeur-test-cdp-pages browser) pages))
      (should (equal (buffer-list) buffers))
      (should-not prompts)
      (should-not (imprimeur-test-cdp-escaped browser)))))

(ert-deftest imprimeur-page-follows-the-theme-without-reloading ()
  (imprimeur-test-require "pandoc")
  (enable-theme 'imprimeur-test-night)
  (unwind-protect
      (imprimeur-page-test-with (buffer browser "doc.org" "* Heading\nSome text.\n")
        (let ((url (imprimeur-url buffer))
              (state "(() => {
  const root = document.documentElement;
  return [root.dataset.appearance ?? null, getComputedStyle(root).getPropertyValue('--emacs-bg'),
          getComputedStyle(root).backgroundColor, window.__kept ?? null, location.href,
          document.querySelectorAll('style').length,
          document.head.contains(document.getElementById('imprimeur-palette')),
          document.getElementById('imprimeur-palette').textContent];
})()"))
          (imprimeur-page-test-wait-shown browser 1)
          (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'dark'")
          (imprimeur-test-cdp-eval browser "window.__kept = 'kept'")
          (should (equal (imprimeur-test-cdp-eval browser state)
                         (vector "dark" "#1d1f21" "rgb(29, 31, 33)" "kept" url 1 t
                                 (plist-get (imprimeur-palette buffer) :css))))
          (disable-theme 'imprimeur-test-night)
          (enable-theme 'imprimeur-test-day)
          (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'light'")
          ;; The style element holds the day palette alone: none of the
          ;; night palette's properties stays.
          (should (equal (imprimeur-test-cdp-eval browser state)
                         (vector "light" "#ffffff" "rgb(255, 255, 255)" "kept" url 1 t
                                 (plist-get (imprimeur-palette buffer) :css))))
          (should (equal (imprimeur-test-cdp-eval browser "window.__violations") []))
          (should-not (imprimeur-test-cdp-errors browser))
          (should-not (imprimeur-test-cdp-escaped browser))))
    (mapc #'disable-theme '(imprimeur-test-night imprimeur-test-day))))

(ert-deftest imprimeur-page-takes-minitel-colours-from-the-palette ()
  (imprimeur-test-require "pandoc")
  (let* ((css ":root {
  --emacs-bg: #000001; --emacs-fg: #000002; --emacs-muted: #000003; --emacs-link: #000004;
  --emacs-kw: #000005; --emacs-str: #000006; --emacs-com: #000007; --emacs-const: #000008;
  --emacs-fn: #000009; --emacs-type: #00000a; --emacs-warn: #00000b;
  --emacs-code-bg: #00000c;
}\n")
         (palette (list :appearance "dark" :css css))
         (pane "getComputedStyle(document.querySelector('main pre')).backgroundColor"))
    (cl-letf (((symbol-function 'imprimeur-palette) (lambda (_buffer) palette)))
      (imprimeur-page-test-with (buffer browser "doc.org" "* Heading\n#+begin_src python\n# TODO\n#+end_src\n")
        (imprimeur-page-test-wait-shown browser 1)
        (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'dark'")
        (should (equal (imprimeur-test-cdp-eval browser "getComputedStyle(document.querySelector('main .al')).backgroundColor")
                       "rgb(0, 0, 11)"))
        (should (equal (imprimeur-test-cdp-eval browser pane) "rgb(0, 0, 12)"))
        (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const style = getComputedStyle(document.documentElement);
  return ['background', 'foreground', 'muted', 'link', 'rule', 'code-background', 'keyword', 'string',
          'comment', 'constant', 'function', 'type']
    .map((token) => [token, style.getPropertyValue('--imp-' + token)]);
})()")
                       [["background" "#000001"] ["foreground" "#000002"] ["muted" "#000003"]
                        ["link" "#000004"] ["rule" "#000003"] ["code-background" "#00000c"]
                        ["keyword" "#000005"] ["string" "#000006"] ["comment" "#000007"]
                        ["constant" "#000008"] ["function" "#000009"] ["type" "#00000a"]]))
        ;; Without a colour of its own, a pane takes Minitel's, not the background.
        (setq palette (list :appearance "dark" :css (string-replace "  --emacs-code-bg: #00000c;\n" "" css)))
        (imprimeur-refresh-palette)
        (imprimeur-test-cdp-wait
         browser "getComputedStyle(document.documentElement).getPropertyValue('--emacs-code-bg') === ''")
        (should (equal (imprimeur-test-cdp-eval browser pane) "rgb(28, 28, 26)"))))))

(defun imprimeur-page-test-minitel (file text)
  "Check that Minitel sets TEXT, held in FILE, in Emacs's family and colours.
TEXT holds headings of the six levels, a paragraph with inline code, a
list item and a block of Python.  The palette is the frame's, whatever
the document: with Org loaded, the headings' colours are the day
theme's `org-level-1' to `org-level-6'."
  (imprimeur-test-require "pandoc")
  (require 'org)
  (mapc #'enable-theme '(imprimeur-test-day imprimeur-test-mono))
  (unwind-protect
      (imprimeur-page-test-with (buffer browser file text)
        (imprimeur-page-test-wait-shown browser 1)
        (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'light'")
        (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const selectors = ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'li', 'pre', 'code'];
  const styles = [...document.querySelectorAll(selectors.map((selector) => 'main ' + selector).join())]
    .map((element) => getComputedStyle(element));
  const unique = (values) => [...new Set(values)];
  const families = unique(styles.map((style) => style.fontFamily));
  const headings = selectors.slice(0, 6)
    .map((selector) => getComputedStyle(document.querySelector('main ' + selector)));
  return [selectors.filter((selector) => !document.querySelector('main ' + selector)),
          families.map((family) => family.split(',').map((name) => name.trim().replace(/^\"(.*)\"$/, '$1'))),
          unique(styles.map((style) => style.fontSize)).length,
          [headings[0].backgroundColor, ...headings.slice(1).map((style) => style.color)],
          getComputedStyle(document.querySelector('main .kw')).color];
})()")
                       (vector [] [["Imprimeur Test Mono" "monospace"]] 1
                               ["rgb(200, 40, 33)" "rgb(200, 40, 34)" "rgb(200, 40, 35)"
                                "rgb(200, 40, 36)" "rgb(200, 40, 37)" "rgb(200, 40, 38)"]
                               "rgb(137, 89, 168)")))
        (should (equal (imprimeur-test-cdp-eval browser "window.__violations") []))
        (should-not (imprimeur-test-cdp-errors browser)))
    (mapc #'disable-theme '(imprimeur-test-day imprimeur-test-mono))))

(ert-deftest imprimeur-page-sets-org-in-the-emacs-family-and-colours ()
  (imprimeur-page-test-minitel
   "doc.org" (concat "* One\n** Two\n*** Three\n**** Four\n***** Five\n"
                     "****** Six\nA paragraph with ~code~.\n\n- an item\n\n"
                     "#+begin_src python\ndef f():\n    return 1\n#+end_src\n")))

(ert-deftest imprimeur-page-sets-markdown-in-the-emacs-family-and-colours ()
  (imprimeur-page-test-minitel
   "doc.md" (concat "# One\n\n## Two\n\n### Three\n\n#### Four\n\n##### Five\n\n"
                    "###### Six\n\nA paragraph with `code`.\n\n- an item\n\n"
                    "```python\ndef f():\n    return 1\n```\n")))

(ert-deftest imprimeur-page-falls-back-on-minitel-colours ()
  (imprimeur-test-require "pandoc")
  ;; A palette with no colour: its appearance alone chooses between
  ;; Minitel's own colours.
  (let ((palette (list :appearance "light" :css ":root {\n}\n"))
        ;; Minitel's own colours, its two lists before plan 003: background,
        ;; foreground, muted, link, rule, code background, keyword, string,
        ;; comment, constant, function and type.
        (light ["#f5f3ec" "#1c1c1a" "#6b6a63" "#1f4fa3" "#8f8d84" "#ebe8de"
                "#8b2f97" "#2f6b1f" "#6b6a63" "#a3501f" "#1f4fa3" "#7a5c00"])
        (dark ["#121211" "#e6e4dc" "#9a988f" "#8cb4ff" "#5d5b55" "#1c1c1a"
               "#d79ae0" "#9fd38a" "#9a988f" "#f0a36e" "#8cb4ff" "#e3c46a"])
        (state "(() => {
  const root = document.documentElement;
  const probe = document.body.appendChild(document.createElement('span'));
  const colours = ['background', 'foreground', 'muted', 'link', 'rule', 'code-background', 'keyword',
                   'string', 'comment', 'constant', 'function', 'type'].map((token) => {
    probe.style.color = 'var(--imp-' + token + ')';
    return '#' + getComputedStyle(probe).color.match(/\\d+/g)
      .map((channel) => Number(channel).toString(16).padStart(2, '0')).join('');
  });
  probe.remove();
  return [root.dataset.appearance ?? null, getComputedStyle(root).getPropertyValue('--emacs-bg'),
          getComputedStyle(root).backgroundColor, colours];
})()")
        (prefer (lambda (browser scheme)
                  (imprimeur-test-cdp-call browser "Emulation.setEmulatedMedia"
                                           `(:features [(:name "prefers-color-scheme" :value ,scheme)])))))
    (cl-letf (((symbol-function 'imprimeur-palette) (lambda (_buffer) palette)))
      (imprimeur-page-test-with (buffer browser "doc.org" "* Heading\n#+begin_src python\n# TODO\n#+end_src\n")
        (funcall prefer browser "dark")
        (imprimeur-page-test-wait-shown browser 1)
        (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'light'")
        (should (equal (imprimeur-test-cdp-eval browser state) (vector "light" "" "rgb(245, 243, 236)" light)))
        ;; With no warning colour, an alert takes the base's error colour.
        (should (equal (imprimeur-test-cdp-eval browser "getComputedStyle(document.querySelector('main .al')).backgroundColor")
                       "rgb(179, 38, 30)"))
        (setq palette (list :appearance "dark" :css ":root {\n}\n"))
        (imprimeur-refresh-palette)
        (funcall prefer browser "light")
        (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'dark'")
        (should (equal (imprimeur-test-cdp-eval browser state) (vector "dark" "" "rgb(18, 18, 17)" dark)))
        ;; Before a palette arrives, the reader's preference chooses.
        (imprimeur-test-cdp-call browser "Network.setBlockedURLs" '(:urls ["*/.imprimeur/events"]))
        (imprimeur-test-cdp-navigate browser (imprimeur-url buffer))
        (imprimeur-test-wait-for
         (lambda () (seq-find (lambda (failure) (equal (plist-get failure :blockedReason) "inspector"))
                              (imprimeur-test-cdp-events-named browser "Network.loadingFailed"))))
        (should (equal (imprimeur-test-cdp-eval browser state) (vector nil "" "rgb(245, 243, 236)" light)))
        (funcall prefer browser "dark")
        (should (equal (imprimeur-test-cdp-eval browser state) (vector nil "" "rgb(18, 18, 17)" dark)))))))

(defun imprimeur-page-test-as-fresh (buffer browser revision)
  "Check that BROWSER's page holds what a fresh load of it shows.
The page is BUFFER's, at REVISION."
  (let* ((main "document.getElementById('imprimeur-main').innerHTML")
         (html (imprimeur-test-cdp-eval browser main)))
    (imprimeur-test-cdp-navigate browser (imprimeur-url buffer))
    (imprimeur-page-test-wait-shown browser revision)
    (should (equal (imprimeur-test-cdp-eval browser main) html))))

(defun imprimeur-page-test-make-clip (buffer)
  "Make clip.webm, a video of 2 s, beside the file of BUFFER, with ffmpeg."
  (should (equal (car (repo-test-run "ffmpeg" '("-nostdin" "-loglevel" "error" "-f" "lavfi" "-i"
                                                "testsrc=duration=2:size=160x120:rate=10"
                                                "-c:v" "libvpx" "clip.webm")
                                     nil (file-name-directory (buffer-file-name buffer))))
                 0)))

(defun imprimeur-page-test-blocks (file text video)
  "Check that an edit replaces only the blocks it touched, in FILE.
FILE holds TEXT: a paragraph starting \"First paragraph.\", then one
starting \"Second\".  An edit appends VIDEO, a link to clip.webm, which
ffmpeg makes; then, once a property is set on the second paragraph
and the video is at 1 s, an edit lengthens the first paragraph."
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "ffmpeg")
  (imprimeur-page-test-with (buffer browser file text)
    (let ((main "document.getElementById('imprimeur-main')"))
      (imprimeur-page-test-wait-shown browser 1)
      (imprimeur-page-test-make-clip buffer)
      (with-current-buffer buffer (goto-char (point-max)) (insert video))
      (imprimeur-page-test-wait-shown browser 2)
      (imprimeur-test-cdp-wait browser "document.querySelector('main video').readyState >= HTMLMediaElement.HAVE_METADATA")
      (should (imprimeur-test-cdp-eval browser "document.querySelector('main video').duration > 1.5"))
      (should (equal (imprimeur-test-cdp-eval browser (format "(async () => {
  const main = %s;
  window.__removed = [];
  new MutationObserver((records) => records.forEach((record) => window.__removed.push(...record.removedNodes)))
    .observe(main, { childList: true, subtree: true });
  [...main.querySelectorAll('p')].find((p) => p.textContent.startsWith('Second')).__kept = 'kept';
  const video = main.querySelector('video');
  const seeked = new Promise((resolve) => video.addEventListener('seeked', resolve, { once: true }));
  video.currentTime = 1;
  await seeked;
  return video.currentTime;
})()" main))
                     1))
      (with-current-buffer buffer
        (goto-char (point-min))
        (search-forward "First paragraph.")
        (insert "\nMore of the first."))
      (imprimeur-page-test-wait-shown browser 3)
      (should (equal (imprimeur-test-cdp-eval browser (format "(() => {
  const main = %s;
  const second = [...main.querySelectorAll('p')].find((p) => p.textContent.startsWith('Second'));
  const video = main.querySelector('video');
  return [main.querySelector('p').textContent.replace(/\\s+/g, ' '), second.__kept ?? null, video.currentTime,
          window.__removed.filter((node) => node.contains(second) || node.contains(video)).length];
})()" main))
                     (vector "First paragraph. More of the first." "kept" 1 0)))
      (imprimeur-page-test-as-fresh buffer browser 3)
      (should (equal (imprimeur-test-cdp-eval browser "window.__violations") []))
      (should-not (imprimeur-test-cdp-errors browser)))))

(ert-deftest imprimeur-page-keeps-the-untouched-blocks-of-org ()
  (imprimeur-page-test-blocks
   "doc.org" "* Blocks\nFirst paragraph.\n\nSecond paragraph with ~code~.\n" "\n[[file:clip.webm]]\n"))

(ert-deftest imprimeur-page-keeps-the-untouched-blocks-of-markdown ()
  (imprimeur-page-test-blocks
   "doc.md" "# Blocks\n\nFirst paragraph.\n\nSecond paragraph with `code`.\n" "\n![clip](clip.webm)\n"))

(ert-deftest imprimeur-page-keeps-what-the-reader-opened ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.md" "First.\n\n<details><summary>More</summary>Hidden</details>\n")
    (imprimeur-page-test-wait-shown browser 1)
    (imprimeur-test-cdp-eval browser "document.querySelector('main details').open = true")
    (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
    (imprimeur-page-test-wait-shown browser 2)
    (should (imprimeur-test-cdp-eval browser "document.querySelector('main details').open"))
    (should (imprimeur-test-cdp-eval browser "document.querySelector('main p').textContent === 'Above.'"))))

(ert-deftest imprimeur-page-moves-the-data-pos-of-a-kept-block ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.md" "First.\n\nSecond with `code`.\n")
    ;; The mark on the block that holds the code, then the line that the
    ;; data-pos of the block and of the code each start at.
    (let ((state "(() => {
  const code = document.querySelector('main code');
  const block = code.closest('#imprimeur-main > *');
  return [block.__kept ?? null, ...[block, code].map((element) => element.dataset.pos.match(/(\\d+):\\d+-/)[1])];
})()"))
      (imprimeur-page-test-wait-shown browser 1)
      (should (equal (imprimeur-test-cdp-eval browser state) [nil "3" "3"]))
      (imprimeur-test-cdp-eval browser "document.querySelector('main code').closest('#imprimeur-main > *').__kept = 'kept'")
      (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
      (imprimeur-page-test-wait-shown browser 2)
      (should (equal (imprimeur-test-cdp-eval browser state) ["kept" "5" "5"])))))

(ert-deftest imprimeur-page-shows-an-edit-of-the-markup-alone ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.md" "[One](x.md)\n\n*Two*\n\n# Three\n")
    (let ((revision 1))
      (imprimeur-page-test-wait-shown browser revision)
      ;; The words stay the same: each new text, with the link's address and
      ;; the elements that hold the emphasis and the heading.
      (pcase-dolist (`(,text . ,markup)
                     '(("[One](y.md)\n\n*Two*\n\n# Three\n" . ["y.md" "em" "h1"])
                       ("[One](y.md)\n\n**Two**\n\n# Three\n" . ["y.md" "strong" "h1"])
                       ("[One](y.md)\n\n**Two**\n\n## Three\n" . ["y.md" "strong" "h2"])))
        (with-current-buffer buffer (erase-buffer) (insert text))
        (setq revision (1+ revision))
        (imprimeur-page-test-wait-shown browser revision)
        (should (equal (imprimeur-test-cdp-eval browser "[document.querySelector('main a').getAttribute('href'),
document.querySelector('main em, main strong').localName, document.querySelector('main h1, main h2').localName]")
                       markup))))))

(ert-deftest imprimeur-page-tries-again-what-failed-to-load ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "ffmpeg")
  (imprimeur-page-test-with (buffer browser "doc.md"
                                    (concat "One\n\n![late](late.svg)\n\n![clip](clip.webm)\n\n"
                                            "<video><source src=\"clip.webm\"></video>\n\nTwo\n"))
    (let ((one "[...document.querySelectorAll('main p')].find((p) => p.textContent === 'One')"))
      (imprimeur-page-test-wait-shown browser 1)
      (imprimeur-test-cdp-wait browser "(() => {
  const picture = document.querySelector('main img');
  const [plain, listed] = document.querySelectorAll('main video');
  return picture.complete && picture.naturalWidth === 0 && plain.error !== null
    && listed.networkState === HTMLMediaElement.NETWORK_NO_SOURCE;
})()")
      (imprimeur-test-cdp-eval browser (concat one ".__kept = 'kept'"))
      (with-temp-file (expand-file-name "late.svg" (file-name-directory (buffer-file-name buffer)))
        (insert "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"2\" height=\"1\"></svg>\n"))
      (imprimeur-page-test-make-clip buffer)
      (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
      (imprimeur-page-test-wait-shown browser 2)
      (imprimeur-test-cdp-wait browser "document.querySelector('main img').naturalWidth === 2
&& [...document.querySelectorAll('main video')]
     .every((video) => video.readyState >= HTMLMediaElement.HAVE_METADATA)")
      ;; Only the blocks that failed are made anew.
      (should (equal (imprimeur-test-cdp-eval browser (concat one ".__kept")) "kept")))))

(ert-deftest imprimeur-page-keeps-a-video-with-a-failed-part ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "ffmpeg")
  (imprimeur-page-test-with (buffer browser "doc.md" "First.\n")
    (imprimeur-page-test-wait-shown browser 1)
    (imprimeur-page-test-make-clip buffer)
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert "\n<video><source src=\"missing.webm\"><source src=\"clip.webm\">"
              "<track default src=\"missing.vtt\"></video>\n"))
    (imprimeur-page-test-wait-shown browser 2)
    (imprimeur-test-cdp-wait browser "document.querySelector('main video').readyState >= HTMLMediaElement.HAVE_METADATA
&& document.querySelector('main track').readyState === HTMLTrackElement.ERROR")
    (imprimeur-test-cdp-eval browser "document.querySelector('main video').__kept = 'kept'")
    (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
    (imprimeur-page-test-wait-shown browser 3)
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('main video').__kept") "kept"))))

(ert-deftest imprimeur-page-applies-each-kind-of-edit-in-place ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.md" "One\n\nTwo\n\nThree\n\nFour\n")
    (let ((revision 1))
      (imprimeur-page-test-wait-shown browser revision)
      ;; Each new text, with its paragraphs and whether each one's node was
      ;; there before.
      (pcase-dolist (`(,text . ,paragraphs)
                     '(("One\n\nThree\n\nFour\n" . [["One" t] ["Three" t] ["Four" t]])
                       ("Four\n\nOne\n\nThree\n" . [["Four" nil] ["One" t] ["Three" t]])
                       ("Four\n\nFour\n\nOne\n\nFive\n\nThree\n"
                        . [["Four" t] ["Four" nil] ["One" t] ["Five" nil] ["Three" t]])
                       ("" . [])
                       ("<p data-pos=\"own\">Raw</p>\n" . [["Raw" nil]])
                       ("Six\n\n<p>Raw</p>\n" . [["Six" nil] ["Raw" t]])))
        (imprimeur-test-cdp-eval browser "document.querySelectorAll('main p').forEach((p) => { p.__shown = true; })")
        (with-current-buffer buffer (erase-buffer) (insert text))
        (setq revision (1+ revision))
        (imprimeur-page-test-wait-shown browser revision)
        (should (equal (imprimeur-test-cdp-eval
                        browser "[...document.querySelectorAll('main p')].map((p) => [p.textContent, p.__shown === true])")
                       paragraphs)))
      (imprimeur-page-test-as-fresh buffer browser revision))
    (should-not (imprimeur-test-cdp-errors browser))))

;;; imprimeur-page-test.el ends here
