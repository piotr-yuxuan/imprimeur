# SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
#
# Sourced by scripts/check-public and scripts/check-commits: the text that
# must not be published, as Perl regular expressions over bytes, for grep
# run with LC_ALL=C.

# U+2013 and U+2014, encoded in UTF-8.
public_dash='\xe2\x80[\x93\x94]'

# Home directories and Nix store paths.
public_path='/home/[A-Za-z]|/Users/[A-Za-z]|/nix/store/[a-z0-9]{32}'

# E-mail addresses, except the noreply identity and example.invalid.
public_email='[A-Za-z0-9._%+-]+@(?!users\.noreply\.github\.com\b|example\.invalid\b)[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'

# Print a pattern matching the text $1 as a whole word, ignoring the case
# of ASCII letters.  Read as bytes, the letters outside ASCII are bytes 0x80
# to 0xff, which \b would take for word boundaries; the lookarounds count
# them as letters.
public_word_pattern() {
  printf '(?i)(?<![A-Za-z0-9_\\x80-\\xff])\\Q%s\\E(?![A-Za-z0-9_\\x80-\\xff])\n' "$1"
}

# Print the machine's user name, IMPRIMEUR_CHECK_USER or else the login,
# as a pattern, unless it is shorter than 4 characters or a generic
# account name, words that occur in ordinary text.
public_user() {
  local user=${IMPRIMEUR_CHECK_USER:-$(id -un)}
  if (( ${#user} >= 4 )) && ! [[ $user =~ ^(root|runner|nixbld[0-9]*|build|user|admin)$ ]]; then
    public_word_pattern "$user"
  fi
}

# Print the private words, one pattern per line, from the file named by
# IMPRIMEUR_PRIVATE_WORDS, or else from docs/work/private-words in the
# primary checkout, which every linked worktree shares; blank lines and
# lines starting with # are ignored.  Without the default file, print a
# notice on standard error and no pattern.  Return 2 when the named file
# does not exist, or outside a git repository.
public_words() {
  local file=${IMPRIMEUR_PRIVATE_WORDS:-} common word
  if [[ -n $file && ! -f $file ]]; then
    echo "no private word list at $file, which IMPRIMEUR_PRIVATE_WORDS names" >&2
    return 2
  fi
  if [[ -z $file ]]; then
    common=$(git rev-parse --path-format=absolute --git-common-dir) || return 2
    file="$(dirname "$common")/docs/work/private-words"
  fi
  if [[ ! -f $file ]]; then
    echo "notice: no private word list at $file" >&2
    return 0
  fi
  while IFS= read -r word || [[ -n $word ]]; do
    word=${word%$'\r'}
    [[ -z $word || $word == \#* ]] || public_word_pattern "$word"
  done < "$file"
}
