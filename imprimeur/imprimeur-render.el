;;; imprimeur-render.el --- Run pandoc for imprimeur  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; One render is one pandoc process: the buffer's text goes to its standard
;; input, and the HTML fragment, with the document's title and language,
;; comes back through a callback called exactly once.  The Lua filter in
;; assets/pandoc/filters rewrites the document for the page, a skin's filters
;; run after it, and finish.lua writes what Emacs reads.  A document is
;; untrusted unless `trusted-content-p' says otherwise: pandoc then runs
;; with --sandbox, which stops `#+INCLUDE' from reading other files.

;;; Code:

(require 'seq)
(require 'subr-x)

(defgroup imprimeur nil
  "Typeset live previews of Org and Markdown."
  :group 'text
  :prefix "imprimeur-")

(defcustom imprimeur-pandoc-program "pandoc"
  "The pandoc program that renders documents."
  :type 'string)

(defcustom imprimeur-reader-alist
  '((org-mode . "org")
    (markdown-mode . "gfm+sourcepos")
    (rst-mode . "rst")
    (mediawiki-mode . "mediawiki")
    (textile-mode . "textile")
    ("\\.creole\\'" . "creole")
    ("\\.pod\\'" . "pod")
    ("\\.ipynb\\'" . "ipynb")
    ("\\.csv\\'" . "csv")
    ("\\.tsv\\'" . "tsv"))
  "How to choose pandoc's reader for a buffer.
Each entry is (MATCHER . READER).  MATCHER is a major mode, which
matches the buffer's mode and the modes derived from it, or a regular
expression matched against the buffer's file name.  The first entry
that matches wins.  `markdown-mode' also matches `gfm-mode', derived
from it, and `markdown-ts-mode', which names it as a parent."
  :type '(alist :key-type (choice (symbol :tag "Major mode")
                                  (regexp :tag "File name"))
                :value-type (string :tag "Reader")))

(defcustom imprimeur-render-timeout 20
  "Seconds after which a render is abandoned."
  :type 'number)

(defconst imprimeur-render-assets
  (expand-file-name "assets" (file-name-directory (or load-file-name buffer-file-name)))
  "The directory of imprimeur's assets, beside this file.")

(defconst imprimeur-render--output-limit (* 64 1024 1024)
  "The largest output, in bytes, that a render may produce.")

(defconst imprimeur-render--meta-marker "<!--imprimeur-meta-->\n"
  "The line that starts the filter's output, before a line of JSON.")

(defvar imprimeur-render--languages nil
  "Alist from a pandoc program to the languages it highlights, comma-separated.")

(defvar imprimeur-render--smart nil
  "Alist from (PROGRAM . FORMAT) to whether that reader names the extension smart.")

(defun imprimeur-reader (&optional buffer)
  "Return the pandoc reader for BUFFER, or the current buffer, or nil."
  (with-current-buffer (or buffer (current-buffer))
    (cdr (seq-find (lambda (entry)
                     (if (symbolp (car entry))
                         (derived-mode-p (car entry))
                       (and buffer-file-name (string-match-p (car entry) buffer-file-name))))
                   imprimeur-reader-alist))))

(defun imprimeur-render-reader-base (reader)
  "Return READER without its extensions: org for org+smart."
  (car (split-string reader "[+-]")))

(defun imprimeur-render-languages (program)
  "Return the languages that PROGRAM highlights, as a comma-separated string.
The answer is asked once per program; a failure gives the empty string,
so that no fence is highlighted rather than every render slowed."
  (or (cdr (assoc program imprimeur-render--languages))
      (let ((languages (condition-case nil
                           (string-join (process-lines program "--list-highlight-languages") ",")
                         (error ""))))
        (push (cons program languages) imprimeur-render--languages)
        languages)))

(defun imprimeur-render-smart-reader (program reader)
  "Return READER with +smart if PROGRAM's reader of that format has the extension.
Some have none, and would stop pandoc.  The answer is asked once per
program and format; a failure gives READER as it is."
  (let* ((key (cons program (imprimeur-render-reader-base reader)))
         (known (or (assoc key imprimeur-render--smart)
                    (car (push (cons key (condition-case nil
                                             (seq-some (lambda (line) (string-match-p "\\`[+-]smart\\'" line))
                                                       (process-lines program
                                                                      (concat "--list-extensions=" (cdr key))))
                                           (error nil)))
                               imprimeur-render--smart)))))
    (if (cdr known) (concat reader "+smart") reader)))

