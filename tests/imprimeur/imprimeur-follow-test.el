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
;; An edit above the window start, which carries it along with its text, is no move:
;; it tells the new line with the same seq, and the page keeps what it shows at its
;; top through the revision that holds the edit (code review of plan 004).  A move
;; made in the same command counts in a text that the page does not hold yet, and
;; moves it again once it does, unless no page had shown anything then.  Text that
;; goes in at the window start, which stays before it, or that takes away the line
;; there, is such a move, as the source then shows other text at its top.  A window
;; start that a narrowing has left outside it, until redisplay brings it back, counts
;; as the nearer end of the narrowing: no report fails on it, and a page's `ready' is
;; answered and given the jump that waits for it (code review of plan 004).
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
;; line stands for the page's top, above whatever comes before the first block.  The
;; page's map ends with the source's last line, so the document gives the lines of
;; the text that its revision was made from, whatever has been typed since (code
;; review of plan 004).
;;
;; "Page to Emacs" and acceptance 4: a 400 px wheel event moves the window start of the
;; source to the new top block's line, and the page stays there.  A scroll that
;; follows no wheel, key, touch or pointer event moves nothing, nor does one driven
;; from Emacs, even right after such an event: it sends no POST.  Posts keep 50 ms
;; apart, and the last place of a burst is told all the same, unless Emacs moves the
;; page meanwhile.  A message of a page behind Emacs moves nothing, as the page will
;; go where Emacs says.  Acceptance 5: a #id link scrolls the page and sends nothing,
;; and a reader who later comes back to that place is heard.  Acceptance 10: with
;; `imprimeur-follow-mode' off, or `imprimeur-scroll-sync' at `to-preview', a wheel
;; on the page moves nothing.  Acceptance 12: with a section folded in the source, a
;; wheel on the page across it leaves it folded, with the window start on its heading
;; and the page where the reader put it, whatever point does next.
;;
;; Acceptance 5 and "Following": a double-click on "Paragraph 120" puts point on its
;; first line, shows the buffer if it is hidden, reveals a folded parent and flashes
;; the line, whatever the following says; the page does not move for it, unless
;; the source's Emacs window has to scroll to show that line, which no redisplay here
;; makes it do, and then follows that scroll as any other.  A double-click on a link
;; or on a video's controls moves nothing, and follows the link as one click does.
;; One on a banner or on a page without text moves nothing either, and a page that
;; has heard no scroll event, the following being off, knows the source's lines.
;;
;; Acceptance 11 and "Following": M-g v, typed through `execute-kbd-macro' with point
;; in "Paragraph 120", brings that block to the top of the page (±2 px) and marks it
;; for a moment, without animation for a reader who asks for reduced motion, whatever
;; the window start, which stays; a page that nothing shows opens first, and goes
;; there once it shows the text, as Emacs says, unless no browser could start, when
;; no later page goes there.  It sends nothing back, and it is unbound where the
;; mode is off, as in any other buffer, whose M-g keeps its keys.
;;
;; What a page asks reaches its own source, in whichever buffer the reader is (code
;; review of plan 004).

;;; Code:

(require 'ert)
(require 'ert-x)
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

(defun imprimeur-follow-test-command-to (text)
  "Put the line of TEXT at the window start, in a command that is running."
  (let ((imprimeur-follow-test-target text))
    (imprimeur-follow-test-command)))

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

(defun imprimeur-follow-test-run (function)
  "Run FUNCTION in a command, after which the hooks run as after any other."
  (let ((overriding-local-map (define-keymap "<f12>" (lambda () (interactive) (funcall function)))))
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
                   ((10 . "a") 12 (10 . "a") 12 nil)
                   ((10 . "a") 12 (10 . "a") 13 point)
                   ((10 . "a") 12 (11 . "a") 12 move)
                   ((10 . "a") 12 (11 . "a") 13 move)
                   ;; An edit has changed what starts there.
                   ((10 . "a") 12 (10 . "b") 12 move)
                   ((nil . "a") nil (1 . "a") 1 move)
                   ((nil . "a") 12 (10 . "a") 12 move)
                   ((10 . "a") nil (10 . "a") 12 point)))
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

(ert-deftest imprimeur-follow-tells-where-a-narrowing-leaves-the-window-start ()
  ;; A report can come before the redisplay that brings the window start within the
  ;; narrowing, and in batch always does.  Until then it tells the nearer end of the
  ;; narrowing, as a move.
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (pcase-dolist (`(,start ,place) '(("Paragraph 5." "Paragraph 20.")
                                      ("Paragraph 50." "Paragraph 40.")))
      (imprimeur-follow-test-with (buffer stream text)
        (imprimeur-follow-test-scroll-to start)
        (imprimeur-follow-test-wait-scrolls stream 1)
        (let ((before (length (imprimeur-follow-test-scrolls stream)))
              (seq (imprimeur-follow-test-seq buffer)))
          (narrow-to-region (save-excursion (goto-char (point-min)) (search-forward "Paragraph 20.") (pos-bol))
                            (save-excursion (goto-char (point-min)) (search-forward "Paragraph 40.") (pos-bol)))
          (imprimeur-follow-test-run-nothing)
          (let ((scroll (imprimeur-follow-test-wait-scrolls stream (1+ before))))
            (should (equal (plist-get scroll :line) (imprimeur-follow-test-line text place)))
            (should (> (plist-get scroll :seq) seq))))))))

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

