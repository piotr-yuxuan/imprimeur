;;; imprimeur-follow-test.el --- Tests of scroll sync  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; In batch, neither `window-scroll-functions' nor `post-command-hook' runs for a
;; bare `set-window-start', so a move of the source is a command, run through
;; `execute-kbd-macro'.  A page is a raw event stream, or headless Chromium.
;;
;; Requirements of plan 004, "Emacs to page": both hooks call one function, and a
;; pure throttle of 50 ms keeps the events apart.  The event `scroll' holds
;; {line, total, point, seq}: the line of the window start and that of point, in
;; the widened buffer whatever the narrowing, and the widened buffer's lines.  A
;; burst of commands gives one event, of where they ended.  Point moving alone
;; tells the page with the same seq, which moves it not at all; nothing moving
;; tells nothing.  A page that reports a revision gets the event, so that the first
;; report aligns it, whatever came before.  Hooks and timers go with the session.
;;
;; Acceptance 2: with a command putting "Paragraph 51" at the window start in a
;; fixture of paragraphs of 1 to 15 lines, that paragraph reaches the top of the
;; page (±2 px), in Org and in Markdown, also under narrowing; a view opened on an
;; already scrolled source shows its top line once `ready' arrives, and so does the
;; same page loaded again, which a later revision moves no more.
;;
;; Acceptance 10: `imprimeur-follow-mode' is on with a new session and off when
;; `imprimeur-scroll-sync' is nil; off, a command that scrolls the source sends no
;; `scroll' event; on again, the page aligns with the source at once.  It needs a
;; session, and survives what the session survives.
;;
;; "Line map": a format without lines syncs by proportion, and the source's first
;; line stands for the page's top, above whatever comes before the first block.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-http)
(require 'imprimeur-test-cdp)
(require 'imprimeur)

(defun imprimeur-follow-test-paragraphs (count &optional section)
  "Return COUNT paragraphs of 1 to 15 lines, each starting Paragraph N.
SECTION, a format for a number, gives the line that starts a section,
before every twentieth paragraph from the first."
  (mapconcat (lambda (number)
               (concat (and section (zerop (% (1- number) 20)) (format section (1+ (/ number 20))))
                       (format "Paragraph %d.\n" number)
                       (apply #'concat (make-list (% (* 7 number) 15) "Another line of this paragraph.\n"))
                       "\n"))
             (number-sequence 1 count)
             ""))

(defun imprimeur-follow-test-line (text part)
  "Return the line of TEXT that holds PART, counted from 1."
  (1+ (seq-count (lambda (char) (eq char ?\n)) (substring text 0 (string-search part text)))))

(defvar imprimeur-follow-test-target nil
  "The text whose line `imprimeur-follow-test-command' puts at the window start.")

(defun imprimeur-follow-test-command ()
  "Put the line of `imprimeur-follow-test-target' at the window start."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (search-forward imprimeur-follow-test-target)
    (set-window-start nil (pos-bol))))

