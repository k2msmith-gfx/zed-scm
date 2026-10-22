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

use zed_extension_api::{
    self as zed, DebugAdapterBinary, DebugConfig, DebugRequest, DebugScenario,
    DebugTaskDefinition, LanguageServerId, Result, StartDebuggingRequestArguments,
    StartDebuggingRequestArgumentsRequest, Worktree, serde_json,
};

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

    // --- the debugger (Z5) ------------------------------------------------
    //
    // `scm-dap` is the break REPL with a UI: it runs the program itself and
    // stops at an uncaught error with the frames live. It cannot attach,
    // because a break handler has to be inside the process that owns the
    // VM, and it has no breakpoints, because the VM has no hook for them.

    fn get_dap_binary(
        &mut self,
        _adapter_name: String,
        config: DebugTaskDefinition,
        user_provided_path: Option<String>,
        worktree: &Worktree,
    ) -> Result<DebugAdapterBinary> {
        let command = user_provided_path
            .or_else(|| worktree.which("scm-dap"))
            .ok_or_else(|| {
                concat!(
                    "scm-dap is not on PATH. Build it from the scm repository:\n",
                    "    cargo install --path scm-dap",
                )
                .to_string()
            })?;
        Ok(DebugAdapterBinary {
            command: Some(command),
            arguments: Vec::new(),
            envs: Vec::new(),
            cwd: Some(worktree.root_path()),
            // stdio, not a port: the adapter owns the program it runs, so
            // there is nothing for Zed to connect to.
            connection: None,
            request_args: StartDebuggingRequestArguments {
                configuration: config.config,
                request: StartDebuggingRequestArgumentsRequest::Launch,
            },
        })
    }

    fn dap_request_kind(
        &mut self,
        _adapter_name: String,
        _config: serde_json::Value,
    ) -> Result<StartDebuggingRequestArgumentsRequest> {
        // Always launch. Attaching would need the break handler to live in
        // someone else's process.
        Ok(StartDebuggingRequestArgumentsRequest::Launch)
    }

    fn dap_config_to_scenario(&mut self, config: DebugConfig) -> Result<DebugScenario> {
        let DebugRequest::Launch(launch) = config.request else {
            return Err("scm can only launch a program, not attach to one".into());
        };
        let configuration = serde_json::json!({
            "program": launch.program,
            "cwd": launch.cwd,
        })
        .to_string();
        Ok(DebugScenario {
            adapter: config.adapter,
            label: format!("scm {}", launch.program),
            config: configuration,
            // Nothing to build first: a Scheme file runs as it is.
            build: None,
            tcp_connection: None,
        })
    }
}

zed::register_extension!(ScmExtension);
