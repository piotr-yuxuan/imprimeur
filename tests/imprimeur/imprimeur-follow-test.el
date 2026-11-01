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
;;
;; "Page to Emacs" and acceptance 4: a 400 px wheel event moves the source's window
;; start to the new top block's line, and the page stays there.  A scroll that
;; follows no wheel, key, touch or pointer event moves nothing, nor does one driven
;; from Emacs, even right after such an event: it sends no POST.  A message of a
;; page behind Emacs moves nothing, as the page will go where Emacs says.  Acceptance
;; 5: a #id link scrolls the page and sends nothing.  Acceptance 10: with
;; `imprimeur-follow-mode' off, or `imprimeur-scroll-sync' at `to-preview', a wheel
;; on the page moves nothing.  Acceptance 12: with a section folded in the source, a
;; wheel on the page across it leaves it folded, with the window start on its heading
;; and the page where the reader put it, whatever point does next.
;;
;; Acceptance 5 and "Following": a double-click on "Paragraph 120" puts point on its
;; first line, shows the buffer if it is hidden, reveals a folded parent and flashes
;; the line, whatever the following says, and the page does not move for it; a
;; double-click on a link or on a video's controls moves nothing.
;;
;; Acceptance 11 and "Following": M-g v, typed through `execute-kbd-macro' with point
;; in "Paragraph 120", brings that block to the top of the page (±2 px) and marks it
;; for a moment, without animation for a reader who asks for reduced motion, whatever
;; the window start, which stays; a page that nothing shows opens first.  It sends
;; nothing back, and it is unbound where the mode is off, as in any other buffer.

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
                       (apply #'concat (make-list (% (* 7 (1+ number)) 15) "Another line of this paragraph.\n"))
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

(defun imprimeur-follow-test-scroll-to-point ()
  "Run a command that puts point's line at the window start."
  (let ((overriding-local-map
         (define-keymap "<f12>" (lambda () (interactive) (set-window-start nil (pos-bol))))))
    (execute-kbd-macro [f12])))

(defun imprimeur-follow-test-run-nothing ()
  "Run a command that moves nothing, after which the hooks run all the same."
  (let ((overriding-local-map (define-keymap "<f12>" #'ignore)))
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

(ert-deftest imprimeur-follow-judges-a-page-s-scroll ()
  (pcase-dolist (`(,follow ,option ,seq ,latest ,moves)
                 '((t both 5 5 t)
                   (t nil 5 5 t)
                   (t both 4 5 nil)
                   (t both 6 5 nil)
                   (t both 0 5 nil)
                   (t to-preview 5 5 nil)
                   (nil both 5 5 nil)
                   (nil to-preview 5 5 nil)
                   (nil nil 5 5 nil)))
    (should (equal (list follow option seq latest
                         (imprimeur-sync--follows-page-p follow option seq latest))
                   (list follow option seq latest moves)))))

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
      (imprimeur-follow-test-run-nothing)
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

;;;; From the page to Emacs

(defun imprimeur-follow-test-seq (buffer)
  "Return the number of the last move of the window start of BUFFER."
  (imprimeur-sync--state-seq (buffer-local-value 'imprimeur-sync--state buffer)))

(defun imprimeur-follow-test-post-scroll (buffer line &optional seq)
  "Post a scroll to LINE from a page of BUFFER that has applied SEQ, or the latest."
  (imprimeur-follow-test-post
   buffer (format "{\"type\":\"scroll\",\"line\":%d,\"seq\":%d}"
                  line (or seq (imprimeur-follow-test-seq buffer)))))

(ert-deftest imprimeur-follow-moves-the-window-start-as-a-page-asks ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (imprimeur-follow-test-settle)
      (let ((count (length (imprimeur-follow-test-scrolls stream)))
            (seq (imprimeur-follow-test-seq buffer))
            (line (imprimeur-follow-test-line text "Paragraph 30.")))
        (should (equal (imprimeur-follow-test-post-scroll buffer line) 204))
        (should (equal (line-number-at-pos (window-start) t) line))
        (should (bolp))
        ;; The hooks run, as after any move, and the page hears no echo of its own.
        (imprimeur-follow-test-run-nothing)
        (run-hook-with-args 'window-scroll-functions (selected-window) (window-start))
        (imprimeur-follow-test-settle)
        (should (equal (length (imprimeur-follow-test-scrolls stream)) count))
        (should (equal (imprimeur-follow-test-seq buffer) seq))
        ;; A command of Emacs's own is still told.
        (imprimeur-follow-test-scroll-to "Paragraph 40.")
        (should (equal (plist-get (imprimeur-follow-test-wait-scrolls stream (1+ count)) :seq) (1+ seq)))))))

(ert-deftest imprimeur-follow-keeps-a-page-s-scroll-within-the-narrowing ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (narrow-to-region (save-excursion (goto-char (point-min)) (search-forward "Paragraph 20.") (pos-bol))
                        (save-excursion (goto-char (point-min)) (search-forward "Paragraph 40.") (pos-bol)))
      (imprimeur-follow-test-post-scroll buffer (imprimeur-follow-test-line text "Paragraph 30."))
      (should (equal (line-number-at-pos (window-start) t) (imprimeur-follow-test-line text "Paragraph 30.")))
      (imprimeur-follow-test-post-scroll buffer 1)
      (should (equal (window-start) (point-min)))
      (imprimeur-follow-test-post-scroll buffer 999999999)
      (should (equal (window-start) (save-excursion (goto-char (point-max)) (pos-bol)))))))

