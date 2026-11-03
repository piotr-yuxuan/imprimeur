;;; check-docs.el --- Check the Markdown's links and the reference  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Usage, from the root of a git work tree, with the packages on the load path:
;;
;;   emacs -Q --batch -l scripts/check-docs.el -f check-docs-batch-links
;;   emacs -Q --batch -L DIR... -l scripts/check-docs.el -f check-docs-batch-reference
;;
;; Two checks, each finding printed as FILE:LINE: MESSAGE, and exit status 1 if any:
;;
;; - every relative link in the tracked Markdown, outside fences and code spans and
;;   but for test fixtures and vendored files, leads to a tracked file or to a directory
;;   that holds one, and its #fragment to a heading or an <a id> in a Markdown file;
;; - every option, face, command and key of the packages, and each key of a skin's
;;   manifest, stands as a code span in its page of docs/reference/.  Anywhere on that
;;   page: a key of one character that two tables hold counts once.
;;
;; A web address is not fetched.  A Markdown file is read as it stands: the parsing
;; stages are `check-docs-unfenced', `check-docs-links' and `check-docs-anchors'.  The
;; two pure decisions, `check-docs-slug' and `check-docs-link-problem', go by tables in
;; the tests.

;;; Code:

(require 'seq)
(require 'subr-x)

(defconst check-docs-link-regexp
  "\\](\\([^() \t\n]+\\)[ )]\\|<\\(?:img\\|a\\|source\\)\\b[^>]*?\\(?:src\\|srcset\\|href\\)=\"\\([^\"]+\\)\""
  "A link in Markdown or raw HTML, whose target is the first or the second group.")

(defconst check-docs-features
  '(imprimeur sommaire imprimeur-skin-minitel imprimeur-skin-xix imprimeur-skin-xviii
              imprimeur-skin-xvii imprimeur-skin-briefing imprimeur-skin-ecrivain
              imprimeur-skin-tianlu)
  "The packages whose names the reference must hold.")

(defconst check-docs-maps
  '(imprimeur-mode-map imprimeur-view-mode-map sommaire-mode-map sommaire-panel-mode-map)
  "The packages' keymaps, every key of which the reference must hold.")

(defvar imprimeur-skin--keys)
(defvar imprimeur-skin--reserved-keys)
(defvar imprimeur-xwidget--minitoc-keys)
(declare-function imprimeur-skin-names "imprimeur-skin" ())
(declare-function imprimeur-skin-get "imprimeur-skin" (name))

(defun check-docs-unfenced (text)
  "Return TEXT with its fenced code blanked, its lines where they were."
  (let ((fence nil))
    (mapconcat (lambda (line)
                 (cond ((and fence (string-match-p (concat "\\`[ \t]*" fence "`*[ \t]*\\'") line))
                        (setq fence nil)
                        "")
                       (fence "")
                       ((string-match "\\`[ \t]*\\(```+\\)" line)
                        (setq fence (match-string 1 line))
                        "")
                       (t line)))
               (split-string text "\n")
               "\n")))

(defun check-docs-links (text)
  "Return the links of the Markdown TEXT, as (LINE . TARGET), in order."
  (let ((links nil))
    (with-temp-buffer
      (insert (replace-regexp-in-string "``[^`\n]*``\\|`[^`\n]*`" "" (check-docs-unfenced text) t t))
      (goto-char (point-min))
      (while (re-search-forward check-docs-link-regexp nil t)
        (push (cons (line-number-at-pos (match-beginning 0))
                    (or (match-string 1) (match-string 2)))
              links)))
    (nreverse links)))

(defun check-docs-slug (heading)
  "Return the anchor that GitHub gives the Markdown HEADING's text."
  (string-replace " " "-"
                  (replace-regexp-in-string
                   "[^[:alnum:] _-]" ""
                   (downcase (string-trim (replace-regexp-in-string
                                           "<[^>]*>\\|\\](\\([^()]*\\))" ""
                                           heading))))))

(defun check-docs-anchors (text)
  "Return the anchors of the Markdown TEXT, numbered as GitHub numbers repeats."
  (let ((anchors nil)
        (seen (make-hash-table :test #'equal)))
    (dolist (line (split-string (check-docs-unfenced text) "\n"))
      (when (string-match "\\`#+[ \t]+\\(.*\\)\\'" line)
        (let* ((slug (check-docs-slug (match-string 1 line)))
               (count (gethash slug seen 0)))
          (puthash slug (1+ count) seen)
          (push (if (zerop count) slug (format "%s-%d" slug count)) anchors)))
      (when (string-match "<a [^>]*id=\"\\([^\"]+\\)\"" line)
        (push (match-string 1 line) anchors)))
    anchors))

(defun check-docs-read (file)
  "Return the contents of FILE, relative to the root, as UTF-8 text."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (buffer-string)))

(defun check-docs-link-problem (file target tracked anchors)
  "Return what is wrong with the link to TARGET from FILE, or nil.
FILE and each of TRACKED, the tracked files, are relative to the root, which is
the current directory.  ANCHORS, a function, gives the anchors of such a file."
  (unless (string-match-p "\\`[a-zA-Z][a-zA-Z0-9+.-]*:" target)
    (pcase-let* ((`(,path ,fragment) (string-split target "#"))
                 (name (if (string-empty-p path)
                           file
                         (file-relative-name (expand-file-name path (or (file-name-directory file) "./"))))))
      (cond ((not (seq-some (lambda (other)
                              (or (equal other name)
                                  (string-prefix-p (file-name-as-directory name) other)))
                            tracked))
             (format "no tracked file at %s" target))
            ((and fragment (string-suffix-p ".md" name)
                  (not (member fragment (funcall anchors name))))
             (format "no anchor for %s" target))))))

(defun check-docs-finish (findings)
  "Print FINDINGS, and exit with status 1 if there are any."
  (dolist (finding findings)
    (princ (concat finding "\n")))
  (kill-emacs (if findings 1 0)))

(defun check-docs-batch-links ()
  "Check the links of every tracked Markdown file; see the commentary."
  (let ((tracked (process-lines "git" "ls-files"))
        (findings nil))
    (dolist (file tracked)
      (when (and (string-suffix-p ".md" file)
                 (not (string-prefix-p "tests/" file))
                 (not (string-search "/vendor/" file)))
        (pcase-dolist (`(,line . ,target) (check-docs-links (check-docs-read file)))
          (when-let* ((problem (check-docs-link-problem
                                file target tracked
                                (lambda (name) (check-docs-anchors (check-docs-read name))))))
            (push (format "%s:%d: %s" file line problem) findings)))))
    (check-docs-finish (nreverse findings))))

(defun check-docs-batch-reference ()
  "Check that the reference holds the packages' names; see the commentary."
  (mapc #'require check-docs-features)
  (let ((options nil)
        (commands nil)
        (keys nil)
        (walk nil))
    (mapatoms (lambda (symbol)
                (when (string-match-p "\\`\\(?:imprimeur\\|sommaire\\)-" (symbol-name symbol))
                  (when (or (custom-variable-p symbol) (facep symbol))
                    (push (symbol-name symbol) options))
                  (when (and (commandp symbol) (not (string-search "--" (symbol-name symbol))))
                    (push (symbol-name symbol) commands)))))
    ;; A map's own keys, without its remappings or its parents.
    (setq walk (lambda (map prefix)
                 (map-keymap-internal
                  (lambda (event binding)
                    (let ((sequence (vconcat prefix (vector event))))
                      (cond ((eq event 'remap))
                            ((keymapp binding) (funcall walk binding sequence))
                            (t (push (key-description sequence) keys)))))
                  map)))
    (mapc (lambda (map) (funcall walk (symbol-value map) [])) check-docs-maps)
    (check-docs-finish
     (mapcan (lambda (entry)
               (let ((text (check-docs-read (car entry))))
                 (mapcar (lambda (name)
                           (format "%s:1: no code span of %s" (car entry) name))
                         (sort (seq-uniq (seq-remove (lambda (name)
                                                       (string-search (format "`%s`" name) text))
                                                     (cdr entry)))))))
             (list (cons "docs/reference/options.md" options)
                   (cons "docs/reference/commands-and-keys.md"
                         (append commands keys
                                 imprimeur-skin--reserved-keys
                                 imprimeur-xwidget--minitoc-keys
                                 (mapcan (lambda (name)
                                           (copy-sequence (plist-get (imprimeur-skin-get name) :keys)))
                                         (imprimeur-skin-names))))
                   (cons "docs/reference/skin-api.md"
                         (mapcar #'symbol-name imprimeur-skin--keys)))))))

(provide 'check-docs)

;;; check-docs.el ends here
