;;; imprimeur-skin.el --- The skins of imprimeur  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; A skin is a manifest: stylesheets and the files they refer to under one
;; directory, pandoc filters run after imprimeur.lua, and options that the
;; page reads as attributes of its root.  `imprimeur-skin-define' registers
;; one.  Installing a skin is installing code: its stylesheet and its module run
;; in the page, its filters in pandoc, and its package with the user's rights.
;;
;; A manifest is a boundary: `imprimeur-skin-parse-manifest' refuses what it
;; does not know, so that a key added later is additive.  Its stages are the
;; `imprimeur-skin--parse-' functions, which throw their refusal to it.  What
;; reaches the page or pandoc from a skin is what was registered here, compared
;; as whole strings: nothing from a page or a document becomes a path, a pandoc
;; argument or an attribute.

;;; Code:

(require 'map)
(require 'seq)
(require 'imprimeur-render)

(defcustom imprimeur-skin 'auto
  "The skin of a view for which no command has chosen.
`auto' means Minitel when its package is installed, and otherwise the
plain page, the skin `base', which holds nothing but the page's base.css.
Another symbol names a skin that `imprimeur-skin-define' registered; one
that nothing registered means `auto', and the echo area says so when a
session starts."
  :type 'symbol
  :group 'imprimeur)

(defcustom imprimeur-skin-options nil
  "The values of skins' options to start from, by skin then by option.
For example ((xix (measure . \"28\"))).  `imprimeur-set-skin-option' gives
the line to keep here.  An entry of a registered skin that it does not
register warns once and is ignored."
  :type '(alist :key-type (symbol :tag "Skin")
                :value-type (alist :key-type (symbol :tag "Option")
                                   :value-type (string :tag "Value")))
  :group 'imprimeur)

(defconst imprimeur-skin--keys
  '(:title :directory :stylesheets :files :filters :smart :notes :module :keys :auto :options
    :menu-key)
  "The keys of a manifest.")

(defconst imprimeur-skin--reserved-keys '("S" "O" "t" "[" "]" "u" "+" "-")
  "The page's keys that no skin's module may take, kept for the core.")

(defconst imprimeur-skin--key-names '("Enter" "Backspace" "Escape")
  "The page's keys that a skin's module may take by a name.
It may take any other by its one printable ASCII character, space apart.")

(defconst imprimeur-skin--media-types
  '(("css" . "text/css; charset=utf-8") ("svg" . "image/svg+xml") ("png" . "image/png")
    ("webp" . "image/webp") ("mjs" . "text/javascript; charset=utf-8"))
  "The extensions of the files of a skin, with their media types.")

(defconst imprimeur-skin--file-regexp
  "\\`[A-Za-z0-9_-][A-Za-z0-9._-]*\\(?:/[A-Za-z0-9_-][A-Za-z0-9._-]*\\)*\\'"
  "A file name that a skin may list: no space, accent, `..', `%' or leading dot.")

(defconst imprimeur-skin--name-regexp "\\`[a-z][a-z0-9-]\\{0,63\\}\\'"
  "A skin's name, or the name of a shared filter.")

(defconst imprimeur-skin--id-regexp "\\`[a-z][a-z0-9-]\\{0,31\\}\\'"
  "An option's identifier.")

(defconst imprimeur-skin--value-regexp "\\`[a-z0-9-]\\{1,32\\}\\'"
  "A value of an option.")

(defvar imprimeur-skin--registry (list (list "base" :title "Plain"))
  "Alist from a skin's name, a string, to its parsed manifest.
A name from elsewhere is compared here, and never interned.  The skin
`base' is no manifest's: it is the page with no sheet of a skin's.")

(defvar imprimeur-skin--warned nil
  "The entries of `imprimeur-skin-options' already warned of.")

(defun imprimeur-skin--refuse (format-string &rest arguments)
  "Stop the parse with the refusal that FORMAT-STRING and ARGUMENTS say."
  (throw 'imprimeur-skin--refused (list :error (apply #'format format-string arguments))))

