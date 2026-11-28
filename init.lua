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
local function recovery_directory(name)
  local path = vim.fn.stdpath('state') .. '/' .. name
  local ok, err = pcall(vim.fn.mkdir, path, 'p', 448) -- 0700
  if ok and vim.fn.isdirectory(path) == 1 and vim.fn.filewritable(path) == 2 then
    return path .. '//'
  end
  vim.notify('Cannot create writable Neovim ' .. name .. ' directory: ' .. path ..
    (ok and '' or ' (' .. tostring(err) .. ')'), vim.log.levels.ERROR)
end
local swap_dir = recovery_directory('swap')
vim.opt.swapfile = swap_dir ~= nil
if swap_dir then vim.opt.directory = swap_dir end
local undo_dir = recovery_directory('undo')
vim.opt.undofile = undo_dir ~= nil
if undo_dir then vim.opt.undodir = undo_dir end
if not swap_dir or not undo_dir then vim.opt.shadafile = 'NONE' end
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
-- Neovim's built-in detection currently assigns .ll to Lifelines.
vim.filetype.add({ extension = { ll = 'llvm' } })
local fish = vim.fn.exepath('fish')
if fish ~= '' then vim.opt.shell = fish end
vim.g.auto_format_save = false

-- Use the user's Rust toolchain without changing the login shell.
vim.env.PATH = vim.fn.expand('~/.cargo/bin') .. ':' .. vim.fn.expand('~/.local/bin') .. ':' .. vim.env.PATH
local lazy = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazy) then
  vim.notify('lazy.nvim is unavailable. Editing still works; install plugins when online.',
    vim.log.levels.WARN)
  return
end
vim.opt.rtp:prepend(lazy)
local lazy_ok, lazy_loader = pcall(require, 'lazy')
if not lazy_ok then
  vim.notify('lazy.nvim is incomplete; reinstall it before using plugins.', vim.log.levels.WARN)
  return
end

local function lsp_capabilities()
  local ok, blink = pcall(require, 'blink.cmp')
  return ok and blink.get_lsp_capabilities() or vim.lsp.protocol.make_client_capabilities()
end

local winbar = {
  lualine_a = {}, lualine_b = {},
  lualine_c = { { function() return require('ui').path() end,
    color = { fg = '#cdd6f4', gui = 'bold' } } },
  lualine_x = { { function() return require('ui').context() end,
    color = { fg = '#a6adc8' } } },
  lualine_y = {}, lualine_z = {},
}