(defun imprimeur-follow-test-scroll-to (text)
  "Run a command that puts the line of TEXT at the window start."
  (let ((imprimeur-follow-test-target text)
        (overriding-local-map (define-keymap "<f12>" #'imprimeur-follow-test-command)))
    (execute-kbd-macro [f12])))

(defun imprimeur-follow-test-base (buffer)
  "Return (PORT . ROUTES) of the session of BUFFER, ROUTES its internal path."
  (let* ((url (url-generic-parse-url (imprimeur-url buffer)))
         (path (url-filename url)))
    (cons (url-port url) (concat (substring path 0 (1+ (string-search "/" path 1))) ".imprimeur/"))))

(defun imprimeur-follow-test-post (buffer body)
  "Post BODY as the page of BUFFER would; return the status."
  (let ((base (imprimeur-follow-test-base buffer)))
    (car (imprimeur-test-http-post (car base) (concat (cdr base) "post") body))))

(defmacro imprimeur-follow-test-with (spec &rest body)
  "Run BODY with BUFFER showing TEXT and STREAM an event stream of its page.
SPEC is (BUFFER STREAM TEXT).  BUFFER visits an Org file, in the selected
Emacs window, in `imprimeur-mode', with the fake pandoc and browser."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,stream ,text) spec))
    `(let* ((imprimeur-pandoc-program imprimeur-test-fake-pandoc)
            (imprimeur-browser-program imprimeur-test-fake-browser)
            (root (repo-test-git-tree (list (cons "doc.org" ,text))))
            (,buffer (find-file-noselect (expand-file-name "doc.org" root))))
       (unwind-protect
           (save-window-excursion
             (switch-to-buffer ,buffer)
             (imprimeur-mode 1)
             (let* ((base (imprimeur-follow-test-base ,buffer))
                    (,stream (imprimeur-test-http-stream (car base) (concat (cdr base) "events"))))
               (imprimeur-test-wait-for
                (lambda () (assoc "palette" (imprimeur-test-http-events ,stream))))
               ,@body))
         (when (buffer-live-p ,buffer)
           (with-current-buffer ,buffer (set-buffer-modified-p nil))
           (kill-buffer ,buffer))))))

(defun imprimeur-follow-test-scrolls (stream)
  "Return the data of the scroll events on STREAM, as plists, oldest first."
  (mapcar (lambda (event) (json-parse-string (cdr event) :object-type 'plist))
          (seq-filter (lambda (event) (equal (car event) "scroll")) (imprimeur-test-http-events stream))))

(defun imprimeur-follow-test-wait-scrolls (stream count)
  "Wait until STREAM has held COUNT scroll events; return the last of them.
What happens in the meantime goes through the timers and processes."
  (imprimeur-test-wait-for (lambda () (>= (length (imprimeur-follow-test-scrolls stream)) count)))
  (car (last (imprimeur-follow-test-scrolls stream))))

(defun imprimeur-follow-test-settle ()
  "Give what must not happen a moment to happen, with timers and processes."
  (accept-process-output nil 0.2))

;;;; Decisions

(ert-deftest imprimeur-follow-throttles-its-reports ()
  (pcase-dolist (`(,sent-at ,now ,delay)
                 '((10.0 10.0 0.05)
                   (10.0 10.02 0.03)
                   (10.0 10.05 0)
                   (10.0 10.2 0)
                   (0 1000.0 0)
                   ;; A clock that went back waits one interval and no more.
                   (10.0 9.0 0.05)))
    (should (equal (list sent-at now (< (abs (- (imprimeur-sync--delay sent-at now) delay)) 1e-9))
                   (list sent-at now t)))))

(ert-deftest imprimeur-follow-judges-what-to-tell ()
  (pcase-dolist (`(,known-line ,known-point ,line ,point ,change)
                 '(;; The echo of a scroll that a page asked for, or nothing new.
                   (10 12 10 12 nil)
                   (10 12 10 13 point)
                   (10 12 11 12 move)
                   (10 12 11 13 move)
                   (nil nil 1 1 move)
                   (nil 12 10 12 move)
                   (10 nil 10 12 point)))
    (should (equal (list known-line known-point line point
                         (imprimeur-sync--judge known-line known-point line point))
                   (list known-line known-point line point change)))))

;;;; From Emacs to the page

(ert-deftest imprimeur-follow-sends-where-a-command-leaves-the-source ()
  (let ((text (imprimeur-follow-test-paragraphs 60 "* Section %d\n")))
    (imprimeur-follow-test-with (buffer stream text)
      (let ((before (length (imprimeur-follow-test-scrolls stream))))
        (imprimeur-follow-test-scroll-to "Paragraph 51.")
        (let ((scroll (imprimeur-follow-test-wait-scrolls stream (1+ before))))
          (should (equal (plist-get scroll :line) (imprimeur-follow-test-line text "Paragraph 51.")))
          (should (equal (plist-get scroll :total) (seq-count (lambda (char) (eq char ?\n)) text)))
          (should (equal (plist-get scroll :point) 1))
          (should (natnump (plist-get scroll :seq))))))))

(ert-deftest imprimeur-follow-counts-in-the-widened-buffer ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (narrow-to-region (save-excursion (goto-char (point-min)) (search-forward "Paragraph 40.") (pos-bol))
                        (save-excursion (goto-char (point-min)) (search-forward "Paragraph 55.") (pos-bol)))
      (goto-char (point-min))
      (forward-line 3)
      (let ((before (length (imprimeur-follow-test-scrolls stream))))
        (imprimeur-follow-test-scroll-to "Paragraph 51.")
        (let ((scroll (imprimeur-follow-test-wait-scrolls stream (1+ before))))
          (should (equal (plist-get scroll :line) (imprimeur-follow-test-line text "Paragraph 51.")))
          (should (equal (plist-get scroll :total) (seq-count (lambda (char) (eq char ?\n)) text)))
          (should (equal (plist-get scroll :point) (+ 3 (imprimeur-follow-test-line text "Paragraph 40.")))))))))

(ert-deftest imprimeur-follow-sends-one-event-for-a-burst ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (let ((before (length (imprimeur-follow-test-scrolls stream))))
      ;; No timer can run between these commands.
      (dolist (number '("10" "20" "30" "40" "50"))
        (imprimeur-follow-test-scroll-to (format "Paragraph %s." number)))
      (should (equal (seq-count (lambda (timer) (eq (timer--function timer) #'imprimeur-sync--report))
                                timer-list)
                     1))
      (imprimeur-follow-test-wait-scrolls stream (1+ before))
      (imprimeur-follow-test-settle)
      (should (equal (length (imprimeur-follow-test-scrolls stream)) (1+ before)))
      (should (equal (plist-get (car (last (imprimeur-follow-test-scrolls stream))) :line)
                     (line-number-at-pos (window-start) t))))))

(ert-deftest imprimeur-follow-tells-point-with-the-same-number ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (imprimeur-follow-test-scroll-to "Paragraph 10.")
    (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-scrolls stream)))
    (let* ((before (imprimeur-follow-test-wait-scrolls
                    stream (length (imprimeur-follow-test-scrolls stream))))
           (count (length (imprimeur-follow-test-scrolls stream))))
      (execute-kbd-macro (kbd "C-n"))
      (let ((after (imprimeur-follow-test-wait-scrolls stream (1+ count))))
        (should (equal (plist-get after :line) (plist-get before :line)))
        (should (equal (plist-get after :seq) (plist-get before :seq)))
        (should (equal (plist-get after :point) (1+ (plist-get before :point)))))
      (imprimeur-follow-test-scroll-to "Paragraph 20.")
      (let ((moved (imprimeur-follow-test-wait-scrolls stream (+ 2 count))))
        (should (> (plist-get moved :seq) (plist-get before :seq)))))))

