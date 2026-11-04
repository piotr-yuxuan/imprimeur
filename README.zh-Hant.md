<div lang="zh-TW">

# imprimeur

[English](README.md) · 繁體中文 · [简体中文](README.zh-Hans.md)

本文譯自英文版（提交 `48061a4`）；文中所連之說明文件，皆為英文原本。

[![CI](https://github.com/piotr-yuxuan/imprimeur/actions/workflows/ci.yml/badge.svg)](https://github.com/piotr-yuxuan/imprimeur/actions/workflows/ci.yml)
[![CD](https://github.com/piotr-yuxuan/imprimeur/actions/workflows/cd.yml/badge.svg)](https://github.com/piotr-yuxuan/imprimeur/actions/workflows/cd.yml)

<img alt="木刻一幅，繪印刷工坊：兩名印工立於木製印刷機旁，身前疊紙成摞，後方為兩名排字工。" src="docs/images/printer-1568.png"><br>

imprimeur 將編輯中之 Org 或 Markdown 緩衝區排印成頁，置於其旁之 Emacs 視窗（window），並使兩者始終相應。停筆片刻，頁面即隨每一更動而更新，存檔與否皆然。任何文件皆不得於頁面中執行程式碼；未受信任之文件，亦不能令頁面自網路擷取任何內容。本套件尚未正式發行。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/emacs-view-dark.png">
  <img alt="同一 Emacs 框架（frame）之內，並列兩個 Emacs 視窗（window）。左為 Org 緩衝區，內有 Mermaid 原始碼一段、檔案連結一則，及表格一張，其列過長而溢出視窗之外。右為同一內容以 Minitel 版式排成之頁面，色彩取自 Emacs 佈景主題：Mermaid 已繪成圖，木刻嵌入頁中並附圖說，表中長文於格內分行，另有語法上色之程式碼一段。" src="docs/images/emacs-view.png">
</picture>

## 安裝

須備 Emacs 31.1、[pandoc](https://pandoc.org/) 3，以及顯示頁面之所：或為編譯時啟用 xwidgets 之 Emacs（於 Nix 下即 `pkgs.emacs-pgtk`），或為 Chromium，以桌面視窗顯示。若用 [straight.el](https://github.com/radian-software/straight.el) 與 `use-package`：

```elisp
(use-package imprimeur
  :straight (imprimeur :type git :host github :repo "piotr-yuxuan/imprimeur"
                       :files ("imprimeur/*.el" "imprimeur/assets")))
```

其後於緩衝區內鍵入 `M-x imprimeur-mode` 即可。[初次預覽](docs/tutorials/first-preview.md)自儲存庫之複本（clone）起，逐步引導，事先無須安裝任何套件。處理 Markdown，請加裝 `markdown-mode`；繪製 Mermaid 圖表，須有 [mermaid-cli](https://github.com/mermaid-js/mermaid-cli)；欲於 Emacs 視窗內播放影片，該 Emacs 之環境須備 GStreamer 外掛。

上述配方隨 `main` 之最新提交而更新。若欲固定於某一[發行版](https://github.com/piotr-yuxuan/imprimeur/releases)，可用 Emacs 內建之 `:vc`，指定其標籤：

```elisp
(use-package imprimeur
  :vc (:url "https://github.com/piotr-yuxuan/imprimeur" :rev "0.0.0" :lisp-dir "imprimeur"))
```

straight 沿用既有之複本，複本更動亦未必察覺。欲更新，請先結束 Emacs，更新複本，並移除其建置所得；下次啟動時即重新建置：

```sh
git -C ~/.emacs.d/straight/repos/imprimeur pull --ff-only
rm -rf ~/.emacs.d/straight/build/imprimeur* ~/.emacs.d/straight/build/sommaire
```

### 先試 xwidgets

Xwidgets 於 Emacs 中尚屬實驗性質，一旦當機，未存之文字亦隨之而去。故於倚賴之前，宜自儲存庫之複本，另開一 Emacs 先行試用：

```sh
nix develop --command make smoke-xwidget
```

此指令另開一桌面視窗，載入實際頁面，歷時約一分鐘，逐項檢查，並印出 `PASS` 或 `FAIL`。若未通過，或無意採用，`(setq imprimeur-target 'browser)` 可使 xwidgets 不涉其中。

## 圖錄

皆為實際擷圖，由 `scripts/make-gallery` 製成。各文件見[範例](examples/README.md)。

https://github.com/user-attachments/assets/6dc2cf75-dcac-4d02-a462-994c99baf4ab

| 版式                                              | 淺色                                            | 深色                                                 |
|---------------------------------------------------|-------------------------------------------------|------------------------------------------------------|
| [Tianlu](imprimeur-skin-tianlu/README.md), _繁體_ | ![](docs/images/gallery/tianlu-traditional.png) | ![](docs/images/gallery/tianlu-traditional-dark.png) |
| _簡體_                                            | ![](docs/images/gallery/tianlu-simplified.png)  | ![](docs/images/gallery/tianlu-simplified-dark.png)  |
| [Minitel](imprimeur-skin-minitel/README.md)       | ![](docs/images/gallery/showcase-minitel.png)   | ![](docs/images/gallery/showcase-minitel-dark.png)   |
|                                                   | ![](docs/images/gallery/minitel.png)            | ![](docs/images/gallery/minitel-dark.png)            |
| [XIX](imprimeur-skin-xix/README.md)               | ![](docs/images/gallery/showcase-xix.png)       | ![](docs/images/gallery/showcase-xix-dark.png)       |
|                                                   | ![](docs/images/gallery/xix.png)                | ![](docs/images/gallery/xix-dark.png)                |
| [XVIII](imprimeur-skin-xviii/README.md)           | ![](docs/images/gallery/showcase-xviii.png)     | ![](docs/images/gallery/showcase-xviii-dark.png)     |
|                                                   | ![](docs/images/gallery/xviii.png)              | ![](docs/images/gallery/xviii-dark.png)              |
| [XVII](imprimeur-skin-xvii/README.md)             | ![](docs/images/gallery/showcase-xvii.png)      | ![](docs/images/gallery/showcase-xvii-dark.png)      |
|                                                   | ![](docs/images/gallery/xvii.png)               | ![](docs/images/gallery/xvii-dark.png)               |
| _法文本_                                          | ![](docs/images/gallery/xvii-descartes.png)     | ![](docs/images/gallery/xvii-descartes-dark.png)     |
| [Briefing](imprimeur-skin-briefing/README.md)     | ![](docs/images/gallery/showcase-briefing.png)  | ![](docs/images/gallery/showcase-briefing-dark.png)  |
|                                                   | ![](docs/images/gallery/briefing.png)           | ![](docs/images/gallery/briefing-dark.png)           |
| [Écrivain](imprimeur-skin-ecrivain/README.md)     | ![](docs/images/gallery/showcase-ecrivain.png)  | ![](docs/images/gallery/showcase-ecrivain-dark.png)  |
|                                                   | ![](docs/images/gallery/ecrivain.png)           | ![](docs/images/gallery/ecrivain-dark.png)           |

## 本儲存庫所收

各套件皆可單獨安裝，配方見[設定](#configuration)。

| 套件                      | 用途                                                                               | 所需                                            |
|---------------------------|------------------------------------------------------------------------------------|-------------------------------------------------|
| `imprimeur`               | 緩衝區之排印頁面                                                                   | Emacs 31.1、pandoc 3，以及 xwidgets 或 Chromium |
| `sommaire`                | 緩衝區內之小目次：於長篇文件中知所在，亦可逕往他處                                 | 僅須 Emacs 31.1，別無所需，imprimeur 亦非必要   |
| `imprimeur-skin-tianlu`   | 版式：宋刻本之頁面，中文直排                                                       | `imprimeur`，及約 580 MB 之字型                 |
| `imprimeur-skin-minitel`  | 版式（skin）：向終端機致意之作，色彩取自您的佈景主題。安裝之後，頁面即以此版式開始 | `imprimeur`，無須字型                           |
| `imprimeur-skin-xix`      | 版式：十九世紀之法國書籍                                                           | `imprimeur` 及其字型                            |
| `imprimeur-skin-xviii`    | 版式：十八世紀之法國書籍                                                           | `imprimeur` 及其字型                            |
| `imprimeur-skin-xvii`     | 版式：十七世紀之法國書籍                                                           | `imprimeur` 及其字型                            |
| `imprimeur-skin-briefing` | 版式：現代商務備忘錄                                                               | `imprimeur` 及其字型                            |
| `imprimeur-skin-ecrivain` | 版式：紙上手書                                                                     | `imprimeur` 及其字型，其格線有賴於此            |

安裝版式，即是安裝程式碼：其樣式表於頁面中執行，其過濾器於 pandoc 中執行。

## <a id="configuration"></a>設定

唯此 Emacs 具備 xwidgets，頁面方能顯示於 Emacs 視窗之內。欲知其有無，可鍵入 `M-: (featurep 'xwidget-internal) RET`：得
`t` 者即已具備；得 `nil` 者，頁面改由瀏覽器開啟。

以下為完整設定，依載入之先後排列；區塊內之註解，一仍英文原文。所列諸值皆為預設，僅須留存有所更動者。刪去一項，則日後發行
版更改預設時隨之而變；留存於此者，則維持不動。

```elisp
;; imprimeur first: a skin's recipe needs it.
(use-package imprimeur
  :straight (imprimeur :type git :host github :repo "piotr-yuxuan/imprimeur"
                       ;; This package's Lisp files, and the page's assets beside them.
                       :files ("imprimeur/*.el" "imprimeur/assets"))
  ;; A key of your own.  The mode adds M-g v, M-g s and M-g o where it is on, and no other.
  :bind ("C-c i" . imprimeur-mode)
  :custom
  ;; Where the page opens: `auto', in an Emacs window when the selected Emacs frame is
  ;; graphic and this Emacs has xwidgets, otherwise in a desktop window of the browser;
  ;; `xwidget', in an Emacs window, refusing where that cannot run; `browser', in a
  ;; desktop window of the browser.
  (imprimeur-target 'auto)
  ;; How `display-buffer' shows the page in an Emacs window: on the right of the Emacs
  ;; frame, half its width, and the source stays selected.  '((display-buffer-same-window))
  ;; takes the source's Emacs window instead, and quitting brings the source back.
  (imprimeur-display-buffer-action
   '((display-buffer-reuse-window display-buffer-in-direction)
     (direction . right)
     (window . root)
     (window-width . 0.5)
     (dedicated . t)
     (reusable-frames . visible)))
  ;; Which way the page and the source follow each other's scrolling: `both'; `to-preview',
  ;; the page follows the source alone; nil, neither, until `imprimeur-follow-mode' by hand.
  (imprimeur-scroll-sync 'both)
  ;; The browser of a desktop window: Chromium, or one that takes its options.
  (imprimeur-browser-program "chromium")
  ;; pandoc 3, or a wrapper whose output stays a bare fragment.
  (imprimeur-pandoc-program "pandoc")
  ;; Which pandoc reader a buffer takes: a major mode, or a pattern on the file name.
  ;; Markdown without markdown-mode: add ("\\.md\\'" . "gfm+sourcepos").
  (imprimeur-reader-alist
   '((org-mode . "org")
     (markdown-mode . "gfm+sourcepos")
     (rst-mode . "rst")
     (mediawiki-mode . "mediawiki")
     (textile-mode . "textile")
     ("\\.creole\\'" . "creole")
     ("\\.pod\\'" . "pod")
     ("\\.ipynb\\'" . "ipynb")
     ("\\.csv\\'" . "csv")
     ("\\.tsv\\'" . "tsv")))
  ;; Seconds of quiet after a change before a render.
  (imprimeur-render-delay 0.3)
  ;; Seconds after which a render happens even while you go on typing.
  (imprimeur-render-max-delay 2.0)
  ;; Seconds after which a render is abandoned, and its error shown.
  (imprimeur-render-timeout 20)
  ;; Whether remote images load: `trusted', for documents that `trusted-content' accepts;
  ;; nil, never; t, always.  Elsewhere each one is a link that names its host.
  (imprimeur-remote-images 'trusted)
  ;; Whether the page is light or dark: `auto', as the Emacs frame; `light'; `dark'.
  (imprimeur-appearance 'auto)
  ;; The script that draws Mermaid diagrams: nil, the copy beside the program mmdc; or a
  ;; file name.  Without one a diagram stays as code, and nothing is fetched.
  (imprimeur-mermaid-script nil)
  ;; The skin of a new page: `auto', Minitel if installed and otherwise the plain page;
  ;; `base', the plain page; or a skin's name, such as `xix'.
  (imprimeur-skin 'auto)
  ;; Each skin's options, to start from; M-g o tries one, and says what to write here.
  (imprimeur-skin-options
   '((minitel
      ;; The colours: "emacs", your theme's; "videotex"; "greys".
      (palette . "emacs")
      ;; The columns: "80"; "40", in larger letters.
      (columns . "80")
      ;; The bar of keys: "fixed"; "end", at the document's end; "off".
      (keys . "fixed"))
     (xix
      ;; The text: "junicode", "bodoni-moda", "bodoni-moda-optical", "playfair",
      ;; "playfair-display", "old-standard", "theano", "libertinus", "eb-garamond".
      (text-face . "junicode")
      ;; "none", "common", "discretionary", "historical".
      (ligatures . "discretionary")
      ;; The column in rem: "24", "24-5" and so on by half a rem, to "40".
      (measure . "30"))
     (xviii
      ;; "baskervville", "junicode".
      (face . "baskervville")
      ;; Long s, under Junicode only: "off", "on".
      (long-s . "off")
      ;; "fleurons", "rinceau", "entrelacs", "perles", "filet".
      (bands . "fleurons"))
     (xvii
      ;; "im-fell", "eb-garamond", "garamond-libre".
      (face . "im-fell")
      ;; Long s: "on", "off".
      (long-s . "on")
      ;; Historical ligatures: "on", "off".
      (ligatures . "on")
      ;; Notes in the margin: "on"; "off", at the end of the section.
      (manchettes . "on"))
     (briefing
      ;; "blue", "teal", "aubergine", "graphite".
      (accent . "blue")
      ;; "compact", "regular", "airy".
      (density . "compact")
      ;; The bottom line, the titles and the callouts alone: "off", "on".
      (skim . "off"))
     (ecrivain
      ;; The hand and its paper: "cahier", "carnet", "notes", "ardoise".
      (variant . "cahier")
      ;; In Cahier: "moderne", "trad".
      (hand . "moderne")
      ;; "variante", the variant's own; "bleu-noir", "bleu", "noir", "violet", "sepia".
      (ink . "variante")
      ;; "pageless", one long sheet; "pages", the leaves of a notebook.
      (sheet . "pageless"))
     (tianlu
      ;; The grid and its dress: "song", "juzhen", "siku".
      (preset . "song")
      ;; "auto", as the preset says; "moe", "kai", "ming", "fang".
      (face . "auto")))))

;; A skin is one recipe, and imprimeur registers it once it loads.  Keep those you want.
(use-package imprimeur-skin-tianlu
  :straight (imprimeur-skin-tianlu :type git :host github :repo "piotr-yuxuan/imprimeur"
                                   :local-repo "imprimeur"
                                   :files ("imprimeur-skin-tianlu/*.el" "imprimeur-skin-tianlu/assets"))
  :defer t)

(use-package imprimeur-skin-minitel
  :straight (imprimeur-skin-minitel :type git :host github :repo "piotr-yuxuan/imprimeur"
                                    :local-repo "imprimeur"
                                    :files ("imprimeur-skin-minitel/*.el" "imprimeur-skin-minitel/assets"))
  :defer t)

(use-package imprimeur-skin-xix
  :straight (imprimeur-skin-xix :type git :host github :repo "piotr-yuxuan/imprimeur"
                                :local-repo "imprimeur"
                                :files ("imprimeur-skin-xix/*.el" "imprimeur-skin-xix/assets"))
  :defer t)

(use-package imprimeur-skin-xviii
  :straight (imprimeur-skin-xviii :type git :host github :repo "piotr-yuxuan/imprimeur"
                                  :local-repo "imprimeur"
                                  :files ("imprimeur-skin-xviii/*.el" "imprimeur-skin-xviii/assets"))
  :defer t)

(use-package imprimeur-skin-xvii
  :straight (imprimeur-skin-xvii :type git :host github :repo "piotr-yuxuan/imprimeur"
                                 :local-repo "imprimeur"
                                 :files ("imprimeur-skin-xvii/*.el" "imprimeur-skin-xvii/assets"))
  :defer t)

(use-package imprimeur-skin-briefing
  :straight (imprimeur-skin-briefing :type git :host github :repo "piotr-yuxuan/imprimeur"
                                     :local-repo "imprimeur"
                                     :files ("imprimeur-skin-briefing/*.el" "imprimeur-skin-briefing/assets"))
  :defer t)

(use-package imprimeur-skin-ecrivain
  :straight (imprimeur-skin-ecrivain :type git :host github :repo "piotr-yuxuan/imprimeur"
                                     :local-repo "imprimeur"
                                     :files ("imprimeur-skin-ecrivain/*.el" "imprimeur-skin-ecrivain/assets"))
  :defer t)

;; sommaire needs none of the above.
(use-package sommaire
  :straight (sommaire :type git :host github :repo "piotr-yuxuan/imprimeur"
                      :local-repo "imprimeur"
                      :files ("sommaire/*.el"))
  ;; On in every Org and Markdown buffer.
  :hook ((org-mode markdown-mode) . sommaire-mode)
  ;; Keys of your own, for the two commands that have none.
  :bind (:map sommaire-mode-map
              ("C-c m" . sommaire-panel)
              ("C-c M" . sommaire-toggle-inline))
  :custom
  ;; Show the segment in the header line: t; nil leaves the header line alone.
  (sommaire-header-line t)
  ;; A button on the headings that have an inline minitoc: t; nil, none.
  (sommaire-heading-buttons t)
  ;; Follow point after this many seconds of idle time.
  (sommaire-idle-delay 0.4)
  ;; What M-g m and the panel list: (ROOT . DEPTH).  ROOT is `section', around point, or
  ;; `document'.  DEPTH is how many levels below it: a positive integer, or `all'.
  (sommaire-scope '(section . 1)))

;; Documents you trust may load remote images and include other files, with pandoc outside
;; its sandbox.  Emacs's own option, which other packages read: list only what you wrote.
;; (setq trusted-content '("~/notes/"))
```

## 按鍵

| 按鍵                                                   | 所在                             | 作用                                           |
|--------------------------------------------------------|----------------------------------|------------------------------------------------|
| `M-g v`                                                | 原稿（source，即編輯中之緩衝區） | 將游標（point）所在之區塊捲至頁面頂端          |
| `M-g v`                                                | 頁面之 Emacs 視窗                | 返回原稿，至頁面頂端所對應之行                 |
| `M-g s`                                                | 兩者皆可                         | 由選單選擇版式                                 |
| `M-g o`                                                | 兩者皆可                         | 設定此頁版式之選項，並告知留存此設定所需之一行 |
| `SPC`, `DEL`, `C-v`, `M-v`, `C-n`, `C-p`, `M-<`, `M->` | 頁面之 Emacs 視窗                | 捲動頁面                                       |
| `q`                                                    | 頁面之 Emacs 視窗                | 隱藏頁面，頁面仍持續更新                       |
| `+`, `-`, `0`                                          | 頁面之 Emacs 視窗                | 放大或縮小頁面，或復其原有大小                 |
| `t`                                                    | 頁面                             | 開啟膠囊標籤之彈出框，即此頁之目次             |
| 連按兩下                                               | 頁面                             | 將游標移至原稿之對應行                         |
| 按住 Control 轉動滾輪                                  | 頁面                             | 放大或縮小頁面；兼按 Alt，則及於所有緩衝區     |
| `M-g m`                                                | sommaire 緩衝區                  | 前往游標所在章節內之某一標題                   |

全部按鍵見[指令與按鍵](docs/reference/commands-and-keys.md)。

## 字型

版式僅指明字型，並不隨附；若缺，頁面則退而採用您現有之字型。Minitel 無須字型。若用 Nix，請將本儲存庫作為一般之 flake
input，即 `inputs.imprimeur = { url = "github:piotr-yuxuan/imprimeur"; flake = false; };`，於 NixOS 下：

```nix
fonts.packages = lib.concatMap
  (skin: import "${inputs.imprimeur}/imprimeur-skin-${skin}/fonts.nix" { inherit pkgs; })
  [ "xix" "xviii" "xvii" "briefing" "ecrivain" ];
```

於 Home Manager 下，同一清單置於 `home.packages`，並設 `fonts.fontconfig.enable = true`。Tianlu 另有兩款字型，須以判斷式
（predicate）許可，請先閱其授權條款。不用 Nix 者，請依各版式 README 之「Fonts」表安裝所列字族；Écrivain 若無其支撐字型
（strut），字母便不能落於格線之上。詳細步驟見[安裝字型](docs/how-to/install-the-fonts.md)。

## 說明文件

**入門教學**

- [初次預覽](docs/tutorials/first-preview.md)：自複本至排印完成之頁面。

**操作指引**

- [選擇並調整版式](docs/how-to/choose-and-tune-a-skin.md)：選定一款，設定其選項，並予留存。
- [撰寫版式](docs/how-to/write-a-skin.md)：先為樣式表，次為過濾器與模組。
- [安裝字型](docs/how-to/install-the-fonts.md)：於 NixOS、Home Manager，或不用 Nix。
- [使用 sommaire](docs/how-to/use-sommaire.md)：於長篇緩衝區內知所在。
- [同步與跟隨](docs/how-to/sync-and-follow.md)：往來於原稿與頁面之間。
- [縮放頁面](docs/how-to/zoom-the-page.md)：其按鍵、滾輪，及 Emacs 之文字縮放。
- [依症狀排解問題](docs/how-to/troubleshoot.md)：訊息之意，及應對之道。

**參考資料**

- [選項](docs/reference/options.md)：所有選項，及其預設值與可選之值。
- [指令與按鍵](docs/reference/commands-and-keys.md)：所有指令、按鍵與點按。
- [文件可容之內容](docs/reference/documents.md)：格式、媒體、圖表、數學式。
- [版式 API](docs/reference/skin-api.md)：`imprimeur-skin-define` 之各鍵。
- [小目次規則](docs/reference/minitoc-rules.md)：何種文件得何種小目次。
- [發行流程](docs/reference/release-pipeline.md)：兩項工作流程、發行時所寫入者，以及如何手動提升版本。
- 各版式之 README：[Tianlu](imprimeur-skin-tianlu/README.md)、[Minitel](imprimeur-skin-minitel/README.md)、[XIX](imprimeur-skin-xix/README.md)、
  [XVIII](imprimeur-skin-xviii/README.md)、[XVII](imprimeur-skin-xvii/README.md)、
  [Briefing](imprimeur-skin-briefing/README.md)、[Écrivain](imprimeur-skin-ecrivain/README.md)：其字型、選項與限制。
- [範例](examples/README.md)：何種版式宜開何種文件。

**原理說明**

- [imprimeur 之運作](docs/explanation/how-it-works.md)：其設計、一次編輯抵達頁面之經過、其防護，以及 sommaire。
- [何以用頁面而不用緩衝區](docs/explanation/why-a-page.md)：瀏覽器引擎之所予，及其所費。
- [何以取這些版式與字型](docs/explanation/why-these-skins-and-faces.md)：套件、清單、字型，以及各版式之所捨。

## 安全

所開啟之文件，來源不一，故除 Emacs 之 `trusted-content` 另有指明者外，皆視為未受信任。pandoc 於其沙盒中執行；頁面每一版
本皆經 DOMPurify 淨化，並受嚴格之 Content Security Policy 所限；伺服器僅於 127.0.0.1 監聽，並以隨機權杖把關；連結則一律
經由 Emacs 開啟。各層詳情，見[防護機制](docs/explanation/how-it-works.md#the-defences)。

## 現況

尚未正式發行。以下猶未試過：真實之 Wayland 工作階段，Emacs 視窗迄今僅於 Xvfb 上執行；於 xwidget 中以人手操作滾輪、按鍵與
連按兩下；影片於其中能否播放；以及 Mac。

## 開發

各項檢查皆於 `nix develop` 中執行，其中備有所有工具，及諸套件所針對之唯一 Emacs：`nix develop --command make check`。
`make gallery` 重製圖片，`make smoke-xwidget` 試驗真實之 xwidget，二者皆須有顯示環境。相關規範見 `AGENTS.md`。

## 授權

imprimeur、sommaire 與諸版式，依歐洲聯盟公共授權條款 1.2（`LICENSE`）授權，或由您選擇，依 GNU 通用公共授權條款第 3 版或
其後任一版本（`COPYING`）授權：`EUPL-1.2 OR GPL-3.0-or-later`。

imprimeur 隨附 DOMPurify 之副本，依 Apache License 2.0 或 Mozilla Public License 2.0 授權，見
`imprimeur/assets/vendor/dompurify/`；另附 hyph-utf8 之法語及英式英語斷字規則，依 MIT 授權條款，見
`imprimeur/assets/vendor/hyph-utf8/`。

</div>
