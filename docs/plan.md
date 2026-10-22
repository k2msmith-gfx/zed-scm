# scm in Zed — the plan

2026-10-21, and current at 2026-10-22. What Zed can be made to do, what it
cannot, and the staging. The feasibility question was asked and answered
before any code: **most of the work is in scm, not in this repository.**

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

## Where this left off — 2026-10-22

**The arc is complete as planned.** Z1, Z2, Z3 and Z5 are built, pushed and
in use; Z4 was spiked and deferred on evidence. Nothing here is half-done,
so the next session is picking a new thing rather than finishing an old one.

| | built | lives in |
|---|---|---|
| Z1 | highlighting, brackets, indents, outline, text objects, `.scm` + `.sld` | this repo, queries only |
| Z2 | a REPL terminal tab and eval of region / form / buffer, all one session | scm's **S22** (`scm --connect`) + `bin/scm-eval` and `examples/` here |
| Z3 | completion, hover, signature help, diagnostics, outline, goto-definition | scm's **S23** (`scm-lsp`) + `[language_servers]` and ~40 lines here |
| Z5 | a debugger: frames, locals, evaluate-in-frame, `,return` | scm's **S24** (`scm-dap`) + a schema, `[debug_adapters]` and three `dap_*` hooks here |

**To run all of it from a clean machine:** install the dev extension
(`zed: install dev extension` on this directory), `cargo install --path
scm-lsp` and `cargo install --path scm-dap` in the scm repository, copy
`examples/tasks.json` and `examples/keymap.json` into `~/.config/zed/`, then
run the `scm: serve` task once. Port 7000 throughout.

**What the whole arc proved, in one line:** a Zed extension cannot add a
command, a keybinding, a panel, or answer a completion request — so the
work goes in scm, and the extension only names programs to launch. Four
stages later the extension is ~150 lines of Rust and scm gained three
crates that any editor can use.

### If you are choosing what is next

Not Z4 — see its section for the measurement. Three candidates, best first:

1. **Streaming output in scm.** Raised *by* the Z4 spike rather than
   planned: `:output` travels with the answer, so a form that prints and
   then runs for two seconds sends nothing until it finishes. Fixing it
   would improve the Z2 task pane, `scm-mode.el` and `ray-scm` together.
   Argued in scm's `docs/repl.md` and `docs/plan.md` §13.3, **including why
   to wait**: the socket half is a two-repo change to the door ray depends
   on, and the modeler port is at 114 of 117. Do the embed-API sink half
   first if it is wanted sooner.
2. **Scoped completion.** Candidates are the global environment plus the
   file's top-level definitions, so a `let` binding is not offered. The
   same limit the REPL has, and fixing it in `scm-lsp` would need the
   token scan to track binding forms.
3. **Multi-dialect highlighting.** The grammar ships
   `dialects/{r5rs,r6rs,r7rs,chez,guile,chicken}`, so other Schemes are one
   `languages/` directory each. A different product, not a tweak — this one
   is deliberately scm-flavoured, which is its value over
   `zed-extensions/scheme`.

Known gap, unchanged: SRFI-4 literals do not parse, and `#f64(1.0 2.5)`
fails **silently** as `#f` + `64` + a list. Allowlisted in
`scripts/check.sh`. The fix belongs upstream.

## Stages

| stage | what | where the work is | status |
|---|---|---|---|
| **Z1** | highlighting, brackets, indents, outline, text objects | this repo, queries only | **DONE** |
| **Z2** | `scm --connect ADDR` + Zed tasks: a REPL in a terminal window, and eval of region / buffer / top-level form sharing one session | scm (`scm-cli`), plus `tasks.json` here | **DONE** |
| **Z3** | `scm-lsp`: completion, hover, signature help, diagnostics, document symbols, goto-definition | scm (new `scm-lsp` crate), ~40 lines here | **DONE** |
| Z4 | a Jupyter kernel, for results inline in the buffer rather than in a terminal | a kernel crate or shim, nothing here | **spiked, deferred** |
| **Z5** | a debug adapter over the break REPL: frames, locals, `,return` | scm (new `scm-dap` crate), plus `debuggers` + a schema here | **DONE** |

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

