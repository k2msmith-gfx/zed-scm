//! The Rust half of the extension: where to find `scm-lsp`.
//!
//! This is all of it, and the smallness is the point. A Zed extension
//! cannot answer a completion request itself -- `language_server_command`
//! returns an argv and everything after that is LSP -- so the work lives in
//! `scm-lsp` in the scm repository, where the modeller's editor pane and
//! any other editor can have it too.
//!
//! The server is not downloaded. Every other language extension fetches a
//! release binary, but `scm-lsp` is built from the scm repository beside
//! the `scm` it talks to, and a downloaded one could answer with a
//! different language's globals than the one the user is running.

use zed_extension_api::{self as zed, LanguageServerId, Result};

struct ScmExtension;

impl zed::Extension for ScmExtension {
    fn new() -> Self {
        ScmExtension
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let command = worktree.which("scm-lsp").ok_or_else(|| {
            // A missing binary is the one failure a user will actually hit,
            // so the message says what to run rather than what went wrong.
            concat!(
                "scm-lsp is not on PATH. Build it from the scm repository:\n",
                "    cargo install --path scm-lsp\n",
                "or point Zed at it in settings.json:\n",
                r#"    "lsp": { "scm-lsp": { "binary": { "path": "/path/to/scm-lsp" } } }"#,
            )
            .to_string()
        })?;
        Ok(zed::Command {
            command,
            // The address is left to `initialization_options`, which Zed
            // forwards from settings.json, so a project on another port
            // needs no change here. The default matches `scm-eval`'s, so
            // one `scm --serve` serves the editor, the prompt and this.
            args: Vec::new(),
            env: Default::default(),
        })
    }
}

zed::register_extension!(ScmExtension);