(ert-deftest imprimeur-follow-tells-an-edit-above-with-the-same-number ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (goto-char (point-min))
    (search-forward "Paragraph 12.")
    (imprimeur-follow-test-scroll-to "Paragraph 10.")
    (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-scrolls stream)))
    (imprimeur-follow-test-settle)
    (let* ((count (length (imprimeur-follow-test-scrolls stream)))
           (before (car (last (imprimeur-follow-test-scrolls stream))))
           (start (window-start)))
      (imprimeur-follow-test-run
       (lambda () (save-excursion (goto-char (point-min)) (insert "New.\n\nNew.\n\n"))))
      (should (equal (window-start) (+ start 12)))
      (let ((after (imprimeur-follow-test-wait-scrolls stream (1+ count))))
        (should (equal (plist-get after :line) (+ 4 (plist-get before :line))))
        (should (equal (plist-get after :point) (+ 4 (plist-get before :point))))
        (should (equal (plist-get after :total) (+ 4 (plist-get before :total))))
        (should (equal (plist-get after :seq) (plist-get before :seq))))
      ;; And away again, by a command that deletes.
      (imprimeur-follow-test-run
       (lambda () (save-excursion (goto-char (point-min)) (delete-char 12))))
      (should (equal (window-start) start))
      (let ((after (imprimeur-follow-test-wait-scrolls stream (+ 2 count))))
        (should (equal (plist-get after :line) (plist-get before :line)))
        (should (equal (plist-get after :seq) (plist-get before :seq))))
      ;; A command that moves the window start is still told as a move.
      (imprimeur-follow-test-scroll-to "Paragraph 20.")
      (should (> (plist-get (imprimeur-follow-test-wait-scrolls stream (+ 3 count)) :seq)
                 (plist-get before :seq))))))

(ert-deftest imprimeur-follow-moves-again-once-a-page-holds-the-text-of-a-move ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (imprimeur-follow-test-settle)
    (imprimeur-sync-page-ready (buffer-chars-modified-tick))
    (let ((session imprimeur--session)
          (rendered (imprimeur--session-revision imprimeur--session)))
      ;; A move and an edit in one command, once a page has shown something.
      (imprimeur-follow-test-run
       (lambda ()
         (save-excursion (goto-char (point-min)) (insert "New.\n\n"))
         (imprimeur-follow-test-command-to "Paragraph 30.")))
      (let ((count (length (imprimeur-follow-test-scrolls stream))))
        (imprimeur-test-wait-for (lambda () (> (imprimeur--session-revision session) rendered)))
        (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-scrolls stream)))
        (imprimeur-follow-test-settle)
        (let ((seq (imprimeur-follow-test-seq buffer))
              (revision (imprimeur--session-revision session)))
          (ert-info ("a revision older than the latest, from a page that is behind")
            (should (equal (imprimeur-follow-test-post
                            buffer (format "{\"type\":\"ready\",\"rev\":%d}" (1- revision)))
                           204))
            (should (equal (imprimeur-follow-test-seq buffer) seq)))
          (ert-info ("the latest, when the text has gone on since")
            (insert "More.\n\n")
            (imprimeur-sync-page-ready (1- (buffer-chars-modified-tick)))
            (should (equal (imprimeur-follow-test-seq buffer) seq))
            (delete-char -7)
            (imprimeur-test-wait-for
             (lambda () (equal (imprimeur--session-rendered-tick session) (buffer-chars-modified-tick))))
            (imprimeur-follow-test-settle))
          (setq revision (imprimeur--session-revision session))
          (ert-info ("the latest, holding that text")
            (should (equal (imprimeur-follow-test-post
                            buffer (format "{\"type\":\"ready\",\"rev\":%d}" revision))
                           204))
            (should (equal (imprimeur-follow-test-seq buffer) (1+ seq))))
          (ert-info ("once")
            (should (equal (imprimeur-follow-test-post
                            buffer (format "{\"type\":\"ready\",\"rev\":%d}" revision))
                           204))
            (should (equal (imprimeur-follow-test-seq buffer) (1+ seq))))
          (should (>= (length (imprimeur-follow-test-scrolls stream)) (+ count 2))))))))

(ert-deftest imprimeur-follow-tells-nothing-for-an-edit-below ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (imprimeur-follow-test-scroll-to "Paragraph 10.")
    (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-scrolls stream)))
    (imprimeur-follow-test-settle)
    (let ((count (length (imprimeur-follow-test-scrolls stream))))
      (imprimeur-follow-test-run
       (lambda () (save-excursion (goto-char (point-max)) (insert "New.\n"))))
      (imprimeur-follow-test-settle)
      (should (equal (length (imprimeur-follow-test-scrolls stream)) count)))))

(ert-deftest imprimeur-follow-reads-the-top-of-the-window-start ()
  (with-temp-buffer
    (insert "One.\n" (make-string 1000 ?x) "\nTwo.\n")
    (should (equal (imprimeur-sync--top 1) "One."))
    (should (equal (imprimeur-sync--top 3) "e."))
    (should (equal (imprimeur-sync--top 6) (make-string imprimeur-sync--top-length ?x)))
    (should (equal (imprimeur-sync--top (point-max)) ""))
    (narrow-to-region 1 3)
    (should (equal (imprimeur-sync--top 1) "On"))))

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
          (imprimeur-sync-page-ready (buffer-chars-modified-tick))
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

