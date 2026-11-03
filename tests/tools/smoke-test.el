;;; smoke-test.el --- Tests of the smoke test's script  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: `make smoke-xwidget' runs on whichever display the environment
;; gives, and without one says so and exits 2 (plan 004).  That it passes on a
;; display is for a run on one, as no test opens a desktop window.
;;
;; A check that waits does not fail because WebKit still sends events of an xwidget
;; that a view has killed, on which the handler of xwidget.el signals; what it
;; waits through otherwise still fails it.

;;; Code:

(require 'ert)
(require 'seq)
(require 'repo-test-helpers)

(ert-deftest smoke-without-a-display-says-so ()
  (let* ((process-environment (seq-remove (lambda (entry)
                                            (string-match-p "\\`\\(?:WAYLAND_\\)?DISPLAY=" entry))
                                          process-environment))
         (result (repo-test-run (expand-file-name "scripts/smoke-xwidget" repo-test-root) nil)))
    (should (equal (car result) 2))
    (should (string-search "DISPLAY" (cdr result)))))

(ert-deftest smoke-waiting-goes-past-a-killed-xwidget-only ()
  ;; In a child Emacs, as the script's timer ends the Emacs that loads it.
  (let ((result
         (repo-test-emacs
          (list "-l" (expand-file-name "scripts/smoke-xwidget.el" repo-test-root)
                "--eval"
                (prin1-to-string
                 '(progn
                    (cancel-function-timers 'smoke-run)
                    (cl-flet ((wait-through (data)
                                (cl-letf (((symbol-function 'redisplay) #'ignore)
                                          ((symbol-function 'read-event)
                                           (lambda (&rest _) (signal 'wrong-type-argument data))))
                                  (smoke-pump 0.01))))
                      (wait-through '(xwidget-live-p killed))
                      (prin1 (list (> smoke-stale-events 0)
                                   (condition-case failure
                                       (wait-through '(stringp 1))
                                     (wrong-type-argument (cadr failure))))))))))))
    (should (equal (car result) 0))
    (should (equal (car (read-from-string (cdr result))) '(t stringp)))))

;;; smoke-test.el ends here
