# scm in Zed — the plan

2026-10-21. What Zed can be made to do, what it cannot, and the staging.
The feasibility question was asked and answered before any code: **most of
the work is in scm, not in this repository.**

## What a Zed extension can provide

Measured against the extension docs and `zed_extension_api` 0.7.0, an
extension provides **languages and grammars, language servers, debug
adapters, themes, icon themes, snippets and MCP servers**, and nothing
else. The `Extension` trait has `language_server_command`,
`label_for_completion`, `get_dap_binary`, `context_server_command` and the
slash-command pair. There is **no API for a custom command, a keybinding,
a panel, a buffer overlay, or "send this form to a process"**.

That single fact decides the shape of everything below. `scm-mode.el` is
528 lines of client-side protocol plumbing; in Zed that plumbing cannot
live in the extension, so it moves into scm — where the modeler's editor
pane and ray's agent pane get it too, which is the better place for it
anyway. `docs/repl.md` already says the terminal prompt is one client among
several; this is another one.

## Stages

| stage | what | where the work is | status |
|---|---|---|---|
| **Z1** | highlighting, brackets, indents, outline, text objects | this repo, queries only | **DONE** |
| **Z2** | `scm --connect ADDR` + Zed tasks: a REPL in a terminal window, and eval of region / buffer / top-level form sharing one session | scm (`scm-cli`), plus `tasks.json` here | **DONE** |
| **Z3** | `scm-lsp`: completion, hover, signature help, diagnostics, document symbols, goto-definition | scm (new `scm-lsp` crate), ~40 lines here | **DONE** |
| Z4 | a Jupyter kernel, for results inline in the buffer rather than in a terminal | a kernel crate or shim, nothing here | |
| Z5 | a debug adapter over the break REPL: frames, locals, `,return` | scm, plus `debuggers` in `config.toml` | |

### Z1 — highlighting (done)

Queries only, no Rust. The decision that made it queries-only was measured
rather than assumed: the grammar at the pinned commit parses `[a b c]` as a
`list`, and both `:at` and `&opt` as plain `symbol`s, because `:` and `&`
are legal R7RS identifier initials. So scm's additions need no grammar
change — they need `#match?` on symbol text, which is what
`languages/scm/highlights.scm` does. `scripts/check.sh` proves it on every
`.scm` file in the scm repository.

**Limitations, which are Zed's and not fixable here.** `indents.scm` can
only say "this form indents its contents one level". There is no
per-head indent amount, so a `let`'s bindings do not align under the
opening paren the way `scheme-mode`'s `scheme-indent-function` aligns them,
and a `cond` clause is indented like any other sub-form. Nothing in the
extension API exposes an indent hook.

### Z2 — a REPL window and eval, the cheap 80%

Zed tasks expose `$ZED_SELECTED_TEXT`, `$ZED_FILE`, `$ZED_ROW` and
`$ZED_COLUMN`, and `task::Spawn { task_name }` is bindable in
`keymap.json`. A task with `use_new_terminal` runs the real terminal client
in a terminal tab — history, completion, comma commands and the break REPL,
free. So:

- **the REPL window** is a task running `scm`;
- **eval region / buffer** are tasks sending `:op eval` over the protocol.

The catch is that the terminal client today owns its own in-process
`Session`, so the window and the buffer evals would be two separate
sessions and would not share state. The fix is in scm, not here:
`scm --connect ADDR`, a terminal client of the protocol rather than of a
local session. `scm-cli/src/main.rs` has `--serve` and no `--connect`.

**`C-x C-e` — the sexp *before point* — does not survive the move.** The
task variables give a row, a column and a selection, not a cursor-aware
parse. What does survive, and is arguably better placed: pass `$ZED_FILE`
and `$ZED_ROW` and let **scm** find the enclosing top-level form. It has a
reader with locations; the editor does not need an AST.

**Z2 is done (2026-10-22).** It landed as scm's **S22** — `scm --connect`,
`Request::to_wire`, `Response::parse` — plus `bin/scm-eval` and
`examples/{tasks,keymap}.json` here. What the stage actually taught:

- **The interrupt was the only hard part.** A remote prompt's VM is in
  another process, so the SIGINT handler's flag was the wrong one. It now
  writes `:op interrupt` to a second connection with `write(2)`, which is
  async-signal-safe, from a descriptor stored at connect time; the text is
  a constant because a handler must not allocate. Tested with a real signal
  to a real client, not a mock.
- **The protocol was half-built and nobody had noticed**, because the only
  Rust consumer was the server. `Request::to_wire` and `Response::parse`
  did not exist, so this client would have formatted its own text — the
  divergence scm's §8 was written to prevent.
- **`C-x C-e` does not survive**, as predicted. `$ZED_ROW` plus a column-0
  heuristic in `scm-eval defun` covers `C-M-x`, which is the key that gets
  used.