(ert-deftest imprimeur-follow-tells-nothing-when-nothing-moved ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (imprimeur-follow-test-settle)
    (let ((count (length (imprimeur-follow-test-scrolls stream))))
      (execute-kbd-macro (kbd "C-l"))
      (imprimeur-follow-test-settle)
      (should (equal (length (imprimeur-follow-test-scrolls stream)) count)))))

(ert-deftest imprimeur-follow-listens-to-both-hooks ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (should (memq #'imprimeur-sync--window-moved post-command-hook))
    (should (memq #'imprimeur-sync--window-moved window-scroll-functions))
    (imprimeur-follow-test-settle)
    (let ((count (length (imprimeur-follow-test-scrolls stream)))
          (start (save-excursion (goto-char (point-min)) (search-forward "Paragraph 30.") (pos-bol))))
      ;; As redisplay does: the window start is set, and the hook runs.
      (set-window-start nil start)
      (run-hook-with-args 'window-scroll-functions (selected-window) start)
      (should (equal (plist-get (imprimeur-follow-test-wait-scrolls stream (1+ count)) :line)
                     (line-number-at-pos start t))))))

(ert-deftest imprimeur-follow-aligns-a-page-at-each-report ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (imprimeur-follow-test-scroll-to "Paragraph 10.")
    (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-scrolls stream)))
    (imprimeur-follow-test-settle)
    (let* ((count (length (imprimeur-follow-test-scrolls stream)))
           (before (car (last (imprimeur-follow-test-scrolls stream)))))
      (should (equal (imprimeur-follow-test-post buffer "{\"type\":\"ready\",\"rev\":1}") 204))
      (should (equal (imprimeur-follow-test-wait-scrolls stream (1+ count)) before)))))

(ert-deftest imprimeur-follow-goes-by-point-where-no-window-shows-the-source ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (goto-char (point-min))
      (search-forward "Paragraph 33.")
      (set-window-buffer nil (get-buffer-create " *imprimeur-follow-test*"))
      (with-current-buffer buffer
        (let ((count (length (imprimeur-follow-test-scrolls stream))))
          (imprimeur-sync-page-ready)
          (should (equal (plist-get (imprimeur-follow-test-wait-scrolls stream (1+ count)) :line)
                         (imprimeur-follow-test-line text "Paragraph 33."))))))))

