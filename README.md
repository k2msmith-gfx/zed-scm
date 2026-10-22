# zed-scm

[scm](https://github.com/k2msmith-gfx/scm) in [Zed](https://zed.dev): an
embeddable R7RS-small Scheme in Rust, with the editing support its Emacs
client already has.

**Z1 (highlighting) and Z2 (a REPL window and SLIME-style evaluation) are
done.** Completion is Z3 and needs an LSP server; the staging is in
[docs/plan.md](docs/plan.md). Most of the work lands in scm rather than
here, because Zed extensions cannot add commands, keybindings or panels.

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

## Z2: a REPL window, and eval from the buffer

Zed has no API for "evaluate this form", so the editor's half is a **task**
and the keys are yours. What makes it a session rather than a series of
one-shot runs is `scm --connect` (scm's S22): the REPL tab and every eval
below are clients of **one** server, so a procedure defined from the buffer
is callable at the prompt a second later.

| key | task | what it does |
|---|---|---|
| | `scm: serve` | start the server; leave the tab open — it is also where a script's own output goes |
| `C-c C-z` | `scm: REPL` | a prompt on that server, in a terminal tab. History, completion, `,help`, the break REPL |
| `C-c C-c` | `scm: eval top-level form` | the form containing the cursor's line |
| `C-c C-r` | `scm: eval selection` | the selection |
| `C-c C-k` | `scm: eval buffer` | `(load FILE)`, so a backtrace names the file |
| `C-c C-b` | `scm: interrupt` | stop a runaway, on a second connection so it arrives |

Copy [examples/tasks.json](examples/tasks.json) into
`~/.config/zed/tasks.json` and [examples/keymap.json](examples/keymap.json)
into `~/.config/zed/keymap.json`, adjusting the path to `bin/scm-eval` and
the port. `bin/scm-eval` is the shell side: it strips the prompt's
furniture, and it echoes the **name** a `define` bound rather than the
nothing an unspecified value prints, the way `scm-mode.el` does.

Then `scm: serve` once, and the keys work.

### What does not survive the move from Emacs

- **`C-x C-e`, the sexp *before point*.** Zed gives a row, a column and a
  selection, not a cursor-aware parse. Select it, or use `C-c C-c`.
- **The break REPL at an eval from the buffer.** A break handler runs
  inside the failing evaluation with the frames live, and a socket carries
  values, not a stack. It works at the REPL tab, which is a real terminal.
- **Results in the echo area.** They land in the task pane. Z4 (a Jupyter
  kernel) is the stage that would put them inline in the buffer.

`scm-eval defun` finds a top-level form the way `beginning-of-defun` does:
one that starts in column 0. A form indented for some reason is not found,
which is the same thing the indentation already told you.

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

Needs `node` (for `npx tree-sitter-cli`) and a built scm. The shell side is
`shellcheck`-clean.

Z2's own gates are in the scm repository, where the work is:
`cargo test -p scm-cli --test connect` drives real sockets and a real
`SIGINT`, and the Emacs batch test proves `scm-mode.el` still works against
the same server.

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