(ert-deftest imprimeur-follow-a-revision-gives-the-lines-it-was-made-from ()
  ;; Not those of the buffer as it is by the time a page fetches the revision.
  (let* ((text (imprimeur-follow-test-paragraphs 3))
         (lines (seq-count (lambda (char) (eq char ?\n)) text))
         (process-environment (cons "IMPRIMEUR_FAKE_PANDOC=slow" process-environment)))
    (imprimeur-follow-test-with (buffer stream text)
      (let* ((session imprimeur--session)
             (base (imprimeur-follow-test-base buffer))
             (document (lambda ()
                         (json-parse-string (nth 2 (imprimeur-test-http-get (car base) (concat (cdr base) "doc")))
                                            :object-type 'plist)))
             (add (lambda (count) (goto-char (point-max)) (insert (make-string count ?\n))))
             (wait-revision (lambda (revision)
                              (imprimeur-test-wait-for (lambda () (= (imprimeur--session-revision session) revision))))))
        (funcall wait-revision 1)
        (should (equal (plist-get (funcall document) :total) lines))
        (let ((imprimeur-render-delay 1000)
              (imprimeur-render-max-delay 1000))
          (ert-info ("typed since the revision, and no render has started")
            (funcall add 2)
            (should (equal (plist-get (funcall document) :rev) 1))
            (should (equal (plist-get (funcall document) :total) lines)))
          (ert-info ("typed while a render runs")
            (let ((imprimeur-render-delay 0))
              (imprimeur--advance session))
            (imprimeur-test-wait-for (lambda () (processp (imprimeur--session-render session))))
            (funcall add 3)
            (funcall wait-revision 2)
            (should (equal (plist-get (funcall document) :total) (+ lines 2))))
          (ert-info ("a failed render, which leaves the revision as it was")
            (let ((process-environment (cons "IMPRIMEUR_FAKE_PANDOC=fail" process-environment))
                  (imprimeur-render-delay 0))
              (imprimeur--advance session))
            (imprimeur-test-wait-for (lambda () (imprimeur--session-error session)))
            (let ((after-failure (funcall document)))
              (should (equal (plist-get after-failure :rev) 2))
              (should (equal (plist-get after-failure :total) (+ lines 2)))))
          (ert-info ("the next revision, which holds all of it")
            (let ((imprimeur-render-delay 0))
              (funcall add 1)
              (imprimeur--advance session))
            (funcall wait-revision 3)
            (should (equal (plist-get (funcall document) :total) (+ lines 6)))))))))

(ert-deftest imprimeur-follow-serves-a-page-whichever-buffer-is-current ()
  ;; The server's filter runs in the buffer that the reader happens to be in.
  (let* ((text (imprimeur-follow-test-paragraphs 60))
         (lines (seq-count (lambda (char) (eq char ?\n)) text)))
    (imprimeur-follow-test-with (buffer stream text)
      (imprimeur-test-wait-for (lambda () (> (imprimeur--session-revision imprimeur--session) 0)))
      (imprimeur-follow-test-settle)
      (let ((window (selected-window))
            (base (imprimeur-follow-test-base buffer))
            (count (length (imprimeur-follow-test-scrolls stream)))
            (start (imprimeur-follow-test-line text "Paragraph 40.")))
        (imprimeur-follow-test-recording-flashes flashes
          (with-temp-buffer
            (insert "Another buffer, of one line.\n")
            (let ((here (point)))
              (ert-info ("the document")
                (should (equal (plist-get
                                (json-parse-string (nth 2 (imprimeur-test-http-get (car base) (concat (cdr base) "doc")))
                                                   :object-type 'plist)
                                :total)
                               lines)))
              (ert-info ("a double-click")
                (should (equal (imprimeur-follow-test-post-goto buffer (imprimeur-follow-test-line text "Paragraph 30."))
                               204)))
              (ert-info ("a scroll")
                (should (equal (imprimeur-follow-test-post-scroll buffer start) 204)))
              (ert-info ("a revision shown")
                (should (equal (imprimeur-follow-test-post buffer "{\"type\":\"ready\",\"rev\":1}") 204)))
              (should (equal (point) here))
              (should (equal (buffer-string) "Another buffer, of one line.\n"))))
          (should (equal (length flashes) 1)))
        (should (with-current-buffer buffer (looking-at-p "Paragraph 30\\.")))
        (should (eq (window-buffer window) buffer))
        (should (equal (window-point window) (with-current-buffer buffer (point))))
        (should (equal (with-current-buffer buffer (line-number-at-pos (window-start window) t)) start))
        ;; That of the source, which a page that reports a revision is told.
        (should (equal (plist-get (imprimeur-follow-test-wait-scrolls stream (1+ count)) :line) start))))))

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

(defun imprimeur-follow-test-jumps (stream)
  "Return the data of the jump events on STREAM, oldest first."
  (mapcar #'cdr (seq-filter (lambda (event) (equal (car event) "jump")) (imprimeur-test-http-events stream))))

(defun imprimeur-follow-test-post-ready (buffer)
  "Report a revision shown, as a page of BUFFER would."
  (should (equal (imprimeur-follow-test-post buffer "{\"type\":\"ready\",\"rev\":1}") 204)))

(ert-deftest imprimeur-follow-jump-sends-point-s-line-in-the-widened-buffer ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (imprimeur-follow-test-post-ready buffer)
      (narrow-to-region (save-excursion (goto-char (point-min)) (search-forward "Paragraph 20.") (pos-bol))
                        (save-excursion (goto-char (point-min)) (search-forward "Paragraph 40.") (pos-bol)))
      (goto-char (point-min))
      (search-forward "Paragraph 30.")
      (execute-kbd-macro (kbd "M-g v"))
      (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-jumps stream)))
      (should (equal (imprimeur-follow-test-jumps stream)
                     (list (format "{\"line\":%d}" (imprimeur-follow-test-line text "Paragraph 30."))))))))

(ert-deftest imprimeur-follow-jump-waits-for-a-page-that-shows-the-text ()
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (goto-char (point-min))
      (search-forward "Paragraph 30.")
      (execute-kbd-macro (kbd "M-g v"))
      (imprimeur-follow-test-settle)
      (should-not (imprimeur-follow-test-jumps stream))
      ;; It goes where point was when the reader asked.
      (goto-char (point-min))
      (imprimeur-follow-test-post-ready buffer)
      (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-jumps stream)))
      (should (equal (imprimeur-follow-test-jumps stream)
                     (list (format "{\"line\":%d}" (imprimeur-follow-test-line text "Paragraph 30.")))))
      ;; After the event that aligns the page, or that would undo it.
      (should (equal (car (car (last (seq-filter (lambda (event) (member (car event) '("scroll" "jump")))
                                                 (imprimeur-test-http-events stream)))))
                     "jump"))
      ;; And once.
      (imprimeur-follow-test-post-ready buffer)
      (imprimeur-follow-test-settle)
      (should (equal (length (imprimeur-follow-test-jumps stream)) 1)))))

