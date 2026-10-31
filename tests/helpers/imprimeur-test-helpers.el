;;; imprimeur-test-helpers.el --- Helpers for the tests of imprimeur  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Waiting with a deadline instead of sleeping, the stand-ins for pandoc
;; and Chromium, and the executables the tests need.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)

(defconst imprimeur-test-fake-pandoc
  (expand-file-name "tests/bin/fake-pandoc" repo-test-root)
  "The stand-in for pandoc.")

(defconst imprimeur-test-fake-browser
  (expand-file-name "tests/bin/fake-browser" repo-test-root)
  "The stand-in for Chromium, which opens no window.")

(defconst imprimeur-test-headless-chromium
  (expand-file-name "tests/bin/headless-chromium" repo-test-root)
  "Chromium without a window, resolving only the loopback address.")

(defun imprimeur-test-wait-for (predicate &optional timeout)
  "Wait until PREDICATE returns non-nil, for at most TIMEOUT seconds.
TIMEOUT defaults to 10.  Process output and timers run meanwhile.
Return PREDICATE's value, or fail the test when the time is up."
  (let ((deadline (+ (float-time) (or timeout 10)))
        (value nil))
    (while (and (not (setq value (funcall predicate))) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (or value (ert-fail (list "Timed out waiting for" predicate)))))

(defun imprimeur-test-require (program)
  "Skip the test unless PROGRAM is on the path; return its file name."
  (or (executable-find program)
      (ert-skip (concat "missing executable " program))))

(provide 'imprimeur-test-helpers)

;;; imprimeur-test-helpers.el ends here