local plugin_setup_ok, plugin_setup_err = pcall(lazy_loader.setup, {
  { 'catppuccin/nvim', name = 'catppuccin', priority = 1000,
    config = function()
      require('catppuccin').setup({ flavour = 'mocha' })
      vim.cmd.colorscheme('catppuccin')
    end },
  { 'nvim-lualine/lualine.nvim', opts = {
    options = { theme = 'catppuccin-mocha', icons_enabled = false, globalstatus = true,
      component_separators = '', section_separators = '',
      disabled_filetypes = { winbar = { 'oil', 'qf', 'TelescopePrompt', 'OverseerList', 'OverseerOutput' } } },
    sections = {
      lualine_a = { { 'mode', fmt = function(s) return s:sub(1, 1) end } },
      lualine_b = { { 'branch', cond = function() return vim.o.columns >= 80 end } },
      lualine_c = { { 'filename', path = 0 } },
      lualine_x = {
        { 'diff', cond = function() return vim.o.columns >= 100 end,
          symbols = { added = '+', modified = '~', removed = '-' },
          source = function()
            local changes = vim.b.gitsigns_status_dict
            if not changes then return nil end
            return { added = changes.added, modified = changes.changed, removed = changes.removed }
          end },
        { 'diagnostics', cond = function() return vim.diagnostic.is_enabled() end,
          sources = { 'nvim_diagnostic' }, sections = { 'error', 'warn' },
          symbols = { error = 'E:', warn = 'W:' } },
      },
      lualine_y = { { 'filetype', cond = function() return vim.o.columns >= 80 end } },
      lualine_z = { 'location', 'progress' },
    },
    winbar = winbar,
    inactive_winbar = winbar,
    extensions = { 'oil', 'quickfix' },
  } },
  { 'lewis6991/gitsigns.nvim', opts = {
    current_line_blame = false,
    current_line_blame_opts = { delay = 1000, virt_text_pos = 'eol' },
    current_line_blame_formatter = '  <author> · <author_time:%R> · <summary>',
  } },
  { 'SmiteshP/nvim-navic', opts = { icons = { enabled = false } } },
  { 'tpope/vim-fugitive', cmd = { 'Git', 'G', 'Gdiffsplit', 'Gvdiffsplit', 'Gread', 'Gwrite' } },
  { 'mg979/vim-visual-multi', branch = 'master',
    keys = { { '<C-n>', mode = { 'n', 'x' } }, { '<C-Down>' }, { '<C-Up>' } },
    init = function() vim.g.VM_leader = '\\' end },
  { 'mfussenegger/nvim-dap', lazy = true,
    config = function() require('workflows').setup_debugger() end },
  { 'stevearc/overseer.nvim', opts = {}, cmd = { 'OverseerRun', 'OverseerToggle', 'OverseerOpen' } },
  { 'folke/which-key.nvim', opts = {} },
  { 'nvim-mini/mini.pairs', version = false, opts = {} },
  { 'nvim-mini/mini.surround', version = false, opts = {} },
  { 'nvim-treesitter/nvim-treesitter', lazy = false, build = ':TSUpdate',
    config = function()
      vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'rust', 'c', 'cpp', 'asm', 'nasm', 'llvm' },
        callback = function(event)
          -- A missing parser leaves the built-in syntax highlighting intact.
          pcall(vim.treesitter.start, event.buf)
        end,
        desc = 'Highlight Rust, C, C++, assembly and LLVM IR with Tree-sitter when installed',
      })
    end },
  { 'nvim-telescope/telescope.nvim', dependencies = { 'nvim-lua/plenary.nvim' }, opts = {} },
  { 'stevearc/oil.nvim',
    dependencies = { { 'nvim-mini/mini.icons', opts = {} } },
    opts = {
    default_file_explorer = true,
    -- File-extension and named-directory icons; Kitty bundles the symbol font.
    columns = { 'icon' },
    delete_to_trash = true,
    skip_confirm_for_simple_edits = false,
    view_options = {
      show_hidden = true,
      is_always_hidden = function(name) return name == '.git' end,
    },
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
          auto_attach = require('rust_analyzer').auto_attach,
          cmd = require('rust_analyzer').command,
          capabilities = lsp_capabilities(),
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
            require('rust_analyzer').set_start_root(root)
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
        capabilities = lsp_capabilities(),
      })
      vim.lsp.enable('clangd')
      vim.lsp.config('basedpyright', {
        capabilities = lsp_capabilities(),
        settings = {
          basedpyright = { analysis = { typeCheckingMode = 'standard' } },
        },
      })
      vim.lsp.enable('basedpyright')
      vim.lsp.config('asm_lsp', {
        filetypes = { 'asm', 'nasm', 'vmasm' },
        capabilities = lsp_capabilities(),
      })
      vim.lsp.enable('asm_lsp')
      vim.lsp.config('lua_ls', {
        capabilities = lsp_capabilities(),
        settings = { Lua = { diagnostics = { globals = { 'vim' } },
          workspace = { checkThirdParty = false,
            library = vim.api.nvim_get_runtime_file('', true) } } },
      })
      vim.lsp.enable('lua_ls')
    end },
}, { install = { missing = false }, checker = { enabled = false }, change_detection = { notify = false } })
if not plugin_setup_ok then
  vim.notify('Plugin setup failed; built-in editing remains available: ' ..
    tostring(plugin_setup_err):match('^[^\n]+'), vim.log.levels.WARN)
  return
end

