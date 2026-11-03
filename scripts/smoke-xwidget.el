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
;;
;; A double-click and a wheel are synthetic here or absent: only the owner can
;; check that those of a person reach the page.

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
          (read-event nil nil 0.02)
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
  "Return non-nil once the block starting with TEXT is at the top of VIEW's page."
  (smoke-until (lambda ()
                 (let ((top (smoke-block-top view text)))
                   (and (numberp top) (<= (abs top) 2))))
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
  "Check that a new palette recolours the page of VIEW."
  (let ((background (face-background 'default)))
    (set-face-background 'default "#123456")
    (imprimeur-refresh-palette)
    (smoke-check (smoke-wait-page view "getComputedStyle(document.documentElement)
.getPropertyValue('--emacs-bg').trim() === '#123456'
&& getComputedStyle(document.documentElement).backgroundColor === 'rgb(18, 52, 86)'" 5)
                 "a palette push recolours the page, without loading it again"
                 (format "%d load committed" (length smoke-commits)))
    (set-face-background 'default background)
    (imprimeur-refresh-palette)))

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
  "Check that VIEW, of SESSION, comes back when its WebKit process dies."
  (let ((origin (smoke-script view "performance.timeOrigin"))
        (killed (smoke-kill-webkit)))
    ;; A script sent to the process as it dies never answers, and costs its wait.
    (smoke-pump 2)
    (smoke-check (and (> killed 0)
                      (smoke-until (lambda ()
                                     (let ((now (smoke-script view "performance.timeOrigin")))
                                       (and (numberp now) (not (equal now origin)))))
                                   10)
                      (smoke-until (lambda () (imprimeur--session-ready session)) 5))
                 "a page whose WebKit process died comes back"
                 (format "%d processes killed" killed))))

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
      (smoke-guarded #'smoke-jumps source window view)
      (smoke-guarded #'smoke-double-click source view)
      (smoke-guarded #'smoke-palette view)
      (smoke-guarded #'smoke-second-window source window view)
      (smoke-guarded #'smoke-resizes view right)
      (smoke-guarded #'smoke-new-window view)
      ;; As if each loss came long after the last: `smoke-keeps-dying' has the
      ;; real time, and these would use up the chances a page has within it.
      (let ((imprimeur-xwidget--quiet 0))
        (smoke-guarded #'smoke-crashes session view)
        (smoke-guarded #'smoke-recovers session view))
      (smoke-guarded #'smoke-features view)
      (smoke-guarded #'smoke-teardown source session view))
    (smoke-guarded #'smoke-same-window (expand-file-name "doc.org" directory))
    (smoke-guarded #'smoke-hostile (expand-file-name "hostile.md" directory))
    (smoke-guarded #'smoke-keeps-dying (expand-file-name "doc.org" directory))))

(defun smoke-run ()
  "Run the part of the smoke test that the environment asks for, and end Emacs."
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
  (smoke-guarded #'smoke-video)
  (imprimeur-stop-all)
  (smoke-say "REPORT" (format "events of a killed xwidget that xwidget.el signalled on: %d" smoke-stale-events))
  (smoke-say "DONE" "")
  (kill-emacs 0))

(run-at-time 1 nil #'smoke-run)

;;; smoke-xwidget.el ends here