;;;; The mode

(ert-deftest imprimeur-follow-is-on-with-a-session-as-the-option-says ()
  (pcase-dolist (`(,option ,on) '((both t) (to-preview t) (nil nil)))
    (let ((imprimeur-scroll-sync option))
      (imprimeur-follow-test-with (buffer stream "Text.\n")
        (should (equal (list option (and imprimeur-follow-mode t)) (list option on)))
        (should (equal (list option (and (memq #'imprimeur-sync--window-moved post-command-hook) t))
                       (list option on)))))))

(ert-deftest imprimeur-follow-needs-a-session ()
  (with-temp-buffer
    (should-error (imprimeur-follow-mode 1) :type 'user-error)
    (should-not imprimeur-follow-mode)
    (should-not (memq #'imprimeur-sync--window-moved post-command-hook))))

(ert-deftest imprimeur-follow-off-sends-nothing-and-on-aligns-at-once ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (imprimeur-follow-test-settle)
    (imprimeur-follow-mode -1)
    (let ((count (length (imprimeur-follow-test-scrolls stream))))
      (should-not (memq #'imprimeur-sync--window-moved post-command-hook))
      (should-not (memq #'imprimeur-sync--window-moved window-scroll-functions))
      (imprimeur-follow-test-scroll-to "Paragraph 30.")
      (imprimeur-follow-test-settle)
      (should (equal (length (imprimeur-follow-test-scrolls stream)) count))
      ;; Nor does a page that reports a revision meanwhile hear of it.
      (should (equal (imprimeur-follow-test-post buffer "{\"type\":\"ready\",\"rev\":1}") 204))
      (imprimeur-follow-test-settle)
      (should (equal (length (imprimeur-follow-test-scrolls stream)) count))
      (imprimeur-follow-mode 1)
      (should (equal (plist-get (imprimeur-follow-test-wait-scrolls stream (1+ count)) :line)
                     (line-number-at-pos (window-start) t))))))

(ert-deftest imprimeur-follow-on-aligns-even-where-the-source-has-not-moved ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (imprimeur-follow-test-scroll-to "Paragraph 30.")
    (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-scrolls stream)))
    (imprimeur-follow-test-settle)
    (let* ((count (length (imprimeur-follow-test-scrolls stream)))
           (seq (plist-get (car (last (imprimeur-follow-test-scrolls stream))) :seq)))
      (imprimeur-follow-mode -1)
      (imprimeur-follow-mode 1)
      (should (> (plist-get (imprimeur-follow-test-wait-scrolls stream (1+ count)) :seq) seq)))))

(ert-deftest imprimeur-follow-survives-a-change-of-major-mode ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (org-mode)
    (should imprimeur-follow-mode)
    (imprimeur-follow-test-settle)
    (let ((count (length (imprimeur-follow-test-scrolls stream))))
      (imprimeur-follow-test-scroll-to "Paragraph 30.")
      (should (equal (plist-get (imprimeur-follow-test-wait-scrolls stream (1+ count)) :line)
                     (line-number-at-pos (window-start) t))))))

(ert-deftest imprimeur-follow-survives-the-death-of-an-indirect-clone ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (kill-buffer (clone-indirect-buffer "clone" nil))
    (should imprimeur-follow-mode)
    (imprimeur-follow-test-settle)
    (let ((count (length (imprimeur-follow-test-scrolls stream))))
      (imprimeur-follow-test-scroll-to "Paragraph 30.")
      (should (equal (plist-get (imprimeur-follow-test-wait-scrolls stream (1+ count)) :line)
                     (line-number-at-pos (window-start) t))))))

(defun imprimeur-follow-test-leftovers ()
  "Return the timers of imprimeur that remain."
  (seq-filter (lambda (timer) (string-prefix-p "imprimeur" (format "%S" (timer--function timer))))
              (append timer-list timer-idle-list)))

(ert-deftest imprimeur-follow-ends-with-the-session ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    ;; A report is armed and has not run when the mode ends.
    (imprimeur-follow-test-scroll-to "Paragraph 30.")
    (should (imprimeur-sync--state-timer imprimeur-sync--state))
    (imprimeur-mode -1)
    (should-not imprimeur-follow-mode)
    (should-not imprimeur-sync--state)
    (should-not (memq #'imprimeur-sync--window-moved post-command-hook))
    (should-not (memq #'imprimeur-sync--window-moved window-scroll-functions))
    (should-not (imprimeur-follow-test-leftovers))))

(ert-deftest imprimeur-follow-ends-with-the-buffer ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (imprimeur-follow-test-scroll-to "Paragraph 30.")
    (should (imprimeur-sync--state-timer imprimeur-sync--state))
    (set-buffer-modified-p nil)
    (kill-buffer buffer)
    (should-not (imprimeur-follow-test-leftovers))))

;;;; On the page

(defmacro imprimeur-follow-test-with-page (spec &rest body)
  "Run BODY with BUFFER showing TEXT and BROWSER, a browser, on no page yet.
SPEC is (BUFFER BROWSER FILE TEXT).  BUFFER visits FILE in the selected
Emacs window, in `imprimeur-mode', with the real pandoc; a Markdown file
has its source positions.  `imprimeur-follow-test-open' loads the page."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,browser ,file ,text) spec))
    `(progn
       (imprimeur-test-require "pandoc")
       (let* ((imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
              (imprimeur-browser-program imprimeur-test-fake-browser)
              (root (repo-test-git-tree (list (cons ,file ,text))))
              (,buffer (find-file-noselect (expand-file-name ,file root))))
         (unwind-protect
             (save-window-excursion
               (switch-to-buffer ,buffer)
               (imprimeur-test-cdp-with-browser ,browser
                 (imprimeur-mode 1)
                 ,@body))
           (with-current-buffer ,buffer (set-buffer-modified-p nil))
           (kill-buffer ,buffer))))))

(defun imprimeur-follow-test-open (browser buffer)
  "Load the page of BUFFER in BROWSER, and wait until it shows a revision."
  (imprimeur-test-cdp-navigate browser (imprimeur-url buffer))
  (imprimeur-test-wait-for
   (lambda () (imprimeur-test-cdp-eval browser "document.documentElement.dataset.revision"))))

(defun imprimeur-follow-test-top (browser text)
  "Return how far BROWSER's page has the block that starts with TEXT from its top.
A page that does not hold it yet has it very far."
  (imprimeur-test-cdp-eval
   browser (format "[...document.querySelectorAll('#imprimeur-main > *')]
.find((block) => block.textContent.trim().startsWith('%s'))?.getBoundingClientRect().top ?? 1e9"
                   text)))

(defun imprimeur-follow-test-wait-top (browser text)
  "Wait until the block that starts with TEXT reaches the top of BROWSER's page."
  (imprimeur-test-wait-for (lambda () (<= (abs (imprimeur-follow-test-top browser text)) 2))))

(defun imprimeur-follow-test-brings-to-top (file text)
  "Check that a command brings Paragraph 51 of FILE, holding TEXT, to the top."
  (imprimeur-follow-test-with-page (buffer browser file text)
    (imprimeur-follow-test-open browser buffer)
    (should (equal (imprimeur-test-cdp-eval browser "window.scrollY") 0))
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    (imprimeur-follow-test-scroll-to "Paragraph 120.")
    (imprimeur-follow-test-wait-top browser "Paragraph 120.")
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-follow-brings-a-paragraph-to-the-top-in-org ()
  (imprimeur-follow-test-brings-to-top "doc.org" (imprimeur-follow-test-paragraphs 150 "* Section %d\n")))

(ert-deftest imprimeur-follow-brings-a-paragraph-to-the-top-in-markdown ()
  (imprimeur-follow-test-brings-to-top "doc.md" (imprimeur-follow-test-paragraphs 150 "# Section %d\n\n")))

(defun imprimeur-follow-test-narrowed (file text)
  "Check that Paragraph 51 of FILE, holding TEXT, reaches the top under narrowing."
  (imprimeur-follow-test-with-page (buffer browser file text)
    (narrow-to-region (save-excursion (goto-char (point-min)) (search-forward "Paragraph 40.") (pos-bol))
                      (save-excursion (goto-char (point-min)) (search-forward "Paragraph 70.") (pos-bol)))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    ;; The page holds the widened buffer.
    (should (imprimeur-test-cdp-eval
             browser "document.getElementById('imprimeur-main').textContent.includes('Paragraph 149.')"))))

(ert-deftest imprimeur-follow-brings-a-paragraph-to-the-top-under-narrowing-in-org ()
  (imprimeur-follow-test-narrowed "doc.org" (imprimeur-follow-test-paragraphs 150 "* Section %d\n")))

(ert-deftest imprimeur-follow-brings-a-paragraph-to-the-top-under-narrowing-in-markdown ()
  (imprimeur-follow-test-narrowed "doc.md" (imprimeur-follow-test-paragraphs 150)))

(ert-deftest imprimeur-follow-aligns-a-view-opened-on-a-scrolled-source ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    ;; The same page loaded again knows nothing, and is aligned again.
    (imprimeur-test-cdp-navigate browser (imprimeur-url buffer))
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-follow-aligns-a-page-that-heard-before-it-showed ()
  ;; This pandoc waits for a file, so that the page has nothing to show until then.
  (let* ((directory (make-temp-file "imprimeur-follow-" t))
         (gate (expand-file-name "gate" directory))
         (imprimeur-pandoc-program (expand-file-name "held-pandoc" directory)))
    (with-temp-file imprimeur-pandoc-program
      (insert "#!/bin/sh\ncase \"$*\" in *--list-highlight-languages*) ;; *)\n"
              (format "while [ ! -e '%s' ]; do sleep 0.05; done ;; esac\n" gate)
              "exec pandoc \"$@\"\n"))
    (set-file-modes imprimeur-pandoc-program #o755)
    (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
      (imprimeur-test-cdp-navigate browser (imprimeur-url buffer))
      (imprimeur-test-wait-for (lambda () (imprimeur--session-clients imprimeur--session)))
      (imprimeur-follow-test-scroll-to "Paragraph 51.")
      (imprimeur-follow-test-settle)
      (should-not (imprimeur-test-cdp-eval browser "document.documentElement.dataset.revision"))
      (write-region "" nil gate nil 'silent)
      (imprimeur-follow-test-wait-top browser "Paragraph 51."))))

(ert-deftest imprimeur-follow-moves-no-page-for-a-later-revision ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    ;; Elsewhere on the page, with no input, so that Emacs hears nothing of it.
    (imprimeur-test-cdp-eval browser "window.scrollTo({ top: 1000, behavior: 'instant' })")
    (save-excursion (goto-char (point-max)) (insert "Paragraph at the end.\n"))
    (imprimeur-test-wait-for
     (lambda () (imprimeur-test-cdp-eval
                 browser "document.getElementById('imprimeur-main').textContent.includes('at the end')")))
    (imprimeur-follow-test-settle)
    (should (equal (imprimeur-test-cdp-eval browser "window.scrollY") 1000))))

(ert-deftest imprimeur-follow-page-keeps-its-place-when-point-alone-moves ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    (imprimeur-test-cdp-eval browser "window.scrollTo({ top: 1000, behavior: 'instant' })")
    (execute-kbd-macro (kbd "C-n"))
    (imprimeur-follow-test-settle)
    (should (equal (imprimeur-test-cdp-eval browser "window.scrollY") 1000))))

(ert-deftest imprimeur-follow-page-does-not-follow-when-off-and-aligns-when-on ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-mode -1)
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-settle)
    (should (equal (imprimeur-test-cdp-eval browser "window.scrollY") 0))
    (imprimeur-follow-mode 1)
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")))

(ert-deftest imprimeur-follow-keeps-the-title-at-the-first-line ()
  ;; The first block comes after the title, and starts at line 3.
  (imprimeur-follow-test-with-page
      (buffer browser "doc.org"
              (concat "#+title: A title\n\n" (imprimeur-follow-test-paragraphs 150)))
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    (imprimeur-follow-test-scroll-to "A title")
    (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") 0)))))

(ert-deftest imprimeur-follow-goes-through-a-long-block-by-proportion ()
  ;; A list is one block, whose lines no anchor tells apart, and here the last.
  (let ((text (concat "Paragraph 1.\n\n"
                      (mapconcat (lambda (number) (format "- Item %d.\n" number)) (number-sequence 1 200) ""))))
    (imprimeur-follow-test-with-page (buffer browser "doc.org" text)
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-follow-test-scroll-to "Item 100.")
      (imprimeur-test-wait-for
       (lambda () (imprimeur-test-cdp-eval
                   browser "(() => {
  const item = [...document.querySelectorAll('li')].find((li) => li.textContent.trim() === 'Item 100.');
  return Math.abs(item.getBoundingClientRect().top) <= 2 * item.getBoundingClientRect().height;
})()"))))))

(ert-deftest imprimeur-follow-goes-by-proportion-without-lines ()
  ;; 100 lines, each paragraph N but the first on the line 2N + 2.
  (let ((text (concat "Paragraph 0.\nOn two lines.\n\n"
                      (mapconcat (lambda (number) (format "Paragraph %d.\n" number))
                                 (number-sequence 1 49) "\n"))))
    (imprimeur-follow-test-with-page (buffer browser "doc.rst" text)
      (imprimeur-follow-test-open browser buffer)
      (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.format") "rst"))
      (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('[data-line]').length") 0))
      (imprimeur-follow-test-scroll-to "Paragraph 24.")
      (should (equal (line-number-at-pos (window-start) t) 50))
      (should (equal (count-lines (point-min) (point-max)) 100))
      (imprimeur-test-wait-for
       (lambda () (<= (abs (- (imprimeur-test-cdp-eval browser "window.scrollY")
                              (/ (imprimeur-test-cdp-eval browser "document.documentElement.scrollHeight")
                                 2.0)))
                      2)))
      ;; The first line is the page's top, not a line's worth below it.
      (imprimeur-follow-test-scroll-to "Paragraph 0.")
      (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") 0))))))

;;; imprimeur-follow-test.el ends here