local map = require('mappings').set
local has_which_key, which_key = pcall(require, 'which-key')
if has_which_key then which_key.add({
  { '<leader>f', group = 'Find' }, { '<leader>c', group = 'Code' },
  { '<leader>x', group = 'Diagnostics' }, { '<leader>g', group = 'Git' },
  { '<leader>b', group = 'Build' }, { '<leader>t', group = 'Tests' },
  { '<leader>d', group = 'Debugger' }, { '<leader>r', group = 'Rust' },
  { '<leader>u', group = 'Editor UI' }, { '<leader>l', group = 'LLVM' },
}) end
map('i', 'jk', '<Esc>', { desc = 'Leave insert mode' })
map('t', '<Esc>', '<C-\\><C-n>', { desc = 'Enter terminal normal mode' })
local explicit_save_busy = {}
local function format_and_save_all(bufnr)
  bufnr = type(bufnr) == 'number' and bufnr or vim.api.nvim_get_current_buf()
  if explicit_save_busy[bufnr] then return end
  explicit_save_busy[bufnr] = true
  local ok, err = xpcall(function()
    local formatting = require('formatting')
    if formatting.eligible(bufnr) then
      formatting.cancel(bufnr) -- Invalidate an older asynchronous Space cf request.
      local formatted, format_err = formatting.format(bufnr, false, 2000)
      if not formatted and format_err ~= 'No formatter is attached' then
        vim.notify(format_err .. '; saving current text', vim.log.levels.WARN)
      end
    end
    require('workflows').save_all()
  end, debug.traceback)
  explicit_save_busy[bufnr] = nil
  if not ok then vim.notify('Format/save failed: ' .. tostring(err), vim.log.levels.ERROR) end
end
map({ 'n', 'i' }, '<C-s>', format_and_save_all, { desc = 'Format current file and save all buffers' })
map('x', '<C-s>', function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  format_and_save_all()
end, { desc = 'Format current file and save all buffers' })
vim.api.nvim_create_autocmd('InsertLeave', {
  group = vim.api.nvim_create_augroup('UserFormatAndSaveOnInsertLeave', { clear = true }),
  callback = function(event)
    if not vim.g.auto_format_save then return end
    local buf = event.buf
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    -- Snippet placeholders can enter Select mode and trigger InsertLeave.
    -- Wait for the mode transition before deciding whether to format.
    vim.schedule(function()
      local formatting = require('formatting')
      if not vim.g.auto_format_save or not formatting.eligible(buf)
        or vim.api.nvim_get_current_buf() ~= buf or not vim.bo[buf].modified
        or vim.api.nvim_buf_get_changedtick(buf) ~= tick then return end
      local mode = vim.api.nvim_get_mode().mode
      if mode:match('^[sS]') or mode == '\19' then return end
      if mode:match('^n') then
        if vim.b[buf].auto_format_saving then return end
        vim.b[buf].auto_format_saving = true
        local clients = vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/formatting' })
        local formatted, format_err = true, nil
        if #clients > 0 then formatted, format_err = formatting.format(buf, false, 1000) end
        if not formatted then
          if format_err then
            vim.notify('Automatic format/save stopped: ' .. tostring(format_err), vim.log.levels.WARN)
          end
        elseif formatting.eligible(buf) and vim.api.nvim_get_current_buf() == buf and vim.bo[buf].modified then
          local saved, save_err = pcall(vim.api.nvim_buf_call, buf, function() vim.cmd.write() end)
          if not saved then vim.notify('Automatic save failed: ' .. tostring(save_err), vim.log.levels.WARN) end
        end
        if vim.api.nvim_buf_is_valid(buf) then vim.b[buf].auto_format_saving = false end
      end
    end)
  end,
  desc = 'Format and save after leaving insert mode for normal mode',
})
map('n', '<leader>uf', function()
  vim.g.auto_format_save = not vim.g.auto_format_save
  vim.notify('Automatic format/save ' .. (vim.g.auto_format_save and 'enabled' or 'disabled'))
end, { desc = 'Toggle automatic format and save' })
map('n', '<leader>w', function() require('workflows').save_all() end, { desc = 'Save all named modified buffers' })
local function plugin_command(name, command, executable)
  return function()
    if executable and vim.fn.executable(executable) ~= 1 then
      vim.notify(executable .. ' is unavailable', vim.log.levels.WARN); return
    end
    if vim.fn.exists(':' .. name) == 0 then
      vim.notify(name .. ' is unavailable; install its plugin with :Lazy', vim.log.levels.WARN)
      return
    end
    vim.cmd(command)
  end
