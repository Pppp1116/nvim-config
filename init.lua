-- Space is the leader key. See README.md for the everyday shortcuts.
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = 'yes'
vim.opt.cursorline = true
vim.opt.mouse = 'a'
vim.opt.clipboard = 'unnamedplus'
vim.opt.swapfile = false
vim.opt.undofile = true
local undo_dir = vim.fn.stdpath('state') .. '/undo'
vim.fn.mkdir(undo_dir, 'p', 448) -- 0700
vim.opt.undodir = undo_dir .. '//'
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.scrolloff = 6
vim.opt.wrap = false
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.updatetime = 250
vim.opt.timeoutlen = 400
vim.opt.completeopt = { 'menu', 'menuone', 'noselect' }
vim.opt.laststatus = 3
vim.opt.showmode = false
vim.opt.winborder = 'rounded'
vim.opt.pumheight = 8
local fish = vim.fn.exepath('fish')
if fish ~= '' then vim.opt.shell = fish end

-- Use the user's Rust toolchain without changing the login shell.
vim.env.PATH = vim.fn.expand('~/.cargo/bin') .. ':' .. vim.fn.expand('~/.local/bin') .. ':' .. vim.env.PATH
local lazy = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazy) then
  local result = vim.fn.system({ 'git', 'clone', '--filter=blob:none', '--branch=stable',
    'https://github.com/folke/lazy.nvim.git', lazy })
  if vim.v.shell_error ~= 0 then error('Could not install lazy.nvim: ' .. result) end
end
vim.opt.rtp:prepend(lazy)

