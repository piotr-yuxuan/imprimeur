;;; imprimeur-session-test.el --- Tests of imprimeur's sessions  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements (plan 002, acceptance 1, 2, 4, 6 and 8): edits within the
;; quiet delay give one render of the final text, continuous edits render
;; at least once per maximum latency, a render under way defers the next
;; one, a change of text properties renders nothing, a page connecting
;; triggers the first render; a failure keeps the last good revision and
;; the next good render clears it; killing the buffer ends everything the
;; session owns; a change of major mode keeps the session when the new
;; mode has a reader; an edit in an indirect buffer renders; links posted
;; by the page reach `browse-url' or `find-file-other-window' as their
;; target allows; a compiled copy finds its own assets.

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

(ert-deftest imprimeur-session-prepends-org-options ()
  (should (equal (imprimeur--source-text "org" "* A") "#+OPTIONS: H:9\n* A"))
  (should (equal (imprimeur--source-text "gfm+sourcepos" "# A") "# A")))

(defmacro imprimeur-session-test-with (buffer text &rest body)
  "Run BODY with BUFFER visiting a scratch Org file holding TEXT.
The file sits in its own git repository; `imprimeur-mode' is on, with
the fake pandoc, whose behaviour IMPRIMEUR_FAKE_PANDOC in
`process-environment' chooses.  The buffer is killed afterwards."
  (declare (indent 2))
  `(let* ((imprimeur-pandoc-program imprimeur-test-fake-pandoc)
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
              (should (>= (imprimeur-session-test-runs log) 3)))
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
                   (cons 0 (directory-file-name (expand-file-name "assets" copy)))))))

;;; imprimeur-session-test.el ends here
