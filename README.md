# Neovim for Rust, C, C++, Lua and assembly

The leader key is Space. The Catppuccin Mocha theme matches Kitty. Type `jk` to
leave insert mode. On returning to normal mode, Neovim formats the current file
and saves modified named buffers. Unnamed drafts stay unsaved, and snippet
selection does not trigger formatting.

## Shortcuts

| Key | Action |
| --- | --- |
| Space Space | Oil file browser with file-type and named-folder icons (`-` goes to parent inside Oil) |
| Space ff | Find files by name |
| Space fg / fb | Search project / switch buffers |
| Space w | Save all modified named buffers |
| Ctrl+S | Format current file, then save modified named buffers (normal, insert or visual mode) |
| gd / grr / K | Definition / references / documentation |
| gri / grt | Implementation / type definition |
| Space fs / fS | Document / workspace symbols |
| Space rn / ca | Rename symbol / code action |
| Space rr / rt | Rust run targets / tests |
| Space rm / re | Expand Rust macro / explain Rust error |
| Space ch (C/C++) | Switch between source and header with clangd |
| Space lc (LLVM IR) | Validate current buffer with `llvm-as` |
| Space ih | Toggle inferred type and parameter hints (enabled by default) |
| Space f | Format current file using its language server |
| Space d / q | Diagnostic popup / diagnostic list |
| Space u d | Toggle all diagnostics, including inline messages, signs, underlines, and status bar counts |
| ]d / [d | Next / previous diagnostic |
| Ctrl+Space | Open completion |
| Ctrl+N / Ctrl+P / Ctrl+Y | Next / previous / accept completion |
| Enter | Accept a selected suggestion; otherwise insert a newline |
| Ctrl+h/j/k/l | Move between editor splits |
| Esc (terminal) | Enter terminal Normal mode (press v to select output) |
| Ctrl+N (normal/visual) | Select word / add next occurrence for multicursor editing |
| Ctrl+Up / Ctrl+Down | Add cursor above / below |
| Space gg / gb / gl / gc | Git status / branches / commit log / commit |
| Space gB | Full-file Git blame view (close with `q`) |
| Space ug | Toggle Gitsigns |
| ]h / [h | Next / previous Git hunk |
| Space hs / hp / hb | Stage hunk / preview hunk / blame current line |
| Space bb / bc / bs | Build or repeat / set build command / stop build |
| Space tt / tr | Run current LLVM lit test / repeat last lit test; in Rust files, Space tt opens testables |
| Space bo, ]q / [q | Open quickfix, next / previous build error |
| gd in quickfix or terminal Normal mode | Open the source line from compiler output |
| F10, F11, F12 | Debug step over, step into, step out |
| Space db / dc / dt | Breakpoint / debug continue / terminate |
| Space dr / dv / dh | Debug console / variables / value under cursor |

## Build and test

Builds save modified named files, run asynchronously from the build root, and fill
quickfix with compiler output. Defaults are `cargo build --message-format=short`,
`cmake --build build` (when configured), or `make`. Use `:Build your command` or
Space bc to override. Space bb repeats that build root's last command for this session.
The Git root is used as the project root. A build file or configured `build/` at
that root takes precedence over nested build files. LLVM's `llvm/CMakeLists.txt`
also selects the repository root. Otherwise, the nearest build file sets the build root.

`:Test path/to/test.ll` runs a specific LLVM lit test. `:TestRepeat` repeats the
last lit command for the project. Space tt tests the current file; Space tr repeats
the last lit test. Lit runs from the Git root using `build/bin/llvm-lit` or
`llvm-lit` on PATH. Build and test commands share quickfix and `:BuildStop`.

Successful builds clear old errors. Custom commands must emit compiler-style
`file:line:column: message` output or another format supported by `errorformat`.
In quickfix, press `gd` on an error or warning to open its source line. In a
terminal running Cargo, press `Esc`, move to a `-->` or `:::` location (or nearby
diagnostic text), then press `gd`. Relative terminal paths use the shell's current
directory, including after `cd`. In source files, `gd` goes to definition.

## Editing and completion

Persistent undo is stored in Neovim's state directory across restarts. Unmodified
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
The global status bar shows a short mode, filename, diagnostic counts and cursor
position; Git branch and file type only appear at terminal widths of 90 or more.
`Ctrl+S` formats the current file through the attached language server, then saves
modified named buffers. It still saves named buffers when no formatter is attached.
Leaving insert mode for normal mode runs the same action; entering snippet selection
does not. `:w` saves the current buffer; Space w saves modified named buffers without
formatting. Visual Multi uses its default backslash leader; `Esc` exits multicursor mode.
Inline diagnostics stay visible and refresh while you edit; `cargo check` diagnostics
refresh after the save completes.

## Language support

Rust Analyzer is selected by rustup from each Rust file's project toolchain,
even when Neovim was started outside the project. rustfmt and Clippy also use rustup.
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

Run `:Lazy install` once to download declared plugins. Missing plugins are not
downloaded automatically at startup, so offline launches work. `lazy-lock.json`
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
