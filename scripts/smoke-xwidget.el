;;; smoke-xwidget.el --- Check the view on a real display  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Loaded by scripts/smoke-xwidget in a graphic `emacs -Q', never by `make check':
;; what an xwidget does needs one.  Each line goes to the file that
;; IMPRIMEUR_SMOKE_RESULTS names, and starts with PASS, FAIL or REPORT; the last
;; one is DONE.  What signals fails on its own and the others run.  What
;; this waits for is bounded, and a question that Emacs asks is answered yes and
;; noted, so that a defect fails a check and stops nothing.
;;
;; IMPRIMEUR_SMOKE_PART is `all', or `video' for that report alone, whose label
;; IMPRIMEUR_SMOKE_LABEL gives.  IMPRIMEUR_SMOKE_SHOT, if set, is a shell command
;; run once while the Emacs frame shows the source and the page side by side.
;; IMPRIMEUR_SMOKE_MENU_SHOT, if set, is another, run once while the frame shows
;; the menu of skins open too.
;;
;; IMPRIMEUR_SMOKE_XDOTOOL, if set, names an xdotool, which sends a real wheel to whichever X
;; display this runs on, so set it on an Xvfb alone.  Unset, a wheel is synthetic here, as a
;; double-click always is: only the owner can check that those of a person reach the page.

;;; Code:

(defvar byte-compile-current-file)

