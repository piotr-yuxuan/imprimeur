# imprimeur-skin-tianlu

The skin Tianlu, 天祿, of [imprimeur](../README.md#skins): a Southern Song block-print page in Qing
palace dress, set in vertical text, in framed bands that still scroll down, each band a half-leaf
with its fold column. A document whose language starts with `zh` takes the Chinese passes below,
and any other language the page alone. `../examples/tianlu/` holds two essays, 庭桂小記 in
traditional and 毕昇与胶泥活字 in simplified characters, with their sources. No reader of Chinese
has checked them.

## Fonts

The skin names fonts and ships none. `fonts.nix` lists them, about 580 MB, most of it I.Ming's,
LXGW's and TW-Kai's sets, and the page falls back through its stacks on what is missing. In a
fallback a glyph may stand off its column's centre in WebKit, as the sheet's correction is by font,
and a face whose advance is not 1 em leaves the grid in Chromium.

| Family | Role | Source | Licence |
|---|---|---|---|
| MOESongUN, 教育部標準宋體UN | Traditional text under `song` and `moe` | The Ministry of Education's file, through `Jiehong/TW-fonts` at `2020-11-14` | CC BY-ND 3.0 Taiwan, credit 中華民國教育部 |
| TW-MOE-Std-Kai, 教育部標準楷書 | Traditional text under `siku` and `kai` | The Ministry of Education's 5.1, through `Jiehong/TW-fonts` at `2026-05-11` | CC BY-ND 3.0 Taiwan, credit 中華民國教育部 |
| TW-Kai, 全字庫正楷體 | Small text under the Song; what the Kai lacks; 注音 | nixpkgs `cns11643-kai` | OFL-1.1 |
| I.MingCP, 一點明體CP | Text under `juzhen` and `ming`; centred marks over Fangsong | nixpkgs `i-dot-ming` | IPA Font License v1.0 |
| Zhuque Fangsong (technical preview) | Simplified text under `song`; `fang` in both | `TrionesType/zhuque`, release v0.212 | OFL-1.1 |
| LXGW WenKai | Simplified text under `siku` and `kai` | nixpkgs `lxgw-wenkai` | OFL-1.1 |
| Noto Serif CJK SC, TC | Simplified text under `juzhen`, `ming` and `moe`; what the Song lacks | nixpkgs `noto-fonts-cjk-serif` | OFL-1.1 |
| Noto Sans Mono CJK TC, SC | Code | nixpkgs `noto-fonts-cjk-sans` | OFL-1.1 |
| Libertinus Serif, Libertinus Math | Latin in a column; mathematics | nixpkgs `libertinus` | OFL-1.1 |

The Ministry's two fonts are under <https://creativecommons.org/licenses/by-nd/3.0/tw/>, with the
credit 中華民國教育部. `fonts.nix` fetches each whole and installs it unchanged, and nothing derived
from either may be made or published, so neither may be subset. nixpkgs calls that licence unfree, so
name them:

```nix
# Only one predicate stands: merge this with any you have.
nixpkgs.config.allowUnfreePredicate = pkg:
  builtins.elem (lib.getName pkg) ["imprimeur-font-moe-song" "imprimeur-font-moe-kai"];
# With inputs.imprimeur.flake = false.  Under Home Manager: home.packages, and fonts.fontconfig.enable = true.
fonts.packages = import "${inputs.imprimeur}/imprimeur-skin-tianlu/fonts.nix" {inherit pkgs;};
```

Then `fc-list : file postscriptname | grep TW-MOE-Std-Kai` must name one file,
`edukai-5.1_20251208.ttf`: remove any other from whatever installs it. The Kai 4.0 shares its family,
PostScript name and fontconfig version, so a machine holding both may draw either: in WebKit the grid
holds and the drawing is the older one, and in Chromium its Han stand at 1.2 em and the grid breaks.
Both happen under `siku` and `kai` alone, never at the default.

## Options

`M-g o` chooses one, and the echo area gives the entry to keep in `imprimeur-skin-options`.

| Option | Values | Default |
|---|---|---|
| `preset` | `song` 宋槧, `juzhen` 聚珍, `siku` 四庫 | `song` |
| `face` | `auto` follows the preset, `moe` 教育部宋, `kai` 楷, `ming` 明 or 宋, `fang` 仿宋 | `auto` |

```elisp
;; Every page starts in Tianlu, rather than in Minitel.
(setq imprimeur-skin 'tianlu
      ;; By skin, then by option: at their defaults, so keep only what you change.
      imprimeur-skin-options '((tianlu (preset . "song")
                                       ;; auto, moe, kai, ming or fang.
                                       (face . "auto"))))
```

What each preset fixes:

| | Grid | Paper and rules | Frame | Ear | `auto`, traditional | `auto`, simplified |
|---|---|---|---|---|---|---|
| `song` 宋槧 | 10 × 20 | Bamboo paper, ink rules | Double left and right, single above and below | Yes | The Ministry's Song | Zhuque Fangsong |
| `juzhen` 聚珍 | 9 × 21 | Palace paper, ink rules | Double all round | No | I.MingCP | Noto Serif CJK SC |
| `siku` 四庫 | 8 × 21 | Palace paper, vermilion rules and fold | Double all round | No | The Ministry's Kai | LXGW WenKai |

What each face gives, whatever the preset:

| Face | Traditional | Simplified |
|---|---|---|
| `moe` | The Ministry's Song, with small text in TW-Kai | Noto Serif CJK SC, as the Song holds no simplified forms |
| `kai` | The Ministry's Kai, with TW-Kai behind it | LXGW WenKai |
| `ming` | I.MingCP: inherited forms, so 為 draws as 爲, and centred marks | Noto Serif CJK SC |
| `fang` | Zhuque Fangsong, with centred marks from I.MingCP | Zhuque Fangsong, with its own marks in the corner |

**The floor of the Song.** It carries hinting that WebKit runs at scale 1, where strokes merge at small
sizes: of the samples' 659 Han, 16 at 16 px, 6 at 18, 2 at 19, none from 22. So notes, headnotes, the
fold, captions, wide tables and diagrams' labels take TW-Kai, with the same forms. The seal stays in
the text's face, where its solid strokes stand out. And on a grid under 19 px the text itself goes to
TW-Kai: under `song` below 488 px tall or 408 px wide, and with `moe` under `juzhen` or `siku` below
507 px tall or 375 px wide.

A document whose language is `zh-CN`, `zh-Hans` or `zh-SG` is simplified, and any other `zh` traditional.

## Writing for it

| To show | In Org | In Markdown |
|---|---|---|
| Seal, end seal, colophon, lunar date | `#+SEAL:`, `#+ENDSEAL:`, `#+COLOPHON:`, `#+LUNAR:` | `seal:`, `endseal:`, `colophon:`, `lunar:` in the front matter |
| Headnote, in vermilion above its paragraph | `#+begin_headnote` | `<div class="headnote">` |
| Note, in two lines in place | `[fn::...]` | `[^1]` |
| 注音 | `@@html:<ruby>帖<rt>ㄊㄧㄝˋ</rt></ruby>@@` | `<ruby>帖<rt>ㄊㄧㄝˋ</rt></ruby>` |
| Emphasis, 點 and 圈 | `/words/`, `*words*` | `*words*`, `**words**` |
| Caption of a diagram | `#+CAPTION:` | `圖：` or `图：` after it |
| Caption of a table | `#+CAPTION:` | `表：` before it |

The lunar date opens with the year's stem and branch, as in 丙午九月二十三日, as only a lunar calendar
knows the year's turn. A pair of the wrong parity prints no date. A first-level heading is a juan, and
closes with its end title. Code, Mermaid, pictures, films, formulas alone and tables over 16 cells wide
are horizontal plates. A table under that runs on the grid.

In Chinese, what a copy gives is the page's text and not the source's: the turned marks `「」` and
`『』`, and no space beside a Han character.

## Limits

A plate wider than what is left of its band starts the next band, so the rest of that band stays blank.
Diagrams keep imprimeur's drawing settings and shrink to their band, so that a long sequence diagram's
labels stand at about 8 px at 420 CSS px. 贅 邊 驚 簷 still merge at 19 to 21 px in the Song. A long note
jumps whole to the next column. Tall tables are blocks, so that a screen reader hears no table. A `rt` is
at `display: none`, so that a copy gives no annotation and a screen reader may not read it. A list item's
first line in Markdown stands 0.35 em further along than in Org. Chromium puts Latin and digits 1 px off
at 20, 21 and 22 px. A click finds its block's first line in the source, and a scroll its band's. A film
has no codecs in the WebKit of an Emacs window here. Tried in WebKit at scale 1 on a virtual display and
in headless Chromium, not on a real Wayland session or on a Mac.
