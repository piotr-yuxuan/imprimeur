;;; make-gallery.el --- Take one picture of the gallery  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Loaded by scripts/make-gallery in a graphic `emacs -Q' on a virtual display, one
;; Emacs per picture: a real xwidget, at scale 1, in a theme of nixpkgs.  The
;; environment says what to show, by GALLERY_SKIN, GALLERY_FILE, GALLERY_THEME,
;; GALLERY_APPEARANCE, GALLERY_FAMILY, Emacs's default family, and GALLERY_OPTIONS, the
;; skin's options to start from, as OPTION=VALUE separated by spaces; GALLERY_BESIDE, if
;; set, keeps the source beside the page, with the mode lines and with its long lines
;; running off the Emacs window, where otherwise the page has the whole Emacs frame.  GALLERY_GRAB is a shell command that takes the picture.
;;
;; Exit status 1, with the reason on standard error, for what must not ship as a picture:
;; a page in another skin than the row's, a banner with text, a page that never shows, a
;; diagram that stays as code, or a page that is not the width of its Emacs window.

;;; Code:

(defvar byte-compile-current-file)

(eval-and-compile
  (add-to-list 'load-path (expand-file-name "../imprimeur"
                                            (file-name-directory (or load-file-name
                                                                     byte-compile-current-file)))))

(require 'xwidget)
(require 'org)
(require 'imprimeur)

(declare-function xwidget-webkit-execute-script "xwidget.c" (xwidget script &optional callback))

(defun gallery-refuse (reason)
  "End this Emacs with status 1, printing REASON."
  (princ (concat "make-gallery: " reason "\n") #'external-debugging-output)
  (kill-emacs 1))

(defun gallery-pump (seconds)
  "Let Emacs run for SECONDS, redisplay and events included."
  (let ((deadline (+ (float-time) seconds)))
    (while (< (float-time) deadline)
      (redisplay)
      (read-event nil nil 0.02))))

(defun gallery-script (xwidget expression)
  "Return the value of the JavaScript EXPRESSION in the page of XWIDGET, or nil."
  (let* ((result 'no-answer)
         (deadline (+ (float-time) 10)))
    (xwidget-webkit-execute-script xwidget (format "JSON.stringify(%s)" expression)
                                   (lambda (value) (setq result value)))
    (while (and (eq result 'no-answer) (< (float-time) deadline))
      (gallery-pump 0.05))
    (and (stringp result) (not (string-empty-p result))
         (json-parse-string result :null-object nil :false-object nil))))

(defun gallery-wait (xwidget expression)
  "Wait for the JavaScript EXPRESSION in XWIDGET's page; return whether it held."
  (let ((deadline (+ (float-time) 60))
        (held nil))
    (while (and (not (setq held (gallery-script xwidget expression))) (< (float-time) deadline))
      (gallery-pump 0.25))
    held))

(defun gallery-run ()
  "Dress this Emacs as the environment says, wait for the page, take the picture."
  (setq frame-resize-pixelwise t
        frame-inhibit-implied-resize t
        inhibit-startup-screen t
        ring-bell-function #'ignore
        native-comp-jit-compilation nil
        vc-handled-backends nil
        imprimeur-target 'xwidget
        imprimeur-skin (intern (getenv "GALLERY_SKIN"))
        imprimeur-appearance (intern (getenv "GALLERY_APPEARANCE"))
        imprimeur-skin-options (list (cons (intern (getenv "GALLERY_SKIN"))
                                           (mapcar (lambda (option)
                                                     (let ((pair (string-split option "=")))
                                                       (cons (intern (car pair)) (cadr pair))))
                                                   (string-split (getenv "GALLERY_OPTIONS") " " t))))
        imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
  (unless (getenv "GALLERY_BESIDE")
    (setq imprimeur-display-buffer-action '((display-buffer-same-window)))
    (setq-default mode-line-format nil)
    (fringe-mode 0)
    (global-visual-line-mode 1))
  (menu-bar-mode -1)
  (tool-bar-mode -1)
  (scroll-bar-mode -1)
  (blink-cursor-mode -1)
  (set-face-attribute 'default nil :family (getenv "GALLERY_FAMILY") :height 110)
  (load-theme (intern (getenv "GALLERY_THEME")) t)
  (set-frame-position nil 0 0)
  ;; The echo area stands below the display.
  (set-frame-size nil (- (display-pixel-width) (- (frame-outer-width) (frame-text-width)))
                  (+ (- (display-pixel-height) (- (frame-outer-height) (frame-text-height)))
                     (frame-char-height))
                  t)
  (gallery-pump 1)
  (let ((source (find-file-noselect (getenv "GALLERY_FILE"))))
    (switch-to-buffer source)
    (imprimeur-mode 1)
    (let* ((view (imprimeur--session-view (buffer-local-value 'imprimeur--session source)))
           (xwidget (buffer-local-value 'imprimeur-xwidget--xwidget view)))
      (unless (gallery-wait xwidget "!!document.documentElement.dataset.revision")
        (gallery-refuse "the page never shows the document"))
      (unless (gallery-wait xwidget "[...document.querySelectorAll('main pre.mermaid')].every((pre) => pre.querySelector('svg'))
&& [...document.images].every((image) => image.complete)")
        (gallery-refuse "a diagram is still code, or a picture still loads"))
      (gallery-script xwidget "document.fonts.ready.then(() => 1), 1")
      (gallery-pump 2)
      (unless (equal (gallery-script xwidget "document.documentElement.dataset.skin")
                     (getenv "GALLERY_SKIN"))
        (gallery-refuse (format "the page is not in the skin %s" (getenv "GALLERY_SKIN"))))
      (let ((banner (gallery-script xwidget "document.getElementById('imprimeur-banner').textContent")))
        (when (and banner (not (string-empty-p banner)))
          (gallery-refuse (format "the page says: %s" banner))))
      (let ((width (gallery-script xwidget "window.innerWidth"))
            (wanted (if (getenv "GALLERY_BESIDE")
                        (window-body-width (get-buffer-window view) t)
                      (display-pixel-width))))
        (unless (eql width wanted)
          (gallery-refuse (format "the page is %s wide, not %d" width wanted))))
      (redisplay t)
      (gallery-pump 0.5)
      (unless (zerop (call-process-shell-command (getenv "GALLERY_GRAB")))
        (gallery-refuse "the picture could not be taken"))))
  (imprimeur-stop-all)
  (kill-emacs 0))

(run-at-time 1 nil #'gallery-run)

;;; make-gallery.el ends here
