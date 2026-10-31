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
;; refused, and with one it is served.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-http)
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
                      kill-emacs-hook)))

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
           (big (* 32 1024 1024)))
      ;; Byte i of ramp.webm is i mod 256.
      (let ((coding-system-for-write 'no-conversion))
        (write-region bytes nil (expand-file-name "ramp.webm" root) nil 'silent))
      ;; A sparse file of 32 MiB and one byte, "x".
      (write-region "x" nil (expand-file-name "big.webm" root) big 'silent)
      (dolist (case `((nil 200 nil 0 ,size)
                      ("bytes=10-19" 206 "bytes 10-19/1048576" 10 20)
                      ("bytes=-500" 206 "bytes 1048076-1048575/1048576" ,(- size 500) ,size)
                      ("bytes=5-1" 416 "bytes */1048576" 0 0)
                      ("bytes=0-1,5-6" 416 "bytes */1048576" 0 0)
                      ("bytes=2000000-" 416 "bytes */1048576" 0 0)))
        (pcase-let* ((`(,range ,status ,content-range ,start ,end) case)
                     (`(,got-status ,headers ,body)
                      (apply #'imprimeur-test-http-get port (concat directory "ramp.webm")
                             (and range (list (concat "Range: " range))))))
          (should (equal (list range got-status (cdr (assoc "content-range" headers))
                               (cdr (assoc "accept-ranges" headers))
                               (equal (string-to-unibyte body) (substring bytes start end)))
                         (list range status content-range "bytes" t)))))
      (pcase-let ((`(,status ,headers ,body)
                   (imprimeur-test-http-get port (concat directory "ramp.webm") "Range: bytes=0-")))
        (should (<= 1 (length body) 262144))
        (should (equal (list status (cdr (assoc "content-range" headers))
                             (equal (string-to-unibyte body) (substring bytes 0 (length body))))
                       (list 206 (format "bytes 0-%d/1048576" (1- (length body))) t))))
      (should (equal (car (imprimeur-test-http-get port (concat directory "big.webm"))) 404))
      (pcase-let ((`(,status ,headers ,body)
                   (imprimeur-test-http-get port (concat directory "big.webm")
                                            (format "Range: bytes=%d-" big))))
        (should (equal (list status (cdr (assoc "content-range" headers)) body)
                       (list 206 (format "bytes %d-%d/%d" big big (1+ big)) "x")))))))

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
