;;; repo-test-helpers.el --- Helpers shared by the repository's tests  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Child processes with a deadline and scratch directories, for the tests
;; of both packages and of the repository's tools.  The tests run in the
;; scratch home that scripts/with-scratch-home makes, so temporary files
;; go to its TMPDIR.

;;; Code:

(defconst repo-test-root
  (expand-file-name "../.." (file-name-directory (or load-file-name buffer-file-name)))
  "The root of the repository under test.")

(defvar repo-test-timeout 120
  "Seconds after which `repo-test-run' kills its child process.")

(defun repo-test-run (program arguments &optional environment directory)
  "Run PROGRAM with ARGUMENTS and return (STATUS . OUTPUT).
OUTPUT holds standard output and standard error.  ENVIRONMENT, a
list of \"NAME=VALUE\" strings, is added to the environment; the
working directory is DIRECTORY, or the repository's root.  The
child is killed after `repo-test-timeout' seconds, and STATUS is
then the symbol `timeout'."
  (let* ((process-environment (append environment process-environment))
         (default-directory (file-name-as-directory (or directory repo-test-root)))
         (deadline (+ (float-time) repo-test-timeout))
         (process (make-process :name "repo-test" :buffer (generate-new-buffer " *repo-test*")
                                :command (cons program arguments)
                                :connection-type 'pipe :noquery t :sentinel #'ignore)))
    (while (and (process-live-p process) (< (float-time) deadline))
      (accept-process-output process 0.1))
    (when (process-live-p process)
      (delete-process process))
    (while (accept-process-output process 0 nil t))
    (prog1 (cons (if (eq (process-status process) 'exit)
                     (process-exit-status process)
                   'timeout)
                 (with-current-buffer (process-buffer process) (buffer-string)))
      (kill-buffer (process-buffer process)))))

(defun repo-test-emacs (arguments &optional environment directory)
  "Run the Emacs running the tests, in batch with -Q, with ARGUMENTS.
ENVIRONMENT and DIRECTORY are as in `repo-test-run'."
  (repo-test-run (expand-file-name invocation-name invocation-directory)
                 (append '("-Q" "--batch") arguments)
                 environment directory))

(defun repo-test-load-effects (feature)
  "Require FEATURE in a child Emacs and return how it changed the state.
The value is the plist that `load-effects-report' prints, or an error
when the child fails.  Both package directories are on the load path."
  (let ((result (repo-test-emacs
                 (list "-L" (expand-file-name "sommaire" repo-test-root)
                       "-L" (expand-file-name "imprimeur" repo-test-root)
                       "-L" (expand-file-name "tests/helpers" repo-test-root)
                       "-l" "load-effects"
                       "--eval" (format "(load-effects-report '%s)" feature)))))
    (unless (equal (car result) 0)
      (error "Loading %s failed: %s" feature (cdr result)))
    (car (read-from-string (cdr result)))))

(defun repo-test-tree (files)
  "Make a scratch directory holding FILES and return its name.
FILES is an alist of relative file names and their contents."
  (let ((directory (file-name-as-directory (make-temp-file "repo-test" t))))
    (pcase-dolist (`(,name . ,contents) files)
      (let ((file (expand-file-name name directory)))
        (make-directory (file-name-directory file) t)
        (with-temp-file file (insert contents))))
    directory))

(provide 'repo-test-helpers)

;;; repo-test-helpers.el ends here