(ert-deftest imprimeur-follow-moves-nothing-for-a-page-behind ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (imprimeur-follow-test-scroll-to "Paragraph 10.")
      (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-scrolls stream)))
      (let ((start (window-start))
            (seq (imprimeur-follow-test-seq buffer)))
        (should (equal (imprimeur-follow-test-post-scroll
                        buffer (imprimeur-follow-test-line text "Paragraph 30.") (1- seq))
                       204))
        (should (equal (window-start) start))))))

(ert-deftest imprimeur-follow-moves-nothing-when-off-or-to-the-preview-alone ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (imprimeur-follow-test-settle)
      (let ((start (window-start))
            (line (imprimeur-follow-test-line text "Paragraph 30.")))
        (let ((imprimeur-scroll-sync 'to-preview))
          (should (equal (imprimeur-follow-test-post-scroll buffer line) 204))
          (should (equal (window-start) start)))
        (imprimeur-follow-mode -1)
        (should (equal (imprimeur-follow-test-post-scroll buffer line) 204))
        (should (equal (window-start) start))))))

(ert-deftest imprimeur-follow-moves-nothing-where-no-window-shows-the-source ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (imprimeur-follow-test-settle)
      (set-window-buffer nil (get-buffer-create " *imprimeur-follow-test*"))
      (should (equal (imprimeur-follow-test-post-scroll
                      buffer (imprimeur-follow-test-line text "Paragraph 30."))
                     204)))))

;;;; A double-click