(ert-deftest imprimeur-follow-jump-waits-out-a-narrowing-not-yet-redisplayed ()
  ;; A page reporting then, with the window start outside the narrowing, is answered,
  ;; aligned with the narrowing's first line and sent the jump that waits for it.
  (let ((text (imprimeur-follow-test-paragraphs 60)))
    (imprimeur-follow-test-with (buffer stream text)
      (goto-char (point-min))
      (search-forward "Paragraph 30.")
      (execute-kbd-macro (kbd "M-g v"))
      (narrow-to-region (save-excursion (goto-char (point-min)) (search-forward "Paragraph 20.") (pos-bol))
                        (save-excursion (goto-char (point-min)) (search-forward "Paragraph 40.") (pos-bol)))
      (imprimeur-follow-test-post-ready buffer)
      (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-jumps stream)))
      (should (equal (imprimeur-follow-test-jumps stream)
                     (list (format "{\"line\":%d}" (imprimeur-follow-test-line text "Paragraph 30.")))))
      (should (equal (plist-get (car (last (imprimeur-follow-test-scrolls stream))) :line)
                     (imprimeur-follow-test-line text "Paragraph 20."))))))

(ert-deftest imprimeur-follow-jump-waits-for-a-page-just-connected ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (imprimeur-follow-test-post-ready buffer)
    (execute-kbd-macro (kbd "M-g v"))
    (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-jumps stream)))
    ;; A page loaded again, or another one, shows nothing yet.
    (let* ((base (imprimeur-follow-test-base buffer))
           (loaded (imprimeur-test-http-stream (car base) (concat (cdr base) "events"))))
      (imprimeur-test-wait-for (lambda () (assoc "palette" (imprimeur-test-http-events loaded))))
      (execute-kbd-macro (kbd "M-g v"))
      (imprimeur-follow-test-settle)
      (should-not (imprimeur-follow-test-jumps loaded))
      (imprimeur-follow-test-post-ready buffer)
      (imprimeur-test-wait-for (lambda () (imprimeur-follow-test-jumps loaded))))))

