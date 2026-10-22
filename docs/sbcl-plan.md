# SBCL in Zed — a plan

**PROPOSED, 2026-10-22. Nothing is built, and this is not scm.** It lives
here because its first decisions are decisions about *this* repository —
what of the extension shape, the language-server design and the debug
adapter is inherited, and where the fork is. Move it once there is a
`zed-sbcl` to put it in.

The named consumer is **raylisp** (`~/devel/raylisp`), the way ray was for
scm. A plan with no consumer invents requirements.

## Why it is worth doing, in Kevin's words

> *about 20% of the functionality of SLIME is what I need, and using Zed
> instead of Emacs is a compelling enough argument for new users of Lisp*

Both halves matter. The 20% sets the scope — this is not a SLIME
replacement and must not drift into one. And the audience being
*newcomers* decides the architecture below, because what loses a newcomer
is not a missing inspector. It is setup.

## The premise, corrected

SBCL is external and is not modified — **and that costs nothing**, because
a Common Lisp image is extended by *loading* code into it. That is how
Swank works. The slot that held "three new crates inside scm" becomes "a
Lisp file the editor loads": no fork, no patch, nothing to keep current
with SBCL's release cycle.

Having SBCL's source matters for a different reason, and a real one — see
*Package locks* below.

## The architecture decision: no Swank

The obvious design is a Swank client, and for 20% of SLIME it is the
expensive way there. Swank is a 200-message asynchronous protocol with
length prefixes, thread ids, interleaved events and `:emacs-rex`/`:return`
correlation; and after writing a client you would **still** need the user
to have Swank installed, which means Quicklisp or a SLIME checkout.

Instead: **a single self-contained `.lisp` file the extension loads**,
speaking plain LSP and DAP — the two protocols this repository has now
implemented twice. Probed against SBCL 2.6.4 before proposing it, all from
standard CL plus `sb-introspect` and `sb-di`, with no Quicklisp and no
ASDF:

| needed | probed |
|---|---|
| arglists, for completion and signature help | `(A &OPTIONAL (B 2) &KEY C)` for a user function; `sb-introspect:function-lambda-list` |
| docstrings, for hover | `documentation` |
| definition sites, for go-to-definition | file **and character offset**, image-wide — including `mapcar` into `SYS:SRC;CODE;LIST.LISP` |
| completion candidates | 978 external symbols of `COMMON-LISP`, fixed by the standard |
| frames at an error | `[0] INNER`, `[1] OUTER`, … |
| locals per frame | `INNER: N = 5` / `OUTER: DOUBLED = 2, K = 5` |
| recovery | `RESTARTS: (CONTINUE-ANYWAY RETRY CONTINUE ABORT ABORT)`, and resuming through one worked |

That is the whole 20%, reachable from loaded code. So the cost inverts:
~700 lines of CL instead of a Swank client, and the editor side becomes a
third copy of a design already known to work.

**And it fixes the thing that actually loses newcomers.** Setup becomes
"install SBCL, install the extension" instead of "install Quicklisp, clone
SLIME, load swank, configure your init". That is the compelling pitch, not
the feature list.

## Which 20%

| in | out |
|---|---|
| highlighting, brackets, outline | the inspector |
| a REPL window sharing the session | xref / who-calls |
| eval form at point, region, buffer | profiler, trace UI |
| completion, with arglists while typing | presentations, fuzzy completion |
| hover: arglist, docstring, value | threads list, multiple connections |
| **compiler warnings as diagnostics** | macroexpand UI, apropos browser |
| go-to-definition, image-wide | full SLDB restart machinery |
| an error stop: frames, locals, restarts | stepping, at first |

## Four things that land better than they did for scm

1. **Real diagnostics.** `compile-file` gives genuine warnings and style
   warnings with source locations. `scm-lsp` has only reader errors.
2. **Go-to-definition needs no index.** `find-definition-sources-by-name`
   answers image-wide with a character offset, so S23b's whole workspace
   index is unnecessary — and it finds names defined at the REPL, which the
   textual index here never can.
3. **Restarts.** scm offers abort or return-a-value; CL offers a named
   menu, which is a better debugger and a *much* better teaching tool.
4. **No tail-call frame loss.** S24's surprise — a tail chain collapsing to
   one frame — does not happen. `OUTER`'s `K = 5` was right there.

And because the protocol would be ours, **streaming output is designed in
from the start** rather than retrofitted (scm's §13.3, and `docs/plan.md`
here for what its absence costs).

## Two constraints the probe found

- **SBCL's internal packages are locked.** Interning a name that does not
  exist is a hard error, not a warning: `sb-debug::eval-in-frame` took the
  probe down. So every internal entry point is confirmed against SBCL's
  source before use — which is where source availability earns its keep.
  Prefer the documented surface (`sb-introspect`, `sb-di`, `sb-ext`).
