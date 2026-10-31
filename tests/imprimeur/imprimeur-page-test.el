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
;; each Minitel colour is the palette's, the background and the code's
;; background --emacs-bg, the foreground --emacs-fg, the muted text and the
;; rules --emacs-muted, links --emacs-link, and the code's keywords,
;; strings, comments, constants, functions and types --emacs-kw, -str,
;; -com, -const, -fn and -type; where the palette gives no colour,
;; Minitel's own light or dark one stands in, chosen by the palette's
;; appearance whatever the reader prefers, or by prefers-color-scheme
;; before a palette arrives.  Acceptance 5: in Minitel, h1 to h6, p, li,
;; pre and code share one font list, the default face's family then
;; monospace, which stands in for a family the browser lacks, and one size;
;; the headings' colours are --emacs-h1 to --emacs-h6, the first level's as
;; its chip's background, and a keyword's the keyword colour.

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
The document starts as CLEAN, then an edit appends HOSTILE, then the
page is loaded again."
  (imprimeur-page-test-with (buffer browser (concat "doc." format) clean)
    (let ((url (imprimeur-url buffer))
          (run "[...document.querySelectorAll('main a')].find((a) => a.textContent === 'run')"))
      (imprimeur-page-test-wait-shown browser 1)
      (with-current-buffer buffer (goto-char (point-max)) (insert hostile))
      (imprimeur-page-test-wait-shown browser 2)
      (should (imprimeur-test-cdp-eval browser "document.querySelector('main').textContent.includes('Hostile end')"))
      (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-inspect) (vector [] "undefined" url url)))
      (imprimeur-test-cdp-click browser run)
      (accept-process-output nil 0.5)
      (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-inspect) (vector [] "undefined" url url)))
      (imprimeur-test-cdp-navigate browser url)
      (imprimeur-page-test-wait-shown browser 2)
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
  (let ((palette (list :appearance "dark" :css ":root {
  --emacs-bg: #000001; --emacs-fg: #000002; --emacs-muted: #000003; --emacs-link: #000004;
  --emacs-kw: #000005; --emacs-str: #000006; --emacs-com: #000007; --emacs-const: #000008;
  --emacs-fn: #000009; --emacs-type: #00000a;
}\n")))
    (cl-letf (((symbol-function 'imprimeur-palette) (lambda (_buffer) palette)))
      (imprimeur-page-test-with (buffer browser "doc.org" "* Heading\n")
        (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'dark'")
        (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const style = getComputedStyle(document.documentElement);
  return ['background', 'foreground', 'muted', 'link', 'rule', 'code-background', 'keyword', 'string',
          'comment', 'constant', 'function', 'type']
    .map((token) => [token, style.getPropertyValue('--imp-' + token)]);
})()")
                       [["background" "#000001"] ["foreground" "#000002"] ["muted" "#000003"]
                        ["link" "#000004"] ["rule" "#000003"] ["code-background" "#000001"]
                        ["keyword" "#000005"] ["string" "#000006"] ["comment" "#000007"]
                        ["constant" "#000008"] ["function" "#000009"] ["type" "#00000a"]]))))))

(ert-deftest imprimeur-page-sets-minitel-in-the-emacs-family-and-colours ()
  (imprimeur-test-require "pandoc")
  (require 'org)
  (mapc #'enable-theme '(imprimeur-test-day imprimeur-test-mono))
  (unwind-protect
      (imprimeur-page-test-with (buffer browser "doc.org"
                                        (concat "* One\n** Two\n*** Three\n**** Four\n***** Five\n"
                                                "****** Six\nA paragraph with ~code~.\n\n- an item\n\n"
                                                "#+begin_src python\ndef f():\n    return 1\n#+end_src\n"))
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

(ert-deftest imprimeur-page-falls-back-on-minitel-colours ()
  (imprimeur-test-require "pandoc")
  ;; With no theme enabled, the faces of batch Emacs give no colour.
  (let ((imprimeur-appearance 'light)
        (state "[document.documentElement.dataset.appearance ?? null,
getComputedStyle(document.documentElement).getPropertyValue('--emacs-bg'),
getComputedStyle(document.documentElement).backgroundColor]")
        (prefer (lambda (browser scheme)
                  (imprimeur-test-cdp-call browser "Emulation.setEmulatedMedia"
                                           `(:features [(:name "prefers-color-scheme" :value ,scheme)])))))
    (imprimeur-page-test-with (buffer browser "doc.org" "* Heading\n")
      (funcall prefer browser "dark")
      (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'light'")
      (should (equal (imprimeur-test-cdp-eval browser state) ["light" "" "rgb(245, 243, 236)"]))
      (setq imprimeur-appearance 'dark)
      (imprimeur-refresh-palette)
      (funcall prefer browser "light")
      (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'dark'")
      (should (equal (imprimeur-test-cdp-eval browser state) ["dark" "" "rgb(18, 18, 17)"]))
      ;; Before a palette arrives, the reader's preference chooses.
      (imprimeur-test-cdp-call browser "Network.setBlockedURLs" '(:urls ["*/.imprimeur/events"]))
      (imprimeur-test-cdp-navigate browser (imprimeur-url buffer))
      (imprimeur-test-wait-for
       (lambda () (seq-find (lambda (failure) (equal (plist-get failure :blockedReason) "inspector"))
                            (imprimeur-test-cdp-events-named browser "Network.loadingFailed"))))
      (should (equal (imprimeur-test-cdp-eval browser state) [nil "" "rgb(245, 243, 236)"]))
      (funcall prefer browser "dark")
      (should (equal (imprimeur-test-cdp-eval browser state) [nil "" "rgb(18, 18, 17)"])))))

;;; imprimeur-page-test.el ends here
