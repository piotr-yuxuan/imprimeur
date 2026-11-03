;;; imprimeur-skin-ecrivain-align.el --- Capture the pages that `align' judges  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Run by tests/imprimeur-skin-ecrivain/align, never by `make check', as it needs the skin's
;; fonts and, for WebKit, a display.  ALIGN_ENGINE says chromium, a headless browser in a
;; batch Emacs, or webkit, an xwidget in an Emacs on the virtual display that `align'
;; starts.  ALIGN_CASES names the cases, DOCUMENT-HAND-SHEET-WIDTH[-dark], and each writes
;; STEM.json and its slices under ALIGN_OUT, as helpers/align-check.py reads them.

;;; Code:

(require 'imprimeur-test-helpers)
(require 'imprimeur-test-cdp)
(require 'imprimeur)
(require 'imprimeur-skin-ecrivain)

(defconst imprimeur-skin-ecrivain-align-out (file-name-as-directory (getenv "ALIGN_OUT"))
  "Where the slices go.")

(defconst imprimeur-skin-ecrivain-align-root
  (file-name-as-directory (getenv "ALIGN_ROOT"))
  "The clone whose skin and samples are judged.")

(defconst imprimeur-skin-ecrivain-align-viewport 1000
  "The height of the page's view, in CSS pixels.")

(defconst imprimeur-skin-ecrivain-align-step 960
  "How far one slice starts below the last, in CSS pixels.")

(defun imprimeur-skin-ecrivain-align-case (name)
  "Return the plist of the case called NAME."
  (pcase-let ((`(,document ,hand ,sheet ,width ,dark) (split-string name "-")))
    (list :name name
          :file (pcase document ("fr" "carnet.org") ("en" "notebook.md"))
          :width (string-to-number width)
          :appearance (if dark 'dark 'light)
          :options `(,@(and (equal hand "trad") '((hand . "trad")))
                     ,@(and (equal sheet "pages") '((sheet . "pages")))))))

(defun imprimeur-skin-ecrivain-align-capture (run shot stem width)
  "Capture the page as STEM at WIDTH, by RUN, which evaluates a script, and SHOT.
SHOT takes the start of a picture's name and the offset to show."
  (funcall run (with-temp-buffer
                 (insert-file-contents
                  (expand-file-name "tests/imprimeur-skin-ecrivain/helpers/align.js"
                                    imprimeur-skin-ecrivain-align-root))
                 (buffer-string)))
  (let* ((facts (funcall run (format "ecrivainAlign.probe(%d)" imprimeur-skin-ecrivain-align-viewport)))
         (height (plist-get (json-parse-string facts :object-type 'plist) :height)))
    (with-temp-file (expand-file-name (concat stem ".json") imprimeur-skin-ecrivain-align-out)
      (insert facts))
    (dolist (part '("real" "ink"))
      (funcall run (format "ecrivainAlign.inkOnly(%s); 'ok'" (if (equal part "ink") "true" "false")))
      (let ((top 0))
        (while (< top height)
          (funcall shot (expand-file-name (format "%s-%s-" stem part) imprimeur-skin-ecrivain-align-out)
                   top)
          (setq top (+ top imprimeur-skin-ecrivain-align-step)))))
    (funcall run "ecrivainAlign.inkOnly(false); 'ok'")
    (message "%s: %s px wide, %d px tall" stem width height)))

(defmacro imprimeur-skin-ecrivain-align-with-document (spec &rest body)
  "Run BODY with BUFFER visiting the sample of CASE under the case's options.
SPEC is (BUFFER CASE)."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,case) spec))
    `(let* ((imprimeur-skin 'ecrivain)
            (imprimeur-skin-options (list (cons 'ecrivain (plist-get ,case :options))))
            (imprimeur-appearance (plist-get ,case :appearance))
            (imprimeur-target 'browser)
            (browse-url-browser-function #'ignore)
            (imprimeur-browser-program
             (expand-file-name "tests/bin/fake-browser" imprimeur-skin-ecrivain-align-root))
            (imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
            (,buffer (find-file-noselect
                      (expand-file-name (concat "examples/ecrivain/" (plist-get ,case :file))
                                        imprimeur-skin-ecrivain-align-root))))
       (unwind-protect
           (progn (with-current-buffer ,buffer (imprimeur-mode 1)) ,@body)
         (with-current-buffer ,buffer (imprimeur-mode -1))
         (kill-buffer ,buffer)))))

(defconst imprimeur-skin-ecrivain-align-settled
  "!!document.documentElement.dataset.revision
&& document.documentElement.dataset.skin === 'ecrivain'
&& [...document.querySelectorAll('main pre.mermaid')].every((pre) => pre.querySelector('svg'))
&& [...document.images].every((image) => image.complete)"
  "A script that is true once the page has all it will draw.")

(defun imprimeur-skin-ecrivain-align-chromium (browser case)
  "Capture CASE in BROWSER."
  (imprimeur-skin-ecrivain-align-with-document (buffer case)
    (let ((width (plist-get case :width)))
      (imprimeur-test-cdp-call browser "Emulation.setDeviceMetricsOverride"
                               `(:width ,width :height ,imprimeur-skin-ecrivain-align-viewport
                                        :deviceScaleFactor 1 :mobile :false))
      ;; A picture beyond the view has no scrollbar, so the page must lay out without one.
      (imprimeur-test-cdp-call browser "Emulation.setScrollbarsHidden" '(:hidden t))
      (imprimeur-test-cdp-navigate browser (imprimeur-url buffer))
      (imprimeur-test-cdp-wait browser imprimeur-skin-ecrivain-align-settled 60)
      (imprimeur-test-cdp-eval browser "document.fonts.ready.then(() => new Promise((done) => setTimeout(done, 1000)))")
      (imprimeur-skin-ecrivain-align-capture
       (lambda (script) (imprimeur-test-cdp-eval browser script))
       (lambda (name top)
         (with-temp-file (format "%s%d.png" name top)
           (set-buffer-multibyte nil)
           (insert (base64-decode-string
                    (plist-get (imprimeur-test-cdp-call
                                browser "Page.captureScreenshot"
                                `(:format "png" :captureBeyondViewport t
                                          :clip (:x 0 :y ,top :width ,width
                                                    :height ,imprimeur-skin-ecrivain-align-viewport :scale 1)))
                               :data)))))
       (concat "chromium-" (plist-get case :name)) width))))

