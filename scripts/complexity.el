;;; complexity.el --- Check the cyclomatic complexity of Lisp functions  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Usage: emacs -Q --batch -l scripts/complexity.el -f repo-complexity-batch FILE...
;;
;; The complexity of a function is 1 plus its decision points, counted on
;; the source as written, macros unexpanded, nested lambdas included:
;;
;; - 1 for each if, when, unless, while, dolist, dotimes, if-let, if-let*,
;;   when-let, when-let*, and-let*, while-let and cl-loop;
;; - 1 for each clause of cond, except a last clause whose test is t;
;; - 1 for each clause of pcase, pcase-exhaustive, cl-case, cl-ecase,
;;   cl-typecase and cl-etypecase, except a default clause (_, t,
;;   otherwise);
;; - 1 for each handler of condition-case;
;; - 1 for each operand of and and or beyond the first.
;;
;; A function whose complexity exceeds 10 is printed as FILE:LINE, and
;; Emacs exits with status 1.

;;; Code:

(require 'seq)

(defconst repo-complexity-limit 10
  "The highest complexity allowed.")

(defconst repo-complexity-definers
  '(defun defmacro defsubst cl-defun cl-defmacro cl-defmethod define-inline)
  "Forms that define a function whose complexity is counted.")

(defconst repo-complexity-branches
  '(if when unless while dolist dotimes if-let if-let* when-let when-let*
       and-let* while-let cl-loop)
  "Forms that each count as one decision point.")

(defconst repo-complexity-case-forms
  '(pcase pcase-exhaustive cl-case cl-ecase cl-typecase cl-etypecase)
  "Forms whose clauses each count as a decision point, but a default one.")

(defun repo-complexity--own (head arguments)
  "Return the decision points that the form (HEAD . ARGUMENTS) adds itself."
  (cond ((memq head repo-complexity-branches) 1)
        ((eq head 'cond)
         (- (length arguments) (if (eq (car-safe (car (last arguments))) t) 1 0)))
        ((memq head repo-complexity-case-forms)
         (seq-count (lambda (clause) (not (memq (car-safe clause) '(_ t otherwise))))
                    (cdr arguments)))
        ((eq head 'condition-case) (length (nthcdr 2 arguments)))
        ((memq head '(and or)) (max 0 (1- (length arguments))))
        (t 0)))

(defun repo-complexity--points (form)
  "Return the number of decision points in FORM and in its subforms."
  (if (or (atom form) (eq (car form) 'quote))
      0
    (let ((points (if (and (symbolp (car form)) (proper-list-p form))
                      (repo-complexity--own (car form) (cdr form))
                    0)))
      (while (consp form)
        (setq points (+ points (repo-complexity--points (car form)))
              form (cdr form)))
      points)))

(defun repo-complexity-file (file)
  "Print each function of FILE that is too complex; return their number."
  (with-temp-buffer
    (insert-file-contents file)
    (set-syntax-table emacs-lisp-mode-syntax-table)
    (let ((offenders 0) (done nil))
      (while (not done)
        (forward-comment (buffer-size))
        (let ((line (line-number-at-pos))
              (form (condition-case nil
                        (read (current-buffer))
                      (end-of-file (setq done t) nil))))
          (unless done
            (when (memq (car-safe form) repo-complexity-definers)
              (let ((complexity (1+ (repo-complexity--points (cddr form)))))
                (when (> complexity repo-complexity-limit)
                  (message "%s:%d: %s has a cyclomatic complexity of %d, above %d"
                           file line (cadr form) complexity repo-complexity-limit)
                  (setq offenders (1+ offenders))))))))
      offenders)))

(defun repo-complexity-batch ()
  "Check the files named on the command line; exit 1 if any function is too complex."
  (let ((offenders (apply #'+ (mapcar #'repo-complexity-file command-line-args-left))))
    (setq command-line-args-left nil)
    (kill-emacs (if (zerop offenders) 0 1))))

;;; complexity.el ends here
