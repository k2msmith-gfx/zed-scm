# zed-scm

[scm](https://github.com/k2msmith-gfx/scm) in [Zed](https://zed.dev): an
embeddable R7RS-small Scheme in Rust, with the editing support its Emacs
client already has.

**Z1 — syntax highlighting — is what exists today.** Completion, a REPL
window and SLIME-style evaluation are staged in
[docs/plan.md](docs/plan.md), and most of that work lands in scm rather
than here: Zed extensions cannot add commands, keybindings or panels, so
completion means an LSP server and evaluation means a task, a kernel or a
debug adapter. The plan says which, and why.

## What Z1 does

Highlighting, bracket matching, indentation, the outline view and Vim text
objects for `.scm` files, over the default parser of
[6cdh/tree-sitter-scheme](https://github.com/6cdh/tree-sitter-scheme).
No Rust and no language server: it is tree-sitter queries and two TOML
files.

Three of scm's spellings get their own treatment, because the generic
Scheme queries cannot see them — `:` and `&` are legal identifier initials,
so the reader hands back ordinary symbols:

| spelling | highlighted as | why |
|---|---|---|
| `:at`, `#:at` | `@string.special.symbol` | a keyword, a type disjoint from symbols |
| `&opt` `&named` `&keys` | `@keyword` | lambda-list markers, not variables |
| `[a b c]` | `@punctuation.special` brackets | a vector constructor, not a list |

The keyword and builtin lists are **measured, not copied**: the special
forms come from `SpecialForms` in scm's `vm.rs`, the macros from
`define-syntax` in its `prelude.scm`, and the 359 builtins from
`(apropos "")` against a live binary — `scripts/gen-builtins.sh`
regenerates that block and `--check` fails when it is stale. So `each`,
`for`, `repeat` and `seq` are coloured, which no generic Scheme query
knows about, and `λ` is **not**, because scm does not read it.

## Install

Not on the extension registry yet. Clone it and use Zed's
`zed: install dev extension`:

```
git clone https://github.com/k2msmith-gfx/zed-scm ~/devel/zed-scm
```

Then `cmd-shift-p` → `zed: install dev extension` → pick `~/devel/zed-scm`.
Zed compiles the grammar itself; nothing else is needed.

### It collides with the Scheme extension

Zed's [Scheme extension](https://github.com/zed-extensions/scheme) also
claims `scm`, and which one wins when both are installed is not defined.
Either uninstall it, or pin the suffix in `settings.json`:

```json
{ "file_types": { "scm Scheme": ["scm"] } }
```

## Checking it

```
SCM=~/devel/scm/target/release/scm ./scripts/check.sh
```

Clones the grammar at the commit `extension.toml` pins, generates the
parser, and then checks three things: that every `.scm` file in the scm
repository parses with no `ERROR` node, that each query file compiles, and
that scm's own spellings land on the capture they are meant to. The third
matters most — a `#match?` on symbol text is easy to get subtly wrong, and
a wrong colour looks exactly like a theme that does not style that
capture.

Needs `node` (for `npx tree-sitter-cli`) and a built scm.

## Known grammar gap

SRFI-4 homogeneous vector literals do not parse, and the interesting half
of that is silent: `#s8(-1 2)` is an honest `ERROR`, but **`#f64(1.0 2.5)`
reads as `#f`, then `64`, then a list** — a boolean where a vector was
written, which will colour as if nothing were wrong. It affects three test
files in the scm repository and none of ray's 45 `.scm` files, so Z1 ships
with it recorded in `scripts/check.sh` rather than forking the grammar.
The fix belongs upstream; 6cdh's README invites widely-used syntax.

## Licence

MIT or Apache-2.0, at your option — the same as scm.