(defmacro imprimeur-follow-test-recording-flashes (flashes &rest body)
  "Run BODY with the positions flashed collected in FLASHES, newest first."
  (declare (indent 1))
  `(let ((,flashes nil))
     (require 'pulse)
     (cl-letf (((symbol-function 'pulse-momentary-highlight-one-line)
                (lambda (&optional position _face) (push position ,flashes))))
       ,@body)))

(defun imprimeur-follow-test-post-goto (buffer line)
  "Post a double-click on LINE from a page of BUFFER."
  (imprimeur-follow-test-post buffer (format "{\"type\":\"goto\",\"line\":%d}" line)))

(ert-deftest imprimeur-follow-goto-puts-point-on-the-line-and-flashes-it ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (imprimeur-follow-test-recording-flashes flashes
        (should (equal (imprimeur-follow-test-post-goto buffer (imprimeur-follow-test-line text "Paragraph 30.")) 204))
        (should (looking-at-p "Paragraph 30\\."))
        (should (equal (window-point) (point)))
        (should (equal flashes (list (point))))))))

(ert-deftest imprimeur-follow-goto-tells-the-pages-of-point-alone ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (imprimeur-follow-test-scroll-to "Paragraph 10.")
      (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-scrolls stream)))
      (imprimeur-follow-test-settle)
      (let* ((count (length (imprimeur-follow-test-scrolls stream)))
             (before (car (last (imprimeur-follow-test-scrolls stream)))))
        (imprimeur-follow-test-post-goto buffer (imprimeur-follow-test-line text "Paragraph 12."))
        (let ((after (imprimeur-follow-test-wait-scrolls stream (1+ count))))
          (should (equal (plist-get after :point) (imprimeur-follow-test-line text "Paragraph 12.")))
          (should (equal (plist-get after :seq) (plist-get before :seq)))
          (should (equal (plist-get after :line) (plist-get before :line))))))))

(ert-deftest imprimeur-follow-goto-works-with-the-following-off ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (imprimeur-follow-mode -1)
      (imprimeur-follow-test-settle)
      (let ((count (length (imprimeur-follow-test-scrolls stream))))
        (imprimeur-follow-test-post-goto buffer (imprimeur-follow-test-line text "Paragraph 30."))
        (should (looking-at-p "Paragraph 30\\."))
        (imprimeur-follow-test-settle)
        (should (equal (length (imprimeur-follow-test-scrolls stream)) count))
        (should-not (imprimeur-sync--state-timer imprimeur-sync--state))))))

(ert-deftest imprimeur-follow-goto-keeps-within-the-narrowing ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (narrow-to-region (save-excursion (goto-char (point-min)) (search-forward "Paragraph 20.") (pos-bol))
                        (save-excursion (goto-char (point-min)) (search-forward "Paragraph 40.") (pos-bol)))
      (imprimeur-follow-test-post-goto buffer (imprimeur-follow-test-line text "Paragraph 30."))
      (should (looking-at-p "Paragraph 30\\."))
      (imprimeur-follow-test-post-goto buffer 1)
      (should (bobp))
      (imprimeur-follow-test-post-goto buffer 999999999)
      (should (eobp)))))

(ert-deftest imprimeur-follow-goto-shows-a-hidden-buffer ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (set-window-buffer nil (get-buffer-create " *imprimeur-follow-test*"))
      (should-not (get-buffer-window buffer))
      (imprimeur-follow-test-post-goto buffer (imprimeur-follow-test-line text "Paragraph 30."))
      (let ((window (get-buffer-window buffer)))
        (should window)
        (should (equal (window-point window)
                       (with-current-buffer buffer
                         (save-excursion (goto-char (point-min)) (search-forward "Paragraph 30.") (pos-bol)))))))))

(ert-deftest imprimeur-follow-goto-moves-point-in-a-window-not-selected ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (let ((source (selected-window)))
        (select-window (split-window))
        (set-window-buffer nil (get-buffer-create " *imprimeur-follow-test*"))
        (imprimeur-follow-test-post-goto buffer (imprimeur-follow-test-line text "Paragraph 30."))
        (should-not (eq (selected-window) source))
        (should (equal (window-point source)
                       (with-current-buffer buffer
                         (save-excursion (goto-char (point-min)) (search-forward "Paragraph 30.") (pos-bol)))))))))

(ert-deftest imprimeur-follow-goto-leaves-a-fold-it-cannot-open ()
  (let ((text "One.\n\nTwo.\n\nThree.\n"))
    (imprimeur-follow-test-with (buffer stream text)
      (let ((overlay (make-overlay (point-min) (point-max))))
        (overlay-put overlay 'invisible t)
        (imprimeur-follow-test-recording-flashes flashes
          (cl-letf (((symbol-function 'org-reveal) (lambda (&rest _) (error "No way"))))
            (should (equal (imprimeur-follow-test-post-goto buffer 3) 204)))
          (should (looking-at-p "Two"))
          (should (equal flashes (list (point)))))))))

(defun imprimeur-follow-test-fold (text)
  "Fold the section of the Org buffer that holds TEXT, with its heading shown."
  (save-excursion
    (goto-char (point-min))
    (search-forward text)
    (org-back-to-heading)
    (org-fold-subtree t)))

(ert-deftest imprimeur-follow-rests-on-the-heading-of-a-fold ()
  (let ((text (imprimeur-follow-test-paragraphs 60 "* Section %d\n")))
    (imprimeur-follow-test-with (buffer stream text)
      (imprimeur-follow-test-fold "Paragraph 30.")
      (imprimeur-follow-test-settle)
      (let ((count (length (imprimeur-follow-test-scrolls stream)))
            (hidden (save-excursion (goto-char (point-min)) (search-forward "Paragraph 30.") (pos-bol))))
        (should (invisible-p hidden))
        (should (equal (imprimeur-follow-test-post-scroll buffer (imprimeur-follow-test-line text "Paragraph 30."))
                       204))
        (should (equal (window-start)
                       (save-excursion (goto-char (point-min)) (search-forward "* Section 2") (pos-bol))))
        (should (invisible-p hidden))
        (imprimeur-follow-test-run-nothing)
        (imprimeur-follow-test-settle)
        (should (equal (length (imprimeur-follow-test-scrolls stream)) count))))))

;;;; The jump

(ert-deftest imprimeur-follow-jump-sends-point-s-line-in-the-widened-buffer ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (narrow-to-region (save-excursion (goto-char (point-min)) (search-forward "Paragraph 20.") (pos-bol))
                        (save-excursion (goto-char (point-min)) (search-forward "Paragraph 40.") (pos-bol)))
      (goto-char (point-min))
      (search-forward "Paragraph 30.")
      (execute-kbd-macro (kbd "M-g v"))
      (imprimeur-test-wait-for (lambda () (assoc "jump" (imprimeur-test-http-events stream))))
      (should (equal (cdr (assoc "jump" (imprimeur-test-http-events stream)))
                     (format "{\"line\":%d}" (imprimeur-follow-test-line text "Paragraph 30.")))))))

(ert-deftest imprimeur-follow-jump-is-bound-where-the-mode-is-on ()
  (with-temp-buffer
    (should-not (eq (key-binding (kbd "M-g v")) #'imprimeur-jump)))
  (should-not (assq 'imprimeur-mode minor-mode-map-alist))
  (imprimeur-follow-test-with (buffer stream "Text.\n")
    (should (eq (key-binding (kbd "M-g v")) #'imprimeur-jump))
    (with-temp-buffer
      (should-not (eq (key-binding (kbd "M-g v")) #'imprimeur-jump))
      (should-error (imprimeur-jump) :type 'user-error))
    (imprimeur-mode -1)
    (should-not (eq (key-binding (kbd "M-g v")) #'imprimeur-jump)))
  (should-not (assq 'imprimeur-mode minor-mode-map-alist)))

(ert-deftest imprimeur-follow-jump-opens-a-page-that-nothing-shows ()
  (imprimeur-follow-test-with (buffer stream "Text.\n")
    (let* ((session imprimeur--session)
           (first (imprimeur--session-viewer session)))
      (delete-process stream)
      (delete-process first)
      (imprimeur-test-wait-for (lambda () (not (imprimeur--session-clients session))))
      (execute-kbd-macro (kbd "M-g v"))
      (should (process-live-p (imprimeur--session-viewer session)))
      (should-not (eq (imprimeur--session-viewer session) first)))))

(ert-deftest imprimeur-follow-jump-opens-no-second-page ()
  (imprimeur-follow-test-with (buffer stream "Text.\n")
    (let* ((session imprimeur--session)
           (first (imprimeur--session-viewer session)))
      (delete-process first)
      (execute-kbd-macro (kbd "M-g v"))
      (should (eq (imprimeur--session-viewer session) first)))))

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

(defconst imprimeur-follow-test-top-line
  "(() => {
  const blocks = [...document.querySelectorAll('#imprimeur-main > [data-line]')];
  return Number(blocks.filter((block) => block.getBoundingClientRect().top <= 0).at(-1).getAttribute('data-line'));
})()"
  "JavaScript giving the line of the last block whose top is at or above the view's.")

(defun imprimeur-follow-test-keep-inputs (browser)
  "Give BROWSER's page an input of the reader's at once, and every 20 ms.
JavaScript's clearInterval(window.__inputs) ends them."
  (imprimeur-test-cdp-eval
   browser "(() => {
  const input = () => window.dispatchEvent(new Event('pointermove'));
  input();
  window.__inputs = setInterval(input, 20);
})()"))

(defun imprimeur-follow-test-wait-still (browser)
  "Wait until the page of BROWSER has stopped moving, and return where it is."
  (let ((last nil))
    (imprimeur-test-wait-for
     (lambda ()
       (let ((now (imprimeur-test-cdp-eval browser "window.scrollY")))
         (prog1 (and (equal now last) now)
           (setq last now)
           (accept-process-output nil 0.1)))))))

(defun imprimeur-follow-test-wheel (file text)
  "Check that a 400 px wheel moves the window start of FILE, holding TEXT."
  (imprimeur-follow-test-with-page (buffer browser file text)
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (let ((seq (imprimeur-follow-test-seq buffer)))
      (imprimeur-test-cdp-wheel browser 400)
      (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") 400)))
      (let ((line (imprimeur-test-cdp-eval browser imprimeur-follow-test-top-line)))
        (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line)))
        ;; Neither view moves on: the page has heard no echo.
        (imprimeur-follow-test-settle)
        (should (equal (imprimeur-test-cdp-eval browser "window.scrollY") 400))
        (should (equal (imprimeur-follow-test-seq buffer) seq))))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-follow-moves-the-source-with-the-wheel-in-org ()
  (imprimeur-follow-test-wheel "doc.org" (imprimeur-follow-test-paragraphs 150 "* Section %d\n")))

(ert-deftest imprimeur-follow-moves-the-source-with-the-wheel-in-markdown ()
  (imprimeur-follow-test-wheel "doc.md" (imprimeur-follow-test-paragraphs 150 "# Section %d\n\n")))

(defun imprimeur-follow-test-posted-of (browser type)
  "Return the messages of TYPE that BROWSER's page has posted, oldest first."
  (seq-filter (lambda (message) (equal (plist-get message :type) type))
              (imprimeur-test-cdp-posted browser ".imprimeur/post")))

(defun imprimeur-follow-test-scrolls-posted (browser)
  "Return the scrolls that BROWSER's page has posted, oldest first."
  (imprimeur-follow-test-posted-of browser "scroll"))

(ert-deftest imprimeur-follow-posts-only-a-new-line ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (imprimeur-test-cdp-wheel browser 400)
    (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") 400)))
    (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-scrolls-posted browser)))
    (imprimeur-follow-test-settle)
    (let ((line (imprimeur-test-cdp-eval browser imprimeur-follow-test-top-line))
          (posts (length (imprimeur-follow-test-scrolls-posted browser))))
      (imprimeur-test-cdp-wheel browser 1)
      (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") 401)))
      (imprimeur-follow-test-settle)
      ;; Unless that pixel happens to reach another block.
      (when (equal (imprimeur-test-cdp-eval browser imprimeur-follow-test-top-line) line)
        (should (equal (length (imprimeur-follow-test-scrolls-posted browser)) posts))))))

(ert-deftest imprimeur-follow-keeps-the-last-place-of-a-burst ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    ;; The second scroll comes within 50 ms of the post of the first, and nothing
    ;; comes after it for a later post to tell.
    (imprimeur-test-cdp-eval browser "(async () => {
  const frames = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  window.dispatchEvent(new Event('wheel'));
  window.scrollTo({ top: 1000, behavior: 'instant' });
  await frames();
  window.scrollTo({ top: 2000, behavior: 'instant' });
  await frames();
})()")
    (let ((line (imprimeur-test-cdp-eval browser imprimeur-follow-test-top-line)))
      (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line))))))

(ert-deftest imprimeur-follow-hears-a-reader-who-goes-back-where-emacs-put-the-page ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    (imprimeur-follow-test-settle)
    (let ((start (window-start))
          (top (imprimeur-test-cdp-eval browser "window.scrollY")))
      (imprimeur-test-cdp-wheel browser 800)
      (imprimeur-test-wait-for (lambda () (not (equal (window-start) start))))
      (imprimeur-follow-test-wait-still browser)
      (imprimeur-follow-test-settle)
      (imprimeur-test-cdp-wheel browser -800)
      (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") top)))
      (imprimeur-test-wait-for (lambda () (equal (window-start) start))))))

(ert-deftest imprimeur-follow-hears-a-reader-who-goes-back-where-the-page-was ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (imprimeur-test-cdp-wheel browser 400)
    (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") 400)))
    (let ((line (imprimeur-test-cdp-eval browser imprimeur-follow-test-top-line)))
      (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line)))
      ;; Emacs moves the page away, and the reader brings it back to the same block.
      (imprimeur-follow-test-scroll-to "Paragraph 120.")
      (imprimeur-follow-test-wait-top browser "Paragraph 120.")
      (imprimeur-follow-test-settle)
      (imprimeur-test-cdp-eval
       browser "window.dispatchEvent(new Event('wheel')); window.scrollTo({ top: 400, behavior: 'instant' })")
      (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line))))))

(ert-deftest imprimeur-follow-drops-a-post-put-off-when-emacs-moves-the-page ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    ;; A post put off, as in a burst; then a move of Emacs's that puts the top of
    ;; the page within a block, whose own line a late post would name instead.
    (imprimeur-test-cdp-eval browser "(async () => {
  const frames = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  window.dispatchEvent(new Event('wheel'));
  window.scrollTo({ top: 1000, behavior: 'instant' });
  await frames();
  window.scrollTo({ top: 2000, behavior: 'instant' });
})()")
    (goto-char (point-min))
    (search-forward "Paragraph 120.")
    (forward-line 4)
    (let ((inside (line-number-at-pos (pos-bol) t)))
      (imprimeur-follow-test-scroll-to-point)
      (imprimeur-test-wait-for
       (lambda () (<= (imprimeur-follow-test-top browser "Paragraph 120.") -2)))
      (imprimeur-follow-test-settle)
      (should (equal (line-number-at-pos (window-start) t) inside)))))

(ert-deftest imprimeur-follow-moves-the-source-with-a-key ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (dolist (type '("rawKeyDown" "keyUp"))
      (imprimeur-test-cdp-call browser "Input.dispatchKeyEvent"
                               `(:type ,type :key "PageDown" :code "PageDown" :windowsVirtualKeyCode 34)))
    (imprimeur-test-wait-for (lambda () (> (imprimeur-test-cdp-eval browser "window.scrollY") 0)))
    (imprimeur-follow-test-wait-still browser)
    (let ((line (imprimeur-test-cdp-eval browser imprimeur-follow-test-top-line)))
      (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line))))))

