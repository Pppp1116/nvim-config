# Neovim for Rust, C, C++ and assembly

The leader key is Space. The Mocha theme matches Kitty.
Type jk quickly to leave insert mode. Leaving insert mode for normal mode formats the current file and saves
modified named buffers. Unnamed drafts stay unsaved. Snippet selection does not trigger formatting.

| Key | Action |
| --- | --- |
| Space Space | Oil file browser with file-type and named-folder icons (`-` goes to parent inside Oil) |
| Space ff | Find files by name |
| Space fg / fb | Search project / switch buffers |
| Space w | Save all modified named buffers |
| Ctrl+S | Format current file, then save modified named buffers (normal, insert or visual mode) |
| gd / grr / K | Definition / references / documentation |
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
| Space bo, ]q / [q | Open quickfix, next / previous build error |
| gd in quickfix or terminal Normal mode | Open the source line from compiler output |
| F10, F11, F12 | Debug step over, step into, step out |
| Space db / dc / dt | Breakpoint / debug continue / terminate |
| Space dr / dv / dh | Debug console / variables / value under cursor |

Persistent undo is stored in Neovim's state directory across restarts. Unmodified
file buffers reload after external changes, including branch switches. Checks run
on focus and terminal exit; unsaved edits are preserved.
`:term` opens ready for typing in terminal mode. Press Esc to inspect terminal
output in Normal mode.

Builds save modified named files, run asynchronously from the project root, and fill
quickfix with compiler output. Defaults are `cargo build --message-format=short`,
`cmake --build build` (when configured), or `make`. Use `:Build your command` or
Space bc to override; Space bb repeats that project's last command for this session.
Successful builds clear old errors. Custom commands must emit compiler-style
`file:line:column: message` output or another format supported by `errorformat`.
In the build quickfix window, press `gd` on an error or warning to open its
source line. In a Neovim terminal running Cargo, press `Esc` to enter terminal Normal mode. Move to a `-->` or `:::` location (or nearby
diagnostic text), and press `gd`. In source files, `gd` still goes to definition.
Relative terminal paths use the shell's current directory, including after `cd`.

New plugins are declared but require downloading: run `:Lazy install` once.
Automatic missing-plugin downloads at startup are disabled so offline launches work.
Debugging uses nvim-dap with the system `lldb-dap` for Rust/C/C++/assembly. Install the
`lldb` package on Fedora and keep `lldb-dap` on PATH. Loading the debugger does
not trigger downloads.
Build first with debug symbols (Cargo's default debug build, or CMake Debug),
set a breakpoint with Space db, then Space dc and select the executable path.
VM uses its default backslash leader; Esc exits multicursor mode.

Start Neovim in your project directory. Blink completion appears as you type,
with LSP, path, snippet and buffer sources. Rust prioritizes LSP and path results,
then falls back to words from the current buffer when they have no results.
The source column distinguishes LSP suggestions from paths or buffer words.
Ctrl+Space opens completion manually.
Exact matches rank first. Rust preserves the analyzer's semantic ordering before
fuzzy/history scores. Deprecated Rust suggestions are hidden and completion docs show
full function signatures. Type-directed term search is disabled because the installed
rust-analyzer panics while handling completion requests in this project.
Rust auto-imports are enabled: select an LSP suggestion and accept it with Enter
or Ctrl+Y to insert the symbol and its use statement. For an already typed
unresolved name, Space ca can offer an import fix.
The menu has at most 8 rows. Labels are capped at 36 columns, documentation at
60 columns by 12 rows. Signature help appears while entering function arguments.
The global status bar shows a short mode, filename, diagnostic counts and cursor
position; Git branch and file type only appear at terminal widths of 90 or more.
Ctrl+S formats the current file through the attached language server, then saves
modified named buffers. It still saves named buffers when no formatter is attached.
Leaving insert mode for normal mode runs the same format-and-save action; entering a snippet selection does not.
:w saves the current buffer; Space w saves modified named buffers without formatting.
Inline diagnostics stay visible and refresh while you edit; `cargo check` diagnostics
refresh after the save completes.

Rust Analyzer is selected by rustup from each Rust file's project toolchain,
even when Neovim was started outside the project. rustfmt and Clippy also use rustup.
Rustaceanvim manages the single Rust language server, with `cargo check` on save,
build scripts, procedural macros, auto-import/snippet completion, run/test targets,
macro expansion and error explanations. Rust-src is installed for standard-library
navigation. Cargo uses normal default features rather than forcing all features.
Per-project rust-analyzer.json settings can override the defaults. For example:
`{"rust-analyzer":{"cargo":{"features":["your-feature"]}}}`.
Use :RustAnalyzer restart after changing toolchains, and :RustLsp for Rust tools.
Rustaceanvim is pinned to version 8 for this Neovim setup.
C and C++ use `clangd` from PATH. External tools are managed outside Neovim.
clangd uses background indexing, clang-tidy diagnostics and detailed completions.
Accepting a C/C++ completion can add the header clangd identifies for that symbol.
Rust, C and C++ use locally installed Tree-sitter parsers. LLVM IR (`.ll`) is
detected as `llvm`; run `:TSInstall llvm` once for highlighting. `llvm-as` checks
the current buffer after each save and reports errors as inline diagnostics.
Use `:LLVMCheck` or Space lc to check edits before saving. It reads the buffer
through standard input and creates no bitcode file. Install `llvm-as` for these checks.
Assembly files (`.s`,
`.S`, `.asm`) and NASM files (`.nasm`) use Tree-sitter after `:TSInstall asm nasm`;
until then, Neovim's built-in syntax highlighting applies. Install `asm-lsp`
with `cargo install asm-lsp` for assembly completion and navigation. Run
`:TSUpdate` to refresh installed parsers after a plugin update.
Use :checkhealth vim.lsp to troubleshoot, :Lazy to manage plugins.
The lazy-lock.json file records installed plugin revisions.

For CMake projects, configure with `cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`.
clangd recognizes a compile_commands.json in build/; for other build directories,
link compile_commands.json into the project root. This gives it the actual
compiler flags and include paths. Check that this file is populated; an empty
`[]` database leaves clangd without the project's compile commands. Existing
project formatting settings apply.
For a simple project without CMake, put one compiler flag per line in
`compile_flags.txt` at the project root. A shared `.h` extension is ambiguous:
Neovim opens it as C++ by default; use `:setfiletype c` for a C header when needed.

Rust toolchain binaries are added to Neovim's PATH. In a shell, use
`source ~/.cargo/env` if Cargo is not on your PATH yet.