- **Presentation is the client's job.** The prompt's banner and `scm> ` are
  right for a terminal and noise in a task pane, so `scm-eval` strips them
  rather than scm growing a `--quiet`. It also echoes the name a `define`
  bound, because "I evaluated this" is answered by the name, not by
  `#<unspecified>` — which is what `scm-mode.el` had already concluded.

### Z3 — `scm-lsp`

Completion in Zed means LSP, because the extension cannot answer a
completion request itself — `language_server_command` returns an argv and
everything after that is the protocol. The mapping onto `docs/repl.md` is
close to mechanical:

| LSP | op |
|---|---|
| `textDocument/completion` | `complete :prefix` |
| `textDocument/hover`, `signatureHelp` | `describe` — kind, signature, doc, value |
| `publishDiagnostics` | `parse` — `invalid` vs `incomplete` |
| `documentSymbol`, `definition` | the reader's location table |

That is `scm-describe-symbol` and `scm-eldoc-function` from the Emacs
client, arriving as hover and signature help. It is an adapter over
`Session`, not new semantics, and it is the stage with real size.

**Z3 is done (2026-10-22).** scm's **S23**: a `scm-lsp` crate, plus
`src/scm.rs` and a `[language_servers.scm-lsp]` entry here. It is a
separate binary, not `scm-lsp` as this plan first said: the `scm` binary
has a 10 ms boot budget with a test enforcing it, and a `--batch` sweep
should not pay for a JSON parser. What the stage taught:

- **It needed no new scm API.** `Interp::complete` and `describe` already
  answered completion and hover, `ReadError::Invalid{span,msg}` gave
  diagnostics a position, and S22 had already built the client half of the
  protocol. Unlike Z2, the `scm` crate was not touched at all.
- **The live session is the whole value.** A parse-the-file server would
  not know the procedure defined at the prompt, the accessor a macro
  generated, or a docstring as the value carries it. The test that matters
  defines something at a prompt and watches the editor complete it.
- **Structure must not come from the reader.** A buffer being edited is
  unparseable most of the time, so the outline comes from a token scan that
  cannot fail. Three lexer cases each cost a test because getting them
  wrong unbalances the rest of the file *silently*: `#\(` is a character,
  `#|` nests, and `'`/`#;` prefix without nesting.
- **Three coordinate systems meet in an LSP** and none is the others:
  scm's spans are char offsets, LSP positions are UTF-16 code units, and
  `Content-Length` is bytes. The test uses an emoji next to a `λ`, since
  one is two units and the other is one.

### Z4 — a Jupyter kernel

Zed's REPL runs any kernel it finds through Jupyter's kernelspec system, so
this needs no extension at all: a `kernel.json` under
`~/Library/Jupyter/kernels/scm/` and `repl: refresh kernelspecs`. The
payoff over Z2 is that results land **inline in the buffer**, which is
much closer to SLIME's overlays than a terminal is.

The message set maps onto scm's ops almost one for one, including the one
nobody expects: `is_complete_request` is exactly `parse`, the same
question `RET` asks in the Emacs REPL and at the terminal prompt.
`execute_request` is `eval`, `complete_request` is `complete`,
`inspect_request` is `describe`.

Two things to settle first. Zed matches a kernelspec's `language` to the
editor's language name and scm is not among the documented kernels
(Python, TypeScript, R, Julia, Scala), though a third-party OCaml kernel is
reported working — so **spike the kernelspec before building the kernel**.
And the wire protocol is ZeroMQ with HMAC-SHA256 signing, which scm's
no-dependencies rule will not have in the library; a kernel is a separate
crate, or a thin shim process, not a feature of `scm`.

### Z5 — a debug adapter

The break REPL (`live_frames`, `bindings_of`, `eval_in`, `,return`) maps
onto DAP's `stackTrace`, `scopes`, `variables` and `evaluate` unusually
well, and Zed supports debug-adapter extensions with a `debuggers` entry in
`config.toml`. It would give frame inspection with a real UI, which the
Emacs client does not have. Last, because Z2–Z4 may remove the appetite.

## What Zed cannot be made to do

A REPL **pane** of this package's own, with its own `RET`-completeness
semantics, read-only prompt text and `M-p` history — `scm-mode.el`'s
`*scm*` buffer. There is no UI API at any price. The terminal client in a
terminal tab is the substitute, and it is a decent one.

## Known grammar gaps

SRFI-4 homogeneous vector literals. `#s8(-1 2)` is an `ERROR`;
`#f64(1.0 2.5)` is worse, because it is **silent** — it reads as `#f`,
then `64`, then a list, and will colour as a boolean with nothing looking
wrong. Three test files in the scm repository; none of ray's 45 `.scm`
files. Recorded in `scripts/check.sh`, which fails if a new file starts
failing *and* if an allowlisted file starts passing, so the list cannot
outlive the gap. The fix belongs upstream.