(ert-deftest imprimeur-follow-takes-each-kind-of-input-as-the-reader-s ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (let ((top 0))
      (dolist (type '("wheel" "keydown" "touchstart" "touchmove" "pointerdown" "pointermove"))
        (setq top (+ top 1000))
        (imprimeur-test-cdp-eval
         browser (format "window.dispatchEvent(new Event('%s')); window.scrollTo({ top: %d, behavior: 'instant' })"
                         type top))
        (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") top)))
        (let ((line (imprimeur-test-cdp-eval browser imprimeur-follow-test-top-line)))
          (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line))))
        ;; Past the time for an input, a scroll is no longer the reader's.
        (imprimeur-test-cdp-eval browser "new Promise((resolve) => setTimeout(resolve, 300))")))))

(ert-deftest imprimeur-follow-moves-the-source-for-no-other-scroll ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (let ((start (window-start)))
      (imprimeur-test-cdp-eval browser "window.scrollTo({ top: 1000, behavior: 'instant' })")
      (imprimeur-follow-test-wait-still browser)
      (imprimeur-follow-test-settle)
      (should (equal (window-start) start))
      (should-not (seq-filter (lambda (message) (equal (plist-get message :type) "scroll"))
                              (imprimeur-test-cdp-posted browser ".imprimeur/post"))))))

