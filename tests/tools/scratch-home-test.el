;;; scratch-home-test.el --- Tests of the scratch home  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: a test runs as a user's Emacs does, where a write to a
;; process that no longer reads is an error that the caller can handle.  A
;; batch Emacs started from scripts/with-scratch-home, as the tests' own is,
;; signals that error and does not die of SIGPIPE.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)

(ert-deftest scratch-home-makes-a-closed-pipe-an-error ()
  ;; Emacs gives its children the default for SIGPIPE, so this Emacs must start
  ;; through the script, as the tests' own does.
  (let ((result (repo-test-run
                 (expand-file-name "scripts/with-scratch-home" repo-test-root)
                 (list (expand-file-name invocation-name invocation-directory) "-Q" "--batch" "--eval"
                       (format "%S"
                               '(let* ((closed nil)
                                       (process (make-process
                                                 :name "closed" :connection-type 'pipe :noquery t
                                                 :command '("sh" "-c" "exec 0<&-; echo closed; sleep 5")
                                                 :filter (lambda (_process _output) (setq closed t)))))
                                  (while (not closed) (accept-process-output process 0.05))
                                  (condition-case nil
                                      (process-send-string process (make-string 1000000 ?x))
                                    (error (kill-emacs 0)))
                                  (kill-emacs 1)))))))
    (should (equal result '(0 . "")))))

;;; scratch-home-test.el ends here
