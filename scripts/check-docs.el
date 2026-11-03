;;; check-docs.el --- Check the Markdown's links and the reference  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Usage, from the root of a git work tree, with the packages on the load path:
;;
;;   emacs -Q --batch -L DIR... -l scripts/check-docs.el -f check-docs-batch
;;
;; Two checks, each finding printed as FILE:LINE: MESSAGE, and exit status 1 if any:
;;
;; - every relative link in the tracked Markdown, outside fences and code spans and
;;   but for test fixtures and vendored files, leads to a tracked file or to a directory
;;   that holds one, and its #fragment to a heading or an <a id> in a Markdown file;
;; - every option, face, command and key of the packages, and each key of a skin's
;;   manifest, stands as a code span in its page of docs/reference/.
;;
;; A web address is not fetched.  A Markdown file is read as it stands: the parsing
;; stages are `check-docs-unfenced', `check-docs-links' and `check-docs-anchors'.

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
                   (downcase (string-trim (replace-regexp-in-string "<[^>]*>" "" heading))))))

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

(defun check-docs-link-problem (file target tracked)
  "Return what is wrong with the link to TARGET from FILE, or nil.
TRACKED lists the tracked files, relative to the root, which is the current
directory, as FILE is."
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
                  (not (member fragment (check-docs-anchors (check-docs-read name)))))
             (format "no anchor for %s" target))))))

(defun check-docs-link-findings ()
  "Return the findings of the links of every tracked Markdown file."
  (let* ((tracked (process-lines "git" "ls-files"))
         (markdown (seq-filter (lambda (file)
                                 (and (string-suffix-p ".md" file)
                                      (not (string-prefix-p "tests/" file))
                                      (not (string-search "/vendor/" file))))
                               tracked)))
    (mapcan (lambda (file)
              (delq nil
                    (mapcar (lambda (link)
                              (when-let* ((problem (check-docs-link-problem file (cdr link) tracked)))
                                (format "%s:%d: %s" file (car link) problem)))
                            (check-docs-links (check-docs-read file)))))
            markdown)))

(defun check-docs-keys (keymap)
  "Return the descriptions of KEYMAP's own keys, but for its remappings."
  (let ((keys nil)
        (walk nil))
    (setq walk (lambda (map prefix)
                 (map-keymap-internal
                  (lambda (event binding)
                    (let ((sequence (vconcat prefix (vector event))))
                      (cond ((eq event 'remap))
                            ((keymapp binding) (funcall walk binding sequence))
                            (t (push (key-description sequence) keys)))))
                  map)))
    (funcall walk keymap [])
    keys))

(defun check-docs-names ()
  "Return the packages' names that the reference holds, by its pages.
The value is a list of (PAGE . NAMES), each page's name relative to the root."
  (let ((options nil)
        (commands nil))
    (mapatoms (lambda (symbol)
                (when (string-match-p "\\`\\(?:imprimeur\\|sommaire\\)-" (symbol-name symbol))
                  (when (or (custom-variable-p symbol) (facep symbol))
                    (push (symbol-name symbol) options))
                  (when (and (commandp symbol) (not (string-search "--" (symbol-name symbol))))
                    (push (symbol-name symbol) commands)))))
    (list (cons "docs/reference/options.md" options)
          (cons "docs/reference/commands-and-keys.md"
                (append commands
                        (mapcan (lambda (map) (check-docs-keys (symbol-value map))) check-docs-maps)
                        imprimeur-skin--reserved-keys
                        imprimeur-xwidget--minitoc-keys
                        (mapcan (lambda (name) (copy-sequence (plist-get (imprimeur-skin-get name) :keys)))
                                (imprimeur-skin-names))))
          (cons "docs/reference/skin-api.md"
                (mapcar #'symbol-name imprimeur-skin--keys)))))

(defun check-docs-reference-findings ()
  "Return the findings of what the reference does not hold."
  (mapc #'require check-docs-features)
  (mapcan (lambda (entry)
            (let ((text (check-docs-read (car entry))))
              (mapcar (lambda (name)
                        (format "%s:1: no code span of %s" (car entry) name))
                      (sort (seq-uniq (seq-remove (lambda (name)
                                                    (string-search (format "`%s`" name) text))
                                                  (cdr entry)))))))
          (check-docs-names)))

(defun check-docs-batch ()
  "Print what the checks find, and exit with status 1 if they find anything."
  (let ((findings (append (check-docs-link-findings) (check-docs-reference-findings))))
    (dolist (finding findings)
      (princ (concat finding "\n")))
    (kill-emacs (if findings 1 0))))

(provide 'check-docs)

;;; check-docs.el ends here