(defun imprimeur-skin--parse-shape (name manifest)
  "Refuse a NAME or a MANIFEST whose keys are not those of a manifest."
  (unless (and (symbolp name)
               (let ((case-fold-search nil))
                 (string-match-p imprimeur-skin--name-regexp (symbol-name name))))
    (imprimeur-skin--refuse "the name %S is not of [a-z][a-z0-9-]*" name))
  (when (memq name '(base auto))
    (imprimeur-skin--refuse "the name %S is the core's" name))
  (unless (plistp manifest)
    (imprimeur-skin--refuse "the manifest is not a list of keys and values"))
  (when-let* ((unknown (seq-difference (map-keys manifest) imprimeur-skin--keys)))
    (imprimeur-skin--refuse "the key %S is unknown" (car unknown)))
  (unless (stringp (plist-get manifest :title))
    (imprimeur-skin--refuse "it has no :title")))

(defun imprimeur-skin--parse-directory (directory)
  "Return DIRECTORY, local and absolute once ~ is expanded, or refuse."
  (unless (and (stringp directory) (not (file-remote-p directory)) (file-name-absolute-p directory))
    (imprimeur-skin--refuse "the directory %S is not local and absolute" directory))
  (file-name-as-directory (expand-file-name directory)))

(defun imprimeur-skin--parse-file (directory name extensions)
  "Return NAME, a regular file under DIRECTORY of one of EXTENSIONS, or refuse."
  (unless (and (stringp name) (string-match-p imprimeur-skin--file-regexp name)
               (member (file-name-extension name) extensions)
               (file-regular-p (expand-file-name name directory)))
    (imprimeur-skin--refuse "%S is no file that it may list" name))
  name)

(defun imprimeur-skin--parse-filter (directory filter)
  "Return the absolute name of FILTER, or refuse.
A string is a file under DIRECTORY; a symbol names a shared filter."
  (if (stringp filter)
      (expand-file-name (imprimeur-skin--parse-file directory filter '("lua")) directory)
    (unless (and filter (symbolp filter) (string-match-p imprimeur-skin--name-regexp (symbol-name filter))
                 (not (memq filter '(imprimeur finish))))
      (imprimeur-skin--refuse "%S is no shared filter" filter))
    (let ((file (expand-file-name (format "pandoc/filters/%s.lua" filter) imprimeur-render-assets)))
      (unless (file-regular-p file)
        (imprimeur-skin--refuse "%S is no shared filter" filter))
      file)))

(defun imprimeur-skin--parse-module (directory module)
  "Return MODULE, nil or one .mjs file under DIRECTORY, or refuse."
  (and module (imprimeur-skin--parse-file directory module '("mjs"))))

(defun imprimeur-skin--parse-keys (keys module)
  "Return KEYS, the page's keys for the module of a manifest, MODULE, or refuse.
Each is exact as the page reads it, so that S is no s, and holds no modifier."
  (unless (and (proper-list-p keys) (or module (not keys)))
    (imprimeur-skin--refuse ":keys is no list, or there is no module to take them"))
  (dolist (key keys)
    (unless (and (stringp key)
                 (or (member key imprimeur-skin--key-names) (string-match-p "\\`[!-~]\\'" key))
                 (not (member key imprimeur-skin--reserved-keys)))
      (imprimeur-skin--refuse "%S is no key that a module may take" key)))
  (unless (equal keys (seq-uniq keys))
    (imprimeur-skin--refuse ":keys holds a key twice"))
  keys)

(defun imprimeur-skin--parse-menu-key (key)
  "Return KEY, nil or one lower-case letter or digit, or refuse.
An option's key in the menu is a capital, so a skin's cannot take one."
  (unless (or (null key) (and (stringp key) (string-match-p "\\`[a-z0-9]\\'" key)))
    (imprimeur-skin--refuse ":menu-key %S is neither a lower-case letter nor a digit" key))
  key)

(defun imprimeur-skin--parse-choices (id choices)
  "Refuse the CHOICES of the option ID unless they are registered values."
  (unless (and (proper-list-p choices) (<= 2 (length choices) 64)
               (seq-every-p (lambda (choice)
                              (and (consp choice) (stringp (car choice)) (stringp (cdr choice))
                                   (string-match-p imprimeur-skin--value-regexp (car choice))))
                            choices)
               (equal choices (seq-uniq choices (lambda (a b) (equal (car a) (car b))))))
    (imprimeur-skin--refuse "the choices of %S are not from 2 to 64 values of [a-z0-9-]" id)))

(defun imprimeur-skin--parse-options (options)
  "Return OPTIONS, or refuse.
Each is (ID :label LABEL :choices CHOICES :default VALUE)."
  (unless (and (proper-list-p options) (seq-every-p #'consp options)
               (equal options (seq-uniq options (lambda (a b) (eq (car a) (car b))))))
    (imprimeur-skin--refuse "the options are not a list of distinct options"))
  (pcase-dolist (`(,id . ,fields) options)
    (unless (and (symbolp id) (string-match-p imprimeur-skin--id-regexp (symbol-name id))
                 (stringp (plist-get fields :label)))
      (imprimeur-skin--refuse "the option %S has no identifier of [a-z][a-z0-9-]* or no :label" id))
    (imprimeur-skin--parse-choices id (plist-get fields :choices))
    (unless (assoc (plist-get fields :default) (plist-get fields :choices))
      (imprimeur-skin--refuse "the default of %S is none of its choices" id)))
  options)

(defun imprimeur-skin-parse-manifest (name manifest)
  "Parse MANIFEST, the keys and values given for the skin NAME.
Return (:ok PLIST), whose :directory is absolute and :filters absolute
file names, or (:error MESSAGE)."
  (catch 'imprimeur-skin--refused
    (imprimeur-skin--parse-shape name manifest)
    (let* ((case-fold-search nil)
           (directory (imprimeur-skin--parse-directory (plist-get manifest :directory)))
           (listed (lambda (key extensions)
                     (let ((names (plist-get manifest key)))
                       (unless (proper-list-p names)
                         (imprimeur-skin--refuse "%S is not a list" key))
                       (mapcar (lambda (file) (imprimeur-skin--parse-file directory file extensions))
                               names))))
           ;; A skin has one module, which `:files' may not add to.
           (extensions (remove "mjs" (mapcar #'car imprimeur-skin--media-types)))
           (stylesheets (funcall listed :stylesheets '("css")))
           (files (funcall listed :files extensions))
           (filters (plist-get manifest :filters)))
      (unless stylesheets
        (imprimeur-skin--refuse "it has no stylesheet"))
      (unless (proper-list-p filters)
        (imprimeur-skin--refuse ":filters is not a list"))
      (unless (memq (plist-get manifest :smart) '(nil t))
        (imprimeur-skin--refuse ":smart is neither t nor nil"))
      (unless (memq (plist-get manifest :notes) '(nil section))
        (imprimeur-skin--refuse ":notes is neither `section' nor nil"))
      (unless (memq (plist-get manifest :auto) '(nil t))
        (imprimeur-skin--refuse ":auto is neither t nor nil"))
      (list :ok (list :title (plist-get manifest :title)
                      :directory directory :stylesheets stylesheets :files files
                      :filters (mapcar (lambda (filter) (imprimeur-skin--parse-filter directory filter))
                                       filters)
                      :smart (plist-get manifest :smart) :notes (plist-get manifest :notes)
                      :module (imprimeur-skin--parse-module directory (plist-get manifest :module))
                      :keys (imprimeur-skin--parse-keys (plist-get manifest :keys) (plist-get manifest :module))
                      :auto (plist-get manifest :auto)
                      :menu-key (imprimeur-skin--parse-menu-key (plist-get manifest :menu-key))
                      :options (imprimeur-skin--parse-options (plist-get manifest :options)))))))

;;;###autoload
(defun imprimeur-skin-define (name &rest manifest)
  "Register the skin NAME, a symbol, as MANIFEST says, and return NAME.
MANIFEST takes :title, a string; :directory, a local absolute directory;
:stylesheets, at least one file name under it, in order; :files, the
other files that a stylesheet refers to; :filters, in order, a Lua file
under the directory, or a symbol naming a shared filter of imprimeur;
:smart, t for pandoc's +smart where the format has it; :notes, `section'
for notes at the end of each section; :module, one .mjs file under the
directory, whose default export the page calls as mount({ signal, option,
key, hold, latest, goToLine }) for as long as the skin is shown; :keys, the
page's keys that the module takes through `key', each one printable ASCII
character, in exact case, or Enter, Backspace or Escape, and none that the
core keeps; :auto, t for the skin that `imprimeur-skin' at `auto' means,
the first by name if several say so; :menu-key, one lower-case letter or
digit, its key in `imprimeur-skin-menu' where `imprimeur-skin-menu-keys'
would derive one that is hard to tell from another's; and :options, a list of
\(ID :label LABEL :choices ((VALUE . LABEL)...) :default VALUE), which the
page reads as data-NAME-ID on its root when away from the default.

A manifest that the parser refuses gives a warning, and registers nothing."
  (pcase (imprimeur-skin-parse-manifest name manifest)
    (`(:ok ,parsed)
     (setf (alist-get (symbol-name name) imprimeur-skin--registry nil nil #'equal) parsed)
     name)
    (`(:error ,reason)
     (display-warning 'imprimeur (format "The skin %s is refused: %s" name reason))
     nil)))

(defun imprimeur-skin-get (name)
  "Return the parsed manifest of the skin NAME, a string, or nil."
  (cdr (assoc name imprimeur-skin--registry)))

(defun imprimeur-skin-names ()
  "Return the names of the registered skins, sorted."
  (sort (mapcar #'car imprimeur-skin--registry)))

(defun imprimeur-skin-menu-keys (entries)
  "Return the keys of the menu, as an alist from each name of ENTRIES to its key.
ENTRIES is an alist from a name to the key that it asks for, or nil.  A key
asked for goes to the first name that asks, and each other name takes the
first free letter of its own, and then of the alphabet.  Names go in sorted
order, so that the order of ENTRIES, which is that of loading, changes
nothing, though a skin installed later may take a letter from a name after it:
only a key asked for stays.  A name left with no letter has no key."
  (let ((sorted (seq-sort-by #'car #'string< entries))
        (taken nil)
        (keys nil))
    (pcase-dolist (`(,name . ,key) sorted)
      (when (and key (not (member key taken)))
        (push key taken)
        (push (cons name key) keys)))
    (pcase-dolist (`(,name . ,_) sorted)
      (unless (assoc name keys)
        (when-let* ((letter (seq-find (lambda (letter)
                                        (and (<= ?a letter ?z)
                                             (not (member (string letter) taken))))
                                      (concat name "abcdefghijklmnopqrstuvwxyz"))))
          (push (string letter) taken)
          (push (cons name (string letter)) keys))))
    (nreverse keys)))

(defun imprimeur-skin-initial-name ()
  "Return the name of the skin that `imprimeur-skin' asks for.
`auto' gives the first skin registered with :auto, or else `base'.  So
does one that nothing registered, with a message that says so."
  (let ((name (symbol-name imprimeur-skin))
        (auto (or (seq-find (lambda (name) (plist-get (imprimeur-skin-get name) :auto))
                            (imprimeur-skin-names))
                  "base")))
    (cond ((eq imprimeur-skin 'auto) auto)
          ((imprimeur-skin-get name) name)
          (t (message "No skin %s is registered: %s stands in" name auto)
             auto))))

(defun imprimeur-skin-render-key (manifest)
  "Return what of MANIFEST changes what pandoc writes."
  (list (plist-get manifest :filters) (plist-get manifest :smart) (plist-get manifest :notes)))

(defun imprimeur-skin-served-file (path)
  "Return (FILE . MEDIA-TYPE) for PATH, skins/NAME/GENERATION/FILE, or nil.
NAME is registered, GENERATION is digits, and FILE is listed by its
manifest, compared whole with no decoding, and regular.  Any registered
skin is served, as a load may be in flight when the reader has moved on."
  (when (and path (string-match "\\`skins/\\([^/]+\\)/[0-9]+/\\(.+\\)\\'" path))
    (let* ((file (match-string 2 path))
           (skin (imprimeur-skin-get (match-string 1 path)))
           (absolute (and (member file (cons (plist-get skin :module)
                                             (append (plist-get skin :stylesheets) (plist-get skin :files))))
                          (expand-file-name file (plist-get skin :directory)))))
      (and absolute (file-regular-p absolute)
           (cons absolute (cdr (assoc (file-name-extension file) imprimeur-skin--media-types)))))))

(defun imprimeur-skin-module-data (manifest)
  "Return what a page needs to run the module of MANIFEST, or nil if it has none.
That is its file, the keys it may take, and the default of each option,
which the root does not hold."
  (when-let* ((file (plist-get manifest :module)))
    (list :file file
          :keys (vconcat (plist-get manifest :keys))
          :defaults (mapcar (lambda (option) (cons (car option) (plist-get (cdr option) :default)))
                            (plist-get manifest :options)))))

(defun imprimeur-skin-configured (name manifest)
  "Return the values that `imprimeur-skin-options' gives the skin NAME.
They are an alist from an option of MANIFEST to one of its values; an
entry that MANIFEST does not register warns once, and is left out."
  (seq-filter
   (lambda (entry)
     (let* ((option (assq (car-safe entry) (plist-get manifest :options)))
            (known (assoc (cdr-safe entry) (plist-get (cdr option) :choices))))
       (unless (or known (member (cons name entry) imprimeur-skin--warned))
         (push (cons name entry) imprimeur-skin--warned)
         (display-warning 'imprimeur (format "The skin %s registers no entry %S" name entry)))
       known))
   (alist-get (intern-soft name) imprimeur-skin-options)))

(defun imprimeur-skin-option-value (option configured chosen)
  "Return the value in force of OPTION, an entry of a manifest's :options.
It is in CHOSEN, or else in CONFIGURED, each an alist from an option to a
registered value, or else OPTION's default."
  (or (alist-get (car option) chosen)
      (alist-get (car option) configured)
      (plist-get (cdr option) :default)))

(defun imprimeur-skin-attributes (name manifest configured chosen)
  "Return the root's attributes for the skin NAME, as [[ATTRIBUTE VALUE]...].
An option of MANIFEST has the value that `imprimeur-skin-option-value' says
from CONFIGURED and CHOSEN.  At its default it has no attribute, so that the
root stays bare."
  (vconcat
   (seq-keep (lambda (option)
               (let ((value (imprimeur-skin-option-value option configured chosen)))
                 (and (not (equal value (plist-get (cdr option) :default)))
                      (vector (format "data-%s-%s" name (car option)) value))))
             (plist-get manifest :options))))

(provide 'imprimeur-skin)

;;; imprimeur-skin.el ends here