(eval-and-compile
  (add-to-list 'load-path (expand-file-name "../imprimeur"
                                            (file-name-directory (or load-file-name
                                                                     byte-compile-current-file)))))

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'org)
(require 'face-remap)
(require 'xwidget)
(require 'imprimeur)

(declare-function xwidget-webkit-execute-script "xwidget.c" (xwidget script &optional callback))
(declare-function xwidget-webkit-goto-uri "xwidget.c" (xwidget uri))
(declare-function xwidget-webkit-uri "xwidget.c" (xwidget))
(defvar xwidget-list)

(defconst smoke-root
  (expand-file-name ".." (file-name-directory (or load-file-name byte-compile-current-file)))
  "The root of the repository.")

(defconst smoke-results (getenv "IMPRIMEUR_SMOKE_RESULTS")
  "The file that takes the lines of the report.")

(defvar smoke-questions nil
  "The questions that Emacs has asked, newest first.")

(defvar smoke-commits nil
  "The addresses of the loads committed in the xwidgets, newest first.")

(defvar smoke-media nil
  "The files that the server has served, newest first.")

(defvar smoke-input nil
  "The events that `smoke-pump' has read, newest first, what Emacs hears of input.")

(defvar smoke-stale-events 0
  "How many events of a killed xwidget the handler of xwidget.el has signalled on.")

(defun smoke-say (kind text)
  "Add the line KIND TEXT to the report."
  (let ((coding-system-for-write 'utf-8))
    (write-region (format "%s %s\n" kind text) nil smoke-results t 'silent)))

(defun smoke-check (passed name &optional detail)
  "Report the check NAME as PASSED or not, with DETAIL, a value, if given."
  (smoke-say (if passed "PASS" "FAIL")
             (concat name (and detail (format " (%s)" detail)))))

(defun smoke-pump (seconds)
  "Let Emacs run for SECONDS, redisplay and events included.
A script's result is a special event, which `sit-for' leaves in the
queue, so this reads events.  WebKit goes on sending events of an xwidget
that a view has killed, on which the handler of xwidget.el signals: that
is no failure of whichever check happens to be waiting, and is counted."
  (let ((deadline (+ (float-time) seconds)))
    (while (< (float-time) deadline)
      (redisplay)
      (condition-case failure
          (when-let* ((event (read-event nil nil 0.02)))
            (push event smoke-input))
        (wrong-type-argument
         (unless (eq (cadr failure) 'xwidget-live-p)
           (signal (car failure) (cdr failure)))
         (setq smoke-stale-events (1+ smoke-stale-events)))))))

(defun smoke-until (predicate seconds)
  "Return what PREDICATE returns once it is non-nil, or nil after SECONDS."
  (let ((deadline (+ (float-time) seconds))
        (value nil))
    (while (and (not (setq value (funcall predicate))) (< (float-time) deadline))
      (smoke-pump 0.05))
    value))

(defun smoke-script (view expression)
  "Return the value of the JavaScript EXPRESSION in VIEW's page, or `no-answer'.
It goes through JSON: false and null come back as nil."
  (let ((result 'no-answer))
    (xwidget-webkit-execute-script (buffer-local-value 'imprimeur-xwidget--xwidget view)
                                   (format "JSON.stringify(%s)" expression)
                                   (lambda (value) (setq result value)))
    (smoke-until (lambda () (not (eq result 'no-answer))) 10)
    (if (and (stringp result) (not (string-empty-p result)))
        (json-parse-string result :object-type 'plist :null-object nil :false-object nil)
      result)))

(defun smoke-wait-page (view expression seconds)
  "Return the value of EXPRESSION in the page of VIEW once it is true, or nil."
  (smoke-until (lambda ()
                 (let ((value (smoke-script view expression)))
                   (and value (not (eq value 'no-answer)) (not (eql value 0)) value)))
               seconds))

(defun smoke-block-top (view text)
  "Return how far from the top of VIEW's page the block that starts with TEXT is."
  (smoke-script view (format "[...document.querySelectorAll('#imprimeur-main > *')]
.find((block) => block.textContent.trim().startsWith('%s'))?.getBoundingClientRect().top ?? 1e9"
                             text)))

(defun smoke-wait-top (view text)
  "Return non-nil once the block starting with TEXT is at the top of VIEW's page.
Within 4 CSS pixels: where a display's dots per inch zoom the page, as the
100 of an Xvfb left to its default do, it rests up to about 2.5 from the top,
as `scrollY' and `scrollTo' keep whole pixels.  The next block is further."
  (smoke-until (lambda ()
                 (let ((top (smoke-block-top view text)))
                   (and (numberp top) (<= (abs top) 4))))
               5))

(defun smoke-position (buffer text)
  "Return where the line that holds TEXT starts in BUFFER."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (search-forward text)
      (pos-bol))))

(defun smoke-document ()
  "Make a directory holding doc.org, pic.png and hostile.md; return its name."
  (let ((directory (file-name-as-directory (make-temp-file "smoke" t))))
    (call-process "ffmpeg" nil nil nil "-nostdin" "-loglevel" "error" "-f" "lavfi"
                  "-i" "color=c=red:size=64x48:duration=0.1" "-frames:v" "1"
                  (expand-file-name "pic.png" directory))
    (with-temp-file (expand-file-name "doc.org" directory)
      (insert "#+TITLE: Smoke\n\nThe first line.\n\n[[file:pic.png]]\n\n"
              "#+begin_src mermaid\ngraph TD; A-->B;\n#+end_src\n\n")
      (dolist (number (number-sequence 1 150))
        (when (zerop (% (1- number) 20))
          (insert (format "* Section %d\n" (1+ (/ number 20)))))
        (insert (format "Paragraph %d.\n" number))
        (insert (apply #'concat (make-list (% (* 7 (1+ number)) 15) "Another line of this paragraph.\n")))
        (insert "\n")))
    (with-temp-file (expand-file-name "hostile.md" directory)
      (insert "# Hostile\n\n")
      (insert-file-contents (expand-file-name "tests/fixtures/page/hostile.html" smoke-root)))
    directory))

(defun smoke-open (file)
  "Visit FILE alone in the selected Emacs window, in `imprimeur-mode'.
Return (SOURCE SESSION WINDOW SECONDS): the buffer, its session, its
Emacs window and how long it took a page to report a revision, or nil."
  (let ((source (find-file-noselect file))
        (start (float-time)))
    (delete-other-windows)
    (switch-to-buffer source)
    (imprimeur-mode 1)
    (let ((session (buffer-local-value 'imprimeur--session source)))
      (list source session (selected-window)
            (and (smoke-until (lambda () (imprimeur--session-ready session)) 20)
                 (- (float-time) start))))))

(defun smoke-end (source)
  "Kill the buffer SOURCE, ending its session, with its changes dropped."
  (with-current-buffer source (set-buffer-modified-p nil))
  (kill-buffer source))

(defun smoke-features (view)
  "Report what the later skins need from the engine of VIEW's page."
  (dolist (entry '(("hanging-punctuation" "CSS.supports('hanging-punctuation', 'first')")
                   ("initial-letter" "CSS.supports('initial-letter', '2')")
                   ("-webkit-initial-letter" "CSS.supports('-webkit-initial-letter', '2')")
                   ("text-wrap: pretty" "CSS.supports('text-wrap', 'pretty')")))
    (smoke-say "REPORT" (format "%s: %s" (car entry)
                                (if (smoke-script view (cadr entry)) "supported" "not supported"))))
  (smoke-say "REPORT"
             (format "vertical multicolumn overflow: %S"
                     (smoke-script view "(() => {
  const box = document.body.appendChild(document.createElement('div'));
  box.style.cssText = 'position: absolute; left: 0; top: 0; writing-mode: vertical-rl; width: 120px;'
    + ' height: 100px; column-count: 1; column-gap: 20px; font: 16px/20px monospace;';
  box.textContent = 'word '.repeat(400);
  const range = document.createRange();
  range.selectNodeContents(box);
  const rects = [...range.getClientRects()];
  const [first, last] = [rects[0], rects[rects.length - 1]];
  const found = { goes: last.top > first.bottom ? 'downward' : last.left < first.left ? 'leftward' : 'nowhere',
                  firstTop: first.top, lastTop: last.top, lastLeft: last.left,
                  scrollHeight: box.scrollHeight, scrollWidth: box.scrollWidth };
  box.remove();
  return found;
})()"))))

(defun smoke-video-state (view selector)
  "Return what the page of VIEW knows of the video that SELECTOR gives."
  (smoke-script view (format "(() => {
  const video = document.querySelector(%S);
  const link = video?.nextElementSibling;
  return video && { networkState: video.networkState, readyState: video.readyState,
                    error: video.error ? video.error.code : null,
                    link: link?.textContent === 'Open externally' };
})()"
                             selector)))

(defun smoke-video ()
  "Report what holds of a video here, and check that one it cannot play has a link."
  (let* ((directory (file-name-as-directory (make-temp-file "smoke-video" t)))
         (label (or (getenv "IMPRIMEUR_SMOKE_LABEL") "as this environment gives"))
         (clip (expand-file-name "clip.webm" directory)))
    (call-process "ffmpeg" nil nil nil "-nostdin" "-loglevel" "error" "-f" "lavfi"
                  "-i" "testsrc=duration=2:size=160x120:rate=10" "-c:v" "libvpx" clip)
    (with-temp-file (expand-file-name "broken.webm" directory)
      (insert "This is no video.\n"))
    (with-temp-file (expand-file-name "video.org" directory)
      (insert "A clip.\n\n[[file:clip.webm]]\n\nNot a clip.\n\n[[file:broken.webm]]\n"))
    (pcase-let* ((`(,source ,session) (smoke-open (expand-file-name "video.org" directory)))
                 (view (imprimeur--session-view session))
                 (broken "video[src$=\"broken.webm\"]")
                 (plain "video[src$=\"clip.webm\"]"))
      (setq smoke-media nil)
      (smoke-wait-page view "document.querySelectorAll('main video').length === 2" 10)
      ;; A second is what the page gives a video; the rest is for the requests.
      (smoke-pump 3)
      (let ((clip-state (smoke-video-state view plain))
            (broken-state (smoke-video-state view broken)))
        (smoke-say "REPORT" (format "video, %s: canPlayType vp8 %S" label
                                    (smoke-script view "document.createElement('video').canPlayType('video/webm; codecs=\"vp8\"')")))
        (smoke-say "REPORT" (format "video, %s: a good clip %S, %d requests from the server" label clip-state
                                    (seq-count (lambda (file) (string-suffix-p "clip.webm" file)) smoke-media)))
        (smoke-say "REPORT" (format "video, %s: a file that is no video %S" label broken-state))
        (smoke-say "REPORT" (format "video, %s: which holds: %s" label
                                    (cond ((plist-get clip-state :error) "the clip failed with an error")
                                          ((eql (plist-get clip-state :networkState) 3)
                                           "the clip is stuck at networkState 3 with no error")
                                          (t "the clip loads"))))
        (smoke-check (plist-get broken-state :link)
                     (format "a video it cannot play offers \"Open externally\", %s" label)
                     broken-state)
        (when (or (plist-get clip-state :error) (eql (plist-get clip-state :networkState) 3))
          (smoke-check (plist-get clip-state :link)
                       (format "the clip that does not load offers \"Open externally\", %s" label)
                       clip-state)))
      (smoke-end source))))

(defun smoke-opens (source window session seconds)
  "Check where the view of SOURCE opens from WINDOW, and its SECONDS to `ready'."
  (let* ((view (imprimeur--session-view session))
         (right (window-in-direction 'right window)))
    (smoke-check (and right (eq (selected-window) window)
                      (eq (window-buffer window) source)
                      (eq (window-buffer right) view)
                      (window-dedicated-p right)
                      (<= (abs (- (window-pixel-width right) (window-pixel-width window))) 20))
                 "the view opens on the right, half wide and dedicated, with the source still selected"
                 (and right (list (window-pixel-width window) (window-pixel-width right)
                                  (window-dedicated-p right) (buffer-name (window-buffer right)))))
    (smoke-check (and (eq (buffer-local-value 'major-mode view) 'xwidget-webkit-mode)
                      (buffer-local-value 'imprimeur-view-mode view))
                 "the view's major mode is exactly xwidget-webkit-mode, with imprimeur-view-mode")
    (smoke-check (and seconds (<= seconds 5)) "ready within 5 s" seconds)))

(defun smoke-page-reports (view right)
  "Report what the page of VIEW shows, in the Emacs window RIGHT."
  (smoke-wait-page view "document.images.length > 0 && document.images[0].complete
&& document.querySelectorAll('main svg').length > 0" 20)
  (smoke-say "REPORT" (format "SVG count: %s" (smoke-script view "document.querySelectorAll('main svg').length")))
  (smoke-say "REPORT" (format "a picture's naturalWidth: %s (the file is 64 wide)"
                              (smoke-script view "document.images[0]?.naturalWidth ?? null")))
  (smoke-say "REPORT" (format "page size: %S; the Emacs window's body is %dx%d pixels; frame-scale-factor %s"
                              (smoke-script view "[window.innerWidth, window.innerHeight, window.devicePixelRatio]")
                              (window-body-width right t) (window-body-height right t)
                              (frame-scale-factor))))

(defun smoke-follows (source window view)
  "Check that VIEW's page follows the Emacs WINDOW of SOURCE and the other way."
  (with-current-buffer source
    (remove-hook 'post-command-hook #'imprimeur-sync--window-moved t))
  (select-window window)
  (set-window-start window (smoke-position source "Paragraph 51."))
  (redisplay t)
  (smoke-check (smoke-wait-top view "Paragraph 51.")
               "window-scroll-functions drive the page, with no command having run")
  (with-current-buffer source
    (add-hook 'post-command-hook #'imprimeur-sync--window-moved nil t))
  (let ((before (window-start window)))
    (select-window (get-buffer-window view))
    (execute-kbd-macro (kbd "C-v"))
    (select-window window)
    (smoke-check (smoke-until (lambda () (> (window-start window) before)) 5)
                 "a key in the view scrolls the page, and the source follows")))

(defun smoke-at-level (view base level)
  "Return non-nil once VIEW's page is at the zoom LEVEL, within 1%.
WebKit's zoom shows in `devicePixelRatio', which is BASE at the level 1."
  (smoke-until (lambda ()
                 (let ((ratio (smoke-script view "window.devicePixelRatio")))
                   (and (numberp ratio) (< (abs (- (/ ratio base) level)) 0.01))))
               5))

(defun smoke-zoom-steps (source window view base)
  "Check each way to zoom VIEW's page, at its place, from Emacs's keys in VIEW.
WINDOW shows SOURCE, and does not move.  BASE is as for `smoke-at-level'."
  (set-window-start window (smoke-position source "Paragraph 51."))
  (redisplay t)
  (smoke-wait-top view "Paragraph 51.")
  (smoke-pump 0.5)
  (let ((start (window-start window)))
    (pcase-dolist (`(,key ,amount) '(("+" 1) ("C-x C-+" 2) ("C-x C--" 1) ("-" 0) ("-" -1) ("0" 0)
                                     ("C-x C-+" 1) ("C-x C-0" 0)))
      (smoke-press view key)
      (let ((level (expt text-scale-mode-step amount)))
        (smoke-check (and (smoke-at-level view base level) (smoke-wait-top view "Paragraph 51.")
                          (= (window-start window) start))
                     (format "%s in the view: the page zooms to %.2f, at its place, and the source stays" key level)
                     (list (smoke-script view "window.devicePixelRatio") (smoke-block-top view "Paragraph 51.")
                           (window-start window)))))
    (with-current-buffer view (text-scale-increase 20))
    (smoke-check (and (smoke-at-level view base 2.99) (eql (buffer-local-value 'text-scale-mode-amount view) 6))
                 "a scale past the limit stops at it, from where one step comes back"
                 (buffer-local-value 'text-scale-mode-amount view))
    (smoke-press view "0")
    (smoke-at-level view base 1)))

(defun smoke-zoom-source (window view base)
  "Check that a scale in WINDOW, the source's, leaves VIEW's zoom alone.
BASE is as for `smoke-at-level'."
  (select-window window)
  (execute-kbd-macro (kbd "C-x C-+"))
  (smoke-pump 0.5)
  (smoke-check (and (eql (buffer-local-value 'text-scale-mode-amount (window-buffer window)) 1)
                    (smoke-at-level view base 1))
               "a text scale in the source zooms the source alone")
  (text-scale-set 0))

(defun smoke-zoom-global (window view base)
  "Check that a global scale, from WINDOW, zooms VIEW's page, and comes back.
BASE is as for `smoke-at-level'."
  (select-window window)
  (let ((height (face-attribute 'default :height)))
    (execute-kbd-macro (kbd "C-x C-M-+"))
    (let ((level (/ (float (face-attribute 'default :height)) height)))
      (smoke-check (and (> level 1) (smoke-at-level view base level))
                   "a global text scale zooms the page by the default face's height"
                   (format "%s to %s" height (face-attribute 'default :height))))
    (execute-kbd-macro (kbd "C-x C-M-0"))
    (smoke-check (and (= (face-attribute 'default :height) height) (smoke-at-level view base 1))
                 "its reset takes that zoom away")
    ;; Any key ends the transient map of that command, in which `+' is still global.
    (keymap-global-set "<f35>" #'ignore)
    (execute-kbd-macro (kbd "<f35>"))))

(defun smoke-zoom-sync (source window view base)
  "Check that the WINDOW of SOURCE and VIEW's page follow at a zoom.
BASE is as for `smoke-at-level'."
  (smoke-press view "+")
  (smoke-press view "+")
  (let ((level (smoke-at-level view base (expt text-scale-mode-step 2))))
    (select-window window)
    (set-window-start window (smoke-position source "Paragraph 120."))
    (redisplay t)
    (smoke-check (and level (smoke-wait-top view "Paragraph 120."))
                 "at a zoom, the page goes where the source's window start says")
    (let ((before (window-start window))
          (scrolled (smoke-script view "window.scrollY")))
      (smoke-press view "C-v")
      (select-window window)
      (smoke-check (and (smoke-until (lambda () (> (window-start window) before)) 5)
                        (<= (* (- (smoke-script view "window.scrollY") scrolled)
                               (smoke-script view "window.devicePixelRatio"))
                            (window-body-height (get-buffer-window view) t)))
                   "at a zoom, C-v goes no further than a page, and the source follows"
                   (format "%s then %s CSS pixels" scrolled (smoke-script view "window.scrollY"))))))

(defun smoke-zoom-keeps (session view base)
  "Check that a skin and a reload leave the zoom of VIEW, of SESSION, as it is.
That zoom is two steps, from `smoke-zoom-sync'.  BASE is as for
`smoke-at-level'."
  (let ((level (expt text-scale-mode-step 2)))
    (with-current-buffer view (imprimeur-choose-skin "minitel"))
    (smoke-wait-page view "document.documentElement.dataset.skin === 'minitel'" 5)
    (smoke-check (smoke-at-level view base level) "a change of skin keeps the zoom")
    (with-current-buffer view (imprimeur-choose-skin "base"))
    (smoke-wait-page view "document.documentElement.dataset.skin === 'base'" 5)
    (smoke-script view "location.reload(), 1")
    (smoke-pump 1)
    (smoke-check (and (smoke-until (lambda () (imprimeur--session-ready session)) 10)
                      (smoke-at-level view base level))
                 "a reload keeps the zoom")))

(defun smoke-wheel-event (view init)
  "Dispatch a WheelEvent of INIT, a JavaScript object's body, at VIEW's page.
Return whether the page prevented what it does by default."
  (smoke-script view (format "(() => {
  const event = new WheelEvent('wheel', { bubbles: true, cancelable: true, %s });
  document.querySelector('main').dispatchEvent(event);
  return event.defaultPrevented;
})()" init)))

(defun smoke-zoom-wheel-events (view)
  "Check what the page of VIEW does with a wheel event that a script makes.
It takes two steps, from a reload that has already happened."
  (let ((amount (lambda () (buffer-local-value 'text-scale-mode-amount view)))
        (height (face-attribute 'default :height)))
    (smoke-check (and (smoke-wheel-event view "ctrlKey: true, wheelDeltaY: -120")
                      (smoke-until (lambda () (eql (funcall amount) 1)) 5))
                 "after a reload, a wheel with Control down is a step smaller of the view's scale")
    (smoke-check (not (smoke-wheel-event view "wheelDeltaY: -120"))
                 "a wheel without Control is left to the page")
    (smoke-check (and (smoke-wheel-event view "ctrlKey: true, altKey: true, wheelDeltaY: 120")
                      (smoke-until (lambda () (> (face-attribute 'default :height) height)) 5))
                 "a wheel with Control and Alt is a step of the global scale"
                 (format "%s to %s" height (face-attribute 'default :height)))
    (execute-kbd-macro (kbd "C-x C-M-0"))
    (execute-kbd-macro (kbd "<f35>"))
    (with-current-buffer view (text-scale-set 0))))

(defun smoke-xdotool (&rest arguments)
  "Run the xdotool of IMPRIMEUR_SMOKE_XDOTOOL with ARGUMENTS, and let Emacs read."
  (apply #'call-process (getenv "IMPRIMEUR_SMOKE_XDOTOOL") nil nil nil arguments)
  (smoke-pump 0.5))

(defun smoke-real-wheel (window view base)
  "Send a real wheel over VIEW's page and over WINDOW, and say what hears of it.
Over the page, it stops in WebKit and the page zooms; over WINDOW, Emacs
hears of it.  `smoke-pump' reads the events, so that no command of Emacs
runs on them.  BASE is as for `smoke-at-level'."
  (if (not (getenv "IMPRIMEUR_SMOKE_XDOTOOL"))
      (smoke-say "REPORT" "a real wheel: not run, as IMPRIMEUR_SMOKE_XDOTOOL names no xdotool")
    (pcase-let* ((`(,left ,top ,right ,bottom) (window-absolute-pixel-edges (get-buffer-window view)))
                 (x (number-to-string (/ (+ left right) 2)))
                 (y (number-to-string (/ (+ top bottom) 2)))
                 (wheel (lambda (button &rest modifiers)
                          (setq smoke-input nil)
                          (apply #'smoke-xdotool
                                 (append (mapcan (lambda (key) (list "keydown" key)) modifiers)
                                         (list "click" button)
                                         (mapcan (lambda (key) (list "keyup" key)) (reverse modifiers))))))
                 (place (lambda () (smoke-script view "window.scrollY"))))
      (smoke-xdotool "mousemove" x y)
      (let ((scrolled (funcall place)))
        (funcall wheel "4" "ctrl")
        (smoke-check (and (smoke-at-level view base text-scale-mode-step)
                          (null smoke-input))
                     "a real wheel up with Control over the page stops in WebKit, and is a step larger"
                     (list (buffer-local-value 'text-scale-mode-amount view) smoke-input))
        (funcall wheel "5" "ctrl")
        (smoke-check (and (smoke-at-level view base 1) (null smoke-input)
                          (<= (abs (- (funcall place) scrolled)) 4))
                     "a real wheel down with Control over the page is a step smaller, and scrolls nothing"
                     (list scrolled (funcall place) smoke-input)))
      ;; What a notch sends must not depend on the zoom.
      (with-current-buffer view (text-scale-set 5))
      (smoke-pump 0.5)
      (funcall wheel "5" "ctrl")
      (smoke-check (eql (buffer-local-value 'text-scale-mode-amount view) 4)
                   "at a large zoom, a notch of a real wheel is still one step"
                   (buffer-local-value 'text-scale-mode-amount view))
      (with-current-buffer view (text-scale-set 0))
      (smoke-pump 0.5)
      (let ((height (face-attribute 'default :height)))
        (funcall wheel "4" "ctrl" "alt")
        (let ((taller (face-attribute 'default :height)))
          (smoke-check (and (> taller height) (null smoke-input))
                       "a real wheel up with Control and Alt over the page is a step of the global scale"
                       (list height taller smoke-input)))
        (funcall wheel "5" "ctrl" "alt")
        (smoke-check (= (face-attribute 'default :height) height)
                     "a real wheel down with Control and Alt comes back"
                     (list height (face-attribute 'default :height))))
      (let ((scrolled (funcall place)))
        (funcall wheel "5")
        (funcall wheel "5")
        (smoke-pump 1)
        (smoke-say "REPORT" (format "a real wheel down, twice, over the page: scrollY %s to %s; Emacs read %S"
                                    scrolled (funcall place) smoke-input)))
      (pcase-let ((`(,left ,top ,_ ,_) (window-absolute-pixel-edges window)))
        (smoke-xdotool "mousemove" (number-to-string (+ left 100)) (number-to-string (+ top 100))))
      (funcall wheel "4" "ctrl")
      (smoke-check (seq-some (lambda (event) (eq (car-safe event) 'C-wheel-up)) smoke-input)
                   "a real wheel up with Control over the source reaches Emacs, as a control of the rest"
                   smoke-input))))

(defun smoke-grid-report (view skin unit tolerance)
  "Report how far from its grid VIEW's blocks in SKIN stand, at each zoom.
UNIT is a CSS declaration that gives an element a box as long as a step
of that grid.  What stands off it, in CSS pixels, is what stands between
two blocks that a whole number of steps would not make: a skin may have
its own reason for some, and a zoom that broke a grid would widen this.
TOLERANCE, if given, is what that may be, for a skin whose blocks all stand
on the grid.  The fonts here are not the skin's: this says nothing of a letter."
  (with-current-buffer view (imprimeur-choose-skin skin))
  (smoke-wait-page view (format "document.documentElement.dataset.skin === %S" skin) 5)
  (smoke-pump 1)
  (dolist (amount '(-2 0 1 3 6))
    (with-current-buffer view (text-scale-set amount))
    (smoke-pump 1)
    (let ((found (smoke-script view (format "(() => {
  const main = document.querySelector('main');
  const vertical = getComputedStyle(main).writingMode !== 'horizontal-tb';
  const probe = document.createElement('p');
  probe.style.cssText = '%s; position: absolute; visibility: hidden; margin: 0; padding: 0';
  main.append(probe);
  const unit = vertical ? probe.getBoundingClientRect().width : probe.getBoundingClientRect().height;
  probe.remove();
  const offsets = [...main.querySelectorAll(':scope > p')].slice(0, 30).map((block) => {
    const box = block.getBoundingClientRect();
    return vertical ? box.right : box.top + window.scrollY;
  });
  const off = offsets.slice(1).map((offset, at) => {
    const rest = Math.abs(offset - offsets[at]) %% unit;
    return Math.min(rest, unit - rest);
  });
  return { unit, width: window.innerWidth, ratio: window.devicePixelRatio, worst: Math.max(...off),
           overflowing: document.documentElement.scrollWidth - window.innerWidth };
})()" unit))))
      (if tolerance
          (smoke-check (< (plist-get found :worst) tolerance)
                       (format "%s's blocks stay on its grid at the scale %d" skin amount) found)
        (smoke-say "REPORT" (format "%s at the scale %d: %S" skin amount found)))))
  (with-current-buffer view (text-scale-set 0))
  (smoke-pump 0.5))

(defun smoke-zoom (source window session view)
  "Check the zoom of VIEW's page, of SESSION, whose source SOURCE is in WINDOW."
  (let ((base (smoke-script view "window.devicePixelRatio")))
    (smoke-say "REPORT" (format "devicePixelRatio at the zoom 1: %s" base))
    (smoke-zoom-steps source window view base)
    (smoke-zoom-source window view base)
    (smoke-zoom-global window view base)
    (smoke-zoom-sync source window view base)
    (smoke-zoom-keeps session view base)
    (smoke-zoom-wheel-events view)
    (smoke-at-level view base 1)
    (smoke-real-wheel window view base)
    (with-current-buffer (window-buffer window) (text-scale-set 0))
    (pcase-dolist (`(,skin ,unit ,tolerance) '(("ecrivain" "height: var(--ecrivain-line)" 0.5)
                                               ("tianlu" "width: var(--tianlu-p)" nil)
                                               ("minitel" "height: 1rlh" nil)))
      (smoke-grid-report view skin unit tolerance))
    (with-current-buffer view (imprimeur-choose-skin "base"))
    (smoke-wait-page view "document.documentElement.dataset.skin === 'base'" 5)))

(defun smoke-jumps (source window view)
  "Check `imprimeur-jump' both ways, from the Emacs WINDOW of SOURCE and from VIEW."
  (select-window window)
  (goto-char (smoke-position source "Paragraph 120."))
  (recenter 3)
  (redisplay t)
  (smoke-pump 0.5)
  (execute-kbd-macro (kbd "M-g v"))
  (smoke-check (and (smoke-wait-top view "Paragraph 120.")
                    (smoke-script view "!!document.querySelector('#imprimeur-main > .imprimeur-flash')"))
               "M-g v brings point's block to the top of the page, and marks it")
  (select-window (get-buffer-window view))
  (execute-kbd-macro (kbd "C-v"))
  (smoke-pump 1)
  (let ((line (smoke-script view "(() => {
  const above = [...document.querySelectorAll('#imprimeur-main > [data-line]')]
    .filter((block) => block.getBoundingClientRect().top <= 0);
  return Number(above[above.length - 1].dataset.line);
})()")))
    (execute-kbd-macro (kbd "M-g v"))
    (smoke-check (and (eq (selected-window) window)
                      (smoke-until (lambda ()
                                     (with-current-buffer source
                                       (eql (line-number-at-pos nil t) line)))
                                   5))
                 "M-g v goes back from the view to the source, at the line of the page's top block"
                 (format "line %s, point on line %d" line
                         (with-current-buffer source (line-number-at-pos nil t))))))

(defun smoke-double-click (source view)
  "Check a double-click in the page of VIEW on a block that SOURCE has folded."
  (with-current-buffer source
    (goto-char (smoke-position source "Paragraph 120."))
    (org-fold-subtree t)
    (goto-char (point-min)))
  (smoke-script view "(() => {
  const block = [...document.querySelectorAll('#imprimeur-main > *')]
    .find((candidate) => candidate.textContent.trim().startsWith('Paragraph 120.'));
  block.scrollIntoView();
  const box = block.getBoundingClientRect();
  block.dispatchEvent(new MouseEvent('dblclick', { bubbles: true, clientX: box.x + 5, clientY: box.y + 5 }));
  return true;
})()")
  (smoke-check (smoke-until (lambda ()
                              (with-current-buffer source
                                (and (= (pos-bol) (smoke-position source "Paragraph 120."))
                                     (not (invisible-p (point))))))
                            5)
               "a double-click in the page puts point on the line and opens the fold"))

(defun smoke-palette (view)
  "Check that a new palette recolours the page of VIEW, in a skin that reads it."
  (let ((background (face-background 'default)))
    (with-current-buffer view (imprimeur-choose-skin "minitel"))
    (smoke-wait-page view "document.documentElement.dataset.skin === 'minitel'" 5)
    (set-face-background 'default "#123456")
    (imprimeur-refresh-palette)
    (smoke-check (smoke-wait-page view "getComputedStyle(document.documentElement)
.getPropertyValue('--emacs-bg').trim() === '#123456'
&& getComputedStyle(document.documentElement).backgroundColor === 'rgb(18, 52, 86)'" 5)
                 "a palette push recolours the page, without loading it again"
                 (format "%d load committed" (length smoke-commits)))
    (set-face-background 'default background)
    (imprimeur-refresh-palette)
    (with-current-buffer view (imprimeur-choose-skin "base"))
    (smoke-wait-page view "document.documentElement.dataset.skin === 'base'" 5)))

(defun smoke-menu (where window view)
  "Check `M-g s', pressed in WINDOW, which shows WHERE, on the page of VIEW.
The menu opens, a skin's key and an option's change the page, with the menu
open and saying so, and closing it gives the Emacs window its height back."
  (with-selected-window window
    ;; In pixels: where the frame is no whole number of lines, as in DejaVu at its 900 pixels,
    ;; the same 883 pixels count as 51 lines or 52, by what resized the window last.
    (let ((height (window-pixel-height))
          (commits (length smoke-commits))
          (session (buffer-local-value 'imprimeur--session view))
          (text (lambda ()
                  (with-current-buffer " *transient*"
                    (buffer-substring-no-properties (point-min) (point-max)))))
          (press (lambda (key)
                   (execute-kbd-macro (kbd key))
                   (smoke-pump 0.3))))
      (funcall press "M-g s")
      (smoke-check (get-buffer-window " *transient*") (format "M-g s opens the menu in the %s" where))
      (funcall press "m")
      (smoke-check (smoke-wait-page view "document.documentElement.dataset.skin === 'minitel'" 5)
                   (format "a skin's key in the menu changes the page, from the %s" where))
      (smoke-check (and (get-buffer-window " *transient*") (string-search "m * Minitel" (funcall text)))
                   (format "the menu stays open and marks the skin, in the %s" where))
      (funcall press "P")
      (let ((value (alist-get 'palette (cdr (assoc "minitel" (imprimeur--session-skin-choices session))))))
        (smoke-check (smoke-wait-page
                      view (format "document.documentElement.dataset.minitelPalette === %S" value) 5)
                     (format "an option's key in the menu changes the page, from the %s" where) value)
        (smoke-check (string-search (format "(minitel (palette . %S))" value) (funcall text))
                     (format "the menu says what keeps the option, in the %s" where)))
      (when-let* ((shot (and (equal where "source") (getenv "IMPRIMEUR_SMOKE_MENU_SHOT"))))
        (redisplay t)
        (smoke-pump 1)
        (call-process-shell-command shot))
      (funcall press "b")
      (smoke-wait-page view "document.documentElement.dataset.skin === 'base'" 5)
      (funcall press "C-g")
      (smoke-check (not (get-buffer-window " *transient*")) (format "C-g closes the menu in the %s" where))
      (smoke-check (= (window-pixel-height) height)
                   (format "the %s's Emacs window has its height back" where))
      (smoke-check (= (length smoke-commits) commits)
                   (format "nothing of the menu in the %s loads the page again" where)))))

(defun smoke-second-window (source window view)
  "Check that an Emacs window made from WINDOW to show VIEW goes back to SOURCE."
  (let ((second (split-window window)))
    (set-window-buffer second view)
    (redisplay t)
    (smoke-check (smoke-until (lambda () (eq (window-buffer second) source)) 3)
                 "a second Emacs window showing the view gets its previous buffer back"
                 (buffer-name (window-buffer second)))
    (delete-window second)))

(defun smoke-resizes (view right)
  "Check that the page of VIEW takes the width of its Emacs window RIGHT."
  (let ((before (smoke-script view "window.innerWidth")))
    (window-resize right -200 t nil t)
    (redisplay t)
    (smoke-check (smoke-until (lambda ()
                                (let ((now (smoke-script view "window.innerWidth")))
                                  (and (numberp now) (< now before))))
                              5)
                 "the page takes the new width of its Emacs window"
                 (format "%s, then %s CSS pixels" before (smoke-script view "window.innerWidth")))
    (window-resize right 200 t nil t)
    (redisplay t)))

(defun smoke-new-window (view)
  "Check that an xwidget that the page of VIEW asks for goes at once."
  (let ((before (length xwidget-list))
        (opened (smoke-script view "!!window.open('about:blank')")))
    (smoke-pump 1)
    (smoke-check (and (= (length xwidget-list) before) (buffer-live-p view))
                 "an xwidget that the page asks for is killed"
                 (format "window.open gave %s; %d xwidgets, %d before" opened (length xwidget-list) before))))

(defun smoke-kill-webkit ()
  "Kill the WebKit processes that this Emacs has started; return how many."
  (let ((children (seq-filter (lambda (pid)
                                (let ((attributes (process-attributes pid)))
                                  (and (eql (alist-get 'ppid attributes) (emacs-pid))
                                       (string-prefix-p "WebKitWebProces" (or (alist-get 'comm attributes) "")))))
                              (list-system-processes))))
    (mapc (lambda (pid) (signal-process pid 'KILL)) children)
    (length children)))

(defun smoke-crashes (session view)
  "Check that VIEW, of SESSION, comes back, zoomed, when WebKit's process dies."
  (let* ((base (smoke-script view "window.devicePixelRatio"))
         (origin (smoke-script view "performance.timeOrigin"))
         (killed (progn (smoke-press view "+") (smoke-kill-webkit))))
    ;; A script sent to the process as it dies never answers, and costs its wait.
    (smoke-pump 2)
    (smoke-check (and (> killed 0)
                      (smoke-until (lambda ()
                                     (let ((now (smoke-script view "performance.timeOrigin")))
                                       (and (numberp now) (not (equal now origin)))))
                                   10)
                      (smoke-until (lambda () (imprimeur--session-ready session)) 5))
                 "a page whose WebKit process died comes back"
                 (format "%d processes killed" killed))
    (smoke-check (smoke-at-level view base text-scale-mode-step) "it comes back at its zoom")
    (smoke-press view "0")
    (smoke-at-level view base 1)))

(defun smoke-beside-a-browser (session view)
  "Check VIEW, of SESSION, when its WebKit process dies beside a browser's stream.
The watchdog hears the session as a whole, so the view stays blank for as long
as the browser is open, and comes back when it closes.  The browser is headless
Chromium, which opens no desktop window."
  (if (not (executable-find "chromium"))
      (smoke-say "REPORT" "a view beside a browser: not run, as there is no chromium")
    (let* ((imprimeur-browser-program (expand-file-name "tests/bin/headless-chromium" smoke-root))
           (clients (lambda () (length (imprimeur--session-clients session))))
           (state (lambda () (buffer-local-value 'imprimeur-xwidget--state view)))
           ;; The stream of the check before may still be going, and the time for the
           ;; browser's report starts when its stream opens.
           (opened (and (smoke-until (lambda () (= (funcall clients) 1)) 5)
                        (progn
                          (with-current-buffer (imprimeur--session-buffer session) (imprimeur-browse))
                          (smoke-until (lambda () (= (funcall clients) 2)) 30))
                        (smoke-until (lambda () (imprimeur--session-ready session)) 30)))
           (killed (smoke-kill-webkit))
           (loads (length smoke-commits)))
      (smoke-until (lambda () (= (funcall clients) 1)) 5)
      ;; Longer than the watchdog waits, in which a load would show.
      (smoke-pump 4)
      (smoke-check (and opened (> killed 0) (= (funcall clients) 1) (eq (funcall state) 'live)
                        (= (length smoke-commits) loads))
                   "a view whose WebKit process dies beside a browser stays as it is"
                   (format "the browser's report: %s, %d processes killed, %s, %d streams, %d loads since"
                           opened killed (funcall state) (funcall clients) (- (length smoke-commits) loads)))
      (signal-process (imprimeur--session-viewer session) 'TERM)
      (smoke-check (and (smoke-until (lambda () (> (length smoke-commits) loads)) 15)
                        (smoke-until (lambda ()
                                       (and (= (funcall clients) 1) (imprimeur--session-ready session)))
                                     15))
                   "that view comes back when the browser closes"
                   (format "%d loads since, %d streams" (- (length smoke-commits) loads) (funcall clients))))))

(defun smoke-keeps-dying (file)
  "Check that a page of FILE that keeps dying as soon as it reports is given up.
The first loss loads it again and the second offers the browser, with the
time that a session really has, and nothing loads it after that."
  (setq smoke-commits nil)
  (pcase-let* ((`(,source ,session) (smoke-open file))
               (view (imprimeur--session-view session))
               (state (lambda () (buffer-local-value 'imprimeur-xwidget--state view))))
    (let ((first (smoke-kill-webkit))
          (back (smoke-until (lambda () (eq (funcall state) 'revived)) 15))
          (second (smoke-kill-webkit)))
      (smoke-until (lambda () (eq (funcall state) 'failed)) 15)
      ;; Longer than the watchdog waits, in which a further load would show.
      (smoke-pump 4)
      (smoke-check (and (> first 0) back (> second 0)
                        (eq (funcall state) 'failed)
                        (= (length smoke-commits) 2)
                        (buffer-local-value 'mode-line-process view)
                        (with-current-buffer "*Messages*"
                          (save-excursion
                            (goto-char (point-max))
                            (search-backward "imprimeur-browse" nil t))))
                   "a page that keeps dying as soon as it reports ends in the offer of a browser"
                   (format "%d and %d processes killed, %s then, %d loads committed"
                           first second (funcall state) (length smoke-commits))))
    (smoke-end source)))

(defun smoke-recovers (session view)
  "Check the watchdog and the callback of VIEW, of SESSION, on a real page."
  (let* ((xwidget (buffer-local-value 'imprimeur-xwidget--xwidget view))
         (home (imprimeur-url (imprimeur--session-buffer session)))
         (port (imprimeur-server-start))
         (origin (smoke-script view "performance.timeOrigin")))
    (mapc #'delete-process (imprimeur--session-clients session))
    (smoke-check (smoke-until (lambda ()
                                (let ((now (smoke-script view "performance.timeOrigin")))
                                  (and (numberp now) (not (equal now origin)))))
                              5)
                 "the last stream closing while live loads the page again")
    (smoke-until (lambda () (imprimeur--session-ready session)) 5)
    ;; A stream beside the page's, as of a browser, so that the page's own going
    ;; away is not its last, and only the rule on foreign loads can bring it back.
    (let ((other (make-network-process :name "smoke-stream" :host "127.0.0.1" :service port
                                       :noquery t :sentinel #'ignore)))
      (process-send-string other (format "GET /%s/.imprimeur/events HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n"
                                         (imprimeur--session-token session) port))
      (smoke-until (lambda () (= (length (imprimeur--session-clients session)) 2)) 5)
      (xwidget-webkit-goto-uri xwidget (format "http://127.0.0.1:%d/foreign" port))
      (smoke-pump 0.5)
      (smoke-check (and (smoke-until (lambda () (equal (xwidget-webkit-uri xwidget) home)) 5)
                        (smoke-until (lambda () (= (length (imprimeur--session-clients session)) 2)) 5))
                   "a load committed outside the session goes back to the page"
                   (format "%d loads committed" (length smoke-commits)))
      (delete-process other))
    (smoke-until (lambda () (imprimeur--session-ready session)) 5)))

(defun smoke-teardown (source session view)
  "Check that VIEW can be killed and made anew, and dies with SOURCE, of SESSION."
  (setq smoke-questions nil)
  (kill-buffer view)
  (smoke-check (and (not smoke-questions) (not (buffer-live-p view))
                    (memq session imprimeur--sessions)
                    (buffer-local-value 'imprimeur-mode source))
               "killing the view asks nothing and keeps the session"
               smoke-questions)
  (with-current-buffer source (imprimeur-show))
  (let ((again (imprimeur--session-view session)))
    (smoke-check (and (buffer-live-p again) (get-buffer-window again)
                      (smoke-until (lambda () (imprimeur--session-ready session)) 5))
                 "imprimeur-show opens the view again")
    (setq smoke-questions nil)
    (smoke-end source)
    (smoke-check (and (not smoke-questions) (not (buffer-live-p again))
                      (not (memq session imprimeur--sessions)))
                 "killing the source kills the view, asking nothing"
                 smoke-questions)))

(defun smoke-same-window (file)
  "Check a view asked for in FILE's Emacs window, and that quitting restores it.
That holds with the source in a second Emacs window too, once redisplay has
run the hooks of the Emacs windows that changed."
  (let ((imprimeur-display-buffer-action '((display-buffer-same-window))))
    (pcase-let* ((`(,source ,session ,window) (smoke-open file))
                 (view (imprimeur--session-view session)))
      (smoke-check (and (eq (selected-window) window) (eq (window-buffer window) view)
                        (one-window-p))
                   "the view opens in the same Emacs window when asked")
      (quit-window)
      (smoke-pump 0.5)
      (smoke-check (eq (window-buffer window) source)
                   "quitting the view restores the source there")
      (let ((second (split-window window)))
        (with-current-buffer source (imprimeur-show))
        (smoke-pump 0.5)
        (quit-window)
        (smoke-pump 0.5)
        (smoke-check (and (eq (window-buffer window) source) (eq (window-buffer second) source))
                     "quitting the view restores the source beside another Emacs window showing it"
                     (list (buffer-name (window-buffer window)) (buffer-name (window-buffer second)))))
      (smoke-end source))))

(defun smoke-hostile (file)
  "Check that the hostile document FILE takes the view nowhere."
  (let ((imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist)))
    (setq smoke-commits nil)
    (pcase-let* ((`(,source ,session) (smoke-open file))
                 (view (imprimeur--session-view session))
                 (home (imprimeur-url source)))
      (smoke-wait-page view "document.querySelector('main p')?.textContent === 'Hostile end'" 5)
      (smoke-pump 2)
      (let ((href (smoke-script view "location.href"))
            (pwned (smoke-script view "typeof window.__pwned"))
            (uri (xwidget-webkit-uri (buffer-local-value 'imprimeur-xwidget--xwidget view))))
        (smoke-check (and (equal href home) (equal uri home) (equal pwned "undefined")
                          (= (length smoke-commits) 1)
                          (equal (car smoke-commits) home))
                     "the hostile fixture navigates nowhere"
                     (format "%d load committed, __pwned is %s" (length smoke-commits) pwned)))
      (smoke-end source))))

(defun smoke-press (view key)
  "Press KEY, as `kbd' reads it, in the Emacs window of VIEW; let the page answer."
  (with-selected-window (get-buffer-window view)
    (execute-kbd-macro (kbd key)))
  (smoke-pump 0.3))

(defun smoke-pill (view)
  "Check that the pill of VIEW's page opens its popover, by a click and a key.
The click is the page's own, so the check first asks whether the pill is what
a pointer would reach there, and that the popover shows entries in the view."
  (let ((reached "(() => {
  const box = document.querySelector('.imprimeur-minitoc-pill').getBoundingClientRect();
  return !!document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2)
    ?.closest('.imprimeur-minitoc-pill');
})()")
        (shows "(() => {
  const popover = document.getElementById('imprimeur-minitoc-popover');
  const box = popover.getBoundingClientRect();
  return !popover.hidden && box.width > 0 && box.height > 0
    && box.top >= 0 && box.right <= window.innerWidth
    && popover.querySelectorAll('[data-minitoc-id]').length > 0
    && document.querySelector('.imprimeur-minitoc-pill').ariaExpanded === 'true';
})()"))
    (smoke-check (and (smoke-wait-page view "!document.getElementById('imprimeur-minitoc').hidden" 5)
                      (smoke-script view reached))
                 "the page's pill stands where a pointer reaches it")
    (smoke-script view "document.querySelector('.imprimeur-minitoc-pill').click(), 1")
    (smoke-check (smoke-wait-page view shows 5) "a click on the pill opens its popover in a view")
    (smoke-press view "<escape>")
    (smoke-check (smoke-wait-page view "document.getElementById('imprimeur-minitoc-popover').hidden" 5)
                 "Esc closes the popover in a view")
    (smoke-press view "t")
    (smoke-check (smoke-wait-page view shows 5) "t opens the popover in a view")
    (smoke-press view "<escape>")))

(defun smoke-keys-of-the-page (view)
  "Check that the keys of Minitel reach the page of VIEW, by its map of forwards."
  (let ((screen "document.getElementById('minitel-screen')?.dataset.kind ?? null")
        (prompt "document.querySelector('.minitel-prompt')?.textContent ?? null")
        (letter "document.querySelector('.minitel-letter').textContent"))
    (smoke-press view "s")
    (smoke-check (equal (smoke-script view screen) "SOMMAIRE") "s opens SOMMAIRE in a view")
    (smoke-press view "1")
    (smoke-press view "2")
    (smoke-press view "DEL")
    (smoke-check (string-search ": 1█" (or (smoke-script view prompt) ""))
                 "a digit and DEL reach the choice in a view" (smoke-script view prompt))
    (smoke-press view "<escape>")
    (smoke-check (not (smoke-script view screen)) "Esc closes the screen in a view")
    (smoke-press view "?")
    (smoke-check (equal (smoke-script view screen) "GUIDE") "? opens GUIDE in a view")
    (smoke-press view "?")
    (smoke-press view "q")
    (smoke-check (equal (smoke-script view letter) "F") "q turns C to F in a view")
    (smoke-press view "q")
    (smoke-check (equal (smoke-script view letter) "C") "q turns F to C in a view")
    (smoke-press view "n")
    (smoke-press view "n")
    (smoke-check (> (smoke-script view "window.scrollY") 0) "n moves to a heading in a view")))

(defun smoke-keys (file)
  "Check the keys of a view of FILE, and that a key declined does its old job.
Nothing with a modifier goes to the page, and another skin gives its keys back."
  (let ((imprimeur-skin 'minitel)
        (directory (make-temp-file "smoke-skin" t)))
    (write-region "@layer skin { }\n" nil (expand-file-name "skin.css" directory) nil 'silent)
    (write-region "export default function mount({ key }) { window.mounted = 1; key('q', () => false); }\n"
                  nil (expand-file-name "page.mjs" directory) nil 'silent)
    (imprimeur-skin-define 'declining :title "Declining" :directory directory :stylesheets '("skin.css")
                           :module "page.mjs" :keys '("q"))
    (pcase-let* ((`(,source ,session) (smoke-open file))
                 (view (imprimeur--session-view session)))
      (smoke-wait-page view "document.getElementById('minitel-keys') !== null" 10)
      (smoke-keys-of-the-page view)
      (with-current-buffer view
        (smoke-check (eq (key-binding (kbd "C-g") t) 'keyboard-quit) "C-g stays Emacs's in a view")
        (smoke-check (eq (key-binding (kbd "M-x") t) 'execute-extended-command) "M-x stays Emacs's in a view"))
      ;; Nothing typed, so the page declines, and DEL scrolls back as the wheel does.
      (smoke-script view "window.scrollTo({ top: 2000, behavior: 'instant' }), 1")
      (smoke-pump 0.5)
      (smoke-press view "DEL")
      (let ((top (smoke-script view "window.scrollY")))
        (smoke-check (and (numberp top) (< top 2000)) "DEL scrolls back when the page declines it" top))
      (with-current-buffer source (imprimeur-choose-skin "declining"))
      (smoke-wait-page view "window.mounted === 1" 10)
      (smoke-press view "q")
      (smoke-check (not (get-buffer-window view)) "q quits the view when the page declines it")
      (with-current-buffer source (imprimeur-show))
      (with-current-buffer source (imprimeur-choose-skin "base"))
      (with-current-buffer view
        (smoke-check (eq (key-binding (kbd "q") t) 'quit-window) "another skin gives a view its keys back"))
      (smoke-end source))))

(defun smoke-guarded (function &rest arguments)
  "Run FUNCTION with ARGUMENTS; if it signals, it fails and the others go on."
  (condition-case failure
      (apply function arguments)
    (error (smoke-check nil (format "%s ran to its end" function) failure))))

(defun smoke-all ()
  "Run the checks of the plan's acceptance 8, and the reports."
  (let ((directory (smoke-document)))
    (pcase-let* ((`(,source ,session ,window ,seconds) (smoke-open (expand-file-name "doc.org" directory)))
                 (view (imprimeur--session-view session))
                 (right (get-buffer-window view)))
      (smoke-guarded #'smoke-opens source window session seconds)
      (smoke-guarded #'smoke-page-reports view right)
      (when-let* ((shot (getenv "IMPRIMEUR_SMOKE_SHOT")))
        (redisplay t)
        (smoke-pump 1)
        (call-process-shell-command shot))
      (smoke-guarded #'smoke-follows source window view)
      (smoke-guarded #'smoke-zoom source window session view)
      (smoke-guarded #'smoke-jumps source window view)
      (smoke-guarded #'smoke-double-click source view)
      (smoke-guarded #'smoke-pill view)
      (smoke-guarded #'smoke-palette view)
      (smoke-guarded #'smoke-menu "source" window view)
      (smoke-guarded #'smoke-menu "view" right view)
      (smoke-guarded #'smoke-second-window source window view)
      (smoke-guarded #'smoke-resizes view right)
      (smoke-guarded #'smoke-new-window view)
      ;; As if each loss came long after the last: `smoke-keeps-dying' has the
      ;; real time, and these would use up the chances a page has within it.
      (let ((imprimeur-xwidget--quiet 0))
        (smoke-guarded #'smoke-crashes session view)
        (smoke-guarded #'smoke-recovers session view)
        (smoke-guarded #'smoke-beside-a-browser session view))
      (smoke-guarded #'smoke-features view)
      (smoke-guarded #'smoke-teardown source session view))
    (smoke-guarded #'smoke-same-window (expand-file-name "doc.org" directory))
    (smoke-guarded #'smoke-hostile (expand-file-name "hostile.md" directory))
    (smoke-guarded #'smoke-keys (expand-file-name "doc.org" directory))
    (smoke-guarded #'smoke-keeps-dying (expand-file-name "doc.org" directory))))

(defun smoke-skin (skin)
  "Check that a page of the showcase comes up whole in a real xwidget, in SKIN."
  (setq imprimeur-skin (intern skin))
  (pcase-let* ((file (if (equal skin "tianlu") "examples/tianlu/showcase.org" "examples/showcase.org"))
               (`(,source ,session ,_window ,seconds) (smoke-open (expand-file-name file smoke-root)))
               (view (imprimeur--session-view session)))
    (smoke-check seconds (format "the page of %s reports a revision" skin))
    (smoke-check (smoke-wait-page view (format "document.documentElement.dataset.skin === '%s'" skin) 10)
                 (format "the page is in %s" skin))
    (smoke-check (smoke-wait-page view "document.querySelector('main pre.mermaid svg') !== null" 20)
                 "its diagram is drawn")
    (smoke-check (smoke-wait-page view "[...document.querySelectorAll('main img')].every((image) => image.complete && image.naturalWidth > 0)" 10)
                 "its pictures load")
    (smoke-check (smoke-wait-page view "document.documentElement.scrollWidth <= innerWidth + 1" 5)
                 "it does not scroll sideways")
    (smoke-end source)
    (smoke-check (not (buffer-live-p view)) "killing the source kills the view")))

(defun smoke-run ()
  "Run the part of the smoke test that the environment asks for, and end Emacs."
  ;; Installed, as a reader has them, though most of what this checks is the plain page's.
  (dolist (directory (file-expand-wildcards (expand-file-name "imprimeur-skin-*" smoke-root)))
    (load (expand-file-name (file-name-nondirectory directory) directory) nil t))
  (setq imprimeur-skin 'base)
  (setq frame-resize-pixelwise t
        ring-bell-function #'ignore)
  (menu-bar-mode -1)
  (tool-bar-mode -1)
  (set-frame-position nil 0 0)
  ;; The sizes given are the text's, which the scroll bars and such go beside.
  (set-frame-size nil (- (min 1400 (display-pixel-width)) (- (frame-outer-width) (frame-text-width)))
                  (- (min 900 (display-pixel-height)) (- (frame-outer-height) (frame-text-height)))
                  t)
  (smoke-pump 0.5)
  (advice-add 'yes-or-no-p :around
              (lambda (_function prompt) (push prompt smoke-questions) t))
  (advice-add 'y-or-n-p :around
              (lambda (_function prompt) (push prompt smoke-questions) t))
  (advice-add 'imprimeur--serve-file :before
              (lambda (_connection file &rest _) (push file smoke-media)))
  (advice-add 'imprimeur-xwidget--event :before
              (lambda (_url xwidget type)
                (when (and (eq type 'load-changed) (equal (nth 3 last-input-event) "load-committed"))
                  (push (xwidget-webkit-uri xwidget) smoke-commits))))
  (smoke-say "REPORT" (format "Emacs %s, window-system %s, GDK_BACKEND %s" emacs-version window-system
                              (or (getenv "GDK_BACKEND") "unset")))
  (when (equal (getenv "IMPRIMEUR_SMOKE_PART") "all")
    (smoke-guarded #'smoke-all))
  (if-let* ((skin (getenv "IMPRIMEUR_SMOKE_SKIN")))
      (smoke-guarded #'smoke-skin skin)
    (smoke-guarded #'smoke-video))
  (imprimeur-stop-all)
  (smoke-say "REPORT" (format "events of a killed xwidget that xwidget.el signalled on: %d" smoke-stale-events))
  (smoke-say "DONE" "")
  (kill-emacs 0))

(run-at-time 1 nil #'smoke-run)

;;; smoke-xwidget.el ends here