(ert-deftest imprimeur-follow-sends-no-post-for-a-scroll-from-emacs ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    (imprimeur-follow-test-settle)
    ;; Even among the reader's inputs, within whose time the scroll then comes.
    (imprimeur-follow-test-keep-inputs browser)
    ;; And within a block, whose own line would be news to Emacs.
    (goto-char (point-min))
    (search-forward "Paragraph 120.")
    (forward-line 4)
    (imprimeur-follow-test-scroll-to-point)
    (imprimeur-test-wait-for (lambda () (<= (imprimeur-follow-test-top browser "Paragraph 120.") -2)))
    (imprimeur-follow-test-settle)
    (imprimeur-test-cdp-eval browser "clearInterval(window.__inputs)")
    (should-not (seq-filter (lambda (message) (equal (plist-get message :type) "scroll"))
                            (imprimeur-test-cdp-posted browser ".imprimeur/post")))))

(ert-deftest imprimeur-follow-follows-a-long-block-from-the-page ()
  (let ((text (concat "Paragraph 1.\n\n"
                      (mapconcat (lambda (number) (format "- Item %d.\n" number)) (number-sequence 1 200) ""))))
    (imprimeur-follow-test-with-page (buffer browser "doc.org" text)
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-follow-test-settle)
      (let ((scroll "(() => {
  const list = document.querySelector('ul');
  return list.getBoundingClientRect().top + window.scrollY + list.offsetHeight / 2;
})()"))
        (imprimeur-test-cdp-wheel browser (imprimeur-test-cdp-eval browser scroll)))
      ;; The middle of the list, which starts at the line 3: about its line 100.
      (imprimeur-test-wait-for (lambda () (< 90 (line-number-at-pos (window-start) t) 115))))))