(defun imprimeur-render-arguments (reader trusted remote-images languages &optional skin)
  "Return pandoc's arguments for READER.
TRUSTED non-nil drops --sandbox; REMOTE-IMAGES non-nil lets remote
images load; LANGUAGES is the comma-separated list of the languages
pandoc highlights.  SKIN, a parsed manifest, adds its :filters between
the core's two, +smart by :smart and notes by :notes; nothing else of it,
and nothing of its options, reaches the command line.  Every option is
explicit, since the pandoc on PATH may be a wrapper that adds defaults of
its own."
  (append (list "-f" (if (plist-get skin :smart)
                         (imprimeur-render-smart-reader imprimeur-pandoc-program reader)
                       reader)
                "-t" "html5" "--mathml" "--wrap=none" "--id-prefix=doc-"
                (concat "--data-dir=" (expand-file-name "pandoc" imprimeur-render-assets))
                (concat "--lua-filter="
                        (expand-file-name "pandoc/filters/imprimeur.lua" imprimeur-render-assets)))
          (mapcar (lambda (filter) (concat "--lua-filter=" filter)) (plist-get skin :filters))
          (list (concat "--lua-filter="
                        (expand-file-name "pandoc/filters/finish.lua" imprimeur-render-assets))
                "-M" (concat "imprimeur-remote-images=" (if remote-images "allow" "block"))
                "-M" (concat "imprimeur-languages=" languages))
          (when (plist-get skin :notes) '("--reference-location=section"))
          (unless trusted '("--sandbox"))))

(defun imprimeur-render-parse-output (output)
  "Split pandoc's OUTPUT into (HTML . META), or return nil if malformed.
OUTPUT starts with the filter's marker line and a line of JSON, which
no document can precede; the HTML follows.  META is a plist of
:title, a string of at most 500 characters, and :lang, a language
tag or nil.  The document controls their values, so anything
unexpected is dropped."
  (let* ((start (length imprimeur-render--meta-marker))
         (end (and (string-prefix-p imprimeur-render--meta-marker output)
                   (or (string-search "\n" output start) (length output)))))
    (when-let* ((end end)
                (meta (ignore-errors
                        (json-parse-string (substring output start end)
                                           :object-type 'plist :null-object nil :false-object nil)))
                ((plistp meta)))
      (let ((title (plist-get meta :title))
            (lang (plist-get meta :lang)))
        (cons (substring output (min (1+ end) (length output)))
              (list :title (and (stringp title) (substring title 0 (min 500 (length title))))
                    :lang (and (stringp lang)
                               (string-match-p "\\`[A-Za-z]\\{2,3\\}\\(?:-[A-Za-z0-9]\\{1,8\\}\\)*\\'"
                                               lang)
                               lang)))))))

(defun imprimeur-render--finish (process outcome)
  "End the render of PROCESS with OUTCOME, once: clean up, then call back.
The callback is not called if the render was cancelled."
  (unless (process-get process :done)
    (process-put process :done t)
    (cancel-timer (process-get process :timer))
    (delete-process process)
    (delete-process (process-get process :stderr))
    (kill-buffer (process-buffer (process-get process :stderr)))
    (kill-buffer (process-buffer process))
    (unless (process-get process :cancelled)
      (funcall (process-get process :callback) outcome))))

(defun imprimeur-render--filter (process output)
  "Collect OUTPUT of PROCESS, and stop it beyond the output limit."
  (with-current-buffer (process-buffer process)
    (goto-char (point-max))
    (insert output)
    (when (> (buffer-size) imprimeur-render--output-limit)
      (imprimeur-render--finish process (list :error 'too-large "Output too large")))))

(defun imprimeur-render--sentinel (process _event)
  "Report the outcome of PROCESS once it has exited."
  (unless (or (process-live-p process) (process-get process :done))
    (let ((stderr (string-trim (with-current-buffer (process-buffer (process-get process :stderr))
                                 (buffer-string))))
          (output (with-current-buffer (process-buffer process) (buffer-string))))
      (imprimeur-render--finish
       process
       (cond ((not (eq (process-status process) 'exit))
              (list :error 'exit (format "pandoc was killed by a signal: %s" stderr)))
             ((/= (process-exit-status process) 0)
              (list :error 'exit stderr))
             (t (let ((parsed (imprimeur-render-parse-output output)))
                  (if parsed
                      (list :ok (car parsed) (cdr parsed) (and (> (length stderr) 0) stderr))
                    (list :error 'bad-output "pandoc's output lacks the filter's metadata")))))))))

(defun imprimeur-render-start (spec callback)
  "Start one render as SPEC says, and call CALLBACK once with its outcome.
SPEC is a plist of :program, :arguments, :text and :directory, the
working directory.  The outcome is (:ok HTML META WARNINGS) or (:error
KIND TEXT), KIND being one of `spawn', `exit', `timeout', `too-large'
and `bad-output'; WARNINGS is pandoc's standard error, or nil.  When
pandoc cannot start, CALLBACK is called before this returns nil.
Otherwise return the process, a handle for `imprimeur-render-cancel'."
  (let* ((default-directory (file-name-as-directory (plist-get spec :directory)))
         (stderr (make-pipe-process :name "imprimeur-pandoc-stderr" :noquery t
                                    :buffer (generate-new-buffer " *imprimeur-pandoc-stderr*")
                                    :sentinel #'ignore))
         (output (generate-new-buffer " *imprimeur-pandoc*"))
         (process (condition-case error
                      (make-process :name "imprimeur-pandoc" :noquery t :buffer output
                                    :command (cons (plist-get spec :program)
                                                   (plist-get spec :arguments))
                                    :connection-type 'pipe :coding 'utf-8-unix :stderr stderr
                                    :filter #'imprimeur-render--filter
                                    :sentinel #'imprimeur-render--sentinel)
                    (file-error
                     (kill-buffer output)
                     (kill-buffer (process-buffer stderr))
                     (delete-process stderr)
                     (funcall callback (list :error 'spawn (error-message-string error)))
                     nil))))
    (when process
      (process-put process :callback callback)
      (process-put process :stderr stderr)
      (process-put process :timer
                   (run-at-time imprimeur-render-timeout nil #'imprimeur-render--finish process
                                (list :error 'timeout
                                      (format "pandoc took longer than %s s" imprimeur-render-timeout))))
      ;; A pandoc that exits before reading all its input closes the pipe,
      ;; and writing signals an error; its sentinel reports how it ended.
      (ignore-errors
        (process-send-string process (plist-get spec :text))
        (process-send-eof process)))
    process))

(defun imprimeur-render-cancel (process)
  "Stop the render PROCESS without calling its callback."
  (process-put process :cancelled t)
  (imprimeur-render--finish process nil))

(provide 'imprimeur-render)

;;; imprimeur-render.el ends here
