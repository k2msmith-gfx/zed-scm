# Installing zed-scm

Everything you need, in order, with a check after each step so a failure
is found where it happened rather than three steps later.

Four pieces, three of which live in the **scm** repository:

| piece | what it gives you | where it comes from |
|---|---|---|
| `scm` | the language, the server, the REPL | `scm/scm-cli` |
| `scm-lsp` | completion, hover, signature help, diagnostics, outline, go-to-definition | `scm/scm-lsp` |
| `scm-dap` | the debugger | `scm/scm-dap` |
| this extension | highlighting, and telling Zed about the other three | here |

## 0. What you need first

- **Zed.** Any recent build. (On this machine it is `Zed Preview.app`.)
- **A Rust toolchain**, for the three binaries and for the extension's
  WebAssembly. `cargo --version` should answer.
- **The `wasm32-wasip1` target**, which the extension compiles to:

      rustup target add wasm32-wasip1

  Harmless if it is already there. Zed fetches the C toolchain for the
  tree-sitter grammar itself, so that is the only target you add.
- **`node`**, *only* if you intend to run `scripts/check.sh`. Nothing at
  runtime needs it.

## 1. Build the three binaries

```
cd ~/devel/scm
cargo build --release
```

**Check:**

```
./target/release/scm --version                        # scm 0.0.1
./target/release/scm-lsp --addr 127.0.0.1:1 </dev/null  # one line, then exits 0
ls -l target/release/scm-dap
```

The middle one looks odd and is deliberate: `scm-lsp` speaks LSP on stdin,
so an empty stdin makes it report where it looked for a session and exit
cleanly. Expect

    scm-lsp: no server on 127.0.0.1:1 (Connection refused …); using this
    process's own session

which is the whole startup path proving itself without an editor.

## 2. Put them where Zed can find them

This is the step that actually goes wrong, and it goes wrong invisibly:
Zed looks the binaries up on the **PATH its shell environment gives it**,
which is not always the PATH you think.

`cargo install --path …` writes to `~/.cargo/bin` — and on a Nix-managed
machine that directory may be on **no** PATH at all, including yours. Check
before trusting it:

```
echo "$PATH" | tr ':' '\n' | grep -q "$HOME/.cargo/bin" \
  && echo "cargo bin is on PATH" || echo "cargo bin is NOT on PATH"
```

### Route A — symlink into a directory already on PATH (recommended)

```
cd ~/devel/scm
for b in scm scm-lsp scm-dap; do
  ln -sf "$PWD/target/release/$b" /opt/homebrew/bin/$b
done
```

`/opt/homebrew/bin` is on PATH and writable here. Symlinks rather than
copies, so a rebuild is picked up with no reinstall — which matters,
because a stale binary is the single most confusing failure in this stack.

**Check:**

```
which scm scm-lsp scm-dap      # three paths, all three found
scm --version
```

### Route B — tell Zed the paths instead

If you would rather not touch a PATH directory, name the binaries in
`~/.config/zed/settings.json`. The extension honours this and prefers it
over PATH:

```json
{
  "lsp": {
    "scm-lsp": {
      "binary": { "path": "/Users/kevinsmith/devel/scm/target/release/scm-lsp" }
    }
  }
}
```

Route B covers the language server. The **tasks** in step 5 invoke `scm`
as a bare command, and the debugger looks `scm-dap` up on PATH, so Route A
is the one that makes everything work with no further configuration.

## 3. Install the extension

1. `cmd-shift-p` → **`zed: install dev extension`**
2. Choose `~/devel/zed-scm`

Zed compiles the tree-sitter grammar and the extension's wasm. It takes a
few seconds the first time.

**Check:** open any `.scm` file — say `~/devel/scm/scm/src/prelude.scm` —
and look at the bottom-right language indicator. It should read **scm
Scheme**, not *Scheme* and not *Plain Text*.

## 4. Get the stock Scheme extension out of the way

Zed's own **Scheme** extension also claims `.scm`, and which one wins is
undefined. It is installed on this machine, so do one of these:

- uninstall it: `cmd-shift-p` → `zed: extensions` → Scheme → Uninstall; or
- pin the suffix in `~/.config/zed/settings.json`:

```json
{ "file_types": { "scm Scheme": ["scm", "sld"] } }
```

**Check:** the indicator still says **scm Scheme** after a restart.

## 5. The REPL and the eval keys

Copy the two example files into your Zed config directory — on this
machine `~/.config/zed/`, which already holds `settings.json`:

```
cp ~/devel/zed-scm/examples/tasks.json  ~/.config/zed/tasks.json
cp ~/devel/zed-scm/examples/keymap.json ~/.config/zed/keymap.json
```