(ert-deftest imprimeur-follow-moves-the-source-by-proportion-without-lines ()
  (let ((text (mapconcat (lambda (number) (format "Paragraph %d.\n\n" number)) (number-sequence 1 50) "")))
    (imprimeur-follow-test-with-page (buffer browser "doc.rst" text)
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-follow-test-settle)
      (imprimeur-test-cdp-wheel browser 400)
      (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") 400)))
      (let ((line (imprimeur-test-cdp-eval
                   browser "Math.floor(100 * 400 / document.documentElement.scrollHeight)")))
        (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line)))))))

(ert-deftest imprimeur-follow-a-fragment-link-sends-nothing ()
  (imprimeur-follow-test-with-page
      (buffer browser "doc.md" (concat "[To section 5](#section-5)\n\n" (imprimeur-follow-test-paragraphs 150 "# Section %d\n\n")))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (let ((start (window-start))
          (posts (length (imprimeur-test-cdp-posted browser ".imprimeur/post"))))
      (imprimeur-test-cdp-click browser "document.querySelector('main a')")
      (imprimeur-follow-test-wait-top browser "Section 5")
      (imprimeur-follow-test-settle)
      (should (equal (length (imprimeur-test-cdp-posted browser ".imprimeur/post")) posts))
      (should (equal (window-start) start))
      ;; The reader's next move is heard from where the link has led.
      (imprimeur-test-cdp-wheel browser 100)
      (imprimeur-test-wait-for (lambda () (not (equal (window-start) start)))))))

