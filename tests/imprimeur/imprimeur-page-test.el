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
;; click or from an image map reaches Emacs or nothing, opening no new page
;; and changing no location.  Headless Chromium never navigates on a
;; dropped link, so the page's guard against drops is checked by hand.
;;
;; Plan 003, acceptance 3 and "Palette to the page": a change of theme in
;; Emacs gives the page the new palette in place of the last, in its one
;; style element, the new background and the new data-appearance, with no
;; navigation: the location and a property set on JavaScript's window survive,
;; and there is no console error and no policy violation.  "Minitel on the palette":
;; each Minitel colour is the palette's, the background --emacs-bg, the
;; code panes' --emacs-code-bg, the foreground --emacs-fg, the muted text
;; and the rules --emacs-muted, links --emacs-link, and the code's
;; keywords, strings, comments, constants, functions and types --emacs-kw,
;; -str, -com, -const, -fn and -type, and the background of its alerts
;; --emacs-warn, like its error colour; where the palette gives no colour,
;; Minitel's own light or dark one stands in, a code pane's even when the
;; palette gives a background, chosen by the palette's appearance whatever the
;; reader prefers, or by prefers-color-scheme before a palette arrives, and
;; an alert takes the error colour.  Acceptance 5: in Minitel, in an
;; Org document as in a Markdown one, h1 to h6, p, li, pre and code share
;; one font list, the default face's family then monospace, which stands in
;; for a family the browser lacks, and one size; the headings' colours are
;; --emacs-h1 to --emacs-h6, the first level's as its chip's background,
;; and a keyword's the keyword colour.
;;
;; Reconnection: when Emacs drops a session's event streams, the browser's
;; EventSource connects again by itself and the page catches up where it is.
;; An edit made while it was away shows; a property set on JavaScript's window
;; and on an untouched node stays; the page keeps one palette style element and
;; its data-appearance; and no banner appears at any moment, since a stream that
;; connects again is no connection lost.
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
;; the page ends as a fresh load shows it, even when a block that stays
;; loses a data-pos of its own.  One edit that changes all the blocks around
;; one keeps it, though the white space between them outnumbers it.  A block
;; changed since it was shown, details that the reader opened, is still the
;; block that the document holds, and stays as it is.  A picture or a video
;; that failed to load is tried again at the next edit, which keeps the
;; blocks around it; a video that plays stays, though a track or a source
;; with another after it failed.  An edit of a block's markup alone, its
;; words unchanged, shows as any other.
;;
;; Acceptance 3 and "Mermaid": the script is requested through its versioned
;; asset, never without a diagram and once for two or more, and runs under
;; the page's policy with no violation and no console error; it is not
;; requested when the shell says that there is none, and a diagram then stays
;; code.  A failed load leaves the code, the message beneath it and no script
;; element, throws nothing, and is tried again at the next edit.  The option's
;; file may set no global or may fail once it has: it is run once, whatever the
;; edits that follow, the code stays, and the message says why.  A drawing keeps
;; its SVG node across an unrelated edit, in
;; an Org document as in a Markdown one, and draws nothing; elements beside a
;; drawing take the new data-pos, and the drawing holds none.  A palette change
;; draws again in the new colours, even within one appearance, a node in
;; --emacs-bg and its text in --emacs-fg, a note likewise, with --emacs-muted for
;; its rule, and the slices of a pie in the colours of code, with Mermaid's
;; darkMode following the appearance, keeping the element of the diagram and
;; leaving the page in place; a palette that comes back, like a source that comes
;; back or a second diagram with the same source, draws nothing.  A drawing is in
;; the page's font, and a palette that changes the font alone draws it again in
;; the new one; one pass of drawing runs at a time, and waits 20 s for each
;; diagram, past which that diagram says so beneath it and the next is drawn,
;; with 20 s of its own, and nothing is thrown.  A parse error keeps
;; the previous drawing with the message as text beneath it, until a good source
;; replaces both, each diagram its own when one edit breaks several; without a
;; previous drawing the code stays, and Mermaid leaves nothing of its own in the
;; page.  A new diagram has the drawing of one gone only when one edit took away
;; as many as it brought: with more gone, or more new, each shows its code.
;; A document that names the id of a drawing, whose element Mermaid removes,
;; does not stop the next edit from showing.
;;
;; Acceptance 4 and "Mermaid": in an Org document as in a Markdown one, hostile
;; diagrams, a directive or a front matter asking for securityLevel: loose, a
;; themeCSS with @import or any other locked key, a label with <img onerror>,
;; a click to javascript: and to _blank, a style that tries to leave its rule,
;; a picture elsewhere, a meta refresh beside maths, which Mermaid puts in the
;; live page while it draws, execute nothing, navigate nowhere, fetch nothing off
;; the loopback address and leave no script, frame, HTML, handler, target or
;; javascript: address in main; a link in a drawing reaches Emacs or nothing,
;; and opens no new page.  A directive changes nothing of a drawing, and Mermaid's
;; site configuration holds the plan's settings and secure list, with
;; dompurifyConfig too, so that no document can loosen its sanitiser.  What Mermaid
;; returns is itself sanitised to SVG, keeping its style element; when nothing
;; of it is SVG, or Mermaid fails, the diagram says so as text.
;;
;; "Mermaid" keeps a drawing to SVG, which drops any label that Mermaid puts in
;; a foreignObject, as a journey's section titles, maths and the text of an event
;; model or a Venn set: the reader is told beneath that drawing, and beneath no
;; other kind of diagram, whose labels all show.  The message beneath a diagram
;; can be read: on its pane it has a contrast of 4.5:1 at least, with the theme's
;; warning colour as with Minitel's own, and it wraps within the pane.
;;
;; "Video": a video that cannot play, in an Org document as in a Markdown one,
;; whether its own address, its last source, a source of a type that the browser
;; refuses unread or a frame past its metadata fails, has right after it one
;; link, "Open externally", to the address that failed.
;; The next edit makes its block anew, so it still has one link, and none once
;; the file plays.  A valid WebM made by ffmpeg has no link, nor a picture that
;; failed, nor a video that plays after a failed source or track.  Following the
;; link visits the file by its true name in Emacs and browses an address
;; elsewhere, leaving the page in place; a link to a missing file visits nothing.
;; A video that names no address has no link, white space being no address, nor
;; has one whose address DOMPurify would take from a document's own link, a data:
;; one, and markup in an address stays in the address: the link holds its text
;; alone.  An address that the page's policy blocks has a link, in a video's src
;; as in a source, and none of this depends on which of DOMPurify's policies ran
;; last.  A video in a container that the server does not serve has the link
;; too, which visits the file.  A sound that failed has no link, by its own address or a
;; source, nor has a picture in a video's fallback content, and neither makes the
;; page throw; a document's own link right after a failed video stays after the
;; page's.  A link that Emacs follows nowhere, to a missing file or of another
;; scheme, says so in Emacs, where a link followed leaves no such message,
;; without naming the session's token.
;;
;; "Tables and maths": in an Org document as in a Markdown one, a table too wide
;; for the page scrolls by itself, and the page does not; a long address or long
;; code in a cell breaks where it must, so that its table fits; cells are aligned
;; to the top, and a header without an alignment of its own starts where its text
;; does, while one with an alignment keeps it.  Maths names fonts made for it, in
;; the plan's order, a little larger than the text around it, and tall brackets
;; stretch around a matrix.  Here, the browser's generic family would find the only
;; maths font too, so the names are what shows that the rule is there: with a
;; plain font first on a machine, brackets stay a line tall without them.
;;
;; Plan 004, "data-line": each block of main carries as data-line the line
;; that it starts at in the source, in Markdown from its data-pos, and a table
;; has its first line, whatever the order of its data-pos.  An edit above
;; replaces no block and moves each line on, so that the page holds what a fresh
;; load shows; a block whose only change is a data-line in it stays, and takes the
;; new one.

;;; Code:

