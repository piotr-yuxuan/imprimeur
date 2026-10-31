;;; imprimeur.el --- Typeset live previews of Org and Markdown  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; Author: piotr-yuxuan <piotr-yuxuan@users.noreply.github.com>
;; Maintainer: piotr-yuxuan <piotr-yuxuan@users.noreply.github.com>
;; URL: https://github.com/piotr-yuxuan/imprimeur
;; Version: 0.0.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: hypermedia, wp, tools

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the licences
;; for more details.

;;; Commentary:

;; imprimeur renders the current buffer, Org, Markdown or another format
;; that pandoc reads, into a typeset page shown beside the source in Emacs
;; or in a browser window.  The page follows the unsaved text, the scrolling
;; and the colours of the Emacs theme.
;;
;; This version holds only the package header; the features come with the
;; following plans.

;;; Code:

(provide 'imprimeur)

;;; imprimeur.el ends here