(ert-deftest imprimeur-follow-a-wheel-moves-nothing-when-off-or-to-the-preview-alone ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (let ((start (window-start)))
      (imprimeur-follow-mode -1)
      (imprimeur-test-cdp-wheel browser 400)
      (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") 400)))
      (imprimeur-follow-test-settle)
      (should (equal (window-start) start))
      (imprimeur-follow-mode 1)
      (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") 0)))
      (let ((imprimeur-scroll-sync 'to-preview))
        (imprimeur-test-cdp-wheel browser 400)
        (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") 400)))
        (imprimeur-follow-test-settle)
        (should (equal (window-start) start))
        ;; This way round it follows all the same.
        (imprimeur-follow-test-scroll-to "Paragraph 51.")
        (imprimeur-follow-test-wait-top browser "Paragraph 51.")))))

(ert-deftest imprimeur-follow-a-wheel-across-a-fold-leaves-it-closed ()
  (let ((text (imprimeur-follow-test-paragraphs 150 "* Section %d\n")))
    (imprimeur-follow-test-with-page (buffer browser "doc.org" text)
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-follow-test-fold "Paragraph 90.")
      (imprimeur-follow-test-settle)
      (let ((hidden (save-excursion (goto-char (point-min)) (search-forward "Paragraph 90.") (pos-bol)))
            (seq (imprimeur-follow-test-seq buffer))
            (before "Paragraph 79."))
        (should (invisible-p hidden))
        ;; Just above the section, with no input, then past its heading.
        (imprimeur-test-cdp-eval
         browser (format "window.scrollTo({ top: window.scrollY + (%s), behavior: 'instant' })"
                         (imprimeur-follow-test-top browser before)))
        (imprimeur-test-wait-for (lambda () (<= (abs (imprimeur-follow-test-top browser before)) 2)))
        (imprimeur-follow-test-settle)
        (imprimeur-test-cdp-wheel browser (ceiling (+ 1 (imprimeur-follow-test-top browser "Paragraph 90."))))
        (let ((place (imprimeur-follow-test-wait-still browser)))
          (imprimeur-test-wait-for
           (lambda () (equal (line-number-at-pos (window-start) t)
                             (imprimeur-follow-test-line text "* Section 5"))))
          (should (invisible-p hidden))
          (imprimeur-follow-test-settle)
          (should (equal (imprimeur-test-cdp-eval browser "window.scrollY") place))
          (should (equal (imprimeur-follow-test-seq buffer) seq))
          ;; Nor does point moving pull it back.
          (execute-kbd-macro (kbd "C-n"))
          (imprimeur-follow-test-settle)
          (should (equal (imprimeur-test-cdp-eval browser "window.scrollY") place)))))))

(defun imprimeur-follow-test-block (text)
  "Return JavaScript giving the block of the page that starts with TEXT."
  (format "[...document.querySelectorAll('#imprimeur-main > *')]
.find((block) => block.textContent.trim().startsWith('%s'))"
          text))

(defun imprimeur-follow-test-double-click (browser text)
  "Bring the block that starts with TEXT into BROWSER's view and double-click it."
  (let ((block (imprimeur-follow-test-block text)))
    (imprimeur-test-cdp-eval browser (concat block ".scrollIntoView({ block: 'center' })"))
    (imprimeur-test-cdp-click browser block nil 2)))

(ert-deftest imprimeur-follow-double-click-in-org-reveals-a-folded-parent ()
  (let ((text (imprimeur-follow-test-paragraphs 150 "* Section %d\n")))
    (imprimeur-follow-test-with-page (buffer browser "doc.org" text)
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-follow-test-fold "Paragraph 120.")
      (imprimeur-follow-test-settle)
      (should (invisible-p (save-excursion (goto-char (point-min)) (search-forward "Paragraph 120.") (pos-bol))))
      (imprimeur-follow-test-recording-flashes flashes
        (imprimeur-follow-test-double-click browser "Paragraph 120.")
        (imprimeur-test-wait-for (lambda () flashes))
        (should (equal (line-number-at-pos nil t) (imprimeur-follow-test-line text "Paragraph 120.")))
        (should (bolp))
        (should-not (invisible-p (point)))
        (should (equal (window-point) (point)))
        ;; A second double-click, on what is open already, moves point all the same.
        (imprimeur-follow-test-double-click browser "Paragraph 100.")
        (imprimeur-test-wait-for (lambda () (equal (length flashes) 2)))
        (should (looking-at-p "Paragraph 100\\.")))
      (should-not (imprimeur-test-cdp-errors browser)))))

(ert-deftest imprimeur-follow-double-click-in-markdown-reveals-a-folded-parent ()
  (let ((text (imprimeur-follow-test-paragraphs 150 "# Section %d\n\n")))
    (imprimeur-follow-test-with-page (buffer browser "doc.md" text)
      (imprimeur-follow-test-open browser buffer)
      (setq-local outline-regexp "#+ ")
      (outline-minor-mode 1)
      (outline-hide-sublevels 1)
      (should (invisible-p (save-excursion (goto-char (point-min)) (search-forward "Paragraph 120.") (pos-bol))))
      (imprimeur-follow-test-recording-flashes flashes
        (imprimeur-follow-test-double-click browser "Paragraph 120.")
        (imprimeur-test-wait-for (lambda () flashes))
        (should (equal (line-number-at-pos nil t) (imprimeur-follow-test-line text "Paragraph 120.")))
        (should-not (invisible-p (point)))))))

(ert-deftest imprimeur-follow-double-click-leaves-the-page-in-place ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (imprimeur-follow-test-recording-flashes flashes
      (imprimeur-follow-test-double-click browser "Paragraph 120.")
      (imprimeur-test-wait-for (lambda () flashes))
      (let ((place (imprimeur-test-cdp-eval browser "window.scrollY")))
        (imprimeur-follow-test-settle)
        (should (equal (imprimeur-test-cdp-eval browser "window.scrollY") place))))))

(ert-deftest imprimeur-follow-double-click-goes-by-proportion-without-lines ()
  (let ((text (mapconcat (lambda (number) (format "Paragraph %d.\n\n" number)) (number-sequence 1 50) "")))
    (imprimeur-follow-test-with-page (buffer browser "doc.rst" text)
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-follow-test-settle)
      (imprimeur-follow-test-recording-flashes flashes
        (imprimeur-follow-test-double-click browser "Paragraph 25.")
        (imprimeur-test-wait-for (lambda () flashes))
        ;; About where it is on the page: the line 49, as near as a proportion goes.
        (should (<= 47 (line-number-at-pos nil t) 51))))))