(require 'ert)
(require 'ert-x)
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

(ert-deftest imprimeur-page-catches-up-after-its-event-stream-drops ()
  (imprimeur-test-require "pandoc")
  (enable-theme 'imprimeur-test-night)
  (unwind-protect
      (imprimeur-page-test-with (buffer browser "doc.md" "First.\n\nSecond.\n")
        (let ((session (buffer-local-value 'imprimeur--session buffer))
              (url (imprimeur-url buffer))
              (live (lambda (session) (seq-filter #'process-live-p (imprimeur--session-clients session)))))
          (imprimeur-page-test-wait-shown browser 1)
          (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'dark'")
          ;; The marks, and a record of whatever the banner ever says.
          (imprimeur-test-cdp-eval browser "(() => {
  const banner = document.getElementById('imprimeur-banner');
  window.__kept = 'kept';
  window.__banners = [];
  new MutationObserver(() => window.__banners.push(banner.textContent))
    .observe(banner, { childList: true, characterData: true, subtree: true });
  document.querySelectorAll('main p')[1].__kept = 'kept';
})()")
          (mapc #'delete-process (imprimeur--session-clients session))
          (should-not (funcall live session))
          (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
          ;; The browser waits a few seconds before it connects again.
          (imprimeur-test-wait-for (lambda () (funcall live session)) 15)
          (imprimeur-page-test-wait-shown browser 2)
          (should (= (imprimeur-page-test-requests browser "/\\.imprimeur/events\\'") 2))
          (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const banner = document.getElementById('imprimeur-banner');
  return [window.__kept ?? null, location.href,
          [...document.querySelectorAll('main p')].map((p) => [p.textContent, p.__kept ?? null]),
          banner.hidden, window.__banners, document.documentElement.dataset.appearance,
          document.querySelectorAll('style').length, document.querySelectorAll('style#imprimeur-palette').length];
})()")
                         (vector "kept" url [["Above." nil] ["First." nil] ["Second." "kept"]] t [] "dark" 1 1)))
          (should-not (imprimeur-test-cdp-errors browser))))
    (disable-theme 'imprimeur-test-night)))

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
          'comment', 'constant', 'function', 'type', 'error']
    .map((token) => [token, style.getPropertyValue('--imp-' + token)]);
})()")
                       [["background" "#000001"] ["foreground" "#000002"] ["muted" "#000003"]
                        ["link" "#000004"] ["rule" "#000003"] ["code-background" "#00000c"]
                        ["keyword" "#000005"] ["string" "#000006"] ["comment" "#000007"]
                        ["constant" "#000008"] ["function" "#000009"] ["type" "#00000a"]
                        ["error" "#00000b"]]))
        ;; Without a colour of its own, a pane takes Minitel's, not the background.
        (setq palette (list :appearance "dark" :css (string-replace "  --emacs-code-bg: #00000c;\n" "" css)))
        (imprimeur-refresh-palette)
        (imprimeur-test-cdp-wait
         browser "getComputedStyle(document.documentElement).getPropertyValue('--emacs-code-bg') === ''")
        (should (equal (imprimeur-test-cdp-eval browser pane) "rgb(28, 28, 26)"))))))

(defun imprimeur-page-test-minitel (file text headings)
  "Check that Minitel sets TEXT, held in FILE, in Emacs's family and colours.
TEXT holds headings of the six levels, a paragraph with inline code, a
list item and a block of Python.  HEADINGS is the vector of the colours
that the day theme gives those levels, with Org loaded, in the major
mode of FILE's buffer."
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
                       (vector [] [["Imprimeur Test Mono" "monospace"]] 1 headings "rgb(137, 89, 168)")))
        (should (equal (imprimeur-test-cdp-eval browser "window.__violations") []))
        (should-not (imprimeur-test-cdp-errors browser)))
    (mapc #'disable-theme '(imprimeur-test-day imprimeur-test-mono))))

(ert-deftest imprimeur-page-sets-org-in-the-emacs-family-and-colours ()
  ;; An Org buffer reads `org-level-N' first.
  (imprimeur-page-test-minitel
   "doc.org" (concat "* One\n** Two\n*** Three\n**** Four\n***** Five\n"
                     "****** Six\nA paragraph with ~code~.\n\n- an item\n\n"
                     "#+begin_src python\ndef f():\n    return 1\n#+end_src\n")
   ["rgb(200, 40, 33)" "rgb(200, 40, 34)" "rgb(200, 40, 35)"
    "rgb(200, 40, 36)" "rgb(200, 40, 37)" "rgb(200, 40, 38)"]))

(ert-deftest imprimeur-page-sets-markdown-in-the-emacs-family-and-colours ()
  (imprimeur-page-test-minitel
   "doc.md" (concat "# One\n\n## Two\n\n### Three\n\n#### Four\n\n##### Five\n\n"
                    "###### Six\n\nA paragraph with `code`.\n\n- an item\n\n"
                    "```python\ndef f():\n    return 1\n```\n")
   ;; Any other buffer reads `org-level-N' last: markdown-mode's faces being no
   ;; faces here, `outline-N' gives these.
   ["rgb(245, 135, 17)" "rgb(245, 135, 18)" "rgb(245, 135, 19)"
    "rgb(245, 135, 20)" "rgb(245, 135, 21)" "rgb(245, 135, 22)"]))

(ert-deftest imprimeur-page-falls-back-on-minitel-colours ()
  (imprimeur-test-require "pandoc")
  ;; A palette with no colour: its appearance alone chooses between
  ;; Minitel's own colours.
  (let ((palette (list :appearance "light" :css ":root {\n}\n"))
        ;; Minitel's own colours, its two lists before plan 003: background,
        ;; foreground, muted, link, rule, code background, keyword, string,
        ;; comment, constant, function and type; then its error colour.
        (light ["#f5f3ec" "#1c1c1a" "#6b6a63" "#1f4fa3" "#8f8d84" "#ebe8de"
                "#8b2f97" "#2f6b1f" "#6b6a63" "#a3501f" "#1f4fa3" "#7a5c00" "#b3261e"])
        (dark ["#121211" "#e6e4dc" "#9a988f" "#8cb4ff" "#5d5b55" "#1c1c1a"
               "#d79ae0" "#9fd38a" "#9a988f" "#f0a36e" "#8cb4ff" "#e3c46a" "#ffb4ab"])
        (state "(() => {
  const root = document.documentElement;
  const probe = document.body.appendChild(document.createElement('span'));
  const colours = ['background', 'foreground', 'muted', 'link', 'rule', 'code-background', 'keyword',
                   'string', 'comment', 'constant', 'function', 'type', 'error'].map((token) => {
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
        ;; With no warning colour, an alert takes Minitel's error colour.
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

(defconst imprimeur-page-test-video-link
  "[...document.querySelectorAll('main a')].filter((a) => a.textContent === 'Open externally')"
  "JavaScript giving the links that the page offers for videos that failed.")

(defun imprimeur-page-test-video-links (browser &optional count)
  "Return the links that BROWSER's page offers for videos that failed.
Wait for COUNT of them, then for a moment in which any other would come.
Each link is [BEFORE ADDRESS ELEMENTS]: the name of the element right
before it, its address relative to the page's directory, and the number
of elements it holds."
  (imprimeur-test-cdp-wait browser (format "%s.length >= %d" imprimeur-page-test-video-link (or count 0)))
  (accept-process-output nil 0.5)
  (imprimeur-test-cdp-eval
   browser (format "%s.map((a) => [a.previousElementSibling?.localName ?? null,
  a.href.replace(new URL('.', document.baseURI).href, ''), a.childElementCount])"
                   imprimeur-page-test-video-link)))

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
      (should (equal (imprimeur-page-test-video-links browser) []))
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
      ;; Each video offers its address, the picture nothing; the file being
      ;; missing, Emacs has nothing to visit.
      (should (equal (imprimeur-page-test-video-links browser 2)
                     [["video" "clip.webm" 0] ["video" "clip.webm" 0]]))
      (imprimeur-test-cdp-click browser (concat imprimeur-page-test-video-link "[0]"))
      (accept-process-output nil 0.5)
      (should-not imprimeur-page-test-followed)
      (imprimeur-test-cdp-eval browser (concat one ".__kept = 'kept'"))
      (with-temp-file (expand-file-name "late.svg" (file-name-directory (buffer-file-name buffer)))
        (insert "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"2\" height=\"1\"></svg>\n"))
      (imprimeur-page-test-make-clip buffer)
      (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
      (imprimeur-page-test-wait-shown browser 2)
      (imprimeur-test-cdp-wait browser "document.querySelector('main img').naturalWidth === 2
&& [...document.querySelectorAll('main video')]
     .every((video) => video.readyState >= HTMLMediaElement.HAVE_METADATA)")
      (should (equal (imprimeur-page-test-video-links browser) []))
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
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('main video').__kept") "kept"))
    (should (equal (imprimeur-page-test-video-links browser) []))))

(defun imprimeur-page-test-offers (file text videos links)
  "Check the links that videos of invalid bytes get, in FILE.
FILE holds TEXT; an edit appends VIDEOS, which name bad.webm first and
may name worse.webm, two files of invalid bytes.  LINKS is what
`imprimeur-page-test-video-links' then gives, before and after an edit
above them, once the videos made anew by that edit have failed in turn.
The first link is then followed."
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser file text)
    (let ((directory (file-name-directory (buffer-file-name buffer)))
          (url (imprimeur-url buffer))
          (pages (imprimeur-test-cdp-pages browser)))
      (imprimeur-page-test-wait-shown browser 1)
      (dolist (name '("bad.webm" "worse.webm"))
        (with-temp-file (expand-file-name name directory) (insert "These bytes are no video.\n")))
      (with-current-buffer buffer (goto-char (point-max)) (insert videos))
      (imprimeur-page-test-wait-shown browser 2)
      (should (equal (imprimeur-page-test-video-links browser (length links)) links))
      (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
      (imprimeur-page-test-wait-shown browser 3)
      (should (equal (imprimeur-page-test-video-links browser (length links)) links))
      (imprimeur-test-cdp-click browser (concat imprimeur-page-test-video-link "[0]"))
      (imprimeur-test-wait-for (lambda () imprimeur-page-test-followed))
      (should (equal imprimeur-page-test-followed
                     `((visit ,(file-truename (expand-file-name "bad.webm" directory))))))
      (should (equal (imprimeur-test-cdp-eval browser "location.href") url))
      (should (= (imprimeur-test-cdp-pages browser) pages))
      (should (equal (imprimeur-test-cdp-eval browser "window.__violations") []))
      (should-not (imprimeur-test-cdp-errors browser)))))

(ert-deftest imprimeur-page-offers-a-video-it-cannot-decode-in-org ()
  (imprimeur-page-test-offers "doc.org" "* Video\nFirst.\n" "\n[[file:bad.webm]]\n" [["video" "bad.webm" 0]]))

(ert-deftest imprimeur-page-offers-a-video-it-cannot-decode-in-markdown ()
  (imprimeur-page-test-offers "doc.md" "# Video\n\nFirst.\n" "\n![bad](bad.webm)\n" [["video" "bad.webm" 0]]))

(ert-deftest imprimeur-page-offers-each-top-level-video-its-last-source ()
  (imprimeur-page-test-offers
   "doc.org" "First.\n"
   (concat "\n#+begin_export html\n<video src=\"bad.webm\"></video>\n"
           "<video><source src=\"bad.webm\"><source src=\"worse.webm\"></video>\n"
           "<video><source src=\"worse.webm\" type=\"video/x-no-such-type\"></video>\n#+end_export\n")
   [["video" "bad.webm" 0] ["video" "worse.webm" 0] ["video" "worse.webm" 0]]))

(ert-deftest imprimeur-page-offers-a-video-that-the-server-does-not-serve ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.md" "First.\n")
    (let ((talk (expand-file-name "talk.mkv" (file-name-directory (buffer-file-name buffer)))))
      (imprimeur-page-test-wait-shown browser 1)
      (with-temp-file talk (insert "A film in a container that browsers leave alone.\n"))
      (with-current-buffer buffer (goto-char (point-max)) (insert "\n![talk](talk.mkv)\n"))
      (imprimeur-page-test-wait-shown browser 2)
      (should (equal (imprimeur-page-test-video-links browser 1) [["video" "talk.mkv" 0]]))
      (imprimeur-test-cdp-click browser (concat imprimeur-page-test-video-link "[0]"))
      (imprimeur-test-wait-for (lambda () imprimeur-page-test-followed))
      (should (equal imprimeur-page-test-followed `((visit ,(file-truename talk))))))))

(ert-deftest imprimeur-page-offers-a-video-that-fails-after-its-metadata ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "ffmpeg")
  (imprimeur-page-test-with (buffer browser "doc.md" "First.\n")
    (let ((clip (expand-file-name "clip.webm" (file-name-directory (buffer-file-name buffer)))))
      (imprimeur-page-test-wait-shown browser 1)
      (imprimeur-page-test-make-clip buffer)
      ;; VP8's start code, in the clip's one key frame: the headers stay good.
      (with-temp-buffer
        (set-buffer-multibyte nil)
        (insert-file-contents-literally clip)
        (should (search-forward (unibyte-string #x9d #x01 #x2a) nil t))
        (replace-match (unibyte-string 0 0 0) t t)
        (let ((coding-system-for-write 'no-conversion))
          (write-region nil nil clip nil 'quiet)))
      (with-current-buffer buffer
        (goto-char (point-max))
        (insert "\n<video><source src=\"clip.webm\"></video>\n"))
      (imprimeur-page-test-wait-shown browser 2)
      (should (equal (imprimeur-page-test-video-links browser 1) [["video" "clip.webm" 0]]))
      (should (imprimeur-test-cdp-eval browser "(() => {
  const video = document.querySelector('main video');
  return video.duration > 1.5 && video.error.code === MediaError.MEDIA_ERR_DECODE;
})()"))
      (imprimeur-test-cdp-click browser (concat imprimeur-page-test-video-link "[0]"))
      (imprimeur-test-wait-for (lambda () imprimeur-page-test-followed))
      (should (equal imprimeur-page-test-followed `((visit ,(file-truename clip))))))))

(ert-deftest imprimeur-page-offers-a-link-for-a-video-alone ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.org" "First.\n")
    (imprimeur-page-test-wait-shown browser 1)
    (dolist (name '("bad.webm" "bad.ogg"))
      (with-temp-file (expand-file-name name (file-name-directory (buffer-file-name buffer)))
        (insert "These bytes are no video.\n")))
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert "\n#+begin_export html\n<audio src=\"bad.ogg\"></audio>\n"
              "<audio><source src=\"bad.ogg\"></audio>\n"
              "<video src=\"bad.webm\"></video><a href=\"other.md\">own</a>\n"
              "<video><img src=\"pic.png\"></video>\n#+end_export\n"))
    (imprimeur-page-test-wait-shown browser 2)
    (imprimeur-test-cdp-wait browser "(() => {
  const [plain, listed] = document.querySelectorAll('main audio');
  const picture = document.querySelector('main video img');
  return plain.error !== null && listed.networkState === HTMLMediaElement.NETWORK_NO_SOURCE
    && document.querySelector('main video').error !== null
    && picture.complete && picture.naturalWidth === 0;
})()")
    (should (equal (imprimeur-page-test-video-links browser 1) [["video" "bad.webm" 0]]))
    (should (equal (imprimeur-test-cdp-eval
                    browser (concat imprimeur-page-test-video-link "[0].nextElementSibling.textContent"))
                   "own"))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-page-says-when-a-link-leads-nowhere ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.md" "[there](other.md) [gone](gone.md) [phone](tel:123)\n")
    (imprimeur-page-test-wait-shown browser 1)
    (let ((token (imprimeur--session-token (buffer-local-value 'imprimeur--session buffer)))
          (nowhere "link leads to no"))
      (ert-with-message-capture said
        (imprimeur-test-cdp-click browser "document.querySelector('main a[href=\"other.md\"]')")
        (imprimeur-test-wait-for (lambda () imprimeur-page-test-followed))
        (should-not (string-search nowhere said))
        (dolist (href '("gone.md" "tel:123"))
          (setq said "")
          (imprimeur-test-cdp-click browser (format "document.querySelector('main a[href=\"%s\"]')" href))
          (imprimeur-test-wait-for (lambda () (string-search nowhere said)))
          (should-not (string-search token said)))
        (should (= (length imprimeur-page-test-followed) 1))))))

(ert-deftest imprimeur-page-keeps-the-links-of-failed-videos-plain ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.org"
                                    (concat "#+begin_export html\n"
                                            "<video><source src=\"https://example.invalid/far.webm\"></video>\n"
                                            "<video src=\"https://example.invalid/near.webm\"></video>\n"
                                            "<video src=\"x&quot;&gt;&lt;img src=y onerror=window.__pwned=1&gt;.webm\"></video>\n"
                                            "<video src=\"\"></video>\n<video><source></video>\n"
                                            "<video><source src=\"\"></video>\n"
                                            "<video src=\" \"></video>\n<video><source src=\" \"></video>\n"
                                            "<video src=\"data:video/webm;base64,AAAA\"></video>\n"
                                            "<video><source src=\"data:text/html,fallback\"></video>\n"
                                            "#+end_export\n"))
    (imprimeur-page-test-wait-shown browser 1)
    (imprimeur-test-cdp-wait browser "[...document.querySelectorAll('main video')].every(
  (video) => video.error !== null || video.networkState === HTMLMediaElement.NETWORK_NO_SOURCE)")
    (should (equal (imprimeur-page-test-video-links browser 3)
                   [["video" "https://example.invalid/far.webm" 0]
                    ["video" "https://example.invalid/near.webm" 0]
                    ["video" "x%22%3E%3Cimg%20src=y%20onerror=window.__pwned=1%3E.webm" 0]]))
    (should (equal (imprimeur-test-cdp-eval browser "[document.querySelector('main img'), typeof window.__pwned]")
                   [nil "undefined"]))
    (let ((url (imprimeur-url buffer)))
      (imprimeur-test-cdp-click browser (concat imprimeur-page-test-video-link "[0]"))
      (imprimeur-test-wait-for (lambda () imprimeur-page-test-followed))
      (should (equal imprimeur-page-test-followed '((browse "https://example.invalid/far.webm"))))
      (should (equal (imprimeur-test-cdp-eval browser "location.href") url))
      (should-not (imprimeur-test-cdp-escaped browser)))))

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
                       ("A\n\nB\n\nC\n\nV\n" . [["A" nil] ["B" nil] ["C" nil] ["V" nil]])
                       ("X\n\nV\n\nY\n\nZ\n" . [["X" nil] ["V" t] ["Y" nil] ["Z" nil]])
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

(defconst imprimeur-page-test-block-lines
  "[...document.getElementById('imprimeur-main').children]
.map((block) => [block.localName, block.getAttribute('data-line')])"
  "JavaScript giving each block of main as [ELEMENT LINE], its data-line.")

(ert-deftest imprimeur-page-gives-each-markdown-block-its-line ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with
      (buffer browser "doc.md"
              (concat "# Heading\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nA paragraph\non two lines.\n\n"
                      "- one\n- two\n\n```python\nprint(1)\n```\n"))
    (imprimeur-page-test-wait-shown browser 1)
    (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-block-lines)
                   [["h1" "1"] ["table" "3"] ["div" "7"] ["div" "10"] ["div" "13"]]))
    (should-not (imprimeur-test-cdp-errors browser))))

(defun imprimeur-page-test-lines-move (file text above lines)
  "Check that an edit above moves the lines of FILE and replaces no block.
FILE holds TEXT; the edit adds ABOVE at its start.  LINES is the
data-line of each block after it, a number, or nil for the block that
the edit makes."
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser file text)
    (imprimeur-page-test-wait-shown browser 1)
    (imprimeur-test-cdp-eval browser "(() => {
  const main = document.getElementById('imprimeur-main');
  window.__removed = [];
  new MutationObserver((records) => records.forEach((record) => window.__removed.push(...record.removedNodes)))
    .observe(main, { childList: true });
  for (const block of main.children) block.__kept = true;
})()")
    (with-current-buffer buffer (goto-char (point-min)) (insert above))
    (imprimeur-page-test-wait-shown browser 2)
    (should (equal (imprimeur-test-cdp-eval browser "[...document.getElementById('imprimeur-main').children]
.map((block) => [block.getAttribute('data-line'), block.__kept === true])")
                   (vconcat (mapcar (lambda (line)
                                      (vector (format "%d" (or line 1)) (and line t)))
                                    lines))))
    (should (equal (imprimeur-test-cdp-eval browser "window.__removed.filter((node) => node.nodeType === Node.ELEMENT_NODE).length")
                   0))
    (imprimeur-page-test-as-fresh buffer browser 2)
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-page-keeps-the-blocks-of-markdown-when-lines-move ()
  (imprimeur-page-test-lines-move
   "doc.md" "# Blocks\n\nFirst paragraph.\n\nSecond paragraph.\n\n| a |\n|---|\n| 1 |\n\n```python\nprint(1)\n```\n"
   "Above.\n\n" '(nil 3 5 7 9 13)))

(ert-deftest imprimeur-page-keeps-a-block-whose-data-line-alone-changes ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.md" "<p data-line=\"1\">Raw</p>\n")
    (let ((raw "document.querySelector('main p')"))
      (imprimeur-page-test-wait-shown browser 1)
      (imprimeur-test-cdp-eval browser (concat raw ".__kept = true"))
      (with-current-buffer buffer (erase-buffer) (insert "<p data-line=\"2\">Raw</p>\n"))
      (imprimeur-page-test-wait-shown browser 2)
      (should (equal (imprimeur-test-cdp-eval browser (format "[%1$s.__kept ?? null, %1$s.getAttribute('data-line')]" raw))
                     [t "2"]))
      (imprimeur-page-test-as-fresh buffer browser 2))))

(defun imprimeur-page-test-tables (file text)
  "Check that FILE, holding TEXT, keeps its tables to themselves.
TEXT holds a table with a long address and long code, then a table of
many columns of long words."
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser file text)
    (imprimeur-page-test-wait-shown browser 1)
    (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const main = document.querySelector('main');
  const [short, wide] = document.querySelectorAll('main table');
  const root = document.documentElement;
  const right = main.getBoundingClientRect().right;
  const cells = [...document.querySelectorAll('main th, main td')];
  return [root.scrollWidth <= root.clientWidth,
          short.getBoundingClientRect().right <= right,
          short.scrollWidth <= short.clientWidth,
          wide.getBoundingClientRect().right <= right,
          wide.scrollWidth > wide.clientWidth,
          getComputedStyle(wide).overflowX,
          [...new Set(cells.map((cell) => getComputedStyle(cell).verticalAlign))],
          [...new Set([...document.querySelectorAll('main th')]
                      .map((cell) => getComputedStyle(cell).textAlign))]];
})()")
                   [t t t t t "auto" ["top"] ["start"]]))
    (should-not (imprimeur-test-cdp-errors browser))))

(defconst imprimeur-page-test-long-address
  (concat "https://example.org/" (mapconcat #'number-to-string (number-sequence 1000 1200) "/"))
  "An address far wider than the page, with nowhere to break.")

(defconst imprimeur-page-test-long-word
  (make-string 40 ?w)
  "A word that no table of many columns can fit.")

(ert-deftest imprimeur-page-keeps-the-tables-of-org-to-themselves ()
  (imprimeur-page-test-tables
   "doc.org"
   (format "| Link | Code |\n|---+---|\n| [[%s][%s]] | ~%s~ |\n\nText.\n\n|%s\n|%s\n|%s\n"
           imprimeur-page-test-long-address imprimeur-page-test-long-address
           (make-string 300 ?c)
           (mapconcat (lambda (_) (concat imprimeur-page-test-long-word "|")) (number-sequence 1 12) "")
           (mapconcat (lambda (_) "---+") (number-sequence 1 12) "")
           (mapconcat (lambda (_) (concat imprimeur-page-test-long-word "|")) (number-sequence 1 12) ""))))

(ert-deftest imprimeur-page-keeps-the-tables-of-markdown-to-themselves ()
  (imprimeur-page-test-tables
   "doc.md"
   (format "| Link | Code |\n|---|---|\n| [%s](%s) | `%s` |\n\nText.\n\n|%s\n|%s\n|%s\n"
           imprimeur-page-test-long-address imprimeur-page-test-long-address
           (make-string 300 ?c)
           (mapconcat (lambda (_) (concat imprimeur-page-test-long-word "|")) (number-sequence 1 12) "")
           (mapconcat (lambda (_) "---|") (number-sequence 1 12) "")
           (mapconcat (lambda (_) (concat imprimeur-page-test-long-word "|")) (number-sequence 1 12) ""))))

(ert-deftest imprimeur-page-keeps-the-alignment-a-header-names ()
  (imprimeur-test-require "pandoc")
  (imprimeur-page-test-with (buffer browser "doc.md" "| A | B | C |\n|:-:|---|--:|\n| a | b | c |\n")
    (imprimeur-page-test-wait-shown browser 1)
    (should (equal (imprimeur-test-cdp-eval
                    browser "[...document.querySelectorAll('main th')].map((cell) => getComputedStyle(cell).textAlign)")
                   ["center" "start" "right"]))))

(ert-deftest imprimeur-page-stretches-brackets-around-a-matrix ()
  (imprimeur-test-require "pandoc")
  ;; Only the fonts of the development shell, whatever else this machine has.
  (let* ((configuration (make-temp-file
                         "fonts" nil ".conf"
                         (format "<fontconfig><dir>%s</dir><cachedir>%s</cachedir></fontconfig>\n"
                                 (getenv "IMPRIMEUR_TEST_FONTS") temporary-file-directory)))
         (process-environment (cons (concat "FONTCONFIG_FILE=" configuration) process-environment)))
    (imprimeur-page-test-with
        (buffer browser "doc.md"
                "Text $x$ here.\n\n$$\\left[\\begin{matrix} a \\\\ b \\\\ c \\end{matrix}\\right]$$\n")
      (imprimeur-page-test-wait-shown browser 1)
      (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const [inline, block] = document.querySelectorAll('main math');
  const row = block.querySelector('mtable').getBoundingClientRect().height;
  const bracket = block.querySelector('mo').getBoundingClientRect().height;
  const names = getComputedStyle(inline).fontFamily.split(',')
    .map((name) => name.trim().replace(/^\"(.*)\"$/, '$1'));
  return [names,
          bracket >= row * 0.9,
          parseFloat(getComputedStyle(inline).fontSize)
            > parseFloat(getComputedStyle(inline.closest('p')).fontSize)];
})()")
                     [["Latin Modern Math" "STIX Two Math" "Libertinus Math" "DejaVu Math TeX Gyre" "math"]
                      t t])))))

(defun imprimeur-page-test-requests (browser pattern)
  "Return the number of URLs matching PATTERN that BROWSER requested."
  (seq-count (lambda (params) (string-match-p pattern (plist-get (plist-get params :request) :url)))
             (imprimeur-test-cdp-events-named browser "Network.requestWillBeSent")))

(defconst imprimeur-page-test-mermaid-url "/\\.imprimeur/a/[0-9a-f]+/mermaid\\.js\\'"
  "The URL of the Mermaid script, a versioned asset of the session.")

(defun imprimeur-page-test-wait-drawn (browser count)
  "Wait until BROWSER's page holds COUNT drawn diagrams."
  (imprimeur-test-cdp-wait
   browser (format "document.querySelectorAll('main pre.mermaid > svg').length === %d" count) 30))

(defconst imprimeur-page-test-count-draws
  "(() => {
  const { render } = mermaid;
  window.__draws = 0;
  mermaid.render = (...args) => {
    window.__draws += 1;
    return render(...args);
  };
})()"
  "Make the page count in window.__draws what it asks Mermaid to draw.")

(defconst imprimeur-page-test-diagram "```mermaid\nflowchart TD\n  A[One] --> B[Two]\n```\n"
  "A diagram of Markdown, with a node named One and one named Two.")

(defun imprimeur-page-test-replace-text (buffer text)
  "Make TEXT the whole of BUFFER."
  (with-current-buffer buffer (erase-buffer) (insert text)))

(ert-deftest imprimeur-page-loads-mermaid-at-the-first-diagram ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.org" "* Plain\nNo diagram.\n")
    (imprimeur-page-test-wait-shown browser 1)
    (should (imprimeur-test-cdp-eval browser "document.documentElement.hasAttribute('data-mermaid')"))
    (with-current-buffer buffer (goto-char (point-max)) (insert "\nStill none.\n"))
    (imprimeur-page-test-wait-shown browser 2)
    (accept-process-output nil 0.5)
    (should (= (imprimeur-page-test-requests browser imprimeur-page-test-mermaid-url) 0))
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert "\n#+begin_src mermaid\nflowchart TD\n  A --> B\n#+end_src\n"
              "\n#+begin_src mermaid\nflowchart TD\n  C --> D\n#+end_src\n"))
    (imprimeur-page-test-wait-drawn browser 2)
    (should (= (imprimeur-page-test-requests browser imprimeur-page-test-mermaid-url) 1))
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert "\n#+begin_src mermaid\nflowchart TD\n  E --> F\n#+end_src\n"))
    (imprimeur-page-test-wait-drawn browser 3)
    (should (= (imprimeur-page-test-requests browser imprimeur-page-test-mermaid-url) 1))
    ;; The browser's memory cache would serve a second element unseen.
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('script[src$=\"/mermaid.js\"]').length") 1))
    (should (equal (imprimeur-test-cdp-eval browser "window.__violations") []))
    (should-not (imprimeur-test-cdp-errors browser))
    (should-not (imprimeur-test-cdp-escaped browser))))

(ert-deftest imprimeur-page-loads-mermaid-once-for-two-diagrams-on-first-load ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.md"
                                    (concat imprimeur-page-test-diagram "\n"
                                            "```mermaid\nflowchart TD\n  C --> D\n```\n"))
    (imprimeur-page-test-wait-drawn browser 2)
    (should (= (imprimeur-page-test-requests browser imprimeur-page-test-mermaid-url) 1))))

(ert-deftest imprimeur-page-shows-a-diagram-as-code-without-a-script ()
  (imprimeur-test-require "pandoc")
  (let ((imprimeur-mermaid-script (expand-file-name "missing.js" temporary-file-directory)))
    (imprimeur-page-test-with (buffer browser "doc.md" imprimeur-page-test-diagram)
      (imprimeur-page-test-wait-shown browser 1)
      (accept-process-output nil 0.5)
      (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const pre = document.querySelector('main pre.mermaid');
  return [document.documentElement.hasAttribute('data-mermaid'), pre.children.length, pre.firstElementChild.localName,
          pre.textContent.trim()];
})()")
                     (vector nil 1 "code" "flowchart TD\n  A[One] --> B[Two]")))
      (should (= (imprimeur-page-test-requests browser "mermaid\\.js") 0)))))

(defconst imprimeur-page-test-script-state
  "(() => {
  const pre = document.querySelector('main pre.mermaid');
  return [window.__runs ?? null, document.querySelectorAll('script[src$=\"/mermaid.js\"]').length,
          pre.firstElementChild.localName, pre.querySelector(':scope > .imprimeur-diagram-error')?.textContent ?? null];
})()"
  "What the Mermaid script has left on the page.
The value is [RUNS ELEMENTS FIRST MESSAGE]: how many times the script
counted itself, its script elements, the first element of the first
diagram and the message beneath that diagram.")

(ert-deftest imprimeur-page-tries-the-script-again-at-the-next-edit ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.md" "First.\n")
    (imprimeur-page-test-wait-shown browser 1)
    (imprimeur-test-cdp-call browser "Network.setBlockedURLs" '(:urls ["*/mermaid.js"]))
    (with-current-buffer buffer (goto-char (point-max)) (insert "\n" imprimeur-page-test-diagram))
    (imprimeur-page-test-wait-shown browser 2)
    (imprimeur-test-wait-for
     (lambda () (seq-find (lambda (failure) (equal (plist-get failure :blockedReason) "inspector"))
                          (imprimeur-test-cdp-events-named browser "Network.loadingFailed"))))
    (accept-process-output nil 0.5)
    (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-script-state)
                   (vector nil 0 "code" "The Mermaid script did not load.")))
    (should-not (imprimeur-test-cdp-events-named browser "Runtime.exceptionThrown"))
    (imprimeur-test-cdp-call browser "Network.setBlockedURLs" '(:urls []))
    (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
    (imprimeur-page-test-wait-drawn browser 1)
    (should (= (imprimeur-page-test-requests browser imprimeur-page-test-mermaid-url) 2))
    (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-script-state)
                   (vector nil 1 "svg" nil)))))

(ert-deftest imprimeur-page-keeps-the-code-with-a-script-that-draws-nothing ()
  (imprimeur-test-require "pandoc")
  (let ((counted "globalThis.__runs = (globalThis.__runs ?? 0) + 1;\n")
        (no-global "The Mermaid script sets no global mermaid."))
    ;; The file's text, its runs, the script elements left, the message beneath
    ;; the code, and the exceptions it threw, whatever the edits that follow.
    (pcase-dolist (`(,text ,runs ,elements ,message ,exceptions)
                   `((,counted 1 0 ,no-global 0)
                     ;; A module taken for a script, as mermaid.esm.min.mjs is.
                     ("import nothing from './nothing.mjs';\n" nil 0 ,no-global 1)
                     (,(concat counted "globalThis.mermaid = { mermaidAPI: { defaultConfig: { secure: [] } },
  initialize: () => { throw new Error('No Mermaid here.'); } };\n")
                      1 1 "No Mermaid here." 0)))
      (let ((imprimeur-mermaid-script (make-temp-file "script" nil ".js" text)))
        (imprimeur-page-test-with (buffer browser "doc.md" imprimeur-page-test-diagram)
          (imprimeur-page-test-wait-shown browser 1)
          (imprimeur-test-cdp-wait browser "!!document.querySelector('main pre.mermaid > .imprimeur-diagram-error')")
          (dotimes (edit 2)
            (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
            (imprimeur-page-test-wait-shown browser (+ edit 2))
            (accept-process-output nil 0.5))
          (should (equal (cons text (imprimeur-test-cdp-eval browser imprimeur-page-test-script-state))
                         (cons text (vector runs elements "code" message))))
          (should (= (length (imprimeur-test-cdp-events-named browser "Runtime.exceptionThrown"))
                     exceptions)))))))

(defun imprimeur-page-test-keeps-a-drawing (file text)
  "Check that an edit above the diagram of TEXT, held in FILE, keeps its drawing."
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser file text)
    (imprimeur-page-test-wait-drawn browser 1)
    (imprimeur-test-cdp-eval browser imprimeur-page-test-count-draws)
    (imprimeur-test-cdp-eval browser "document.querySelector('main pre.mermaid > svg').__kept = 'kept'")
    (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
    (imprimeur-page-test-wait-shown browser 2)
    (accept-process-output nil 0.5)
    (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const svgs = document.querySelectorAll('main pre.mermaid > svg');
  return [svgs.length, svgs[0].__kept ?? null, window.__draws, document.querySelector('main p').textContent];
})()")
                   (vector 1 "kept" 0 "Above.")))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-page-keeps-a-drawing-across-an-edit-in-org ()
  (imprimeur-page-test-keeps-a-drawing
   "doc.org" "#+begin_src mermaid\nflowchart TD\n  A --> B\n#+end_src\n"))

(ert-deftest imprimeur-page-keeps-a-drawing-across-an-edit-in-markdown ()
  (imprimeur-page-test-keeps-a-drawing "doc.md" imprimeur-page-test-diagram))

(ert-deftest imprimeur-page-moves-the-data-pos-around-a-drawing ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.md"
                                    "> ```mermaid\n> flowchart TD\n>   A --> B\n> ```\n>\n> After.\n")
    ;; The line each one starts at: the diagram, the element around the paragraph.
    (let ((state "(() => {
  const line = (element) => element.dataset.pos.match(/(\\d+):\\d+-/)[1];
  return [document.querySelector('main blockquote').parentNode.__kept ?? null,
          line(document.querySelector('main pre.mermaid')),
          line(document.querySelector('main blockquote p').closest('[data-pos]')),
          document.querySelectorAll('main pre.mermaid > svg').length,
          document.querySelectorAll('main pre.mermaid > svg [data-pos], main pre.mermaid > svg[data-pos]').length];
})()"))
      (imprimeur-page-test-wait-drawn browser 1)
      (should (equal (imprimeur-test-cdp-eval browser state) [nil "1" "6" 1 0]))
      (imprimeur-test-cdp-eval browser "document.querySelector('main blockquote').parentNode.__kept = 'kept'")
      (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
      (imprimeur-page-test-wait-shown browser 2)
      (should (equal (imprimeur-test-cdp-eval browser state) ["kept" "3" "8" 1 0])))))

(ert-deftest imprimeur-page-draws-diagrams-again-on-a-palette-change ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (enable-theme 'imprimeur-test-night)
  (unwind-protect
      (imprimeur-page-test-with (buffer browser "doc.md" imprimeur-page-test-diagram)
        (let ((url (imprimeur-url buffer))
              ;; A node's fill and its text's, and Mermaid's dark mode.
              (look "(() => {
  const svg = document.querySelector('main pre.mermaid > svg');
  return [getComputedStyle(svg.querySelector('.node rect')).fill,
          getComputedStyle(svg.querySelector('.node text')).fill,
          mermaid.mermaidAPI.getSiteConfig().themeVariables.darkMode];
})()"))
          (imprimeur-page-test-wait-drawn browser 1)
          (should (equal (imprimeur-test-cdp-eval browser look) ["rgb(29, 31, 33)" "rgb(197, 200, 198)" t]))
          (imprimeur-test-cdp-eval browser imprimeur-page-test-count-draws)
          (imprimeur-test-cdp-eval browser "(() => {
  const pre = document.querySelector('main pre.mermaid');
  pre.__kept = 'kept';
  pre.firstElementChild.__night = true;
})()")
          (disable-theme 'imprimeur-test-night)
          (enable-theme 'imprimeur-test-day)
          (imprimeur-test-cdp-wait
           browser "getComputedStyle(document.querySelector('main pre.mermaid > svg .node rect')).fill === 'rgb(255, 255, 255)'")
          (should (equal (imprimeur-test-cdp-eval browser look) ["rgb(255, 255, 255)" "rgb(77, 77, 76)" nil]))
          (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const pre = document.querySelector('main pre.mermaid');
  return [pre.__kept ?? null, pre.children.length, pre.firstElementChild.__night ?? null, window.__draws, location.href];
})()")
                         (vector "kept" 1 nil 1 url)))
          ;; The night palette comes back, and its drawing with it.
          (disable-theme 'imprimeur-test-day)
          (enable-theme 'imprimeur-test-night)
          (imprimeur-test-cdp-wait
           browser "getComputedStyle(document.querySelector('main pre.mermaid > svg .node rect')).fill === 'rgb(29, 31, 33)'")
          (should (equal (imprimeur-test-cdp-eval browser look) ["rgb(29, 31, 33)" "rgb(197, 200, 198)" t]))
          (should (equal (imprimeur-test-cdp-eval browser "window.__draws") 1))
          (should (= (imprimeur-page-test-requests browser imprimeur-page-test-mermaid-url) 1))
          (should (equal (imprimeur-test-cdp-eval browser "window.__violations") []))
          (should-not (imprimeur-test-cdp-errors browser))
          (should-not (imprimeur-test-cdp-escaped browser))))
    (mapc #'disable-theme '(imprimeur-test-night imprimeur-test-day))))

(defun imprimeur-page-test-palette (&rest colours)
  "Return a dark palette that gives the properties of COLOURS, a plist.
Each key of COLOURS is the name of a property after --emacs-, as a keyword."
  (list :appearance "dark"
        :css (concat ":root {\n"
                     (cl-loop for (name colour) on colours by #'cddr
                              concat (format "  --emacs-%s: %s;\n" (substring (symbol-name name) 1) colour))
                     "}\n")))

(ert-deftest imprimeur-page-draws-diagrams-again-within-an-appearance ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (let ((palette (imprimeur-page-test-palette :bg "#000001"))
        (fill "getComputedStyle(document.querySelector('main pre.mermaid > svg .node rect')).fill"))
    (cl-letf (((symbol-function 'imprimeur-palette) (lambda (_buffer) palette)))
      (imprimeur-page-test-with (buffer browser "doc.md" imprimeur-page-test-diagram)
        (imprimeur-page-test-wait-drawn browser 1)
        (should (equal (imprimeur-test-cdp-eval browser fill) "rgb(0, 0, 1)"))
        (setq palette (imprimeur-page-test-palette :bg "#000002"))
        (imprimeur-refresh-palette)
        (imprimeur-test-cdp-wait browser (format "%s === 'rgb(0, 0, 2)'" fill) 30)))))

(ert-deftest imprimeur-page-draws-diagrams-in-the-font-of-the-page ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (mapc #'enable-theme '(imprimeur-test-day imprimeur-test-mono))
  (unwind-protect
      (imprimeur-page-test-with (buffer browser "doc.md" imprimeur-page-test-diagram)
        (imprimeur-page-test-wait-drawn browser 1)
        (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const families = (selector) => getComputedStyle(document.querySelector(selector)).fontFamily;
  return families('main pre.mermaid > svg .node text') === families('main');
})()")
                       t))
        (should (string-search "Imprimeur Test Mono"
                               (imprimeur-test-cdp-eval browser "getComputedStyle(document.querySelector('main')).fontFamily"))))
    (mapc #'disable-theme '(imprimeur-test-day imprimeur-test-mono))))

(ert-deftest imprimeur-page-draws-diagrams-again-in-a-new-font ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (let ((palette (imprimeur-page-test-palette :font-mono "\"Imprimeur Test One\""))
        (family "getComputedStyle(document.querySelector('main pre.mermaid > svg .node text')).fontFamily"))
    (cl-letf (((symbol-function 'imprimeur-palette) (lambda (_buffer) palette)))
      (imprimeur-page-test-with (buffer browser "doc.md" imprimeur-page-test-diagram)
        (imprimeur-page-test-wait-drawn browser 1)
        (should (string-search "Imprimeur Test One" (imprimeur-test-cdp-eval browser family)))
        (imprimeur-test-cdp-eval browser imprimeur-page-test-count-draws)
        (setq palette (imprimeur-page-test-palette :font-mono "\"Imprimeur Test Two\""))
        (imprimeur-refresh-palette)
        (imprimeur-test-cdp-wait browser (format "%s.includes('Imprimeur Test Two')" family) 30)
        (should (equal (imprimeur-test-cdp-eval browser "window.__draws") 1))))))

(ert-deftest imprimeur-page-colours-notes-and-pies-from-the-palette ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (let ((palette (imprimeur-page-test-palette :bg "#000001" :fg "#000002" :muted "#000003" :kw "#000005" :str "#000006")))
    (cl-letf (((symbol-function 'imprimeur-palette) (lambda (_buffer) palette)))
      (imprimeur-page-test-with (buffer browser "doc.md"
                                        (concat "```mermaid\nsequenceDiagram\n  A->>B: Hello\n  Note over B: Thinking\n```\n\n"
                                                "```mermaid\npie\n  \"Most\" : 3\n  \"Fewer\" : 1\n```\n"))
        (imprimeur-page-test-wait-drawn browser 2)
        (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const [notes, pie] = document.querySelectorAll('main pre.mermaid > svg');
  const style = (element) => getComputedStyle(element);
  return [style(notes.querySelector('.note')).fill, style(notes.querySelector('.note')).stroke,
          style(notes.querySelector('.noteText')).fill,
          ...[...pie.querySelectorAll('.pieCircle')].map((slice) => style(slice).fill)];
})()")
                       ["rgb(0, 0, 1)" "rgb(0, 0, 3)" "rgb(0, 0, 2)" "rgb(0, 0, 5)" "rgb(0, 0, 6)"]))))))

(ert-deftest imprimeur-page-gives-each-diagram-its-last-drawing ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.md"
                                    (concat imprimeur-page-test-diagram "\n"
                                            "```mermaid\nflowchart TD\n  C[Three] --> D[Four]\n```\n"))
    (imprimeur-page-test-wait-drawn browser 2)
    (imprimeur-test-cdp-eval browser "document.querySelectorAll('main pre.mermaid > svg')
.forEach((svg, index) => { svg.__kept = index; })")
    ;; One edit breaks both.
    (imprimeur-page-test-replace-text
     buffer "```mermaid\nflowchart TD\n  A --> -->\n```\n\n```mermaid\nflowchart TD\n  C --> -->\n```\n")
    (imprimeur-page-test-wait-shown browser 2)
    (imprimeur-test-cdp-wait
     browser "document.querySelectorAll('main pre.mermaid > .imprimeur-diagram-error').length === 2" 30)
    (should (equal (imprimeur-test-cdp-eval browser "[...document.querySelectorAll('main pre.mermaid')]
.map((pre) => [pre.children.length, pre.firstElementChild.__kept ?? null])")
                   [[2 0] [2 1]]))))

(ert-deftest imprimeur-page-pairs-drawings-only-when-as-many-go-as-come ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (let ((other "```mermaid\nflowchart TD\n  C[Three] --> D[Four]\n```\n")
        (broken "```mermaid\nflowchart TD\n  C[Three] --> -->\n```\n")
        ;; Each diagram: its first element, that element's words, whether a message follows.
        (state "[...document.querySelectorAll('main pre.mermaid')]
.map((pre) => [pre.firstElementChild.localName, pre.firstElementChild.textContent,
               pre.querySelector(':scope > .imprimeur-diagram-error')?.textContent.length > 0])")
        (code "flowchart TD\n  C[Three] --> -->"))
    (imprimeur-page-test-with (buffer browser "doc.md" (concat imprimeur-page-test-diagram "\n" other))
      (imprimeur-page-test-wait-drawn browser 2)
      ;; One edit deletes the first and breaks the second: two went, one came.
      (imprimeur-page-test-replace-text buffer broken)
      (imprimeur-page-test-wait-shown browser 2)
      (imprimeur-test-cdp-wait browser "!!document.querySelector('main pre.mermaid > .imprimeur-diagram-error')" 30)
      (should (equal (imprimeur-test-cdp-eval browser state) (vector (vector "code" code t))))
      (imprimeur-page-test-replace-text buffer other)
      (imprimeur-page-test-wait-shown browser 3)
      (imprimeur-page-test-wait-drawn browser 1)
      ;; One edit makes two broken diagrams of the one drawn: one went, two came.
      (imprimeur-page-test-replace-text buffer (concat broken "\n" broken))
      (imprimeur-page-test-wait-shown browser 4)
      (imprimeur-test-cdp-wait
       browser "document.querySelectorAll('main pre.mermaid > .imprimeur-diagram-error').length === 2" 30)
      (should (equal (imprimeur-test-cdp-eval browser state)
                     (vector (vector "code" code t) (vector "code" code t)))))))

(ert-deftest imprimeur-page-draws-one-pass-at-a-time ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (let ((palette (imprimeur-page-test-palette :bg "#000001")))
    (cl-letf (((symbol-function 'imprimeur-palette) (lambda (_buffer) palette)))
      (imprimeur-page-test-with (buffer browser "doc.md" imprimeur-page-test-diagram)
        (imprimeur-page-test-wait-drawn browser 1)
        ;; A stand-in that draws only when it is told to.
        (imprimeur-test-cdp-eval browser "(() => {
  window.__draws = 0;
  window.__finish = [];
  mermaid.render = async () => {
    window.__draws += 1;
    await new Promise((resolve) => window.__finish.push(resolve));
    return { svg: '<svg></svg>' };
  };
})()")
        (setq palette (imprimeur-page-test-palette :bg "#000002"))
        (imprimeur-refresh-palette)
        (imprimeur-test-cdp-wait browser "window.__draws === 1")
        ;; A second palette while the first is being drawn: the page has it,
        ;; and its pass waits for the one under way.
        (setq palette (imprimeur-page-test-palette :bg "#000003"))
        (imprimeur-refresh-palette)
        (imprimeur-test-cdp-wait
         browser "getComputedStyle(document.documentElement).getPropertyValue('--emacs-bg') === '#000003'")
        (accept-process-output nil 0.5)
        (should (equal (imprimeur-test-cdp-eval browser "window.__draws") 1))
        (imprimeur-test-cdp-eval browser "window.__finish.shift()()")
        (imprimeur-test-cdp-wait browser "window.__draws === 2")
        (imprimeur-test-cdp-eval browser "window.__finish.shift()()")))))

(ert-deftest imprimeur-page-gives-up-on-a-diagram-past-its-deadline ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.md" imprimeur-page-test-diagram)
    (imprimeur-page-test-wait-drawn browser 1)
    ;; A stand-in that never settles for one source; and the first delay of
    ;; 20 s, which is that source's, fires at once.  Mermaid gets the others.
    (imprimeur-test-cdp-eval browser "(() => {
  const { render } = mermaid;
  const { setTimeout: later } = window;
  window.__deadlines = 0;
  mermaid.render = (id, source) => (source.includes('Stuck') ? new Promise(() => {}) : render(id, source));
  window.setTimeout = (callback, delay, ...rest) => {
    if (delay === 20000) window.__deadlines += 1;
    return later(callback, delay === 20000 && window.__deadlines === 1 ? 0 : delay, ...rest);
  };
})()")
    (imprimeur-page-test-replace-text
     buffer "```mermaid\nflowchart TD\n  A[Stuck]\n```\n\n```mermaid\nflowchart TD\n  B[Next]\n```\n")
    (imprimeur-page-test-wait-shown browser 2)
    (imprimeur-test-cdp-wait browser "document.querySelector('main pre.mermaid:last-of-type > svg .node text')
  ?.textContent.trim() === 'Next'" 30)
    (should (equal (imprimeur-test-cdp-eval browser "[...document.querySelectorAll('main pre.mermaid')]
.map((pre) => [pre.firstElementChild.localName,
               pre.querySelector(':scope > .imprimeur-diagram-error')?.textContent ?? null])")
                   [["code" "This diagram took too long to draw."] ["svg" nil]]))
    (should (equal (imprimeur-test-cdp-eval browser "window.__deadlines") 2))
    (should-not (imprimeur-test-cdp-events-named browser "Runtime.exceptionThrown"))))

(ert-deftest imprimeur-page-draws-a-source-once ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (let ((other "```mermaid\nflowchart TD\n  C[Three] --> D[Four]\n```\n"))
    (imprimeur-page-test-with (buffer browser "doc.md" imprimeur-page-test-diagram)
      (let ((labels "[...document.querySelectorAll('main pre.mermaid > svg')]
.map((svg) => svg.querySelector('.node text').textContent.trim())"))
        (imprimeur-page-test-wait-drawn browser 1)
        (imprimeur-test-cdp-eval browser imprimeur-page-test-count-draws)
        ;; The revision, the text, then the first label of each diagram and
        ;; how many Mermaid has drawn since the first.
        (pcase-dolist (`(,revision ,text ,shown ,draws)
                       `((2 ,(concat imprimeur-page-test-diagram "\n" imprimeur-page-test-diagram) ["One" "One"] 0)
                         (3 ,(concat imprimeur-page-test-diagram "\n" other) ["One" "Three"] 1)
                         (4 ,(concat imprimeur-page-test-diagram "\n" imprimeur-page-test-diagram) ["One" "One"] 1)))
          (imprimeur-page-test-replace-text buffer text)
          (imprimeur-page-test-wait-shown browser revision)
          (imprimeur-test-cdp-wait browser (format "JSON.stringify(%s) === '%s'" labels (json-serialize shown)))
          (should (equal (imprimeur-test-cdp-eval browser "window.__draws") draws)))))))

(ert-deftest imprimeur-page-offers-a-video-that-fails-after-a-drawing ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.md" (concat imprimeur-page-test-diagram "\n![clip](clip.webm)\n"))
    (imprimeur-page-test-wait-drawn browser 1)
    (imprimeur-page-test-video-links browser 1)
    ;; No sanitising since the drawing's: its policy is the last used.
    (imprimeur-test-cdp-eval browser (format "%s.forEach((a) => a.remove());
document.querySelector('main video').load()"
                                             imprimeur-page-test-video-link))
    (should (equal (imprimeur-page-test-video-links browser 1) [["video" "clip.webm" 0]]))))

(ert-deftest imprimeur-page-shows-edits-after-mermaid-removed-an-element ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.md"
                                    (concat "<p>Before <a id=\"imprimeur-diagram-1\" href=\"x.md\">link</a>.</p>\n\n"
                                            imprimeur-page-test-diagram))
    (imprimeur-page-test-wait-drawn browser 1)
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('main a').length") 0))
    (with-current-buffer buffer (goto-char (point-min)) (insert "Above.\n\n"))
    (imprimeur-page-test-wait-shown browser 2)
    (should (imprimeur-test-cdp-eval browser "document.querySelector('main').textContent.includes('Above.')"))
    (should-not (imprimeur-test-cdp-events-named browser "Runtime.exceptionThrown"))))

(ert-deftest imprimeur-page-keeps-the-last-drawing-on-a-parse-error ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.md" imprimeur-page-test-diagram)
    (imprimeur-page-test-wait-drawn browser 1)
    (imprimeur-test-cdp-eval browser "document.querySelector('main pre.mermaid > svg').__kept = 'kept'")
    (imprimeur-page-test-replace-text buffer "```mermaid\nflowchart TD\n  A --> --> <b>bold</b>\n```\n")
    (imprimeur-page-test-wait-shown browser 2)
    (imprimeur-test-cdp-wait browser "!!document.querySelector('main pre.mermaid > .imprimeur-diagram-error')" 30)
    (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const pre = document.querySelector('main pre.mermaid');
  const [svg, message] = pre.children;
  return [pre.children.length, svg.localName, svg.__kept ?? null, message.children.length,
          message.textContent.length > 0, message.getBoundingClientRect().top >= svg.getBoundingClientRect().bottom];
})()")
                   (vector 2 "svg" "kept" 0 t t)))
    (imprimeur-page-test-replace-text buffer "```mermaid\nflowchart TD\n  C[Three] --> D[Four]\n```\n")
    (imprimeur-page-test-wait-shown browser 3)
    (imprimeur-test-cdp-wait browser "document.querySelector('main pre.mermaid > svg').__kept === undefined" 30)
    (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const pre = document.querySelector('main pre.mermaid');
  return [pre.children.length, pre.querySelector('svg .node text').textContent.trim()];
})()")
                   (vector 1 "Three")))))