(defun imprimeur-skin-ecrivain-align-run-chromium ()
  "Capture every case of ALIGN_CASES in a headless Chromium, and exit."
  (imprimeur-test-cdp-with-browser browser
    (dolist (name (split-string (getenv "ALIGN_CASES")))
      (imprimeur-skin-ecrivain-align-chromium browser (imprimeur-skin-ecrivain-align-case name))))
  (kill-emacs 0))

;; WebKit, on a display of its own.

(defun imprimeur-skin-ecrivain-align-pause (seconds)
  "Let Emacs run for SECONDS, reading events: an xwidget's answer comes as one."
  (let ((deadline (+ (float-time) seconds)))
    (while (< (float-time) deadline)
      (read-event nil nil (max 0.01 (- deadline (float-time)))))))

(defun imprimeur-skin-ecrivain-align-script (session script)
  "Return what SCRIPT gives in SESSION, the xwidget, within 30 seconds."
  (let ((value nil) (done nil) (deadline (+ (float-time) 30)))
    (xwidget-webkit-execute-script session script (lambda (result) (setq value result done t)))
    (while (and (not done) (< (float-time) deadline))
      (imprimeur-skin-ecrivain-align-pause 0.05))
    value))

(defun imprimeur-skin-ecrivain-align-webkit (case)
  "Capture CASE in the xwidget of the selected frame."
  (imprimeur-skin-ecrivain-align-with-document (buffer case)
    (let ((width (plist-get case :width)) session)
      (xwidget-webkit-browse-url (imprimeur-url buffer) t)
      (setq session (xwidget-webkit-current-session))
      (with-current-buffer (xwidget-buffer session)
        (setq-local mode-line-format nil header-line-format nil))
      (switch-to-buffer (xwidget-buffer session))
      (delete-other-windows)
      (redisplay t)
      (xwidget-resize session width imprimeur-skin-ecrivain-align-viewport)
      (let ((deadline (+ (float-time) 60)))
        (while (and (< (float-time) deadline)
                    (not (eq t (imprimeur-skin-ecrivain-align-script
                                session (concat "(" imprimeur-skin-ecrivain-align-settled ") ? true : false")))))
          (imprimeur-skin-ecrivain-align-pause 0.25)))
      (imprimeur-skin-ecrivain-align-pause 2)
      (imprimeur-skin-ecrivain-align-capture
       (lambda (script) (imprimeur-skin-ecrivain-align-script session script))
       (lambda (name top)
         ;; The foot of the page stops the scroll short, so a slice is named where it is.
         (let ((actual (imprimeur-skin-ecrivain-align-script
                        session (format "window.scrollTo(0, %d); String(Math.round(window.scrollY))" top))))
           (redisplay t)
           (imprimeur-skin-ecrivain-align-pause 0.5)
           (call-process (getenv "ALIGN_IMPORT") nil nil nil "-silent" "-display" (getenv "DISPLAY")
                         "-window" "root" (format "%s%s.png" name actual))))
       (concat "webkit-" (plist-get case :name)) width)
      (kill-emacs 0))))

(defun imprimeur-skin-ecrivain-align-run-webkit ()
  "Capture the one case of ALIGN_CASES in an xwidget, and exit."
  (setq frame-resize-pixelwise t frame-inhibit-implied-resize t inhibit-startup-screen t
        ring-bell-function #'ignore xwidget-webkit-enable-plugins nil)
  (setq-default mode-line-format nil)
  (menu-bar-mode -1)
  (tool-bar-mode -1)
  (scroll-bar-mode -1)
  (blink-cursor-mode -1)
  (fringe-mode 0)
  (set-frame-parameter nil 'internal-border-width 0)
  (set-frame-position nil 0 0)
  (set-frame-size nil (x-display-pixel-width) (x-display-pixel-height) t)
  (imprimeur-skin-ecrivain-align-pause 0.5)
  (run-at-time
   0.5 nil
   (lambda ()
     (condition-case failure
         (imprimeur-skin-ecrivain-align-webkit (imprimeur-skin-ecrivain-align-case (getenv "ALIGN_CASES")))
       (error (princ (format "%S\n" failure) #'external-debugging-output)
              (kill-emacs 1))))))

(provide 'imprimeur-skin-ecrivain-align)

;;; imprimeur-skin-ecrivain-align.el ends here
