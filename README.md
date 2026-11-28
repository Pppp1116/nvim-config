# Neovim for Rust, C, C++, Lua and assembly

The leader key is Space. The Catppuccin Mocha theme matches Kitty. Type `jk` to
leave insert mode. Automatic formatting and saving are disabled by default; Space uf
toggles them for the current session.

## Shortcuts

Which-key shows the groups after Space: Find (`f`), Code (`c`), Diagnostics
(`x`), Git (`g`), Build (`b`), Tests (`t`), Debugger (`d`), Rust (`r`), Editor
UI (`u`) and LLVM (`l`). Rust, C/C++ and LLVM commands appear in their filetypes.

| Key | Action |
| --- | --- |
| Space Space / `-` | Oil explorer / current directory |
| Space w | Save all modified named ordinary buffers, without formatting |
| Ctrl+S | Format current file, then save all modified named ordinary buffers |
| Space ff / fg / fb / fh | Files / project text / buffers / help |
| Space fs / fS | Document / workspace symbols |
| Space ca / cr / cf | Code action / rename / format current file |
| Space ch (C/C++) | Switch source and header |
| Space xd / xq / xt / xa | Diagnostic popup / location list / toggle all diagnostics / toggle full Rust presentation |
| Space xe / xr / xR / xl (Rust) | Explain error / render current or next diagnostic / related locations |
| Space gg / gb / gl / gc / gB | Git status / branches / log / commit / file blame |
| Space gs / gp / gh / gd | Stage hunk / preview hunk / line blame / diff against index |
| Space gu / gi | Toggle Git signs / inline blame |
| Space bb / bc / bs / bo | Build or repeat / set build command / stop / quickfix |
| Space tt / tr | Select or run tests / repeat previous test for current language |
| Space db / dc / dt / dr / dv / dh | Breakpoint / continue / terminate / console / scopes / hover |
| Space rr / rm (Rust) | Run targets / expand macro |
| Space uh / uf | Toggle inlay hints / automatic format and save |
| Space lc (LLVM) | Validate LLVM IR with `llvm-as` |
| gd / grr / gri / grt / K | Definition / references / implementation / type definition / hover |
| ]b / [b, ]h / [h, ]q / [q | Buffer / Git hunk / quickfix navigation |
| F10 / F11 / F12 | Debug step over / into / out |
| Esc (terminal) | Terminal Normal mode; `gd` opens a compiler or Rust backtrace location |
| Ctrl+N, Ctrl+Up / Ctrl+Down | Multicursor selection and additional cursors |
| Ctrl+Space, Ctrl+N / Ctrl+P / Ctrl+Y | Completion menu / next / previous / accept |
| Enter | Accept selected completion or insert newline |
| Ctrl+h/j/k/l | Focus adjacent splits |

Old mappings Space f, d, q, rn, rt, re, rd, rD, rl, ih, ud, ua, ug, ub,
hs, hp, hb and hd were removed or moved into these groups. Non-leader `gd`
still means definition in source and source navigation in terminal/quickfix.

## Build and test

Builds save modified named files, run as Overseer tasks from the build root, and fill
quickfix with compiler output. A failed save prevents the task from starting. Space bs
sends SIGTERM to the verified build process group and SIGKILL after one second if
original group members remain; the same cleanup runs on Neovim exit. `:OverseerToggle` shows the task list and output.
Defaults are `cargo build --message-format=short`,
`cmake --build build` (when configured), or `make`. Use `:Build your command` or
Space bc to override. Space bb repeats that build root's last command for this session.
The Git root is used as the project root. A build file or configured `build/` at
that root takes precedence over nested build files. LLVM's `llvm/CMakeLists.txt`
also selects the repository root. Otherwise, the nearest build file sets the build root.

`:Test path/to/test.ll` runs a specific LLVM lit test. `:TestRepeat` repeats the
last lit command for the project. Space tt opens Rustaceanvim test selection in Rust buffers or runs the current LLVM lit file. Space tr repeats the last selected Rust test with `:RustLsp! testables` or the last LLVM lit test for that project. Before any Rust test is selected, Rustaceanvim opens test selection instead. Other filetypes receive a notification. Lit runs from the Git root using `build/bin/llvm-lit` or
`llvm-lit` on PATH. Build and test commands share quickfix and `:BuildStop`.

Successful builds clear old errors. Custom commands must emit compiler-style
`file:line:column: message` output or another format supported by `errorformat`.
In quickfix, press `gd` on an error or warning to open its source line. In a
terminal running Cargo, press `Esc`, move to an `at`, `-->` or `:::` location (or a
nearby backtrace frame heading), then press `gd`. Navigation opens source in an
ordinary editor window and preserves terminal and modified output buffers. Relative terminal paths use the shell's current
directory, including after `cd`. In source files, `gd` goes to definition.
Rust compiler locations use character columns; Rust `at` backtrace frames use
byte columns. C/C++ navigation chooses the column that starts a token when
GCC's character count and Clang's byte count differ. Neovim diagnostic location
lists already use byte columns and are opened without another conversion.

## Editing and completion

Swap files for recovery of unsaved changes and persistent undo are stored in separate Neovim state directories across restarts. If a state directory cannot be created or written, Neovim reports the problem and disables that recovery feature for the session. Unmodified
buffers reload after external changes, including branch switches. Checks run on
focus and terminal exit; unsaved edits are preserved. `:term` opens ready for
typing. Press `Esc` to inspect terminal output in normal mode.

Start Neovim in your project directory. Blink completion appears as you type,
with LSP, path, snippet and buffer sources. Rust prioritizes LSP and path results,
then falls back to words from the current buffer when they have no results.
The source column distinguishes LSP suggestions from paths or buffer words.
`Ctrl+Space` opens completion manually.
Exact matches rank first. Rust preserves the analyzer's semantic ordering before
fuzzy/history scores. Deprecated Rust suggestions are hidden and completion docs show
full function signatures. Type-directed term search is disabled because the installed
rust-analyzer panics while handling completion requests in this project.
Rust auto-imports are enabled: select an LSP suggestion and accept it with `Enter`
or `Ctrl+Y` to insert the symbol and its use statement. For an already typed
unresolved name, Space ca can offer an import fix.
The menu has at most 8 rows. Labels are capped at 36 columns, documentation at
60 columns by 12 rows. Signature help appears while entering function arguments.
Each source window has a top bar with its path relative to the Git root and, when
the language server supplies document symbols, its namespace, type and current
function. Without Git, the path is relative to the working directory when possible.
Long paths and symbol chains shorten to keep the filename and nearest function
visible. Terminals, Oil, quickfix and other special windows have no top bar.
Lualine draws the top bar using Navic's public symbol data. A guarded Navic
internal call refreshes context for each window's cursor because the public
API only caches one context per buffer. Symbol context is cached per window until
its cursor or Navic symbol tree changes. The global status
bar shows the short mode, Git branch, filename with modified or readonly marker,
Git added/changed/deleted counts, diagnostic errors and warnings,
file type, line and column, and file percentage. Git counts appear at widths of at
least 100 columns; branch and file type appear at 80 columns. Diagnostic counts
include language server diagnostics and LLVM IR checks from `llvm-as`.
Inline blame, when toggled on, appears after a short pause as author, relative
date and commit summary at the end of the current line.
`Ctrl+S` formats the current file with one deterministic language server, then saves
modified named buffers. It still saves named buffers when no formatter is attached.
Space cf requests formatting asynchronously; its result is ignored if the buffer
changes before the reply. A formatting timeout or error is reported. Ctrl+S still
saves the current text after a formatting error; automatic format/save stops without
writing when formatting fails.
Automatic formatting and saving are off by default. Space uf enables it for the session: leaving Insert mode for Normal mode formats and saves only the modified current named ordinary buffer. Snippet selection does not trigger it. Formatting errors leave edits in the buffer and show a warning. `:w` saves the current buffer; Space w saves modified named buffers without
formatting. Visual Multi uses its default backslash leader; `Esc` exits multicursor mode.
Inline diagnostics refresh after leaving insert mode; `cargo check` diagnostics
refresh after the save completes. Rust inline messages omit known low-priority
lint codes (`unused_imports`, `unused_variables`, `unused_mut`,
`unused_assignments`, `dead_code`, `non_snake_case`,
`non_camel_case_types`, `non_upper_case_globals`,
`clippy::unnecessary_cast`, `clippy::needless_return` and
`clippy::redundant_clone`), while
errors, including warnings promoted to errors, safety warnings and unknown codes stay visible. Rust underlines apply
only to visible errors and warnings. Redundant rust-analyzer/rustc diagnostics
appear once inline only when code, severity, message and location agree; distinct
errors remain visible. Secondary compiler spans are shown once. The original diagnostics remain in Space xd, Space xq and diagnostic
navigation; code actions remain available with Space ca. Space xr displays the
compiler's colored diagnostic with notes, help and source context when
rust-analyzer supplies it; press Enter in its popup to open a split. Space xe
opens the longer `rustc --explain` text for an error code. Rust inlay hints can
be turned off when needed with Space uh.

## Language support

Rust Analyzer is selected by rustup from each Rust file's project toolchain,
even when Neovim was started outside the project. Resolution has a two-second
timeout and a short cache. Missing Rustup, toolchains and components produce one
useful notification per project instead of launching an invalid command. New Rust
files attach after their first save, once the file exists.
Rustaceanvim 8 shares an active analyzer across workspaces before evaluating the
next project's command; when two projects need different analyzer binaries, the
second automatic attachment is skipped with a notification. Open those projects
in separate Neovim instances. rustfmt and Clippy also use rustup.
Rustaceanvim manages the single Rust language server, with `cargo check` on save,
build scripts, procedural macros, auto-import/snippet completion, run/test targets,
macro expansion and error explanations. Rust-src is installed for standard-library
navigation. Cargo uses normal default features rather than forcing all features.
Per-project `rust-analyzer.json` settings can override the defaults. For example:
`{"rust-analyzer":{"cargo":{"features":["your-feature"]}}}`.
Use `:RustAnalyzer restart` after changing toolchains and `:RustLsp` for Rust tools.
Rustaceanvim is pinned to version 8 for this Neovim setup.

C and C++ use `clangd` from PATH. External tools are managed outside Neovim.
clangd uses background indexing, clang-tidy diagnostics and detailed completions.
Accepting a C/C++ completion can add the header clangd identifies for that symbol.
Lua files use `lua-language-server` (`lua_ls`) from PATH for completion, diagnostics,
and navigation of Neovim APIs.

Rust, C and C++ use locally installed Tree-sitter parsers. LLVM IR (`.ll`) is
detected as `llvm`; run `:TSInstall llvm` once for highlighting. `llvm-as` checks
the current buffer after each save and reports errors as inline diagnostics.
Use `:LLVMCheck` or Space lc to check edits before saving. It reads the buffer
through standard input and creates no bitcode file. Install `llvm-as` for these checks.

Assembly files (`.s`, `.S`, `.asm`) and NASM files (`.nasm`) use Tree-sitter
after `:TSInstall asm nasm`; until then, Neovim's built-in syntax highlighting
applies. Install `asm-lsp`
with `cargo install asm-lsp` for assembly completion and navigation. Run
`:TSUpdate` to refresh installed parsers after a plugin update.

## Setup and debugging

Install `lazy.nvim` first, then run `:Lazy install` once to download declared
plugins, including Overseer. Missing plugins are not downloaded automatically at
startup. If `lazy.nvim` itself is missing, Neovim opens with its built-in editing
features and reports that plugins need installation. `lazy-lock.json`
records installed plugin revisions. Use `:Lazy` to manage plugins and
`:checkhealth vim.lsp` to troubleshoot language servers.

Debugging uses nvim-dap with the system `lldb-dap` for Rust, C, C++, and assembly.
Install the `lldb` package on Fedora and keep `lldb-dap` on PATH. Loading the
debugger does not trigger downloads. Build with debug symbols (Cargo's default
debug build or CMake Debug), set a breakpoint with Space db, then press Space dc
and select the executable path.

For CMake projects, configure with `cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`.
clangd recognizes `compile_commands.json` in `build/`; for other build directories,
link it into the project root. This gives clangd the actual compiler flags and
include paths. Check that the file is populated; an empty
`[]` database leaves clangd without the project's compile commands. Existing
project formatting settings apply.
For a simple project without CMake, put one compiler flag per line in
`compile_flags.txt` at the project root. A shared `.h` extension is ambiguous:
Neovim opens it as C++ by default; use `:setfiletype c` for a C header when needed.

Rust toolchain binaries are added to Neovim's PATH. In a shell, use
`source ~/.cargo/env` if Cargo is not on your PATH yet.

## Configuration tests

Run `python3 tests/run.py` from this repository. The runner gives Neovim
disposable state and cache directories, exits nonzero on failure, and checks
startup without plugins. Tests cover mappings, invalid contexts, diagnostics,
Rust Analyzer resolution, formatting races, Unicode locations, independent
saves, plugin-buffer contexts, real build process cancellation and Rustaceanvim's
repeat command. The full suite requires the installed
plugins, Python 3, Linux `/proc`, and Neovim 0.12. Restart Neovim after changing
this configuration; sourcing `init.lua` inside a running editor is not a supported
reload path.