(ert-deftest imprimeur-page-keeps-the-code-of-a-diagram-that-never-drew ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.md" "```mermaid\nflowchart TD\n  A --> -->\n```\n")
    (imprimeur-page-test-wait-shown browser 1)
    (imprimeur-test-cdp-wait browser "!!document.querySelector('main pre.mermaid > .imprimeur-diagram-error')" 30)
    (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const pre = document.querySelector('main pre.mermaid');
  return [pre.children.length, pre.firstElementChild.localName, pre.firstElementChild.textContent,
          [...document.body.children].map((element) => element.localName).join()];
})()")
                   (vector 2 "code" "flowchart TD\n  A --> -->" "header,div,main")))
    (should (equal (imprimeur-test-cdp-eval browser "window.__violations") []))
    (should-not (imprimeur-test-cdp-events-named browser "Runtime.exceptionThrown"))))

(ert-deftest imprimeur-page-makes-the-message-of-a-diagram-readable ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (enable-theme 'imprimeur-test-night)
  (unwind-protect
      (imprimeur-page-test-with (buffer browser "doc.md" "```mermaid\nflowchart TD\n  A --> -->\n```\n")
        (let ((check (lambda (appearance)
                       (imprimeur-test-cdp-wait
                        browser (format "document.documentElement.dataset.appearance === '%s'
&& !!document.querySelector('main pre.mermaid > .imprimeur-diagram-error')"
                                        appearance)
                        30)
                       ;; The contrast of WCAG 2, then whether the longest line stays in the pane.
                       (pcase-let ((`[,contrast ,inside] (imprimeur-test-cdp-eval browser "(() => {
  const note = document.querySelector('main pre.mermaid > .imprimeur-diagram-error');
  const luminance = (colour) => {
    const [red, green, blue] = colour.match(/[\\d.]+/g).map((value) => {
      const channel = Number(value) / 255;
      return channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
  };
  const [light, dark] = [getComputedStyle(note).color, getComputedStyle(note.parentElement).backgroundColor]
    .map(luminance).sort((one, other) => other - one);
  return [(light + 0.05) / (dark + 0.05), note.parentElement.scrollWidth <= note.parentElement.clientWidth];
})()")))
                         (should (>= contrast 4.5))
                         (should inside)))))
          ;; The theme's warning colour, then Minitel's own, each of them chosen
          ;; by an appearance that changes, so that the page is seen to have it.
          (funcall check "dark")
          (dolist (appearance '("light" "dark"))
            (cl-letf (((symbol-function 'imprimeur-palette)
                       (lambda (_buffer) (list :appearance appearance :css ":root {\n}\n"))))
              (imprimeur-refresh-palette))
            (funcall check appearance))))
    (disable-theme 'imprimeur-test-night)))

(ert-deftest imprimeur-page-bounds-the-drawings-it-keeps ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.md" imprimeur-page-test-diagram)
    (imprimeur-page-test-wait-drawn browser 1)
    ;; A stand-in that draws at once, and a text of several diagrams.
    (imprimeur-test-cdp-eval browser "mermaid.render = async () => ({ svg: '<svg></svg>' })")
    (imprimeur-test-cdp-eval browser imprimeur-page-test-count-draws)
    (let ((fence (lambda (number) (format "```mermaid\nflowchart TD\n  N%d\n```\n" number))))
      ;; More diagrams than the page keeps drawings: the oldest are forgotten,
      ;; the last one kept.
      (imprimeur-page-test-replace-text
       buffer (mapconcat fence (number-sequence 1 100) "\n"))
      (imprimeur-page-test-wait-shown browser 2)
      (imprimeur-page-test-wait-drawn browser 100)
      (should (equal (imprimeur-test-cdp-eval browser "window.__draws") 100))
      (imprimeur-page-test-replace-text buffer (funcall fence 100))
      (imprimeur-page-test-wait-shown browser 3)
      (imprimeur-page-test-wait-drawn browser 1)
      (should (equal (imprimeur-test-cdp-eval browser "window.__draws") 100))
      ;; The page keeps 64: the oldest of those is still there, the one before
      ;; it is not.
      (imprimeur-page-test-replace-text buffer (funcall fence 37))
      (imprimeur-page-test-wait-shown browser 4)
      (imprimeur-page-test-wait-drawn browser 1)
      (should (equal (imprimeur-test-cdp-eval browser "window.__draws") 100))
      (imprimeur-page-test-replace-text buffer (funcall fence 36))
      (imprimeur-page-test-wait-shown browser 5)
      (imprimeur-test-cdp-wait browser "window.__draws === 101"))))

(defconst imprimeur-page-test-inspect-drawings
  "(() => {
  const main = document.getElementById('imprimeur-main');
  const tags = ['script', 'iframe', 'frame', 'object', 'embed', 'form', 'input', 'button', 'select', 'textarea',
                'template', 'map', 'area', 'base', 'meta', 'link', 'img', 'foreignobject', 'use', 'animate', 'set', 'b'];
  const found = [];
  for (const element of main.querySelectorAll('*')) {
    if (tags.includes(element.localName.toLowerCase())) found.push(element.localName);
    if (element.localName === 'style' && !element.closest('svg')) found.push('style outside a drawing');
    for (const attribute of element.attributes)
      if (/^on/i.test(attribute.name)
          || ['target', 'ping', 'download', 'srcdoc', 'formaction', 'draggable'].includes(attribute.name)
          || /^\\s*javascript:/i.test(attribute.value))
        found.push(element.localName + '[' + attribute.name + ']');
  }
  const css = [...main.querySelectorAll('svg style')].map((style) => style.textContent).join();
  if (/@import|imprimeur-hostile|Imprimeur Hostile|body/i.test(css)) found.push('a hostile style');
  return [found, typeof window.__pwned, location.href, document.baseURI, getComputedStyle(document.body).display];
})()"
  "What the page holds that a hostile diagram must not have put there.
The value is [FOUND PWNED HREF BASE DISPLAY]: the forbidden elements,
attributes and styles found in main, the type of window.__pwned, the
location, the base URL and how the body displays.")

(ert-deftest imprimeur-page-sanitises-what-mermaid-returns ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.md" imprimeur-page-test-diagram)
    (let ((url (imprimeur-url buffer))
          (diagrams "document.querySelectorAll('main pre.mermaid')")
          (add (lambda (name revision)
                 (with-current-buffer buffer
                   (goto-char (point-max))
                   (insert "\n```mermaid\nflowchart TD\n  " name " --> Z\n```\n"))
                 (imprimeur-page-test-wait-shown browser revision))))
      (imprimeur-page-test-wait-drawn browser 1)
      ;; A drawing with all that the SVG profile must remove, and what it keeps.
      (imprimeur-test-cdp-eval browser "mermaid.render = async () => ({ svg: `<svg id=\"stub\" onload=\"window.__pwned=1\">
<style>#stub .kept { fill: rgb(1, 2, 3); }</style>
<script>window.__pwned=2</script>
<title><b>Markup</b></title>
<circle class=\"kept\" r=\"5\" onclick=\"window.__pwned=3\" draggable=\"true\"></circle>
<foreignObject><img src=\"https://example.invalid/foreign.png\" onerror=\"window.__pwned=4\"></foreignObject>
<use xlink:href=\"https://example.invalid/use.svg#x\"></use>
<animate attributeName=\"href\" to=\"javascript:window.__pwned=5\"></animate>
<a xlink:href=\"javascript:window.__pwned=6\"><text>run</text></a>
<a id=\"out\" xlink:href=\"https://example.invalid/out\" target=\"_blank\" ping=\"https://example.invalid/ping\" download=\"out\"><text>out</text></a>
</svg>` })")
      (funcall add "B" 2)
      (imprimeur-page-test-wait-drawn browser 2)
      (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-inspect-drawings)
                     (vector [] "undefined" url url "block")))
      (should (equal (imprimeur-test-cdp-eval browser (format "(() => {
  const svg = %s[1].firstElementChild;
  return [getComputedStyle(svg.querySelector('.kept')).fill,
          svg.querySelector('#out').getAttributeNS('http://www.w3.org/1999/xlink', 'href')];
})()" diagrams))
                     ["rgb(1, 2, 3)" "https://example.invalid/out"]))
      (accept-process-output nil 0.5)
      (should-not (imprimeur-test-cdp-escaped browser))
      ;; Nothing of it is SVG.
      (imprimeur-test-cdp-eval browser "mermaid.render = async () => ({ svg: '<p>No drawing</p>' })")
      (funcall add "C" 3)
      (imprimeur-test-cdp-wait browser (format "%s[2].children.length === 2" diagrams) 30)
      (should (equal (imprimeur-test-cdp-eval browser (format "(() => {
  const [code, message] = %s[2].children;
  return [code.localName, message.textContent, message.children.length];
})()" diagrams))
                     ["code" "This diagram has no drawing that the page can show." 0]))
      ;; A failure of Mermaid, whose message is shown as text.
      (imprimeur-test-cdp-eval browser "mermaid.render = async () => { throw new Error('<img src=x onerror=\"window.__pwned=7\">'); }")
      (funcall add "D" 4)
      (imprimeur-test-cdp-wait browser (format "%s[3].children.length === 2" diagrams) 30)
      (should (equal (imprimeur-test-cdp-eval browser (format "(() => {
  const [code, message] = %s[3].children;
  return [code.localName, message.textContent, message.children.length];
})()" diagrams))
                     ["code" "<img src=x onerror=\"window.__pwned=7\">" 0]))
      (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-inspect-drawings)
                     (vector [] "undefined" url url "block"))))))

(defconst imprimeur-page-test-diagram-kinds
  '(("flowchart TD\n  A[Alpha one] --> B[Beta two]\n" . "Alpha one")
    ("sequenceDiagram\n  Alice->>Bob: Hello there\n  Note over Bob: Thinking\n" . "Thinking")
    ("classDiagram\n  class Animal {\n    +int age\n  }\n" . "+int age")
    ("stateDiagram-v2\n  [*] --> Still\n  Still --> Moving: go\n" . "Moving")
    ("erDiagram\n  CUSTOMER ||--o{ ORDER : places\n" . "places")
    ("gantt\n  title A plan\n  dateFormat YYYY-MM-DD\n  section Part\n  First task :a1, 2024-01-01, 30d\n"
     . "First task")
    ("pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85\n" . "Dogs")
    ("quadrantChart\n  x-axis Low --> High\n  y-axis Few --> Many\n  quadrant-1 Expand\n" . "Expand")
    ("requirementDiagram\n  requirement test_req {\n    id: 1\n    text: the test text\n  }\n" . "test_req")
    ("gitGraph\n  commit id: \"one\"\n  branch develop\n" . "develop")
    ("C4Context\n  Person(customer, \"Customer\", \"A person\")\n" . "A person")
    ("mindmap\n  root((Root idea))\n    Origins\n" . "Origins")
    ("timeline\n  title History\n  2002 : LinkedIn\n" . "LinkedIn")
    ("sankey-beta\n\nAgriculture,Waste,10\n" . "Agriculture")
    ("xychart-beta\n  title \"Sales\"\n  x-axis [jan, feb]\n  bar [50, 60]\n" . "Sales")
    ("block-beta\n  columns 2\n  a[\"Alpha\"] b[\"Beta\"]\n" . "Beta")
    ("packet-beta\n  0-15: \"Source Port\"\n  16-31: \"Destination Port\"\n" . "Source Port")
    ("kanban\n  todo[To do]\n    t1[Write the tests]\n" . "Write the tests")
    ("architecture-beta\n  service db(database)[Database]\n" . "Database")
    ("radar-beta\n  axis a[\"Speed\"], b[\"Power\"], c[\"Range\"]\n  curve x[\"One\"]{1, 2, 3}\n" . "Speed")
    ("treemap-beta\n\"Group\"\n    \"Leaf one\": 12\n" . "Leaf one")
    ("venn-beta\n  set A[\"First\"]\n  set B[\"Second\"]\n" . "First")
    ("journey\n  section Go to work\n    Make tea: 5: Me\n")
    ("journey\n  section Go to work\n    Make tea: 5: Me\n")
    ("sequenceDiagram\n  Alice->>Bob: $$x^2$$\n  Note over Bob: $$y^2$$\n")
    ("eventmodeling\ntf 01 evt Cart.Created { \"id\": 1 }\ntf 02 cmd Cart.Pay\n")
    ("venn-beta\n  set A[\"First\"]\n    text A1[\"Inside\"]\n  set B[\"Second\"]\n"))
  "Each kind of diagram, as Mermaid 12.0.0 draws it, and a label that must show.
Without one, some labels are in a foreignObject, which no drawing keeps.  The
second diagram of a source comes from the page's cache.")

(ert-deftest imprimeur-page-says-when-a-drawing-lost-labels ()
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (imprimeur-page-test-with (buffer browser "doc.md"
                                    (mapconcat (lambda (kind) (concat "```mermaid\n" (car kind) "```\n"))
                                               imprimeur-page-test-diagram-kinds "\n"))
    (imprimeur-test-cdp-wait browser (format "document.querySelectorAll('main pre.mermaid > svg').length === %d"
                                             (length imprimeur-page-test-diagram-kinds))
                             90)
    (cl-mapc (lambda (kind shown)
               (pcase-let ((`(,source . ,label) kind)
                           (`[,text ,message ,foreign] shown))
                 (should (equal (list source (and label (string-search label text) t) message foreign)
                                (list source (and label t)
                                      (unless label
                                        "Some labels of this diagram cannot be shown: the page draws SVG text alone.")
                                      0)))))
             imprimeur-page-test-diagram-kinds
             ;; The text of a drawing but for its style, its message, its foreignObjects.
             (append (imprimeur-test-cdp-eval browser "[...document.querySelectorAll('main pre.mermaid')].map((pre) => {
  const svg = pre.querySelector(':scope > svg').cloneNode(true);
  svg.querySelectorAll('style').forEach((style) => style.remove());
  return [svg.textContent, pre.querySelector(':scope > .imprimeur-diagram-error')?.textContent ?? null,
          svg.querySelectorAll('foreignObject').length];
})")
                     nil))))

(defun imprimeur-page-test-hostile-diagrams (file fence)
  "Check that hostile diagrams harm neither the page nor Emacs, in FILE.
FENCE turns the source of a diagram into a block of that file's format."
  (imprimeur-test-require "pandoc")
  (imprimeur-test-require "mmdc")
  (let* ((plain "flowchart TD\n  A[\"<img src=x onerror=window.__pwned=1>\"] --> B[Two]\n")
         ;; Mermaid puts maths, with what surrounds it, in the live page, before
         ;; any drawing: what stops the refresh is Mermaid's sanitiser alone.
         (maths (concat "sequenceDiagram\n  A->>B: $$z$$ <img src=https://example.invalid/katex.png>"
                        "<meta http-equiv=\"refresh\" content=\"0,url=https://example.invalid/refresh\">\n"))
         (locked (concat "{\"securityLevel\": \"loose\", \"theme\": \"dark\","
                         " \"themeVariables\": {\"primaryColor\": \"#ff0000\"},"
                         " \"themeCSS\": \"@import url(https://example.invalid/theme.css);"
                         " .imprimeur-hostile { fill: red; }\","
                         " \"fontFamily\": \"Imprimeur Hostile\", \"htmlLabels\": true, \"darkMode\": true,"
                         " \"flowchart\": {\"htmlLabels\": true, \"curve\": \"step\", \"nodeSpacing\": 300},"
                         " \"secure\": [], \"maxTextSize\": 1, \"maxEdges\": 0, \"startOnLoad\": true,"
                         " \"suppressErrorRendering\": false}"))
         (sources
          (list plain
                (concat "%%{init: " locked "}%%\n" plain)
                (concat "---\nconfig: " locked "\n---\n" plain)
                "flowchart TD\n  E[run]\n  click E \"javascript:window.__pwned=2\"\n  F[call]\n  click F call pwn()\n"
                "flowchart TD\n  G[blank]\n  click G \"https://example.invalid/blank\" _blank\n"
                "stateDiagram-v2\n  classDef x fill:red}} body{display:none\n  [*] --> S:::x\n"
                (concat "sequenceDiagram\n  participant L\n  link L: run @ javascript:window.__pwned=3\n"
                        "  links L: {\"go\": \"javascript:window.__pwned=4\"}\n")
                "classDiagram\n  class M\n  click M href \"javascript:window.__pwned=5\"\n"
                (concat "gantt\n  section A\n  U :u1, 2024-01-01, 3d\n  click u1 href \"javascript:window.__pwned=6\"\n"
                        "  V :v1, 2024-01-01, 3d\n  click v1 call pwn()\n")
                "flowchart TD\n  W[\"`[md](javascript:window.__pwned=7)`\"]\n"
                "flowchart TD\n  Y[\"<script>window.__pwned=8</script><style>body{display:none}</style>\"]\n"
                (concat "%%{init: {\"dompurifyConfig\": {\"ADD_TAGS\": [\"script\", \"iframe\"],"
                        " \"ADD_ATTR\": [\"onerror\"]}}}%%\nflowchart TD\n"
                        "  N[\"<iframe src=https://example.invalid/frame></iframe>\"]\n")
                maths
                (concat "%%{init: {\"dompurifyConfig\": {\"ADD_TAGS\": [\"meta\"],"
                        " \"ADD_ATTR\": [\"http-equiv\", \"content\"]}}}%%\n" maths)
                ;; Drawn only if the picture loads, which the policy stops.
                "flowchart TD\n  K@{ img: \"https://example.invalid/picture.png\", label: \"k\" }\n")))
    (imprimeur-page-test-with (buffer browser file (mapconcat fence sources "\n"))
      (let ((url (imprimeur-url buffer))
            (pages (imprimeur-test-cdp-pages browser))
            (links "document.querySelectorAll('main svg a, main svg .clickable')"))
        (imprimeur-page-test-wait-shown browser 1)
        (imprimeur-test-cdp-eval browser "window.pwn = () => { window.__pwned = 'called'; }")
        ;; All are drawn but the style that tries to leave its rule, whose
        ;; message is one of three: the other two say that maths is lost.
        (imprimeur-test-cdp-wait browser (format "document.querySelectorAll('main pre.mermaid > svg').length === %d
&& document.querySelectorAll('main pre.mermaid > .imprimeur-diagram-error').length === 3"
                                                 (1- (length sources)))
                                 30)
        (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-inspect-drawings)
                       (vector [] "undefined" url url "block")))
        ;; The directive and the front matter change nothing of the drawing.
        (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const [plain, directive, front] = [...document.querySelectorAll('main pre.mermaid > svg')]
    .map((svg) => svg.outerHTML.replaceAll(/imprimeur-diagram-\\d+/g, 'id'));
  return [plain === directive, plain === front];
})()")
                       [t t]))
        (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const { securityLevel, theme, htmlLabels, startOnLoad, secure } = mermaid.mermaidAPI.getSiteConfig();
  return [securityLevel, theme, htmlLabels, startOnLoad,
          ['secure', 'securityLevel', 'startOnLoad', 'maxTextSize', 'suppressErrorRendering', 'maxEdges',
           'theme', 'themeVariables', 'themeCSS', 'fontFamily', 'htmlLabels', 'flowchart', 'darkMode',
           'dompurifyConfig']
            .filter((key) => !secure.includes(key))];
})()")
                       (vector "strict" "base" nil nil [])))
        (dotimes (index (imprimeur-test-cdp-eval browser (concat links ".length")))
          (let ((element (format "%s[%d]" links index)))
            (imprimeur-test-cdp-eval browser (concat element ".scrollIntoView({ block: 'center' })"))
            (imprimeur-test-cdp-click browser element)))
        (imprimeur-test-wait-for (lambda () imprimeur-page-test-followed))
        (accept-process-output nil 0.5)
        (should (equal (seq-uniq imprimeur-page-test-followed) '((browse "https://example.invalid/blank"))))
        (should (equal (imprimeur-test-cdp-eval browser imprimeur-page-test-inspect-drawings)
                       (vector [] "undefined" url url "block")))
        (should (= (imprimeur-test-cdp-pages browser) pages))
        (should (= (imprimeur-page-test-requests browser "example\\.invalid/\\(?:theme\\|frame\\)") 0))
        (should-not (imprimeur-test-cdp-events-named browser "Page.frameRequestedNavigation"))
        (should-not (imprimeur-test-cdp-escaped browser))))))

(ert-deftest imprimeur-page-resists-hostile-diagrams-in-org ()
  (imprimeur-page-test-hostile-diagrams
   "doc.org" (lambda (source) (concat "#+begin_src mermaid\n" source "#+end_src\n"))))

(ert-deftest imprimeur-page-resists-hostile-diagrams-in-markdown ()
  (imprimeur-page-test-hostile-diagrams
   "doc.md" (lambda (source) (concat "```mermaid\n" source "```\n"))))

;;; imprimeur-page-test.el ends here
