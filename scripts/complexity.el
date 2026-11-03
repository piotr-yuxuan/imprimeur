;;; complexity.el --- Check the cyclomatic complexity of Lisp functions  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Usage: emacs -Q --batch -l scripts/complexity.el -f repo-complexity-batch FILE...
;;
;; Every definition in `repo-complexity-definers' is measured, at top level
;; or inside the forms of `repo-complexity-containers' (progn,
;; with-eval-after-load, eval-when-compile, eval-and-compile, when, unless,
;; let, let*): functions, macros, generic functions, methods, modes, ERT
;; tests, `defalias' of a lambda, and the value of a `defconst', which may be
;; a table of lambdas.  Lambdas given to other top-level forms, such as
;; `add-hook', are not measured.  A definition's complexity is 1 plus its
;; decision points, counted on the source as written, macros unexpanded,
;; nested lambdas included, by `repo-complexity-rules':
;;
;; - 1 for each if, when, unless, while, dolist, dotimes, seq-doseq,
;;   cl-dolist, pcase-dolist, if-let, if-let*, when-let, when-let*, and-let*
;;   and while-let;
;; - 1 for each cl-loop, plus 1 for each of its when, if, unless, while,
;;   until, always, never and thereis clauses;
;; - 1 for each clause of cond, except a last clause whose test is t;
;; - 1 for each clause of pcase, pcase-exhaustive, cl-case, cl-ecase,
;;   cl-typecase and cl-etypecase, except a default clause (_, t,
;;   otherwise);
;; - 1 for each handler of condition-case;
;; - 1 for each operand of and and or beyond the first.
;;
;; A definition whose complexity exceeds 10 is printed as FILE:LINE, the
;; line of its top-level form, and Emacs exits with status 1.

;;; Code:

(require 'seq)

(defconst repo-complexity-limit 10
  "The highest complexity allowed.")

(defconst repo-complexity-definers
  '(defun defmacro defsubst cl-defun cl-defmacro cl-defmethod cl-defgeneric
          define-inline ert-deftest define-minor-mode define-globalized-minor-mode
          define-derived-mode defalias defconst)
  "Forms whose body is measured; the name is their second element.")

(defconst repo-complexity-containers
  '(progn with-eval-after-load eval-when-compile eval-and-compile when unless let let*)
  "Top-level forms in which definitions are looked for too.")

(defconst repo-complexity-rules
  (let ((one (lambda (_arguments) 1))
        (clauses (lambda (arguments)
                   (seq-count (lambda (clause)
                                (not (memq (car-safe clause) '(_ t otherwise))))
                              (cdr arguments))))
        (operands (lambda (arguments) (max 0 (1- (length arguments))))))
    (append
     (mapcar (lambda (head) (cons head one))
             '(if when unless while dolist dotimes seq-doseq cl-dolist pcase-dolist
                  if-let if-let* when-let when-let* and-let* while-let))
     (mapcar (lambda (head) (cons head clauses))
             '(pcase pcase-exhaustive cl-case cl-ecase cl-typecase cl-etypecase))
     `((and . ,operands)
       (or . ,operands)
       (cond . ,(lambda (arguments)
                  (- (length arguments)
                     (if (eq (car-safe (car (last arguments))) t) 1 0))))
       (condition-case . ,(lambda (arguments) (length (nthcdr 2 arguments))))
       (cl-loop . ,(lambda (arguments)
                     (1+ (seq-count (lambda (word)
                                      (memq word '(when if unless while until
                                                        always never thereis)))
                                    arguments)))))))
  "Alist from a form's head to a function of its arguments.
The function returns the decision points that the form adds itself.")

(defun repo-complexity--points (form)
  "Return the number of decision points in FORM and in its subforms."
  (if (or (atom form) (eq (car form) 'quote))
      0
    (let* ((rule (and (symbolp (car form)) (proper-list-p form)
                      (alist-get (car form) repo-complexity-rules)))
           (points (if rule (funcall rule (cdr form)) 0)))
      (while (consp form)
        (setq points (+ points (repo-complexity--points (car form)))
              form (cdr form)))
      points)))

(defun repo-complexity--definitions (form)
  "Return the definitions in the top-level FORM as (NAME . BODY) pairs."
  (cond ((memq (car-safe form) repo-complexity-containers)
         (mapcan #'repo-complexity--definitions (cdr form)))
        ((memq (car-safe form) repo-complexity-definers)
         (list (cons (cadr form) (cddr form))))))

(defun repo-complexity-file (file)
  "Print each definition of FILE that is too complex; return their number."
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
          (dolist (definition (repo-complexity--definitions form))
            (let ((complexity (1+ (repo-complexity--points (cdr definition)))))
              (when (> complexity repo-complexity-limit)
                (message "%s:%d: %S has a cyclomatic complexity of %d, above %d"
                         file line (car definition) complexity repo-complexity-limit)
                (setq offenders (1+ offenders)))))))
      offenders)))

(defun repo-complexity-batch ()
  "Check the files named on the command line.
Exit with status 1 if any definition is too complex, 0 otherwise."
  (let ((offenders (apply #'+ (mapcar #'repo-complexity-file command-line-args-left))))
    (setq command-line-args-left nil)
    (kill-emacs (if (zerop offenders) 0 1))))

;;; complexity.el ends here