end
map('n', '<leader><space>', plugin_command('Oil', 'Oil'), { desc = 'Browse files' })
map('n', '-', plugin_command('Oil', 'Oil'), { desc = 'Browse current file directory' })
map('n', '<leader>ff', plugin_command('Telescope', 'Telescope find_files'), { desc = 'Find files' })
map('n', '<leader>fg', plugin_command('Telescope', 'Telescope live_grep', 'rg'),
  { desc = 'Search project text' })
map('n', '<leader>fb', plugin_command('Telescope', 'Telescope buffers'), { desc = 'Find open buffers' })
map('n', ']b', '<cmd>bnext<cr>', { desc = 'Next listed buffer' })
map('n', '[b', '<cmd>bprevious<cr>', { desc = 'Previous listed buffer' })
map('n', '<leader>fh', plugin_command('Telescope', 'Telescope help_tags'), { desc = 'Search help' })
map('n', '<Esc>', '<cmd>nohlsearch<cr>')
map('n', '<C-h>', '<C-w>h', { desc = 'Focus left split' })
map('n', '<C-j>', '<C-w>j', { desc = 'Focus lower split' })
map('n', '<C-k>', '<C-w>k', { desc = 'Focus upper split' })
map('n', '<C-l>', '<C-w>l', { desc = 'Focus right split' })
map('n', '<leader>xd', vim.diagnostic.open_float, { desc = 'Show diagnostic popup' })
map('n', '<leader>xt', function()
  vim.diagnostic.enable(not vim.diagnostic.is_enabled())
end, { desc = 'Toggle diagnostics' })
map('n', '<leader>xa', function()
  require('diagnostic_presentation').toggle_all()
end, { desc = 'Toggle full Rust diagnostics' })
map('n', '<leader>xq', vim.diagnostic.setloclist, { desc = 'Open diagnostic location list' })
map('n', '<leader>cf', function()
  local ok, err = require('formatting').format(vim.api.nvim_get_current_buf(), true)
  if not ok then vim.notify(err, vim.log.levels.WARN) end
end, { desc = 'Format current file' })

vim.diagnostic.config({ severity_sort = true, underline = true, update_in_insert = false,
  virtual_text = { spacing = 2 }, float = { border = 'rounded' } })
require('diagnostic_presentation').setup()
require('ui').setup()
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLsp', { clear = true }),
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if client and client.server_capabilities.documentSymbolProvider
      and client:supports_method('textDocument/documentSymbol', event.buf) then
      local ok, navic = pcall(require, 'nvim-navic')
      if ok and not navic.is_available(event.buf) then navic.attach(client, event.buf) end
    end
    if client and client:supports_method('textDocument/inlayHint', event.buf) then
      vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
    end
  end,
})
map('n', 'gd', vim.lsp.buf.definition, { desc = 'Go to definition' })
map('n', 'grr', vim.lsp.buf.references, { desc = 'Find references' })
map('n', 'gri', vim.lsp.buf.implementation, { desc = 'Go to implementation' })
map('n', 'grt', vim.lsp.buf.type_definition, { desc = 'Go to type definition' })
map('n', 'K', vim.lsp.buf.hover, { desc = 'Documentation' })
local function supported(method)
  return #vim.lsp.get_clients({ bufnr = 0, method = method }) > 0
