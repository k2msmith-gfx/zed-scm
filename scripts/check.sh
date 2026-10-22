#!/usr/bin/env bash
# What this checks, and why each check exists:
#
#   1. the grammar at the pinned commit parses scm's own source with no
#      ERROR node -- the thing that decides whether this can be a
#      queries-only extension or needs a grammar fork;
#   2. every query file compiles against that grammar -- a typo'd node name
#      is silently inert in Zed, so it has to fail here instead;
#   3. the spellings scm added to R7RS actually land on the capture they are
#      supposed to. A `#match?` on symbol text is easy to get subtly wrong,
#      and a wrong colour looks exactly like a theme that does not style it.
#
# Needs node (for npx) and a built scm. Set SCM to the binary.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
SCM="${SCM:-$HOME/devel/scm/target/release/scm}"
TS="npx -y tree-sitter-cli@latest"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/zed-scm"
commit=$(awk -F'"' '/^commit/ {print $2}' extension.toml)
repo=$(awk -F'"' '/^repository/ && /tree-sitter/ {print $2}' extension.toml)
fail=0
note() { printf '%s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*" >&2; fail=1; }

# --- the grammar, at the commit extension.toml pins -------------------------
if [ ! -d "$cache/grammar/.git" ]; then
  note "cloning $repo"
  mkdir -p "$cache"
  git clone -q "$repo" "$cache/grammar"
fi
git -C "$cache/grammar" fetch -q origin "$commit" 2>/dev/null || git -C "$cache/grammar" fetch -q
git -C "$cache/grammar" checkout -q "$commit"
cd "$cache/grammar"
[ -f src/parser.c ] || { note "generating parser"; $TS generate >/dev/null; }

# --- 1. parsing ------------------------------------------------------------
sources=("$root"/test/*.scm)
if [ -x "$SCM" ]; then
  scmrepo=$(cd "$(dirname "$SCM")/../.." && pwd)
  while IFS= read -r f; do sources+=("$f"); done < <(
    find "$scmrepo" \( -name '*.scm' -o -name '*.sld' \) -not -path '*/target/*' \
      -not -name 'r7rs-tests.scm' 2>/dev/null)
else
  note "no scm at $SCM; checking only test/*.scm"
fi
# Files the pinned grammar is known not to parse. The allowlist is checked
# both ways: a new failure outside it fails, and a file in it that now parses
# fails too, so the list cannot quietly outlive the gap it records. See
# docs/plan.md, "Known grammar gaps".
known_gap() { case "$(basename "$1")" in srfi/4.scm|4.scm) return 0;; *) return 1;; esac; }
for f in "${sources[@]}"; do
  n=$($TS parse "$f" 2>&1 | grep -c 'ERROR\|MISSING' || true)
  if known_gap "$f"; then
    if [ "$n" -gt 0 ]; then
      note "known gap: $n parse error(s) in $(basename "$f")"
    else
      bad "$(basename "$f") now parses; drop it from known_gap in $0"
    fi
  else
    [ "$n" -eq 0 ] || bad "$n parse error(s) in $f"
  fi
done
note "parsed ${#sources[@]} file(s)"

# --- 2. the queries compile ------------------------------------------------
for q in highlights brackets indents outline textobjects; do
  out=$($TS query "$root/languages/scm/$q.scm" "$root/test/spellings.scm" 2>&1) \
    || { bad "$q.scm does not compile:"; printf '%s\n' "$out" | head -5 >&2; continue; }
  note "$q.scm compiles"
  [ "$q" = highlights ] && printf '%s\n' "$out" > "$root/.check-highlights.txt"
done

# --- 3. scm's own spellings land on the right capture ----------------------
if [ -f "$root/.check-highlights.txt" ]; then
  expect() { # capture, text
    grep -qE "capture: [0-9]+ - $1, .*text: \`$2\`\$" "$root/.check-highlights.txt" \
      || bad "\`$2\` is not captured as @$1"
  }
  expect string.special.symbol ':tex-scale'   # a bare-colon keyword
  expect string.special.symbol ':a\*'
  expect keyword '&opt'                       # a lambda-list marker
  expect keyword '&named'
  expect keyword '&keys'
  expect punctuation.special '\['             # bracket vectors, not parens
  expect keyword 'define-record-type'
  expect keyword 'else'
  expect function.builtin 'vector-ref'        # from the generated block
  expect function 'f'                         # the name a define binds
  expect comment "; scm's own spellings"
  note "spelling checks done"
  rm -f "$root/.check-highlights.txt"
fi

# --- 4. the generated block is current -------------------------------------
if [ -x "$SCM" ]; then
  SCM="$SCM" "$root/scripts/gen-builtins.sh" --check || fail=1
fi

if [ "$fail" -eq 0 ]; then
  note "all checks passed"
else
  note "checks failed"
  exit 1
fi
