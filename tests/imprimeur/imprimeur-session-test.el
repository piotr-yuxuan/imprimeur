;;; imprimeur-session-test.el --- Tests of imprimeur's sessions  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements (plan 002, acceptance 1 to 6 and 8): edits within the
;; quiet delay give one render of the final text, continuous edits render
;; at least once per maximum latency, edits during a render give one more
;; render after it and never two at once, a change of text properties
;; renders nothing, a page connecting triggers the first render; a failure
;; keeps the last good revision and the next good render clears it, even
;; after a pandoc that ended before reading its input; a
;; five-level Org chain gives five heading levels; a buffer without a
;; reader is a user error that starts nothing; killing the buffer ends
;; everything the session owns; a buffer has one session, which survives a
;; change to a mode with a reader, a second enabling and the death of an
;; indirect clone; an edit in an indirect buffer renders; links posted by
;; the page reach `browse-url' or `find-file-other-window' as their target
;; allows, and nothing for a file outside the root, a device, a directory
;; or a file that is neither a document nor media; a compiled copy serves
;; its own assets.
;;
;; Plan 003, acceptance 2, on a 1 MiB file whose byte i is i mod 256:
;; bytes=10-19 gives 206 with Content-Range: bytes 10-19/1048576 and
;; exactly those bytes; bytes=0- 206 with at most 256 KiB; bytes=-500 the
;; last 500 bytes; bytes=5-1, two ranges and bytes=2000000- 416 with
;; Content-Range: bytes */1048576.  Every media answer carries
;; Accept-Ranges: bytes; without Range, a file of 32 MiB or more is
;; refused, and with one it is served.  A GET reads from disk the
;; bytes it sends and no others (plan 003, "Range requests").  RFC 9110,
;; section 14.2, defines ranges for GET alone, so a HEAD with Range gets
;; the head of a GET without one.
;;
;; Plan 003, acceptance 1 and "Palette to the page": a page gets the
;; palette when it connects, even unchanged since the last one sent;
;; switching night to day, three hook calls, sends exactly one palette,
;; with the day colours: the hooks read no face and arm one timer, which
;; reads them once.  Re-enabling the same theme sends none;
;; `imprimeur-refresh-palette' sends a palette that changed otherwise, as
;; by `imprimeur-appearance'.  The hooks stay while a session remains,
;; whichever others end; the last session's end leaves no theme hook and
;; no timer, even one armed by a change of theme.  A write that fails, as
;; to a page closed before Emacs noticed, closes that page alone: the
;; other pages, of its session and of the others, still get the palette,
;; and a session that loses a page so still ends.  The palette depends on
;; the buffer's major mode, so a change of mode that keeps the session sends
;; the palette when that changes it, and nothing otherwise.
;;
;; Plan 003, "Mermaid": the asset mermaid.js is served, as a versioned asset
;; with a JavaScript type, only when found: the regular file that
;; `imprimeur-mermaid-script' names, whatever mmdc offers; or, when that is
;; nil, the copy in the tree of mermaid-cli, from the true name of mmdc,
;; installed as nixpkgs does, a program in bin beside lib, or as npm does, a
;; link in bin into the tree.  The page's shell has data-mermaid exactly
;; when the asset is served; otherwise the asset is refused.
;;
;; Plan 004, "Lines on the page": what pandoc reads for an Org buffer holds its
;; anchors, whatever the narrowing; for a buffer under another reader, the
;; widened text as it is.  A scanner that fails costs the anchors alone: the
;; page gets that revision, and the next edit renders with anchors again.
;;
;; `imprimeur--asset-file': only the names listed have a file, so the asset
;; route answers 404 for a file of the package that is not listed, and for
;; a path that leaves the assets, with .. segments, percent-encoded or not,
;; towards the package's own files or a file elsewhere.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-http)
(require 'imprimeur-test-themes)
(require 'imprimeur)

(ert-deftest imprimeur-session-schedule-decides ()
  (let ((state '(:tick 5 :rendered-tick 4 :rendering nil :clients 1
                 :first-change 10.0 :last-change 10.0 :delay 0.3 :max-delay 2.0)))
    (should (< (abs (- (imprimeur--schedule state 10.1) 0.2)) 1e-9))
    (should (eq (imprimeur--schedule state 10.3) 'render))
    (should (eq (imprimeur--schedule (plist-put (copy-sequence state) :last-change 11.9) 12.0)
                'render))
    (should (eq (imprimeur--schedule (plist-put (copy-sequence state) :rendering t) 11.0) 'idle))
    (should (eq (imprimeur--schedule (plist-put (copy-sequence state) :clients 0) 11.0) 'idle))
    (should (eq (imprimeur--schedule (plist-put (copy-sequence state) :rendered-tick 5) 11.0) 'idle))
    (should (eq (imprimeur--schedule (append '(:first-change nil :last-change nil) state) 10.0)
                'render))))

(defmacro imprimeur-session-test-with (buffer text &rest body)
  "Run BODY with BUFFER visiting a scratch Org file holding TEXT.
The file sits in its own git repository; `imprimeur-mode' is on, with
the fake pandoc, whose behaviour IMPRIMEUR_FAKE_PANDOC in
`process-environment' chooses.  The buffer is killed afterwards."
  (declare (indent 2))
  `(let* ((imprimeur-pandoc-program imprimeur-test-fake-pandoc)
          (imprimeur-browser-program imprimeur-test-fake-browser)
          (imprimeur-render-delay 0.3)
          (root (repo-test-git-tree (list (cons "doc.org" ,text) (cons "pic.png" "PNG!")
                                          (cons "notes.txt" "Notes"))))
          (,buffer (find-file-noselect (expand-file-name "doc.org" root))))
     (unwind-protect
         (progn (with-current-buffer ,buffer (imprimeur-mode 1)) ,@body)
       (when (buffer-live-p ,buffer)
         (with-current-buffer ,buffer (set-buffer-modified-p nil))
         (kill-buffer ,buffer)))))

(defun imprimeur-session-test-port-and-path (buffer)
  "Return (PORT . PATH) of the page of BUFFER."
  (let ((url (url-generic-parse-url (imprimeur-url buffer))))
    (cons (url-port url) (url-filename url))))

(defun imprimeur-session-test-base (buffer)
  "Return the path of the session's internal routes for BUFFER."
  (let ((path (cdr (imprimeur-session-test-port-and-path buffer))))
    (concat (substring path 0 (1+ (string-search "/" path 1))) ".imprimeur/")))

(defun imprimeur-session-test-document (buffer)
  "Fetch the latest revision of the page of BUFFER, as a plist."
  (json-parse-string (nth 2 (imprimeur-test-http-get
                             (car (imprimeur-session-test-port-and-path buffer))
                             (concat (imprimeur-session-test-base buffer) "doc")))
                     :object-type 'plist))

(defun imprimeur-session-test-runs (log)
  "Return the number of pandoc runs recorded in the fake pandoc's LOG."
  (if (file-exists-p log)
      (with-temp-buffer
        (insert-file-contents log)
        (how-many "^start$" (point-min) (point-max)))
    0))

(ert-deftest imprimeur-session-renders-the-final-text-of-a-burst ()
  (let* ((log (make-temp-file "pandoc-log"))
         (process-environment (append (list "IMPRIMEUR_FAKE_PANDOC=echo"
                                            (concat "IMPRIMEUR_FAKE_PANDOC_LOG=" log))
                                      process-environment)))
    (with-current-buffer (get-buffer-create " *imprimeur-log*") (erase-buffer))
    (imprimeur-session-test-with buffer "Hello\n"
      (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                                (concat (imprimeur-session-test-base buffer) "events"))))
        (unwind-protect
            (progn
              (imprimeur-test-wait-for (lambda () (assoc "revision" (imprimeur-test-http-events stream))))
              (should (string-search "Hello" (plist-get (imprimeur-session-test-document buffer) :html)))
              (with-current-buffer buffer
                (goto-char (point-max))
                (dolist (char (string-to-list "0123456789")) (insert char))
                (put-text-property (point-min) (point-max) 'face 'bold))
              (imprimeur-test-wait-for
               (lambda () (string-search "0123456789"
                                         (plist-get (imprimeur-session-test-document buffer) :html))))
              (accept-process-output nil 0.7)
              (should (= (imprimeur-session-test-runs log) 2))
              (should (= (plist-get (imprimeur-session-test-document buffer) :rev) 2)))
          (delete-process stream))))
    (should (equal (with-current-buffer " *imprimeur-log*" (buffer-string)) ""))))

(ert-deftest imprimeur-session-sends-an-org-buffer-with-its-anchors ()
  (let* ((log (make-temp-file "pandoc-log"))
         (process-environment (append (list "IMPRIMEUR_FAKE_PANDOC=echo"
                                            (concat "IMPRIMEUR_FAKE_PANDOC_LOG=" log))
                                      process-environment))
         (sent (lambda ()
                 (with-temp-buffer (insert-file-contents log) (buffer-string)))))
    (imprimeur-session-test-with buffer "* One\n\nWords.\n\n* Two\n"
      ;; Narrowing leaves the page and the lines as they are.
      (with-current-buffer buffer (narrow-to-region 8 14))
      (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                                (concat (imprimeur-session-test-base buffer) "events"))))
        (unwind-protect
            (progn
              (imprimeur-test-wait-for (lambda () (assoc "revision" (imprimeur-test-http-events stream))))
              (should (equal (funcall sent)
                             (concat "start\n#+OPTIONS: H:9\n\n\n#+IMPRIMEUR_LINE: 1\n* One\n\n"
                                     "\n\n#+IMPRIMEUR_LINE: 3\nWords.\n\n"
                                     "\n\n#+IMPRIMEUR_LINE: 5\n* Two\nend\n"))))
          (delete-process stream))))
    ;; Another reader gets the widened text as it is.
    (with-temp-file log)
    (let ((imprimeur-reader-alist '((org-mode . "gfm+sourcepos"))))
      (imprimeur-session-test-with buffer "* One\n\nWords.\n"
        (with-current-buffer buffer (narrow-to-region 8 14))
        (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                                  (concat (imprimeur-session-test-base buffer) "events"))))
          (unwind-protect
              (progn
                (imprimeur-test-wait-for (lambda () (assoc "revision" (imprimeur-test-http-events stream))))
                (should (equal (funcall sent) "start\n* One\n\nWords.\nend\n")))
            (delete-process stream)))))))

(ert-deftest imprimeur-session-renders-when-the-scanner-fails ()
  (let* ((log (make-temp-file "pandoc-log"))
         (process-environment (append (list "IMPRIMEUR_FAKE_PANDOC=echo"
                                            (concat "IMPRIMEUR_FAKE_PANDOC_LOG=" log))
                                      process-environment))
         (sent (lambda ()
                 (with-temp-buffer (insert-file-contents log) (buffer-string)))))
    (imprimeur-session-test-with buffer "* One\n"
      (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                                (concat (imprimeur-session-test-base buffer) "events"))))
        (unwind-protect
            (progn
              (cl-letf (((symbol-function 'imprimeur-sync--closers)
                         (lambda () (error "Failing on purpose"))))
                (imprimeur-test-wait-for (lambda () (assoc "revision" (imprimeur-test-http-events stream))))
                (should (equal (funcall sent) "start\n#+OPTIONS: H:9\n* One\nend\n")))
              (with-current-buffer buffer
                (goto-char (point-max))
                (insert "Two.\n"))
              (imprimeur-test-wait-for
               (lambda () (string-search "#+IMPRIMEUR_LINE: 2\nTwo." (funcall sent)))))
          (delete-process stream))))))

(ert-deftest imprimeur-session-renders-while-typing-continues ()
  (let* ((log (make-temp-file "pandoc-log"))
         (process-environment (append (list (concat "IMPRIMEUR_FAKE_PANDOC_LOG=" log))
                                      process-environment))
         (imprimeur-render-max-delay 1.0))
    (imprimeur-session-test-with buffer "Hello\n"
      (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                                (concat (imprimeur-session-test-base buffer) "events"))))
        (unwind-protect
            (progn
              (imprimeur-test-wait-for (lambda () (assoc "revision" (imprimeur-test-http-events stream))))
              (dotimes (_ 30)
                (with-current-buffer buffer (goto-char (point-max)) (insert "x"))
                (accept-process-output nil 0.1))
              (should (>= (imprimeur-session-test-runs log) 2)))
          (delete-process stream))))))

(ert-deftest imprimeur-session-keeps-the-last-good-revision-on-failure ()
  (let ((process-environment (cons "IMPRIMEUR_FAKE_PANDOC=echo" process-environment)))
    (imprimeur-session-test-with buffer "Good\n"
      (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                                (concat (imprimeur-session-test-base buffer) "events"))))
        (unwind-protect
            (progn
              (imprimeur-test-wait-for (lambda () (assoc "revision" (imprimeur-test-http-events stream))))
              (setq process-environment (cons "IMPRIMEUR_FAKE_PANDOC=fail" process-environment))
              (with-current-buffer buffer (goto-char (point-max)) (insert "Bad\n"))
              (imprimeur-test-wait-for (lambda () (assoc "error" (imprimeur-test-http-events stream))))
              (should (string-search "boom" (cdr (assoc "error" (imprimeur-test-http-events stream)))))
              (let ((document (imprimeur-session-test-document buffer)))
                (should (= (plist-get document :rev) 1))
                (should (string-search "Good" (plist-get document :html)))
                (should (string-search "boom" (plist-get document :error))))
              (setq process-environment (cons "IMPRIMEUR_FAKE_PANDOC=echo" process-environment))
              (with-current-buffer buffer (goto-char (point-max)) (insert "Fixed\n"))
              (imprimeur-test-wait-for
               (lambda () (= (plist-get (imprimeur-session-test-document buffer) :rev) 2)))
              (should (equal (plist-get (imprimeur-session-test-document buffer) :error) "")))
          (delete-process stream))))))

(defun imprimeur-session-test-leftovers ()
  "Return what imprimeur still owns: processes, timers, hook functions."
  (append (seq-filter (lambda (process) (string-prefix-p "imprimeur" (process-name process)))
                      (process-list))
          (seq-filter (lambda (timer) (string-prefix-p "imprimeur" (format "%S" (timer--function timer))))
                      (append timer-list timer-idle-list))
          (seq-filter (lambda (function) (string-prefix-p "imprimeur" (format "%S" function)))
                      (append kill-emacs-hook enable-theme-functions disable-theme-functions))))

(ert-deftest imprimeur-session-killing-the-buffer-ends-everything ()
  (let (port stream)
    (imprimeur-session-test-with buffer "Hello\n"
      (setq port (car (imprimeur-session-test-port-and-path buffer))
            stream (imprimeur-test-http-stream port (concat (imprimeur-session-test-base buffer) "events")))
      (imprimeur-test-wait-for (lambda () (assoc "revision" (imprimeur-test-http-events stream))))
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (kill-buffer buffer)
      (imprimeur-test-wait-for (lambda () (not (process-live-p stream)))))
    (should (assoc "close" (imprimeur-test-http-events stream)))
    (should-not (imprimeur-session-test-leftovers))
    (should-error (imprimeur-test-http-open port) :type 'file-error)))

(defun imprimeur-session-test-palettes (stream)
  "Return the palettes received on STREAM, each (BACKGROUND KEYWORD APPEARANCE)."
  (mapcar (lambda (event)
            (let* ((palette (json-parse-string (cdr event) :object-type 'plist))
                   (css (plist-get palette :css)))
              (list (and (string-match "--emacs-bg: \\([^;]*\\);" css) (match-string 1 css))
                    (and (string-match "--emacs-kw: \\([^;]*\\);" css) (match-string 1 css))
                    (plist-get palette :appearance))))
          (seq-filter (lambda (event) (equal (car event) "palette"))
                      (imprimeur-test-http-events stream))))

(ert-deftest imprimeur-session-sends-a-palette-once-per-change-of-theme ()
  (let* ((reads 0)
         (calls 0)
         (count (lambda (_theme) (setq calls (1+ calls))))
         (read (symbol-function 'imprimeur-palette)))
    (enable-theme 'imprimeur-test-night)
    (unwind-protect
        (cl-letf (((symbol-function 'imprimeur-palette)
                   (lambda (buffer) (setq reads (1+ reads)) (funcall read buffer))))
          (imprimeur-session-test-with buffer "Hello\n"
            (let* ((port (car (imprimeur-session-test-port-and-path buffer)))
                   (events (concat (imprimeur-session-test-base buffer) "events"))
                   (stream (imprimeur-test-http-stream port events))
                   (second nil))
              (unwind-protect
                  (progn
                    (imprimeur-test-wait-for (lambda () (imprimeur-session-test-palettes stream)))
                    ;; A page that connects gets the palette, unchanged as it is.
                    (setq second (imprimeur-test-http-stream port events))
                    (imprimeur-test-wait-for (lambda () (imprimeur-session-test-palettes second)))
                    (should (equal (imprimeur-session-test-palettes second)
                                   '(("#1d1f21" "#aabbcc" "dark"))))
                    (setq reads 0)
                    (let ((timers (length timer-list)))
                      (add-hook 'enable-theme-functions count)
                      (add-hook 'disable-theme-functions count)
                      (disable-theme 'imprimeur-test-night)
                      (enable-theme 'imprimeur-test-day)
                      (remove-hook 'enable-theme-functions count)
                      (remove-hook 'disable-theme-functions count)
                      ;; The hooks read no face; they arm one timer, which will.
                      (should (equal (list calls reads (- (length timer-list) timers)) '(3 0 1))))
                    (imprimeur-test-wait-for (lambda () (cdr (imprimeur-session-test-palettes stream))))
                    (should (= reads 1))
                    (enable-theme 'imprimeur-test-day)
                    (imprimeur-test-wait-for (lambda () (>= reads 2)))
                    (disable-theme 'imprimeur-test-day)
                    (enable-theme 'imprimeur-test-night)
                    (imprimeur-test-wait-for (lambda () (nthcdr 2 (imprimeur-session-test-palettes stream))))
                    (let ((imprimeur-appearance 'light))
                      (imprimeur-refresh-palette))
                    (imprimeur-test-wait-for (lambda () (nthcdr 3 (imprimeur-session-test-palettes stream))))
                    (should (equal (cons reads (imprimeur-session-test-palettes stream))
                                   '(4 ("#1d1f21" "#aabbcc" "dark") ("#ffffff" "#8959a8" "light")
                                       ("#1d1f21" "#aabbcc" "dark") ("#1d1f21" "#aabbcc" "light")))))
                (delete-process stream)
                (when second (delete-process second))))))
      (mapc #'disable-theme '(imprimeur-test-night imprimeur-test-day)))))

(ert-deftest imprimeur-session-sends-a-new-page-the-palette-then-the-revision ()
  ;; So that the first thing a page shows is already in the theme's colours.
  (imprimeur-session-test-with buffer "Hello\n"
    (let* ((port (car (imprimeur-session-test-port-and-path buffer)))
           (events (concat (imprimeur-session-test-base buffer) "events"))
           (first (imprimeur-test-http-stream port events))
           (second nil)
           (kinds (lambda (stream) (mapcar #'car (imprimeur-test-http-events stream)))))
      (unwind-protect
          (progn
            (imprimeur-test-wait-for (lambda () (member "revision" (funcall kinds first))))
            (setq second (imprimeur-test-http-stream port events))
            (imprimeur-test-wait-for (lambda () (member "revision" (funcall kinds second))))
            (should (equal (funcall kinds second) '("palette" "revision"))))
        (delete-process first)
        (when second (delete-process second))))))

(ert-deftest imprimeur-session-end-cancels-a-pending-palette ()
  (unwind-protect
      (imprimeur-session-test-with buffer "Hello\n"
        (enable-theme 'imprimeur-test-day))
    (disable-theme 'imprimeur-test-day))
  (should-not (imprimeur-session-test-leftovers)))

(ert-deftest imprimeur-session-follows-the-theme-while-a-session-remains ()
  (enable-theme 'imprimeur-test-night)
  (unwind-protect
      (imprimeur-session-test-with kept "Kept\n"
        (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path kept))
                                                  (concat (imprimeur-session-test-base kept) "events"))))
          (unwind-protect
              (progn
                (imprimeur-test-wait-for (lambda () (imprimeur-session-test-palettes stream)))
                ;; A second session starts and ends while the first remains.
                (imprimeur-session-test-with ended "Ended\n")
                (disable-theme 'imprimeur-test-night)
                (enable-theme 'imprimeur-test-day)
                (imprimeur-test-wait-for (lambda () (cdr (imprimeur-session-test-palettes stream))))
                (should (equal (imprimeur-session-test-palettes stream)
                               '(("#1d1f21" "#aabbcc" "dark") ("#ffffff" "#8959a8" "light")))))
            (delete-process stream))))
    (mapc #'disable-theme '(imprimeur-test-night imprimeur-test-day)))
  (should-not (imprimeur-session-test-leftovers)))

(defun imprimeur-session-test-breaking (send prefix)
  "Return SEND, `process-send-string', but failing the first write of PREFIX.
It fails as Emacs does on a page closed before it noticed."
  (let ((broken nil))
    (lambda (process string)
      (if (and (not broken) (string-prefix-p prefix string))
          (progn (setq broken t)
                 (error "Process %s no longer connected to pipe; closed it" (process-name process)))
        (funcall send process string)))))

(ert-deftest imprimeur-session-gives-the-palette-to-the-pages-left ()
  (enable-theme 'imprimeur-test-night)
  (unwind-protect
      (imprimeur-session-test-with one "One\n"
        (imprimeur-session-test-with two "Two\n"
          (let ((streams (mapcar (lambda (buffer)
                                   (imprimeur-test-http-stream
                                    (car (imprimeur-session-test-port-and-path buffer))
                                    (concat (imprimeur-session-test-base buffer) "events")))
                                 (list one two two))))
            (unwind-protect
                (progn
                  (dolist (stream streams)
                    (imprimeur-test-wait-for (lambda () (imprimeur-session-test-palettes stream))))
                  (cl-letf (((symbol-function 'process-send-string)
                             (imprimeur-session-test-breaking (symbol-function 'process-send-string)
                                                              "event: palette")))
                    (disable-theme 'imprimeur-test-night)
                    (enable-theme 'imprimeur-test-day)
                    (imprimeur-refresh-palette))
                  (imprimeur-test-wait-for
                   (lambda () (seq-every-p (lambda (stream)
                                             (or (not (process-live-p stream))
                                                 (cdr (imprimeur-session-test-palettes stream))))
                                           streams)))
                  (should (equal (mapcar #'imprimeur-session-test-palettes
                                         (seq-remove #'process-live-p streams))
                                 '((("#1d1f21" "#aabbcc" "dark")))))
                  (should (equal (mapcar #'imprimeur-session-test-palettes
                                         (seq-filter #'process-live-p streams))
                                 (make-list 2 '(("#1d1f21" "#aabbcc" "dark")
                                                ("#ffffff" "#8959a8" "light"))))))
              (mapc #'delete-process streams)))))
    (mapc #'disable-theme '(imprimeur-test-night imprimeur-test-day)))
  (should-not (imprimeur-session-test-leftovers)))

(ert-deftest imprimeur-session-ends-despite-a-page-gone-unnoticed ()
  (imprimeur-session-test-with buffer "Hello\n"
    (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                              (concat (imprimeur-session-test-base buffer) "events"))))
      (unwind-protect
          (progn
            (imprimeur-test-wait-for (lambda () (imprimeur-session-test-palettes stream)))
            (cl-letf (((symbol-function 'process-send-string)
                       (imprimeur-session-test-breaking (symbol-function 'process-send-string)
                                                        "event: close")))
              (with-current-buffer buffer (set-buffer-modified-p nil))
              (kill-buffer buffer))
            (should-not (buffer-live-p buffer))
            (imprimeur-test-wait-for (lambda () (not (process-live-p stream)))))
        (delete-process stream))))
  (should-not (imprimeur-session-test-leftovers)))

(ert-deftest imprimeur-session-survives-a-mode-with-a-reader-only ()
  (imprimeur-session-test-with buffer "Hello\n"
    (with-current-buffer buffer
      (let ((url (imprimeur-url)))
        (org-mode)
        (should imprimeur-mode)
        (should (equal (imprimeur-url) url))
        (text-mode)
        (should-not imprimeur-mode)
        (should-not imprimeur--session))))
  (should-not (imprimeur-session-test-leftovers)))

(ert-deftest imprimeur-session-sends-the-palette-that-a-change-of-mode-changes ()
  (define-derived-mode imprimeur-session-test-other-mode text-mode "Other")
  (enable-theme 'imprimeur-test-day)
  (unwind-protect
      (let ((imprimeur-reader-alist (cons '(imprimeur-session-test-other-mode . "gfm")
                                          imprimeur-reader-alist)))
        (imprimeur-session-test-with buffer "Hello\n"
          (let* ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                                     (concat (imprimeur-session-test-base buffer) "events")))
                 ;; The first level's colour in each palette received: the day
                 ;; theme's `org-level-1' in Org, its `outline-1' in another mode.
                 (headings (lambda ()
                             (mapcar (lambda (event)
                                       (let ((css (plist-get (json-parse-string (cdr event) :object-type 'plist)
                                                             :css)))
                                         (and (string-match "--emacs-h1: \\([^;]*\\);" css)
                                              (match-string 1 css))))
                                     (seq-filter (lambda (event) (equal (car event) "palette"))
                                                 (imprimeur-test-http-events stream))))))
            (unwind-protect
                (progn
                  (imprimeur-test-wait-for (lambda () (funcall headings)))
                  (with-current-buffer buffer (imprimeur-session-test-other-mode))
                  (imprimeur-test-wait-for (lambda () (cdr (funcall headings))))
                  (with-current-buffer buffer (org-mode))
                  (imprimeur-test-wait-for (lambda () (nthcdr 2 (funcall headings))))
                  ;; A mode that reads the same faces changes nothing.
                  (with-current-buffer buffer (org-mode))
                  (accept-process-output nil 0.3)
                  (should (equal (funcall headings) '("#c82821" "#f58711" "#c82821"))))
              (delete-process stream)))))
    (disable-theme 'imprimeur-test-day)))

(ert-deftest imprimeur-session-renders-edits-made-in-an-indirect-buffer ()
  (imprimeur-session-test-with buffer "Hello\n"
    (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                              (concat (imprimeur-session-test-base buffer) "events")))
          (indirect (with-current-buffer buffer (clone-indirect-buffer "indirect" nil))))
      (unwind-protect
          (progn
            (imprimeur-test-wait-for (lambda () (assoc "revision" (imprimeur-test-http-events stream))))
            (with-current-buffer indirect (goto-char (point-max)) (insert "From the indirect buffer\n"))
            (imprimeur-test-wait-for
             (lambda () (string-search "indirect buffer"
                                       (plist-get (imprimeur-session-test-document buffer) :html)))
             5))
        (kill-buffer indirect)
        (delete-process stream)))))

(ert-deftest imprimeur-session-follows-links-as-their-target-allows ()
  (imprimeur-session-test-with buffer "Hello\n"
    (let* ((port (car (imprimeur-session-test-port-and-path buffer)))
           (post (concat (imprimeur-session-test-base buffer) "post"))
           (token (cadr (split-string (cdr (imprimeur-session-test-port-and-path buffer)) "/")))
           (browsed nil) (visited nil))
      (with-temp-file (expand-file-name "other.md" (file-name-directory (buffer-file-name buffer)))
        (insert "# Other\n"))
      (cl-letf (((symbol-function 'browse-url) (lambda (url &rest _) (push url browsed)))
                ((symbol-function 'find-file-other-window) (lambda (file &rest _) (push file visited))))
        (should (equal (car (imprimeur-test-http-post port post "{\"type\":\"ready\",\"rev\":1}")) 204))
        (should (equal (car (imprimeur-test-http-post
                             port post "{\"type\":\"open\",\"url\":\"https://example.org/\"}"))
                       204))
        (should (equal (car (imprimeur-test-http-post
                             port post "{\"type\":\"open\",\"url\":\"javascript:alert(1)\"}"))
                       400))
        (should (equal (car (imprimeur-test-http-post
                             port post (format "{\"type\":\"open\",\"url\":\"http://127.0.0.1:%d/%s/other.md\"}"
                                               port token)))
                       204)))
      (should (equal browsed '("https://example.org/")))
      (should (equal (mapcar #'file-name-nondirectory visited) '("other.md"))))))

(ert-deftest imprimeur-session-serves-the-shell-and-media ()
  (imprimeur-session-test-with buffer "Hello\n"
    (let* ((port (car (imprimeur-session-test-port-and-path buffer)))
           (page (cdr (imprimeur-session-test-port-and-path buffer)))
           (shell (imprimeur-test-http-get port page))
           (directory (file-name-directory page)))
      (should (equal (car shell) 200))
      (should-not (string-search "{{assets}}" (nth 2 shell)))
      (should (string-search (concat (imprimeur-session-test-base buffer) "a/") (nth 2 shell)))
      (should (equal (seq-take (imprimeur-test-http-get port (concat directory "pic.png")) 1) '(200)))
      (should (equal (nth 2 (imprimeur-test-http-get port (concat directory "pic.png"))) "PNG!"))
      (should (equal (car (imprimeur-test-http-get port (concat directory "notes.txt"))) 404))
      (should (string-search "Refused notes.txt"
                             (with-current-buffer " *imprimeur-log*" (buffer-string)))))))

(ert-deftest imprimeur-session-serves-media-by-range ()
  (imprimeur-session-test-with buffer "Hello\n"
    (let* ((port (car (imprimeur-session-test-port-and-path buffer)))
           (directory (file-name-directory (cdr (imprimeur-session-test-port-and-path buffer))))
           (root (file-name-directory (buffer-file-name buffer)))
           (size 1048576)
           (bytes (apply #'concat (make-list (/ size 256) (apply #'unibyte-string
                                                                 (number-sequence 0 255)))))
           (big (* 32 1024 1024))
           (original (symbol-function 'insert-file-contents-literally))
           (spans nil))
      ;; Byte i of ramp.webm is i mod 256.
      (let ((coding-system-for-write 'no-conversion))
        (write-region bytes nil (expand-file-name "ramp.webm" root) nil 'silent))
      ;; A sparse file of exactly 32 MiB, whose last byte is "x".
      (write-region "x" nil (expand-file-name "big.webm" root) (1- big) 'silent)
      ;; Each read of a .webm file is recorded as the span [BEG, END) it covers.
      (cl-letf (((symbol-function 'insert-file-contents-literally)
                 (lambda (file &optional visit beg end replace)
                   (when (string-suffix-p ".webm" file)
                     (push (list (or beg 0) (or end (file-attribute-size (file-attributes file))))
                           spans))
                   (funcall original file visit beg end replace))))
        (dolist (case `((nil 200 nil 0 ,size)
                        ("bytes=10-19" 206 "bytes 10-19/1048576" 10 20)
                        ("bytes=-500" 206 "bytes 1048076-1048575/1048576" ,(- size 500) ,size)
                        ("bytes=5-1" 416 "bytes */1048576" 0 0)
                        ("bytes=0-1,5-6" 416 "bytes */1048576" 0 0)
                        ("bytes=2000000-" 416 "bytes */1048576" 0 0)))
          (setq spans nil)
          (pcase-let* ((`(,range ,status ,content-range ,start ,end) case)
                       (`(,got-status ,headers ,body)
                        (apply #'imprimeur-test-http-get port (concat directory "ramp.webm")
                               (and range (list (concat "Range: " range))))))
            (should (equal (list range got-status (cdr (assoc "content-range" headers))
                                 (cdr (assoc "accept-ranges" headers))
                                 (equal (string-to-unibyte body) (substring bytes start end))
                                 spans)
                           (list range status content-range "bytes" t
                                 (and (< start end) `((,start ,end))))))))
        (setq spans nil)
        (pcase-let ((`(,status ,headers ,body)
                     (imprimeur-test-http-get port (concat directory "ramp.webm") "Range: bytes=0-")))
          (should (<= 1 (length body) 262144))
          (should (equal (list status (cdr (assoc "content-range" headers))
                               (equal (string-to-unibyte body) (substring bytes 0 (length body)))
                               spans)
                         (list 206 (format "bytes 0-%d/1048576" (1- (length body))) t
                               `((0 ,(length body)))))))
        (setq spans nil)
        (should (equal (list (car (imprimeur-test-http-get port (concat directory "big.webm"))) spans)
                       '(404 nil)))
        (pcase-let ((`(,status ,headers ,body)
                     (imprimeur-test-http-get port (concat directory "big.webm")
                                              (format "Range: bytes=%d-" (1- big)))))
          (should (equal (list status (cdr (assoc "content-range" headers)) body spans)
                         (list 206 (format "bytes %d-%d/%d" (1- big) (1- big) big) "x"
                               `((,(1- big) ,big))))))
        (dolist (name '("ramp.webm" "big.webm"))
          (let ((head (imprimeur-test-http
                       port (format "HEAD %s%s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nRange: bytes=0-9\r\n\r\n"
                                    directory name port)))
                (get (imprimeur-test-http-get port (concat directory name))))
            (should (equal (cons name head) (list name (car get) (nth 1 get) "")))))))))

(ert-deftest imprimeur-session-compiled-copy-finds-its-own-assets ()
  "A copy compiled elsewhere must not hold the build directory's path."
  (let* ((copy (expand-file-name "imprimeur/" (make-temp-file "copy" t))))
    (copy-directory (expand-file-name "imprimeur" repo-test-root) copy nil t t)
    (let ((compile (repo-test-emacs
                    (list "-L" copy "--eval"
                          (format "(dolist (file (directory-files %S t \"\\\\.el\\\\'\")) (byte-compile-file file))"
                                  copy)))))
      (should (equal (car compile) 0)))
    (should (equal (repo-test-emacs (list "-L" copy "-l" "imprimeur-render"
                                          "--eval" "(princ imprimeur-render-assets)"))
                   (cons 0 (directory-file-name (expand-file-name "assets" copy)))))
    ;; The copy's own runtime, marked, is the one its server sends.
    (with-temp-buffer
      (insert "// The compiled copy's runtime.\n")
      (append-to-file (point-min) (point-max) (expand-file-name "assets/js/runtime.mjs" copy)))
    (let ((served (repo-test-emacs
                   (list "-L" copy "-L" (expand-file-name "tests/helpers" repo-test-root)
                         "-l" "imprimeur" "-l" "imprimeur-test-http" "--eval"
                         (format "(let* ((imprimeur-pandoc-program %S) (imprimeur-browser-program %S)
       (buffer (find-file-noselect (expand-file-name \"doc.org\" (make-temp-file \"doc\" t))))
       (session (progn (with-current-buffer buffer (imprimeur-mode 1))
                       (buffer-local-value 'imprimeur--session buffer))))
  (princ (nth 2 (imprimeur-test-http-get
                 (imprimeur-server-start)
                 (format \"/%%s/.imprimeur/a/%%s/js/runtime.mjs\"
                         (imprimeur--session-token session) imprimeur--asset-version))))
  (with-current-buffer buffer (set-buffer-modified-p nil))
  (kill-buffer buffer))"
                                 imprimeur-test-fake-pandoc imprimeur-test-fake-browser)))))
      (should (equal (car served) 0))
      (should (string-search "// The compiled copy's runtime." (cdr served))))))

(ert-deftest imprimeur-session-serves-the-mermaid-script-when-found ()
  (let* ((tree "lib/node_modules/@mermaid-js/mermaid-cli/node_modules/mermaid/dist/mermaid.min.js")
         (cli "lib/node_modules/@mermaid-js/mermaid-cli/src/cli.js")
         (scratch (repo-test-tree (list (cons "own.js" "// The named file.\n")
                                        (cons "nix/bin/mmdc" "#!/bin/sh\n")
                                        (cons (concat "nix/" tree) "// The copy of nixpkgs.\n")
                                        (cons (concat "npm/" cli) "#!/bin/sh\n")
                                        (cons (concat "npm/" tree) "// The copy of npm.\n")
                                        (cons "alone/bin/mmdc" "#!/bin/sh\n"))))
         (in (lambda (name) (expand-file-name name scratch))))
    (dolist (file '("nix/bin/mmdc" "alone/bin/mmdc"))
      (set-file-modes (funcall in file) #o755))
    (set-file-modes (funcall in (concat "npm/" cli)) #o755)
    (make-directory (funcall in "npm/bin"))
    (make-symbolic-link (concat "../" cli) (funcall in "npm/bin/mmdc"))
    (make-directory (funcall in "profile/bin") t)
    (make-symbolic-link "../../nix/bin/mmdc" (funcall in "profile/bin/mmdc"))
    (make-directory (funcall in "empty"))
    (imprimeur-session-test-with buffer "* A\n"
      (let* ((port (car (imprimeur-session-test-port-and-path buffer)))
             (page (cdr (imprimeur-session-test-port-and-path buffer)))
             (asset (format "%sa/%s/mermaid.js" (imprimeur-session-test-base buffer) imprimeur--asset-version)))
        ;; The option, the directory on the path, and the text served or nil.
        (pcase-dolist (`(,script ,directory ,text)
                       `((,(funcall in "own.js") "empty" "// The named file.\n")
                         (,(funcall in "own.js") "nix/bin" "// The named file.\n")
                         (,(funcall in "missing.js") "nix/bin" nil)
                         (,(funcall in "empty") "nix/bin" nil)
                         (nil "nix/bin" "// The copy of nixpkgs.\n")
                         (nil "profile/bin" "// The copy of nixpkgs.\n")
                         (nil "npm/bin" "// The copy of npm.\n")
                         (nil "alone/bin" nil)
                         (nil "empty" nil)))
          (let* ((imprimeur-mermaid-script script)
                 (exec-path (list (funcall in directory)))
                 (response (imprimeur-test-http-get port asset))
                 (shell (nth 2 (imprimeur-test-http-get port page)))
                 (case (list script directory)))
            (should (equal (list case (and (string-match-p "<html[^>]* data-mermaid>" shell) t))
                           (list case (and text t))))
            (should-not (string-search "{{mermaid}}" shell))
            (should (equal (cons case (car response)) (cons case (if text 200 404))))
            (when text
              (should (equal (nth 2 response) text))
              (should (equal (cdr (assoc "content-type" (nth 1 response))) "text/javascript; charset=utf-8"))
              (should (equal (cdr (assoc "cache-control" (nth 1 response))) "max-age=31536000, immutable")))))))))

(ert-deftest imprimeur-session-serves-only-the-listed-assets ()
  (imprimeur-session-test-with buffer "* A\n"
    (let* ((port (car (imprimeur-session-test-port-and-path buffer)))
           (assets (format "%sa/%s/" (imprimeur-session-test-base buffer) imprimeur--asset-version))
           ;; Elsewhere, and named as a listed asset is.
           (outside (expand-file-name "runtime.mjs" (make-temp-file "outside" t)))
           (to-outside (file-relative-name outside imprimeur-render-assets))
           (above (apply #'concat (make-list 32 "../"))))
      (write-region "// Elsewhere.\n" nil outside nil 'silent)
      (should (equal (car (imprimeur-test-http-get port (concat assets "js/runtime.mjs"))) 200))
      ;; Files of the package that are not listed, then ways out of its assets.
      (dolist (name (list "pandoc/filters/imprimeur.lua" "page/index.html" "vendor/dompurify/LICENSE"
                          "js" "js/" "no-such-file"
                          "../imprimeur.el" "js/../../imprimeur.el" "js/runtime.mjs/../../../imprimeur.el"
                          "%2e%2e/imprimeur.el" "..%2fimprimeur.el" "%2E%2E%2Fimprimeur.el"
                          to-outside (concat above (substring outside 1))
                          (string-replace ".." "%2e%2e" to-outside)
                          (concat "/" (substring outside 1))))
        (should (equal (cons name (car (imprimeur-test-http-get port (concat assets name))))
                       (cons name 404)))))))

(defun imprimeur-session-test-pandoc-processes ()
  "Return the number of pandoc processes that imprimeur runs."
  (seq-count (lambda (process)
               (and (process-live-p process)
                    (string-match-p "\\`imprimeur-pandoc\\(?:<[0-9]+>\\)?\\'" (process-name process))))
             (process-list)))

(ert-deftest imprimeur-session-renders-edits-made-during-a-render-once-after-it ()
  (let* ((log (make-temp-file "pandoc-log"))
         (process-environment (append (list "IMPRIMEUR_FAKE_PANDOC=slow"
                                            (concat "IMPRIMEUR_FAKE_PANDOC_LOG=" log))
                                      process-environment))
         (most 0))
    (imprimeur-session-test-with buffer "Hello\n"
      (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                                (concat (imprimeur-session-test-base buffer) "events"))))
        (unwind-protect
            (progn
              (imprimeur-test-wait-for (lambda () (assoc "revision" (imprimeur-test-http-events stream))))
              (with-current-buffer buffer (goto-char (point-max)) (insert "a"))
              (imprimeur-test-wait-for (lambda () (= (imprimeur-session-test-pandoc-processes) 1)))
              (with-current-buffer buffer (insert "b") (insert "c"))
              (imprimeur-test-wait-for
               (lambda ()
                 (setq most (max most (imprimeur-session-test-pandoc-processes)))
                 (string-search "Hello\nabc" (plist-get (imprimeur-session-test-document buffer) :html))))
              (accept-process-output nil 1.5)
              (should (= most 1))
              (should (= (imprimeur-session-test-runs log) 3)))
          (delete-process stream))))))

(ert-deftest imprimeur-session-recovers-from-a-pandoc-that-exits-before-reading ()
  "More text than a pipe holds lets pandoc end while it is being written."
  (let ((process-environment (cons "IMPRIMEUR_FAKE_PANDOC=early" process-environment)))
    (imprimeur-session-test-with buffer (make-string (* 200 1024) ?x)
      (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                                (concat (imprimeur-session-test-base buffer) "events")))
            (session (buffer-local-value 'imprimeur--session buffer)))
        (unwind-protect
            (progn
              (imprimeur-test-wait-for (lambda () (assoc "error" (imprimeur-test-http-events stream))))
              (setq process-environment (cons "IMPRIMEUR_FAKE_PANDOC=echo" process-environment))
              (with-current-buffer buffer (goto-char (point-max)) (insert "y"))
              (imprimeur-test-wait-for (lambda () (assoc "revision" (imprimeur-test-http-events stream))))
              (imprimeur-test-wait-for (lambda () (null (imprimeur--session-render session)))))
          (delete-process stream))))))

(ert-deftest imprimeur-session-renders-nothing-for-a-change-of-text-properties ()
  (let* ((log (make-temp-file "pandoc-log"))
         (process-environment (append (list "IMPRIMEUR_FAKE_PANDOC=echo"
                                            (concat "IMPRIMEUR_FAKE_PANDOC_LOG=" log))
                                      process-environment)))
    (imprimeur-session-test-with buffer "Hello\n"
      (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                                (concat (imprimeur-session-test-base buffer) "events"))))
        (unwind-protect
            (progn
              (imprimeur-test-wait-for (lambda () (assoc "revision" (imprimeur-test-http-events stream))))
              (with-current-buffer buffer (put-text-property (point-min) (point-max) 'face 'bold))
              ;; Longer than the quiet delay and the period of the check.
              (accept-process-output nil 1.5)
              (should (= (imprimeur-session-test-runs log) 1)))
          (delete-process stream))))))

(ert-deftest imprimeur-session-renders-a-deep-org-chain-as-headings ()
  (imprimeur-test-require "pandoc")
  (imprimeur-session-test-with buffer "* One\n** Two\n*** Three\n**** Four\n***** Five\n"
    (setq imprimeur-pandoc-program "pandoc")
    (let ((stream (imprimeur-test-http-stream (car (imprimeur-session-test-port-and-path buffer))
                                              (concat (imprimeur-session-test-base buffer) "events"))))
      (unwind-protect
          (progn
            (imprimeur-test-wait-for (lambda () (assoc "revision" (imprimeur-test-http-events stream))) 20)
            (let ((html (plist-get (imprimeur-session-test-document buffer) :html)))
              (dotimes (level 5)
                (should (string-match-p (format "<h%d[ >]" (1+ level)) html)))
              (should-not (string-search "<li" html))))
        (delete-process stream)))))

(ert-deftest imprimeur-session-needs-a-reader ()
  (let ((imprimeur-pandoc-program imprimeur-test-fake-pandoc)
        (imprimeur-browser-program imprimeur-test-fake-browser))
    (with-temp-buffer
      (text-mode)
      (should-error (imprimeur-mode 1) :type 'user-error)
      (should-not imprimeur-mode)
      (should-not imprimeur--sessions)
      (should-not (imprimeur-session-test-leftovers)))))

(ert-deftest imprimeur-session-is-one-per-buffer ()
  (let* ((imprimeur-pandoc-program imprimeur-test-fake-pandoc)
         (imprimeur-browser-program imprimeur-test-fake-browser)
         (org-mode-hook (list #'imprimeur-mode))
         (root (repo-test-git-tree '(("doc.org" . "Hello\n"))))
         (buffer (find-file-noselect (expand-file-name "doc.org" root))))
    (unwind-protect
        (with-current-buffer buffer
          (should imprimeur-mode)
          (let ((session imprimeur--session))
            (org-mode)
            (imprimeur-mode 1)
            (should (equal imprimeur--sessions (list session)))
            (should (eq imprimeur--session session))))
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (kill-buffer buffer))
    (should-not imprimeur--sessions)
    (should-not (imprimeur-session-test-leftovers))))

(ert-deftest imprimeur-session-survives-the-death-of-an-indirect-clone ()
  (imprimeur-session-test-with buffer "Hello\n"
    (let ((session (buffer-local-value 'imprimeur--session buffer)))
      (kill-buffer (with-current-buffer buffer (clone-indirect-buffer "clone" nil)))
      (should (equal imprimeur--sessions (list session)))
      (should (buffer-local-value 'imprimeur-mode buffer))
      (should (process-live-p imprimeur-server--process))
      (should (process-live-p (imprimeur--session-viewer session))))))

(ert-deftest imprimeur-session-stop-all-ends-a-session-whose-buffer-died ()
  (imprimeur-session-test-with buffer "Hello\n"
    (with-current-buffer buffer
      (remove-hook 'kill-buffer-hook #'imprimeur--stop t)
      (set-buffer-modified-p nil))
    (kill-buffer buffer)
    (should imprimeur--sessions)
    (imprimeur-stop-all)
    (should-not imprimeur--sessions)
    (should-not (imprimeur-session-test-leftovers))))

(ert-deftest imprimeur-session-opens-nothing-outside-the-root ()
  (imprimeur-session-test-with buffer "Hello\n"
    (let* ((port (car (imprimeur-session-test-port-and-path buffer)))
           (post (concat (imprimeur-session-test-base buffer) "post"))
           (token (cadr (split-string (cdr (imprimeur-session-test-port-and-path buffer)) "/")))
           (root (file-name-directory (buffer-file-name buffer)))
           (outside (make-temp-file "outside" nil ".md" "# Outside\n"))
           (followed nil))
      (make-symbolic-link outside (expand-file-name "outside.md" root))
      (make-symbolic-link "/dev/zero" (expand-file-name "zero.md" root))
      (make-directory (expand-file-name "folder.md" root))
      (with-temp-file (expand-file-name "run.sh" root) (insert "true\n"))
      (let ((buffers (buffer-list)))
        (cl-letf (((symbol-function 'browse-url) (lambda (&rest arguments) (push arguments followed)))
                  ((symbol-function 'find-file-other-window) (lambda (&rest arguments) (push arguments followed))))
          (dolist (path (list "run.sh" "outside.md" "zero.md" "folder.md" "%2e%2e/x.md"
                              (concat "%2e%2e/" (file-name-nondirectory outside))))
            (should (equal (cons path (car (imprimeur-test-http-post
                                            port post (format "{\"type\":\"open\",\"url\":\"http://127.0.0.1:%d/%s/%s\"}"
                                                              port token path))))
                           (cons path 400)))))
        (should-not followed)
        (should (equal (buffer-list) buffers))))))

;;; imprimeur-session-test.el ends here