**Spiked 2026-10-22. Viable, and cheaper to reach than expected on one
axis — but the payoff is smaller than this plan assumed.** Four findings,
three of them from Zed's source rather than from trying things.

**1. The kernelspec hook is official, not an accident.** Zed matches a
kernelspec to a buffer with `Language::matches_kernel_language`, which
accepts the language's `code_fence_block_name`, its `name` lowercased, or
any entry in **`kernel_language_names`** — a `config.toml` field whose
docstring in `language_config.rs` says exactly this:

> *Alternative language names that Jupyter kernels may report for this
> language. Used when a kernel's `language` field differs from Zed's
> language name. For example, the Nu extension would set this to
> `["nushell"]`.*

So `kernel_language_names = ["scheme", "scm"]` here plus
`"language": "scheme"` in the kernelspec, and the picker finds it. The
earlier plan rested on a third-party report that an OCaml kernel worked;
it does not need to. A user can also pin one with `jupyter.kernel_selections`.

**2. The message mapping is as close to one-for-one as it looked.**
`execute_request`→`eval`, `complete_request`→`complete`,
`inspect_request`→`describe`, and `is_complete_request`→`parse` exactly —
Jupyter and scm's REPL ask the same question in the same words.

**3. Output does not stream, and this is what shrinks the prize.**
Measured against a live server: a form that `display`s, spins for two
seconds, then `display`s again and returns, sends **nothing for 2.00s** and
then everything at once —

    first bytes after 2.00s; complete after 2.00s
    (:id 1 :status ok :value "42" :output "FIRSTSECOND")

because `:output` travels with the answer (`scm/docs/repl.md`). A kernel
can only emit its `stream` messages after execution finishes. So inline
results would appear *when a form completes*, which for the long
operations this project cares about — a render — is no better than the
task pane Z2 already has. The win is confined to short forms.

Fixing it is not part of Z4: it needs an unsolicited `:output` message
pushed while an evaluation is still running, which means a second,
asynchronous path out of the session and contradicts "`Session::handle` is
the only door". That is a protocol stage of its own, and it would improve
Z2, `scm-mode.el` and `ray-scm` at the same time — which is an argument for
doing *it* rather than Z4.

**4. A trap to build against: Zed hangs on a kernel that does not bind the
stdin socket.** `zed#56918` — IHaskell works under `jupyter console` and
hangs Zed for ever on "Connecting to kernel…". Closed by a staleness bot
rather than fixed, so it stands.

**Cost, and the recommendation.** A Rust kernel means ZeroMQ, HMAC-SHA256
and the v5 message framing — several dependencies for a project whose
whole character is not having them. A Python `ipykernel` shim forwarding to
`scm --serve` is maybe 80 lines and no Rust dependencies, but puts a Python
runtime between the editor and a Rust language.

Given finding 3, **Z4 is deferred**: its remaining value over Z2 is
cosmetic placement of short-form results, and Z5 gives something that does
not exist at all today. If the inline feel is wanted before paying for a
Rust kernel, the Python shim is the trial, and it is throwaway by design.

### Z4 — a Jupyter kernel (original sketch)

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

**Z5 is done (2026-10-22).** scm's **S24**: a `scm-dap` crate, plus
`debug_adapter_schemas/scm.json`, a `[debug_adapters.scm]` entry and three
`dap_*` methods here. What the stage taught:

- **A tail call leaves no frame, and a debugger is where that becomes
  visible.** Three nested calls all in tail position stop with one frame
  and the outer binding is genuinely gone. §5 working correctly, now a
  test — because the test beside it had assumed otherwise, which is what a
  user will assume too.
- **What it refuses matters as much as what it does.** No breakpoints, no
  stepping, no attach, each for a structural reason, each refused with a
  message rather than accepted and ignored.
- **The obvious threading deadlocks.** The handler cannot have its own
  reply channel, because the thread that would drain it is blocked inside
  the evaluation the handler is describing.
- **This is the one piece that is not a client of `--serve`**: a break
  handler must be inside the process that owns the `Vm`.

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