- **Locals need `(optimize (debug 3))`.** Without it SBCL discards
  variables and the debugger shows an empty frame. SLIME users meet this
  too. For raylisp it is a real trade, so it belongs behind a per-session
  toggle rather than a global proclaim.

## Stages

| stage | what | where | size |
|---|---|---|---|
| **L1** | highlighting, brackets, indents, outline, text objects | the extension, queries only | 0.1 |
| **L2** | the server: one `.lisp` file, loaded, speaking LSP over a socket; plus a REPL terminal task and eval-at-point | new, ~700 lines of CL | 0.4 |
| **L3** | completion, hover, signature help, diagnostics, definition | the same file, plus an extension stub | 0.2 |
| **L4** | the debugger: frames, locals, evaluate-in-frame, **restarts** | DAP, re-shaped from `scm-dap` | 0.2 |
| **L5** | stepping, if wanted — SBCL has a stepper, unlike scm | the same file | 0.1 |

### L1 — highlighting

Greenfield: **no Common Lisp extension exists** in Zed's 1,579 (elisp,
racket and scheme are there). `tree-sitter-grammars/tree-sitter-commonlisp`
is maintained. The method transfers from Z1 wholesale, including generating
the builtin list from the image rather than recalling it — and here the
list cannot rot, being the standard's 978 symbols.

What is new is CL's richer reader: `|weird symbol|`, `#'f`, `#p"…"`,
`pkg:sym` versus `pkg::sym`, `#(`/`#C(`/`#2A(`, `&optional`/`&rest`/`&key`/
`&body`, `#+`/`#-` reader conditionals, and the `*special*` / `+constant+`
conventions, which deserve their own faces because they are how a reader
tells a global from a local at a glance.

### L2 — the server

One file, loaded by the extension, listening on a socket. It is not a
Swank client and it is not Swank: it answers LSP, with eval as an LSP
extension method or over the same socket in a small framing of our own.

Decisions to make before writing it, not during:

- **`*package*` per request.** A newcomer's first confusion is that a
  symbol means different things in different packages. The server must
  carry the buffer's `in-package` and say which package a request ran in.
- **One image or one per project?** One per workspace, started by the
  extension, is the newcomer answer: no daemon to manage.
- **What `eval` returns.** The value *printed*, plus output, plus the
  package it ran in — and output **streamed**, per above.

### L4 — the debugger, and restarts

DAP has no concept of a restart. The honest mapping is the one `scm-dap`
already uses for `,return`: expose them in the Debug Console as commands
(`,restart 2`, or by name), and list them in the `stopped` event's
description so they are visible without typing. For a newcomer this is
strictly better than SLDB's wall of text.

## What to reuse from this repository

- the extension shape: `extension.toml`, a `languages/<lang>/` directory,
  `get_dap_binary`/`dap_request_kind`/`dap_config_to_scenario`, and the
  rule that the extension only ever *names programs to launch*;
- `scm-lsp`'s division of labour — names from a live session, structure
  from a token scan that cannot fail, diagnostics from the real reader;
- `scm-dap`'s shape, including sharing one request queue with the break
  handler rather than giving it channels (which deadlocks);
- `scripts/check.sh`'s discipline: parse a real corpus, compile every
  query, and assert that the language's *own* spellings land on the right
  capture;
- the `gen-builtins.sh` pattern, generated from a live image with
  `--check` in CI so it cannot go stale.

## Two lessons from Z1–Z5 that would otherwise be repaid in full

- **A cursor position needs a test per boundary, not a representative
  one.** `token_at` preferred a token that merely *ended* at the cursor, so
  hover and go-to-definition did nothing for a symbol written straight
  after a delimiter — most symbols in a Lisp. Thirteen protocol tests
  passed over it for a day, because each happened to put the cursor
  *inside* a name.
- **Measure the thing the feature is for, not the feature.** The Z4 spike
  died on a measurement nobody had taken (`:output` does not stream), and
  S24 shipped with a hole the tests could not see (no output at a break).
  Both were found by driving the real binary and *timing* it.

## The question this plan does not answer

SLIME and Sly exist and are twenty years ahead. For a long time this would
be strictly worse for an experienced user. Kevin's answer is above — the
target is a newcomer, for whom Zed's familiarity and a one-step install
outweigh an inspector they have not yet needed — and that is a judgement
about who it is for, not an engineering claim. If the answer ever changes,
**L1 plus a terminal REPL plus the L2 spike** is the cheap slice that tests
it: a couple of days, no CL server, and enough to know whether the rest is
worth it.
