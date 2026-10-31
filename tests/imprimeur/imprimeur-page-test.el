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
;; Emacs gives the page the new palette, in its one style element, and the
;; new data-appearance, with no navigation: the location and a property
;; set on window survive, and there is no console error and no policy
;; violation.

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
          window.__kept ?? null, location.href, document.querySelectorAll('style').length,
          document.head.contains(document.getElementById('imprimeur-palette'))];
})()"))
          (imprimeur-page-test-wait-shown browser 1)
          (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'dark'")
          (imprimeur-test-cdp-eval browser "window.__kept = 'kept'")
          (should (equal (imprimeur-test-cdp-eval browser state) (vector "dark" "#1d1f21" "kept" url 1 t)))
          (disable-theme 'imprimeur-test-night)
          (enable-theme 'imprimeur-test-day)
          (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'light'")
          (should (equal (imprimeur-test-cdp-eval browser state) (vector "light" "#ffffff" "kept" url 1 t)))
          (should (equal (imprimeur-test-cdp-eval browser "window.__violations") []))
          (should-not (imprimeur-test-cdp-errors browser))
          (should-not (imprimeur-test-cdp-escaped browser))))
    (mapc #'disable-theme '(imprimeur-test-night imprimeur-test-day))))

;;; imprimeur-page-test.el ends here
