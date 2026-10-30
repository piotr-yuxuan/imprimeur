;;; run-ert.el --- Run ERT tests and fail on anything unexpected  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Usage, through scripts/with-scratch-home:
;;
;;   emacs -Q --batch -L DIR... -l tests/run-ert.el TEST-DIR...
;;
;; Loads every *-test.el file under each TEST-DIR and runs all their tests.
;; Exits with status 0 when every test passed; 1 on an unexpected result,
;; when there is no test, or when a test was skipped for a reason that the
;; environment variable IMPRIMEUR_TEST_ALLOW_SKIP does not list (reasons
;; separated by commas, compared as whole strings); 2 when HOME is not a
;; scratch home.  `ert-run-tests-batch-and-exit' would exit 0 on skips,
;; which would let a missing tool pass silently.

;;; Code:

(require 'ert)

(unless (file-exists-p (expand-file-name "~/.imprimeur-scratch"))
  (message "run-ert: HOME is not a scratch home; use scripts/with-scratch-home")
  (kill-emacs 2))

(let* ((directories command-line-args-left)
       (files (mapcan (lambda (directory)
                        (directory-files-recursively (expand-file-name directory)
                                                     "-test\\.el\\'"))
                      directories))
       (allowed (split-string (or (getenv "IMPRIMEUR_TEST_ALLOW_SKIP") "")
                              "," t "[[:space:]]+"))
       (refused 0))
  (setq command-line-args-left nil)
  (mapc #'load files)
  (let ((stats (ert-run-tests-batch t)))
    (mapc (lambda (test)
            (let ((result (ert-test-most-recent-result test)))
              (when (and (ert-test-skipped-p result)
                         (not (member (cadr (ert-test-result-with-condition-condition
                                            result))
                                      allowed)))
                (message "run-ert: skip not allowed: %s" (ert-test-name test))
                (setq refused (1+ refused)))))
          (ert--stats-tests stats))
    (message "run-ert: %d tests in %d files, %d unexpected, %d skipped, %d skips refused"
             (ert-stats-total stats) (length files)
             (ert-stats-completed-unexpected stats)
             (ert-stats-skipped stats) refused)
    (kill-emacs (if (and (> (ert-stats-total stats) 0)
                         (zerop (ert-stats-completed-unexpected stats))
                         (zerop refused))
                    0
                  1))))

;;; run-ert.el ends here
