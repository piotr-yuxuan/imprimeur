;;; imprimeur-load-test.el --- Loading imprimeur has no side effect  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: loading a package prints nothing, leaves the other package
;; of the repository unloaded, and adds no timer, global hook or global key
;; (plan 001, acceptance 5).

;;; Code:

(require 'ert)
(require 'repo-test-helpers)

(ert-deftest imprimeur-load-prints-nothing ()
  "Loading imprimeur in batch prints nothing and succeeds."
  (should (equal (repo-test-emacs (list "-L" (expand-file-name "imprimeur" repo-test-root)
                                        "-l" "imprimeur"))
                 '(0 . ""))))

(ert-deftest imprimeur-load-changes-no-global-state ()
  "Requiring imprimeur adds no timer, hook or key, and loads no sommaire."
  (should (equal (repo-test-load-effects 'imprimeur)
                 '(:timers 0 :hooks nil :global-map nil :minor-modes nil
                   :auto-modes nil :sommaire nil :imprimeur t))))

;;; imprimeur-load-test.el ends here
