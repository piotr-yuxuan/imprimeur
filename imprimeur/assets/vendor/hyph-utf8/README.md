# hyph-utf8 patterns

`hyph-fr.pat.txt` (V2.13, 1216 patterns) and `hyph-en-gb.pat.txt` (8527 patterns) are
copied unchanged from the package hyph-utf8, as TeX Live ships it through nixpkgs:
<http://www.hyphenation.org/tex>. Both are under the MIT licence. They carry no header
of their own, so `NOTICE` holds the header of each `.tex` file word for word, the
licence's text and the grant of Oxford University Press included.

`imprimeur/assets/pandoc/filters/hyphenate.lua` holds the same bytes as two long
strings, as a filter may load no file; a test checks that they stay equal.

SHA-256:

```
fd40a89e9e8eb0784a0919e50378814843e44afa41c5beaf0a85f6562820f6c2  hyph-fr.pat.txt
651b89b4a0d4051995db8586e81ab109a4c7395d7706c06483893ebab5af013b  hyph-en-gb.pat.txt
```