require('lazy').setup({
  { 'catppuccin/nvim', name = 'catppuccin', priority = 1000,
    config = function()
      require('catppuccin').setup({ flavour = 'mocha' })
      vim.cmd.colorscheme('catppuccin')
    end },
  { 'nvim-lualine/lualine.nvim', opts = {
    options = { theme = 'catppuccin-mocha', icons_enabled = false, globalstatus = true,
      component_separators = '', section_separators = '' },
    sections = {
      lualine_a = { { 'mode', fmt = function(s) return s:sub(1, 1) end } },
      lualine_b = { { 'branch', cond = function() return vim.o.columns >= 90 end } },
      lualine_c = { { 'filename', path = 0, shorting_target = function() return math.floor(vim.o.columns * 0.6) end } },
      lualine_x = { { 'diagnostics', cond = function() return vim.diagnostic.is_enabled() end,
        sources = { 'nvim_lsp' }, sections = { 'error', 'warn' },
        symbols = { error = 'E:', warn = 'W:' } } },
      lualine_y = { { 'filetype', cond = function() return vim.o.columns >= 90 end } },
      lualine_z = { 'location' },
    },
    extensions = { 'oil', 'quickfix' },
  } },
  { 'lewis6991/gitsigns.nvim', opts = {} },
  { 'tpope/vim-fugitive', cmd = { 'Git', 'G', 'Gdiffsplit', 'Gvdiffsplit', 'Gread', 'Gwrite' } },
  { 'mg979/vim-visual-multi', branch = 'master',
    keys = { { '<C-n>', mode = { 'n', 'x' } }, { '<C-Down>' }, { '<C-Up>' } },
    init = function() vim.g.VM_leader = '\\' end },
  { 'mfussenegger/nvim-dap', lazy = true,
    config = function() require('workflows').setup_debugger() end },
  { 'folke/which-key.nvim', opts = {} },
  { 'nvim-mini/mini.pairs', version = false, opts = {} },
  { 'nvim-mini/mini.surround', version = false, opts = {} },
  { 'nvim-treesitter/nvim-treesitter', lazy = false, build = ':TSUpdate',
    config = function()
      vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'rust', 'c', 'cpp', 'asm', 'nasm' },
        callback = function(event)
          -- A missing parser leaves the built-in syntax highlighting intact.
          pcall(vim.treesitter.start, event.buf)
        end,
        desc = 'Highlight Rust, C, C++ and assembly with Tree-sitter when installed',
      })
    end },
  { 'nvim-telescope/telescope.nvim', dependencies = { 'nvim-lua/plenary.nvim' }, opts = {} },
  { 'stevearc/oil.nvim',
    dependencies = { { 'nvim-mini/mini.icons', opts = {} } },
    opts = {
    default_file_explorer = true,
    -- File-extension and named-directory icons; Kitty bundles the symbol font.
    columns = { 'icon' },
    view_options = { show_hidden = true },
  } },
  { 'saghen/blink.cmp', version = '1.*', opts = {
    keymap = { preset = 'default', ['<CR>'] = { 'accept', 'fallback' } },
    appearance = { nerd_font_variant = 'mono' },
    fuzzy = {
      implementation = 'prefer_rust',
      sorts = function()
        -- Preserve Rust Analyzer's semantic ranking before fuzzy/history scores.
        if vim.bo.filetype == 'rust' then return { 'exact', 'sort_text', 'score', 'label' } end
        return { 'exact', 'score', 'sort_text', 'label' }
      end,
    },
    sources = {
      default = { 'lsp', 'path', 'snippets', 'buffer' },
      -- Keep LSP suggestions first; fall back to words already in the buffer
      -- when rust-analyzer has no result for an incomplete expression.
      per_filetype = { rust = { 'lsp', 'path', 'buffer' } },
    },
    completion = {
      -- Auto-import edits arrive during completionItem/resolve. Allow busy
      -- workspaces more than Blink's default 100 ms to return those edits.
      accept = { resolve_timeout_ms = 1000 },
      list = { max_items = 80, selection = { preselect = false, auto_insert = false } },
      menu = { min_width = 16, max_height = 8, border = 'rounded',
        draw = { columns = { { 'label' }, { 'kind', gap = 1 }, { 'source_name' } },
          components = { label = { width = { max = 36 } }, kind = { width = { max = 10 } },
            source_name = { width = { max = 7 } } } } },
      documentation = { auto_show = true, auto_show_delay_ms = 300,
        window = { max_width = 60, max_height = 12, border = 'rounded' } },
      ghost_text = { enabled = false },
    },
    signature = { enabled = true, window = { border = 'rounded', max_width = 60, max_height = 8 } },
    cmdline = { enabled = false },
  } },
  { 'mrcjkb/rustaceanvim', version = '8.*', lazy = false, dependencies = { 'saghen/blink.cmp' },
    init = function()
      vim.g.rustaceanvim = {
        tools = { code_actions = { ui_select_fallback = true } },
        server = {
          cmd = function()
            -- Resolve from the Rust file's directory, even if Neovim was opened elsewhere.
            local cwd = vim.fn.expand('%:p:h')
            if cwd == '' then cwd = vim.fn.getcwd() end
            local result = vim.system({ 'rustup', 'which', 'rust-analyzer' },
              { cwd = cwd, text = true }):wait()
            local rust_analyzer = result.stdout and vim.trim(result.stdout) or ''
            if result.code ~= 0 or vim.fn.executable(rust_analyzer) ~= 1 then
              vim.notify('Install rust-analyzer for the project toolchain with rustup component add rust-analyzer',
                vim.log.levels.ERROR)
              return { 'rust-analyzer' }
            end
            return { rust_analyzer }
          end,
          capabilities = require('blink.cmp').get_lsp_capabilities(),
          default_settings = { ['rust-analyzer'] = {
            cargo = { buildScripts = { enable = true } },
            procMacro = { enable = true },
            diagnostics = { enable = true, experimental = { enable = false } },
            completion = {
              autoimport = { enable = true },
              hideDeprecated = true,
              fullFunctionSignatures = { enable = true },
              -- This rust-analyzer build panics in term search on completion.
              termSearch = { enable = false },
            },
            checkOnSave = true,
            check = { command = 'check' },
          } },
          settings = function(root, defaults)
            local path = root and (root .. '/rust-analyzer.json')
            if not path or vim.fn.filereadable(path) == 0 then return defaults end
            local ok, overrides = pcall(function()
              return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
            end)
            if not ok or type(overrides) ~= 'table' or type(overrides['rust-analyzer']) ~= 'table' then
              vim.notify('Invalid rust-analyzer.json: expected a rust-analyzer settings object', vim.log.levels.WARN)
              return defaults
            end
            return vim.tbl_deep_extend('force', {}, defaults, overrides)
          end,
        },
        dap = { autoload_configurations = false },
      }
    end,
  },
  { 'neovim/nvim-lspconfig', dependencies = { 'saghen/blink.cmp' },
    config = function()
      vim.lsp.config('clangd', {
        cmd = { 'clangd', '--background-index', '--clang-tidy', '--completion-style=detailed' },
        capabilities = require('blink.cmp').get_lsp_capabilities(),
      })
      vim.lsp.enable('clangd')
      vim.lsp.config('basedpyright', {
        capabilities = require('blink.cmp').get_lsp_capabilities(),
        settings = {
          basedpyright = { analysis = { typeCheckingMode = 'standard' } },
        },
      })
      vim.lsp.enable('basedpyright')
      vim.lsp.config('asm_lsp', {
        filetypes = { 'asm', 'nasm', 'vmasm' },
        capabilities = require('blink.cmp').get_lsp_capabilities(),
      })
      vim.lsp.enable('asm_lsp')
    end },
}, { install = { missing = false }, checker = { enabled = false }, change_detection = { notify = false } })

