;;; make-demo.el --- Play the 30 seconds of the demo  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Loaded by scripts/make-demo in a graphic `emacs -Q' on a virtual display.  It opens
;; every document first, then starts DEMO_RECORD, a shell command, and plays a fixed
;; timeline.  The echo area says what happens, as the video is silent, and DEMO_KEYS names
;; a file to hold the keys pressed, as `TIME TEXT' lines, which scripts/make-demo draws over
;; the video.  Exit status 1, with the reason on standard error, if a page never shows or a
;; step fails.

;;; Code:

(defvar byte-compile-current-file)

(eval-and-compile
  (add-to-list 'load-path (expand-file-name "../imprimeur"
                                            (file-name-directory (or load-file-name
                                                                     byte-compile-current-file)))))

(require 'xwidget)
(require 'org)
(require 'imprimeur)
(require 'imprimeur-xwidget)

(declare-function xwidget-webkit-execute-script "xwidget.c" (xwidget script &optional callback))

(defvar demo-start 0
  "When the recording began, in seconds.")

(defvar demo-keys nil
  "The keys pressed so far, latest first, each as (SECONDS . TEXT).")

(defun demo-note-key (text)
  "Note that TEXT was pressed now."
  (push (cons (- (float-time) demo-start) text) demo-keys))

(defun demo-refuse (reason)
  "End this Emacs with status 1, printing REASON."
  (princ (concat "make-demo: " reason "\n") #'external-debugging-output)
  (kill-emacs 1))

(defun demo-pump (seconds)
  "Let Emacs run for SECONDS, redisplay and events included."
  (let ((deadline (+ (float-time) seconds)))
    (while (< (float-time) deadline)
      (redisplay)
      (sit-for 0.02 t))))

(defun demo-at (seconds)
  "Let Emacs run until SECONDS into the recording."
  (demo-pump (max 0 (- (+ demo-start seconds) (float-time)))))

(defun demo-view (source)
  "Return the view of the buffer SOURCE."
  (imprimeur--session-view (buffer-local-value 'imprimeur--session source)))

(defun demo-ready-p (source)
  "Return whether the page of SOURCE is whole within a minute.
That is its document shown, a diagram drawn, and its pictures loaded."
  (let ((xwidget (buffer-local-value 'imprimeur-xwidget--xwidget (demo-view source)))
        (deadline (+ (float-time) 60))
        (ready nil))
    (while (and (not ready) (< (float-time) deadline))
      (xwidget-webkit-execute-script
       xwidget "JSON.stringify(!!document.documentElement.dataset.revision && (document.querySelectorAll('main pre.mermaid').length === 0 || !!document.querySelector('main pre.mermaid svg')) && [...document.images].every((image) => image.complete))"
       (lambda (value) (setq ready (equal value "true"))))
      (demo-pump 0.25))
    ready))

(defun demo-open (file skin)
  "Return a buffer visiting FILE, under the repository, its page ready in SKIN."
  (let ((source (find-file-noselect (expand-file-name file (getenv "DEMO_ROOT"))))
        (imprimeur-skin skin))
    (delete-other-windows)
    (switch-to-buffer source)
    (imprimeur-mode 1)
    (unless (demo-ready-p source)
      (demo-refuse (format "the page of %s never shows" file)))
    source))

(defun demo-show (source)
  "Show the buffer SOURCE beside its page, with SOURCE selected, from its top."
  (delete-other-windows)
  (switch-to-buffer source)
  (goto-char (point-min))
  (imprimeur-xwidget-display (demo-view source)))

(defun demo-type (text)
  "Type TEXT at point, a key at a time."
  (demo-note-key text)
  (mapc (lambda (char)
          (execute-kbd-macro (vector char))
          (demo-pump 0.05))
        text))

(defun demo-press (&rest keys)
  "Press each of KEYS, as `kbd' reads them, holding on each for a little."
  (dolist (key keys)
    (demo-note-key key)
    (execute-kbd-macro (kbd key))
    (demo-pump 0.2)))

(defun demo-play ()
  "Open the documents, start the recording and play the timeline."
  (let* ((showcase (demo-open "examples/showcase.org" 'minitel))
         (dickens (demo-open "examples/xix/dickens.md" 'xix))
         (milton (demo-open "examples/xvii/milton.md" 'xvii))
         (bagehot (demo-open "examples/briefing/bagehot.org" 'briefing))
         (tianlu (demo-open "examples/tianlu/tinggui-xiaoji.org" 'tianlu)))
    (demo-show showcase)
    (demo-pump 1.5)
    (start-process-shell-command "demo-record" "*demo-record*" (getenv "DEMO_RECORD"))
    (setq demo-start (float-time))
    (message "An Org buffer, and its page typeset beside it")
    (demo-at 2)
    (search-forward "stop typing.")
    (message "The page follows as you type, saved or not")
    (demo-type " Try it.")
    (demo-at 5)
    (goto-char (point-min))
    (search-forward "Your skin")
    (message "Change the source of a diagram, and it is drawn again")
    (demo-press "M-DEL")
    (demo-type "own")
    (demo-at 7.5)
    (message "M-g s: another skin, in place, keeping your place")
    (demo-press "M-g s")
    (dolist (key '("9" "8" "7" "r" "e"))
      (demo-press key)
      (demo-pump 0.9))
    (demo-press "m" "C-g")
    (demo-at 14)
    (message "C-x C-+ in the page zooms the page, and the source stays as it is")
    (with-selected-window (get-buffer-window (demo-view showcase))
      (demo-press "C-x C-+")
      (demo-pump 0.7)
      (demo-press "C-x C-+")
      (demo-pump 0.7)
      (demo-press "C-x C-0"))
    (demo-at 16.5)
    (message "The page takes its colours from your theme")
    (disable-theme 'sanityinc-tomorrow-night)
    (load-theme 'sanityinc-tomorrow-day t)
    (demo-at 18)
    (disable-theme 'sanityinc-tomorrow-day)
    (load-theme 'sanityinc-tomorrow-night t)
    (demo-at 18.5)
    (demo-show dickens)
    (message "Markdown too: Dickens in XIX; scrolling either side moves the other")
    (demo-at 20)
    (demo-press "C-v")
    (demo-at 21.5)
    (demo-show milton)
    (message "Milton in XVII, with its long s and its notes in the margin")
    (demo-at 24)
    (demo-show bagehot)
    (message "A briefing, from Bagehot's Lombard Street")
    (demo-at 26.5)
    (demo-show tianlu)
    (message "Tianlu: vertical Chinese, as a Song block-printed book")
    (demo-at 28.5)
    (demo-press "C-v")
    (demo-at 30.8)))

(defun demo-run ()
  "Dress this Emacs, play the timeline and end."
  (setq frame-resize-pixelwise t
        frame-inhibit-implied-resize t
        inhibit-startup-screen t
        ring-bell-function #'ignore
        native-comp-jit-compilation nil
        vc-handled-backends nil
        imprimeur-target 'xwidget
        imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
  (menu-bar-mode -1)
  (tool-bar-mode -1)
  (scroll-bar-mode -1)
  (blink-cursor-mode -1)
  (mapc #'require '(imprimeur-skin-minitel imprimeur-skin-xix imprimeur-skin-xviii imprimeur-skin-xvii
                                           imprimeur-skin-briefing imprimeur-skin-ecrivain imprimeur-skin-tianlu))
  (set-face-attribute 'default nil :family "Iosevka Nerd Font Mono" :height 110)
  (load-theme 'sanityinc-tomorrow-night t)
  (set-frame-position nil 0 0)
  (set-frame-size nil (- (display-pixel-width) (- (frame-outer-width) (frame-text-width)))
                  (- (display-pixel-height) (- (frame-outer-height) (frame-text-height)))
                  t)
  (demo-pump 1)
  (condition-case failure
      (demo-play)
    (error (demo-refuse (error-message-string failure))))
  (with-temp-file (getenv "DEMO_KEYS")
    (dolist (key (reverse demo-keys))
      (insert (format "%.2f %s\n" (car key) (cdr key)))))
  (imprimeur-stop-all)
  (kill-emacs 0))

(run-at-time 1 nil #'demo-run)

;;; make-demo.el ends here