end
local function rust_action(command)
  if vim.bo.filetype ~= 'rust' or vim.fn.exists(':RustLsp') == 0
    or #vim.lsp.get_clients({ bufnr = 0, name = 'rust-analyzer' }) == 0 then
    vim.notify('Rust Analyzer is not attached', vim.log.levels.WARN); return
  end
  vim.cmd('RustLsp ' .. command)
end
map('n', '<leader>fs', function()
  if not supported('textDocument/documentSymbol') then
    vim.notify('Document symbols are unavailable', vim.log.levels.WARN); return
  end
  plugin_command('Telescope', 'Telescope lsp_document_symbols')()
end, { desc = 'Find document symbols' })
map('n', '<leader>fS', function()
  if not supported('workspace/symbol') then
    vim.notify('Workspace symbols are unavailable', vim.log.levels.WARN); return
  end
  plugin_command('Telescope', 'Telescope lsp_dynamic_workspace_symbols')()
end, { desc = 'Find workspace symbols' })
map('n', '<leader>cr', function()
  if supported('textDocument/rename') then vim.lsp.buf.rename()
  else vim.notify('Rename is unavailable', vim.log.levels.WARN) end
end, { desc = 'Rename symbol' })
map('n', '<leader>ca', function()
  if vim.bo.filetype == 'rust' and #vim.lsp.get_clients({ bufnr = 0, name = 'rust-analyzer' }) > 0 then
    rust_action('codeAction')
  elseif supported('textDocument/codeAction') then vim.lsp.buf.code_action()
  else vim.notify('Code actions are unavailable', vim.log.levels.WARN) end
end, { desc = 'Code actions' })
map('n', '<leader>uh', function()
  local buf = vim.api.nvim_get_current_buf()
  if not supported('textDocument/inlayHint') then
    vim.notify('Inlay hints are unavailable', vim.log.levels.WARN); return
  end
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }), { bufnr = buf })
end, { desc = 'Toggle inlay hints' })
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('UserLanguageMappings', { clear = true }),
  pattern = 'rust', callback = function(event)
    local function rust_map(key, command, desc)
      map('n', '<leader>' .. key, function() rust_action(command) end,
        { buffer = event.buf, desc = desc })
    end
    rust_map('rr', 'runnables', 'Rust run targets')
    rust_map('rm', 'expandMacro', 'Expand Rust macro')
    rust_map('xe', 'explainError current', 'Explain current Rust error')
    rust_map('xr', 'renderDiagnostic current', 'Show formatted Rust diagnostic')
    rust_map('xR', 'renderDiagnostic cycle', 'Next formatted Rust diagnostic')
    rust_map('xl', 'relatedDiagnostics', 'Go to related Rust locations')
  end,
})
vim.api.nvim_create_autocmd('FileType', {
  group = 'UserLanguageMappings', pattern = { 'c', 'cpp' }, callback = function(event)
    map('n', '<leader>ch', function()
      if #vim.lsp.get_clients({ bufnr = 0, name = 'clangd' }) > 0 then
        if vim.fn.exists(':LspClangdSwitchSourceHeader') ~= 0 then
          vim.cmd('LspClangdSwitchSourceHeader')
        else vim.notify('Clangd source/header command is unavailable', vim.log.levels.WARN) end
      else vim.notify('Clangd is not attached', vim.log.levels.WARN) end
    end, { buffer = event.buf, desc = 'Switch C/C++ source and header' })
  end,
})
vim.api.nvim_create_autocmd('FileType', {
  group = 'UserLanguageMappings', pattern = '*', callback = function(event)
    local ft = vim.bo[event.buf].filetype
    if ft ~= 'rust' then
      for _, key in ipairs({ 'rr', 'rm', 'xe', 'xr', 'xR', 'xl' }) do
        pcall(vim.keymap.del, 'n', '<leader>' .. key, { buffer = event.buf })
      end
    end
    if ft ~= 'c' and ft ~= 'cpp' then
      pcall(vim.keymap.del, 'n', '<leader>ch', { buffer = event.buf })
    end
  end,
})
-- Blink handles automatic completion, signatures, snippets and popup sizing.
require('workflows').setup()
