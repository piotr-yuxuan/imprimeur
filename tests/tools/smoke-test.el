;;; smoke-test.el --- Tests of the smoke test's script  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: `make smoke-xwidget' runs on whichever display the environment
;; gives, and without one says so and exits 2, having started nothing (plan 004).
;; That it passes on a display is for a run on one, as no test opens a desktop window.

;;; Code:

(require 'ert)
(require 'seq)
(require 'repo-test-helpers)

(ert-deftest smoke-without-a-display-says-so ()
  (let* ((process-environment (seq-remove (lambda (entry)
                                            (string-match-p "\\`\\(?:WAYLAND_\\)?DISPLAY=" entry))
                                          process-environment))
         (marker (expand-file-name "started" (make-temp-file "smoke-test" t)))
         (result (repo-test-run (expand-file-name "scripts/smoke-xwidget" repo-test-root) nil
                                (list (format "EMACS=touch %s" marker)))))
    (should (equal (car result) 2))
    (should (string-search "DISPLAY" (cdr result)))
    (should-not (file-exists-p marker))))

;;; smoke-test.el ends here