local map = vim.keymap.set
map('i', 'jk', '<Esc>', { desc = 'Leave insert mode' })
map('t', '<Esc>', '<C-\\><C-n>', { desc = 'Enter terminal normal mode' })
local function format_and_save_all(bufnr)
  bufnr = type(bufnr) == 'number' and bufnr or vim.api.nvim_get_current_buf()
  if #vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/formatting' }) > 0 then
    -- Finish formatting before writing so the formatted text reaches disk.
    local ok, err = pcall(vim.lsp.buf.format, { bufnr = bufnr, async = false, timeout_ms = 2000 })
    if not ok then
      vim.notify('Formatting failed; saving current text: ' .. tostring(err), vim.log.levels.WARN)
    end
  end
  require('workflows').save_all()
end
map({ 'n', 'i' }, '<C-s>', format_and_save_all, { desc = 'Format current file and save all buffers' })
map('x', '<C-s>', function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  format_and_save_all()
end, { desc = 'Format current file and save all buffers' })
vim.api.nvim_create_autocmd('InsertLeave', {
  group = vim.api.nvim_create_augroup('UserFormatAndSaveOnInsertLeave', { clear = true }),
  callback = function(event)
    local buf = event.buf
    -- Snippet placeholders can enter Select mode and trigger InsertLeave.
    -- Wait for the mode transition before deciding whether to format.
    vim.schedule(function()
      if not vim.api.nvim_buf_is_loaded(buf) then return end
      local mode = vim.api.nvim_get_mode().mode
      if mode:match('^[sS]') or mode == '\19' then return end
      if mode:match('^n') then format_and_save_all(buf) end
    end)
  end,
  desc = 'Format and save after leaving insert mode for normal mode',
})
map('n', '<leader>w', function() require('workflows').save_all() end, { desc = 'Save all named modified buffers' })
map('n', '<leader><space>', '<cmd>Oil<cr>', { desc = 'Browse files' })
map('n', '<leader>ff', '<cmd>Telescope find_files<cr>', { desc = 'Find files' })
map('n', '<leader>fg', '<cmd>Telescope live_grep<cr>', { desc = 'Search project text' })
map('n', '<leader>fb', '<cmd>Telescope buffers<cr>', { desc = 'Find open buffers' })
map('n', '<leader>fh', '<cmd>Telescope help_tags<cr>', { desc = 'Search help' })
map('n', '<Esc>', '<cmd>nohlsearch<cr>')
map('n', '<C-h>', '<C-w>h', { desc = 'Focus left split' })
map('n', '<C-j>', '<C-w>j', { desc = 'Focus lower split' })
map('n', '<C-k>', '<C-w>k', { desc = 'Focus upper split' })
map('n', '<C-l>', '<C-w>l', { desc = 'Focus right split' })
map('n', '<leader>d', vim.diagnostic.open_float, { desc = 'Show diagnostic' })
local inline_diagnostic_options = { spacing = 2 }
map('n', '<leader>ud', function()
  vim.diagnostic.enable(not vim.diagnostic.is_enabled())
end, { desc = 'Toggle all diagnostics' })
map('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'List diagnostics' })
map('n', '<leader>f', function() vim.lsp.buf.format({ async = true }) end, { desc = 'Format file' })

vim.diagnostic.config({ severity_sort = true, underline = true, update_in_insert = true,
  virtual_text = inline_diagnostic_options, float = { border = 'rounded' } })
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLsp', { clear = true }),
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if client and client:supports_method('textDocument/inlayHint', event.buf) then
      vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
    end
    local function bind(key, action, desc)
      map('n', key, action, { buffer = event.buf, desc = desc })
    end
    bind('gd', vim.lsp.buf.definition, 'Go to definition')
    bind('grr', vim.lsp.buf.references, 'Find references')
    bind('K', vim.lsp.buf.hover, 'Documentation')
    bind('<leader>rn', vim.lsp.buf.rename, 'Rename symbol')
    bind('<leader>ca', vim.lsp.buf.code_action, 'Code action')
    bind('<leader>ih', function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }), { bufnr = event.buf })
    end, 'Toggle type hints')
    if client and client.name == 'rust-analyzer' then
      bind('<leader>rr', '<cmd>RustLsp runnables<cr>', 'Rust run targets')
      bind('<leader>rt', '<cmd>RustLsp testables<cr>', 'Rust tests')
      bind('<leader>rm', '<cmd>RustLsp expandMacro<cr>', 'Expand Rust macro')
      bind('<leader>re', '<cmd>RustLsp explainError current<cr>', 'Explain Rust error')
      bind('<leader>ca', '<cmd>RustLsp codeAction<cr>', 'Rust code actions')
    elseif client and client.name == 'clangd' then
      bind('<leader>ch', '<cmd>LspClangdSwitchSourceHeader<cr>', 'Switch C/C++ source and header')
    end
  end,
})
-- Blink handles automatic completion, signatures, snippets and popup sizing.
require('workflows').setup()