If either file already exists, **merge** rather than overwrite: both are
JSON arrays, so paste the entries in.

The tasks assume `~/devel/zed-scm/bin/scm-eval` and port **7000**. If you
cloned elsewhere, edit the paths in `tasks.json`.

Then, once per session: `cmd-shift-p` → **`task: spawn`** → **`scm:
serve`**. Leave that terminal tab open — it is also where a script's own
output goes.

| key | does |
|---|---|
| `ctrl-c ctrl-z` | open a REPL on that server |
| `ctrl-c ctrl-c` | evaluate the top-level form containing the cursor |
| `ctrl-c ctrl-r` | evaluate the selection |
| `ctrl-c ctrl-k` | `(load …)` the file |
| `ctrl-c ctrl-b` | interrupt a runaway |

**Check, in this order — each one tests something the last did not:**

1. `ctrl-c ctrl-z`, then type `(+ 1 2)` → `3`. The REPL works.
2. In a buffer, write `(define (mine x) (* x 2))` and press
   `ctrl-c ctrl-c` → the pane says `mine`. Eval-from-buffer works.
3. Back in the REPL tab: `(mine 21)` → `42`. **The buffer and the REPL
   share one session**, which is the whole point of the arrangement.
4. Type `mi` in a buffer and complete → `mine` is offered, with no save
   and no re-eval. The language server is talking to that same session.

## 6. The debugger

Needs `scm-dap` on PATH (step 2, Route A).

Either `cmd-shift-p` → `debugger: start` and pick **scm**, or write
`.zed/debug.json` in a project:

```json
[{ "label": "run this file", "adapter": "scm", "program": "$ZED_FILE" }]
```

**Check:** make a file that fails —

```scheme
(define (inner n) (* 1 (car n)))
(display (+ 0 (inner 5)))
```

— and run it under the debugger. You should stop with `car: not a pair: 5`,
four frames, and `n = 5` in the variables pane. In the Debug Console, `n`
answers `5`, `(* n 10)` answers `50`, and **`,return 9`** continues the
program, which then prints `9`.

Mind what `,return` means: the value replaces **the expression that
failed**, which here is `(car n)`. So `,return 9` works and
`,return '(9)` does not — it would make `(car n)` produce a list, and the
`(* 1 …)` around it fails next with *not a number*. That is the feature
behaving correctly, and it is a sharp edge worth meeting on purpose.

Two things that are **not** bugs: there are no breakpoints or stepping
(scm's VM has no hook for either, so the adapter refuses them with a
message), and a chain of **tail calls** collapses to one frame — that is
correct Scheme, which is why the example above wraps the call in `(* 1 …)`
to keep the frame alive.

## 7. Optional: check the extension itself

```
cd ~/devel/zed-scm
SCM=~/devel/scm/target/release/scm ./scripts/check.sh
```

Parses every `.scm` and `.sld` in the scm repository, compiles each query
file, and asserts scm's own spellings land on the right capture. Needs
`node`. Expect `all checks passed` and one reported *known gap* — SRFI-4
literals, which the grammar does not parse.

## When something does not work

**Completion is empty.** Ask which session the server found: the
`initialize` handshake reports it. `cmd-shift-p` → `zed: open language
server logs` → `scm-lsp`. You will see one of

```
scm-lsp: connected to scm 0.0.1 on 127.0.0.1:7000
scm-lsp: no server on 127.0.0.1:7000 (…); using this process's own session
```

The second is not broken — completion still works over the prelude's 386
names — but it means `scm: serve` is not running, so names you defined at
the REPL will not appear.

**A different port.** Everything defaults to `127.0.0.1:7000`. To move it,
change all three: `tasks.json`, `SCM_ADDR` for `scm-eval`, and

```json
{ "lsp": { "scm-lsp": { "initialization_options": { "address": "127.0.0.1:7001" } } } }
```

**The language server never starts.** Its error names the fix. The usual
cause is step 2: `which scm-lsp` in a terminal is not proof, because Zed
may have a different PATH — Route A's symlink in `/opt/homebrew/bin` is on
both.

**Nothing changed after a rebuild.** If you copied the binaries instead of
symlinking them, you are running the old ones. `ls -l $(which scm-lsp)`
and compare against `target/release`.

**The editor behaves as if the extension were an older version.** Zed does
not rebuild a dev extension on its own. After `git pull` in `zed-scm`:
`cmd-shift-p` → `zed: reload extensions`, or install the dev extension
again.

**Output appears only when a form finishes.** That was true before scm's
S25 and is fixed; if you see it, the binaries predate it — rebuild
(step 1).