(ert-deftest imprimeur-follow-jump-is-bound-where-the-mode-is-on ()
  (with-temp-buffer
    (should-not (eq (key-binding (kbd "M-g v")) #'imprimeur-jump)))
  (should-not (assq 'imprimeur-mode minor-mode-map-alist))
  (imprimeur-follow-test-with (buffer stream "Text.\n")
    (should (eq (key-binding (kbd "M-g v")) #'imprimeur-jump))
    (should (eq (key-binding (kbd "M-g g")) #'goto-line))
    (with-temp-buffer
      (should-not (eq (key-binding (kbd "M-g v")) #'imprimeur-jump))
      (should-error (imprimeur-jump) :type 'user-error))
    (imprimeur-mode -1)
    (should-not (eq (key-binding (kbd "M-g v")) #'imprimeur-jump)))
  (should-not (assq 'imprimeur-mode minor-mode-map-alist)))

(ert-deftest imprimeur-follow-jump-says-that-it-waits ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (ert-with-message-capture messages
      (execute-kbd-macro (kbd "M-g v"))
      (should (string-search "once it shows the text" messages)))
    (imprimeur-follow-test-post-ready buffer)
    (ert-with-message-capture messages
      (execute-kbd-macro (kbd "M-g v"))
      (should-not (string-search "once it shows the text" messages)))))

(ert-deftest imprimeur-follow-jump-keeps-no-line-when-no-browser-starts ()
  (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
    (let ((session imprimeur--session)
          (base (imprimeur-follow-test-base buffer)))
      (delete-process stream)
      (delete-process (imprimeur--session-viewer session))
      (imprimeur-test-wait-for (lambda () (not (imprimeur--session-clients session))))
      (let ((imprimeur-browser-program "/nonexistent/imprimeur-browser"))
        (should-error (imprimeur-jump) :type 'user-error))
      ;; A page that opens for another reason, later, has not been asked for that line.
      (let ((later (imprimeur-test-http-stream (car base) (concat (cdr base) "events"))))
        (imprimeur-test-wait-for (lambda () (assoc "palette" (imprimeur-test-http-events later))))
        (imprimeur-follow-test-post-ready buffer)
        (imprimeur-follow-test-settle)
        (should-not (imprimeur-follow-test-jumps later))))))

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

(ert-deftest imprimeur-follow-an-indirect-clone-leaves-a-report-armed ()
  ;; The death of the clone, or the following turned off in it, cancels nothing of
  ;; the source's: the page would stay behind until the next command there.
  (pcase-dolist (`(,name ,leave)
                 `(("killed" ,#'kill-buffer)
                   ("turned off" ,(lambda (clone)
                                    (with-current-buffer clone (imprimeur-follow-mode -1))))
                   ("its mode ended" ,(lambda (clone)
                                        (with-current-buffer clone (imprimeur-mode -1))))))
    (ert-info (name)
      (imprimeur-follow-test-with (buffer stream (imprimeur-follow-test-paragraphs 60))
        (let ((clone (clone-indirect-buffer " clone" nil)))
          (unwind-protect
              (progn
                (imprimeur-follow-test-settle)
                (let ((count (length (imprimeur-follow-test-scrolls stream))))
                  (imprimeur-follow-test-scroll-to "Paragraph 30.")
                  (should (imprimeur-sync--state-timer imprimeur-sync--state))
                  (funcall leave clone)
                  (should (equal (plist-get (imprimeur-follow-test-wait-scrolls stream (1+ count)) :line)
                                 (line-number-at-pos (window-start) t)))))
            (when (buffer-live-p clone) (kill-buffer clone))))))))

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

(defun imprimeur-follow-test-wait-revision (browser revision)
  "Wait until BROWSER's page shows REVISION, and for what may come after it."
  (imprimeur-test-wait-for
   (lambda () (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.revision")
                     (number-to-string revision))))
  (imprimeur-follow-test-settle)
  (imprimeur-follow-test-wait-still browser))

(defconst imprimeur-follow-test-new-paragraphs "New one.\n\nNew two.\n\nNew three.\n\nNew four.\n\nNew five.\n\n"
  "What the tests of an edit insert, in Org and in Markdown.")

(defun imprimeur-follow-test-edits-above (file text)
  "Check that edits above the window start of FILE, holding TEXT, move nothing."
  (imprimeur-follow-test-with-page (buffer browser file text)
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    (imprimeur-follow-test-settle)
    (let ((seq (imprimeur-follow-test-seq buffer))
          (first (imprimeur-test-cdp-eval browser "document.documentElement.dataset.revision"))
          (inserted (length imprimeur-follow-test-new-paragraphs)))
      (should (equal first "1"))
      (ert-info ("text goes in at the top of the buffer")
        (imprimeur-follow-test-run
         (lambda () (save-excursion (goto-char (point-min)) (insert imprimeur-follow-test-new-paragraphs))))
        (should (looking-at-p "New one\\."))
        (imprimeur-follow-test-wait-revision browser 2)
        (should (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-main').textContent.includes('New five')"))
        (should (<= (abs (imprimeur-follow-test-top browser "Paragraph 51.")) 2))
        (should (save-excursion (goto-char (window-start)) (looking-at-p "Paragraph 51\\.")))
        (should (equal (imprimeur-follow-test-seq buffer) seq)))
      (ert-info ("and goes out, as an undo would take it")
        (imprimeur-follow-test-run
         (lambda () (save-excursion (goto-char (point-min)) (delete-char inserted))))
        (imprimeur-follow-test-wait-revision browser 3)
        (should-not (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-main').textContent.includes('New five')"))
        (should (<= (abs (imprimeur-follow-test-top browser "Paragraph 51.")) 2))
        (should (equal (imprimeur-follow-test-seq buffer) seq)))
      (ert-info ("the source's next move counts in the new text")
        (imprimeur-follow-test-scroll-to "Paragraph 120.")
        (imprimeur-follow-test-wait-top browser "Paragraph 120.")))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-follow-keeps-the-top-of-the-page-through-an-edit-above-in-org ()
  (imprimeur-follow-test-edits-above "doc.org" (imprimeur-follow-test-paragraphs 150 "* Section %d\n")))

(ert-deftest imprimeur-follow-keeps-the-top-of-the-page-through-an-edit-above-in-markdown ()
  (imprimeur-follow-test-edits-above "doc.md" (imprimeur-follow-test-paragraphs 150 "# Section %d\n\n")))

(ert-deftest imprimeur-follow-shows-what-goes-in-at-the-window-start ()
  ;; The window start stays before what goes in at it, which the source then shows at
  ;; its top, and so does the page.
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    (imprimeur-follow-test-settle)
    (imprimeur-follow-test-run
     (lambda () (save-excursion (goto-char (window-start)) (insert imprimeur-follow-test-new-paragraphs))))
    (should (save-excursion (goto-char (window-start)) (looking-at-p "New one\\.")))
    (imprimeur-follow-test-wait-revision browser 2)
    (imprimeur-follow-test-wait-top browser "New one.")))

(ert-deftest imprimeur-follow-shows-what-follows-the-text-of-the-window-start ()
  ;; The window start and what the page knows of it collapse with the text deleted,
  ;; and the page had kept the place of a block that has gone.
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    (imprimeur-follow-test-settle)
    (imprimeur-follow-test-run
     (lambda ()
       (delete-region (save-excursion (goto-char (point-min)) (search-forward "Paragraph 45.") (pos-bol))
                      (save-excursion (goto-char (point-min)) (search-forward "Paragraph 55.") (pos-bol)))))
    (should (save-excursion (goto-char (window-start)) (looking-at-p "Paragraph 55\\.")))
    (imprimeur-follow-test-wait-revision browser 2)
    (imprimeur-follow-test-wait-top browser "Paragraph 55.")))

(ert-deftest imprimeur-follow-keeps-a-place-the-reader-chose-through-an-edit-above ()
  ;; Elsewhere than the source, as the reader may be with the page following alone.
  (let ((imprimeur-scroll-sync 'to-preview))
    (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-follow-test-scroll-to "Paragraph 51.")
      (imprimeur-follow-test-wait-top browser "Paragraph 51.")
      (imprimeur-test-cdp-wheel browser (ceiling (imprimeur-follow-test-top browser "Paragraph 80.")))
      (imprimeur-test-wait-for (lambda () (<= (abs (imprimeur-follow-test-top browser "Paragraph 80.")) 2)))
      (imprimeur-follow-test-wait-still browser)
      (imprimeur-follow-test-run
       (lambda () (save-excursion (goto-char (point-min)) (insert imprimeur-follow-test-new-paragraphs))))
      (imprimeur-follow-test-wait-revision browser 2)
      (should (<= (abs (imprimeur-follow-test-top browser "Paragraph 80.")) 2)))))

(ert-deftest imprimeur-follow-moves-a-page-again-for-a-move-made-with-an-edit ()
  ;; The page goes to that line of the text it holds, one that the edit has moved.
  (let ((text (imprimeur-follow-test-paragraphs 150)))
    (imprimeur-follow-test-with-page (buffer browser "doc.org" text)
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-follow-test-scroll-to "Paragraph 51.")
      (imprimeur-follow-test-wait-top browser "Paragraph 51.")
      (imprimeur-follow-test-settle)
      (imprimeur-follow-test-run
       (lambda ()
         (save-excursion (goto-char (point-min)) (insert imprimeur-follow-test-new-paragraphs))
         (imprimeur-follow-test-command-to "Paragraph 90.")))
      (imprimeur-follow-test-wait-revision browser 2)
      (should (<= (abs (imprimeur-follow-test-top browser "Paragraph 90.")) 2))
      (should (save-excursion (goto-char (window-start)) (looking-at-p "Paragraph 90\\."))))))

(ert-deftest imprimeur-follow-moves-a-page-once-for-a-move-made-without-an-edit ()
  ;; A page shows the text of the move, and no later report moves it again.
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (imprimeur-follow-test-scroll-to "Paragraph 51.")
    (imprimeur-follow-test-wait-top browser "Paragraph 51.")
    (imprimeur-follow-test-settle)
    (let ((seq (imprimeur-follow-test-seq buffer)))
      (should (equal (imprimeur-follow-test-post buffer "{\"type\":\"ready\",\"rev\":1}") 204))
      (should (equal (imprimeur-follow-test-seq buffer) seq)))))

(ert-deftest imprimeur-follow-hears-a-reader-on-a-line-that-an-edit-has-renumbered ()
  ;; The line that the page last told or heard of means another place now.
  (let ((text (imprimeur-follow-test-paragraphs 150)))
    (imprimeur-follow-test-with-page (buffer browser "doc.org" text)
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-follow-test-scroll-to "Paragraph 51.")
      (imprimeur-follow-test-wait-top browser "Paragraph 51.")
      (imprimeur-follow-test-settle)
      (let* ((line (imprimeur-follow-test-line text "Paragraph 51."))
             (earlier (imprimeur-follow-test-line text "Paragraph 40."))
             (lines (- line earlier)))
        ;; Paragraph 40 comes to the line that Paragraph 51 was on.
        (imprimeur-follow-test-run
         (lambda ()
           (save-excursion
             (goto-char (point-min))
             (insert (apply #'concat (make-list (1- lines) "New line.\n")) "\n"))))
        (imprimeur-follow-test-wait-revision browser 2)
        (should (equal (imprimeur-follow-test-line (buffer-string) "Paragraph 40.") line))
        (imprimeur-follow-test-keep-inputs browser)
        (imprimeur-test-cdp-eval
         browser (format "window.scrollTo({ top: window.scrollY + (%s), behavior: 'instant' })"
                         (imprimeur-follow-test-top browser "Paragraph 40.")))
        (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line)))
        (imprimeur-follow-test-stop-inputs browser)))))

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

(defun imprimeur-follow-test-keep-inputs (browser &optional type)
  "Give BROWSER's page an event of TYPE at once, and every 20 ms from then on.
TYPE defaults to pointermove, an input of the reader's, so that a scroll
follows one however loaded the machine is, which it could not be sure of
from a single input.  `imprimeur-follow-test-stop-inputs' ends them."
  (imprimeur-test-cdp-eval
   browser (format "(() => {
  const input = () => window.dispatchEvent(new Event('%s'));
  input();
  window.__inputs = setInterval(input, 20);
})()"
                   (or type "pointermove"))))

(defun imprimeur-follow-test-stop-inputs (browser)
  "End the events of `imprimeur-follow-test-keep-inputs' in BROWSER's page."
  (imprimeur-test-cdp-eval browser "clearInterval(window.__inputs)"))

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

(defun imprimeur-follow-test-burst (browser &rest tops)
  "Scroll BROWSER's page to each of TOPS after an input, with no time between.
The page's clock stands still meanwhile, so that however loaded the machine is,
each scroll but the first comes too soon after the post of the first, and a post
is put off; and nothing comes after them for a later post to tell."
  (imprimeur-test-cdp-eval
   browser (format "(async () => {
  const frames = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  const clock = performance.now;
  const now = clock.call(performance);
  performance.now = () => now;
  window.dispatchEvent(new Event('wheel'));
  for (const top of [%s]) {
    window.scrollTo({ top, behavior: 'instant' });
    await frames();
  }
  performance.now = clock;
})()"
                   (mapconcat #'number-to-string tops ", "))))

(ert-deftest imprimeur-follow-keeps-the-last-place-of-each-burst ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (dolist (burst '((1000 2000) (3000 4000)))
      (apply #'imprimeur-follow-test-burst browser burst)
      (let ((line (imprimeur-test-cdp-eval browser imprimeur-follow-test-top-line)))
        (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line)))))))

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
      (imprimeur-follow-test-keep-inputs browser)
      (imprimeur-test-cdp-eval browser "window.scrollTo({ top: 400, behavior: 'instant' })")
      (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line)))
      (imprimeur-follow-test-stop-inputs browser))))

(ert-deftest imprimeur-follow-drops-a-post-put-off-when-emacs-moves-the-page ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    ;; A post put off, as in a burst, and for long enough; then a move of Emacs's
    ;; that puts the top of the page within a block, whose own line a late post
    ;; would name instead.
    (imprimeur-test-cdp-eval browser "(() => {
  const later = window.setTimeout;
  window.setTimeout = (run, delay) => {
    window.__putOff = true;
    return later(run, delay + 1000);
  };
})()")
    (imprimeur-follow-test-burst browser 1000 2000 3000)
    (should (imprimeur-test-cdp-eval browser "window.__putOff"))
    (goto-char (point-min))
    (search-forward "Paragraph 120.")
    (forward-line 4)
    (let ((inside (line-number-at-pos (pos-bol) t)))
      (imprimeur-follow-test-scroll-to-point)
      (imprimeur-test-wait-for
       (lambda () (<= (imprimeur-follow-test-top browser "Paragraph 120.") -2)))
      ;; For that time and a little more.
      (accept-process-output nil 1.5)
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
        (imprimeur-follow-test-keep-inputs browser type)
        (imprimeur-test-cdp-eval browser (format "window.scrollTo({ top: %d, behavior: 'instant' })" top))
        (imprimeur-test-wait-for (lambda () (equal (imprimeur-test-cdp-eval browser "window.scrollY") top)))
        (let ((line (imprimeur-test-cdp-eval browser imprimeur-follow-test-top-line)))
          (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line))))
        (imprimeur-follow-test-stop-inputs browser)
        ;; The time for the input of this type goes, so that the next type has to count.
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
    (imprimeur-follow-test-stop-inputs browser)
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

(ert-deftest imprimeur-follow-hears-a-reader-back-where-a-link-was-overtaken ()
  (imprimeur-follow-test-with-page
      (buffer browser "doc.md" (concat "[To section 5](#section-5)\n\n" (imprimeur-follow-test-paragraphs 150 "# Section %d\n\n")))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (imprimeur-follow-test-keep-inputs browser)
    ;; The link moves the page, and the reader moves it on before any scroll event,
    ;; so that none ever comes of the place that the link left it in.
    (let ((there (imprimeur-test-cdp-eval browser "(async () => {
  document.querySelector('main a').click();
  const there = window.scrollY;
  window.scrollTo({ top: there + 3000, behavior: 'instant' });
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  return there;
})()")))
      (should (> there 0))
      (let ((line (imprimeur-test-cdp-eval browser imprimeur-follow-test-top-line)))
        (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line))))
      ;; The reader's coming back to that very place is no echo of the link's move.
      (imprimeur-test-cdp-eval browser (format "window.scrollTo({ top: %s, behavior: 'instant' })" there))
      (let ((line (imprimeur-test-cdp-eval browser imprimeur-follow-test-top-line)))
        (imprimeur-test-wait-for (lambda () (equal (line-number-at-pos (window-start) t) line))))
      (imprimeur-follow-test-stop-inputs browser))))

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

(ert-deftest imprimeur-follow-goes-by-proportion-with-the-following-off ()
  ;; A page that has heard no scroll event still knows how long the source is.
  (let ((imprimeur-scroll-sync nil)
        ;; 100 lines, each paragraph N but the first on the line 2N + 2.
        (text (concat "Paragraph 0.\nOn two lines.\n\n"
                      (mapconcat (lambda (number) (format "Paragraph %d.\n" number))
                                 (number-sequence 1 49) "\n"))))
    (imprimeur-follow-test-with-page (buffer browser "doc.rst" text)
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-follow-test-settle)
      (should-not imprimeur-follow-mode)
      (imprimeur-follow-test-recording-flashes flashes
        (imprimeur-follow-test-double-click browser "Paragraph 24.")
        (imprimeur-test-wait-for (lambda () flashes))
        (should (<= 47 (line-number-at-pos nil t) 53)))
      (imprimeur-test-cdp-eval browser "window.scrollTo({ top: 0, behavior: 'instant' })")
      (goto-char (point-min))
      (search-forward "Paragraph 24.")
      (execute-kbd-macro (kbd "M-g v"))
      (imprimeur-test-wait-for
       (lambda () (<= (abs (- (imprimeur-test-cdp-eval browser "window.scrollY")
                              (/ (imprimeur-test-cdp-eval browser "document.documentElement.scrollHeight")
                                 2.0)))
                      2))))))

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

(ert-deftest imprimeur-follow-double-click-on-a-link-follows-it-once ()
  (let ((opened nil))
    (cl-letf (((symbol-function 'browse-url) (lambda (url &rest _) (push url opened))))
      (imprimeur-follow-test-with-page (buffer browser "doc.md" "A [link](https://example.invalid/x) in words.\n")
        (imprimeur-follow-test-open browser buffer)
        (imprimeur-follow-test-settle)
        (imprimeur-test-cdp-click browser "document.querySelector('main a')" nil 2)
        (imprimeur-test-wait-for (lambda () opened))
        (imprimeur-follow-test-settle)
        (should (equal opened '("https://example.invalid/x")))
        ;; The second click takes the page nowhere either.
        (should (equal (imprimeur-test-cdp-eval browser "location.href") (imprimeur-url buffer)))
        ;; A click of its own still follows it.
        (imprimeur-test-cdp-click browser "document.querySelector('main a')")
        (imprimeur-test-wait-for (lambda () (equal (length opened) 2)))))))

(ert-deftest imprimeur-follow-double-click-on-a-fragment-link-moves-nothing ()
  (imprimeur-follow-test-with-page
      (buffer browser "doc.md" (concat "[To section 5](#section-5)\n\n" (imprimeur-follow-test-paragraphs 150 "# Section %d\n\n")))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    (imprimeur-follow-test-recording-flashes flashes
      ;; The first click moves the page, so that the second one lands on something else.
      (imprimeur-test-cdp-click browser "document.querySelector('main a')" nil 2)
      (imprimeur-follow-test-wait-top browser "Section 5")
      (imprimeur-follow-test-settle)
      (should-not (imprimeur-follow-test-posted-of browser "goto"))
      (should-not flashes)
      (should (bobp))
      ;; And a double-click after it is one like any other.
      (imprimeur-follow-test-double-click browser "Paragraph 90.")
      (imprimeur-test-wait-for (lambda () flashes))
      (should (looking-at-p "Paragraph 90\\.")))))

(ert-deftest imprimeur-follow-double-click-on-a-page-without-text-moves-nothing ()
  (let ((imprimeur-pandoc-program imprimeur-test-fake-pandoc)
        (process-environment (cons "IMPRIMEUR_FAKE_PANDOC=fail" process-environment)))
    (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 60))
      (imprimeur-test-cdp-navigate browser (imprimeur-url buffer))
      (imprimeur-test-cdp-wait browser "!document.getElementById('imprimeur-banner').hidden")
      (search-forward "Paragraph 30.")
      (let ((place (point)))
        (imprimeur-follow-test-recording-flashes flashes
          (imprimeur-test-cdp-click browser "document.getElementById('imprimeur-banner')" nil 2)
          ;; With nothing in it, the middle of main is the page around it.
          (imprimeur-test-cdp-click browser "document.getElementById('imprimeur-main')" nil 2)
          (imprimeur-follow-test-settle)
          (should-not (imprimeur-follow-test-posted-of browser "goto"))
          (should-not flashes)
          (should (equal (point) place)))))))

(ert-deftest imprimeur-follow-double-click-on-the-banner-moves-nothing ()
  (let ((imprimeur-pandoc-program imprimeur-test-fake-pandoc)
        (process-environment (cons "IMPRIMEUR_FAKE_PANDOC=warn" process-environment)))
    (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 60))
      (imprimeur-follow-test-open browser buffer)
      (imprimeur-test-cdp-wait browser "!document.getElementById('imprimeur-banner').hidden")
      (imprimeur-follow-test-settle)
      (imprimeur-follow-test-recording-flashes flashes
        (imprimeur-test-cdp-click browser "document.getElementById('imprimeur-banner')" nil 2)
        (imprimeur-follow-test-settle)
        (should-not (imprimeur-follow-test-posted-of browser "goto"))
        (should-not flashes)
        ;; The text beneath it does.
        (imprimeur-test-cdp-click browser "document.querySelector('main p')" nil 2)
        (imprimeur-test-wait-for (lambda () flashes))))))

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
      (imprimeur-follow-test-stop-inputs browser)
      (should (<= (abs (imprimeur-follow-test-top browser "Paragraph 120.")) 2))
      (should (equal (window-start) start))
      (should-not (imprimeur-follow-test-scrolls-posted browser))
      (should-not (imprimeur-test-cdp-errors browser)))))

(ert-deftest imprimeur-follow-jump-brings-point-s-block-to-the-top-in-org ()
  (imprimeur-follow-test-jump "doc.org" (imprimeur-follow-test-paragraphs 150 "* Section %d\n")))

(ert-deftest imprimeur-follow-jump-brings-point-s-block-to-the-top-in-markdown ()
  (imprimeur-follow-test-jump "doc.md" (imprimeur-follow-test-paragraphs 150 "# Section %d\n\n")))

(ert-deftest imprimeur-follow-jump-reaches-a-page-that-opens-after-it ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (goto-char (point-min))
    (search-forward "Paragraph 120.")
    (execute-kbd-macro (kbd "M-g v"))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-wait-top browser "Paragraph 120.")
    (imprimeur-follow-test-settle)
    (should (<= (abs (imprimeur-follow-test-top browser "Paragraph 120.")) 2))))

(ert-deftest imprimeur-follow-jump-reaches-a-page-that-has-connected-again ()
  (imprimeur-follow-test-with-page (buffer browser "doc.org" (imprimeur-follow-test-paragraphs 150))
    (imprimeur-follow-test-open browser buffer)
    (imprimeur-follow-test-settle)
    ;; It reports what it has shown, and not what it has only heard of.
    (should (equal (imprimeur-follow-test-posted-of browser "ready") '((:type "ready" :rev 1))))
    ;; The stream breaks, and the page connects again by itself, with its text.
    (let* ((session imprimeur--session)
           (broken (imprimeur--session-clients session)))
      (should broken)
      (mapc #'delete-process broken)
      (imprimeur-test-wait-for (lambda () (and (imprimeur--session-clients session)
                                               (not (seq-intersection (imprimeur--session-clients session) broken))))))
    (goto-char (point-min))
    (search-forward "Paragraph 120.")
    (execute-kbd-macro (kbd "M-g v"))
    (imprimeur-follow-test-wait-top browser "Paragraph 120.")
    (should (equal (length (imprimeur-follow-test-posted-of browser "ready")) 2))))

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