(ert-deftest imprimeur-follow-double-click-on-a-link-or-a-control-moves-nothing ()
  (cl-letf (((symbol-function 'browse-url) #'ignore))
    (imprimeur-follow-test-with-page
        (buffer browser "doc.md"
                (concat "A [link](https://example.invalid/x) in words.\n\n"
                        "<video controls width=\"320\" height=\"180\" src=\"clip.webm\"></video>\n\n"
                        "<audio controls src=\"sound.ogg\"></audio>\n\n"
                        "<details><summary>A summary</summary>Its text.</details>\n\n"
                        "Plain words.\n"))
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-follow-test-settle)
      (imprimeur-follow-test-recording-flashes flashes
        (dolist (element '("main a" "main video" "main audio" "main summary"))
          (imprimeur-test-cdp-click browser (format "document.querySelector('%s')" element) nil 2)
          ;; The middle of a sound's controls keeps its events to itself.
          (imprimeur-test-cdp-eval
           browser (format "document.querySelector('%s').dispatchEvent(new MouseEvent('dblclick', { bubbles: true }))"
                           element))
          (imprimeur-follow-test-settle)
          (should (equal (list element flashes) (list element nil)))
          (should (equal (list element (plist-get (car (imprimeur-follow-test-posted-of browser "goto")) :line))
                         (list element nil))))
        (should (bobp))
        ;; The words themselves do.
        (imprimeur-test-cdp-click browser "[...document.querySelectorAll('main > *')].at(-1)" nil 2)
        (imprimeur-test-wait-for (lambda () flashes))
        (should (looking-at-p "Plain words"))))))

(defun imprimeur-follow-test-jump (file text)
  "Check that M-g v brings Paragraph 120 of FILE, holding TEXT, to the top."
  (imprimeur-follow-test-with-page (buffer browser file text)
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    (imprimeur-follow-test-settle)
    (goto-char (point-min))
    (search-forward "Paragraph 120.")
    (forward-line 3)
    (let ((start (window-start))
          (block (imprimeur-follow-test-block "Paragraph 120.")))
      ;; It sends nothing, even among the reader's inputs.
      (imprimeur-follow-test-keep-inputs browser)
      (execute-kbd-macro (kbd "M-g v"))
      (imprimeur-follow-test-wait-top browser "Paragraph 120.")
      (imprimeur-test-cdp-wait browser (concat block ".classList.contains('imprimeur-flash')"))
      (should (equal (imprimeur-test-cdp-eval browser (format "getComputedStyle(%s).animationName" block))
                     "imprimeur-flash"))
      (imprimeur-test-cdp-wait browser (concat "!" block ".classList.contains('imprimeur-flash')"))
      (imprimeur-follow-test-settle)
      (imprimeur-test-cdp-eval browser "clearInterval(window.__inputs)")
      (should (<= (abs (imprimeur-follow-test-top browser "Paragraph 120.")) 2))
      (should (equal (window-start) start))
      (should-not (imprimeur-follow-test-scrolls-posted browser))
      (should-not (imprimeur-test-cdp-errors browser)))))

(ert-deftest imprimeur-follow-jump-brings-point-s-block-to-the-top-in-org ()
  (imprimeur-follow-test-jump "doc.org" (imprimeur-follow-test-paragraphs 150 "* Section %d\n")))

(ert-deftest imprimeur-follow-jump-brings-point-s-block-to-the-top-in-markdown ()
  (imprimeur-follow-test-jump "doc.md" (imprimeur-follow-test-paragraphs 150 "# Section %d\n\n")))

(ert-deftest imprimeur-follow-jump-marks-without-motion-when-asked ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-test-cdp-call browser "Emulation.setEmulatedMedia"
                             '(:features [(:name "prefers-reduced-motion" :value "reduce")]))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (goto-char (point-min))
    (search-forward "Paragraph 120.")
    (let ((block (imprimeur-follow-test-block "Paragraph 120.")))
      (execute-kbd-macro (kbd "M-g v"))
      (imprimeur-follow-test-wait-top browser "Paragraph 120.")
      (imprimeur-test-cdp-wait browser (concat block ".classList.contains('imprimeur-flash')"))
      (should (equal (imprimeur-test-cdp-eval
                      browser (format "[getComputedStyle(%1$s).animationName, getComputedStyle(%1$s).outlineStyle]"
                                      block))
                     ["none" "solid"]))
      (imprimeur-test-cdp-wait browser (concat "!" block ".classList.contains('imprimeur-flash')")))))

(ert-deftest imprimeur-follow-jump-from-the-end-marks-the-last-block ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (goto-char (point-max))
    (execute-kbd-macro (kbd "M-g v"))
    (imprimeur-test-cdp-wait browser (concat (imprimeur-follow-test-block "Paragraph 150.")
                                             ".classList.contains('imprimeur-flash')"))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-follow-jump-goes-to-the-top-above-the-first-block ()
  (imprimeur-follow-test-with-page
      (buffer browser "doc.org" (concat "#+title: A title\n\n" (imprimeur-follow-test-paragraphs 150)))
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    (goto-char (point-min))
    (execute-kbd-macro (kbd "M-g v"))
    (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") 0)))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-follow-jump-goes-by-proportion-without-lines ()
  (let ((text (concat "Paragraph 0.\nOn two lines.\n\n"
                      (mapconcat (lambda (number) (format "Paragraph %d.\n" number))
                                 (number-sequence 1 49) "\n"))))
    (imprimeur-follow-test-with-page (buffer browser "doc.rst" text)
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-follow-test-settle)
      (goto-char (point-min))
      (search-forward "Paragraph 24.")
      (execute-kbd-macro (kbd "M-g v"))
      (imprimeur-test-wait-for
       (lambda () (<= (abs (- (imprimeur-test-cdp-eval browser "window.scrollY")
                              (/ (imprimeur-test-cdp-eval browser "document.documentElement.scrollHeight")
                                 2.0)))
                      2)))
      (should-not (imprimeur-test-cdp-errors browser)))))

;;; imprimeur-follow-test.el ends here
