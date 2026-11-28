local function check(value, message)
  if not value then error(message, 2) end
end

local mappings = require('mappings')
check(not pcall(mappings.set, 'n', '<leader>ff', function() end,
  { desc = 'Accidental duplicate' }), 'duplicate declaration was accepted')
local function audit_registered_mappings()
  for key, description in pairs(mappings.declarations) do
    local mode, lhs = key:match('^(.-)%z(.*)$')
    if lhs:sub(1, 1) == ' ' and mode == 'n' then
      local final = vim.fn.maparg(lhs, mode, false, true)
      check(final.desc == description, 'mapping was silently overridden: ' .. lhs)
    end
  end
end
audit_registered_mappings()

local notices = {}
local old_notify = vim.notify
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
local function invoke(lhs)
  local entry = vim.fn.maparg(lhs, 'n', false, true)
  check(type(entry.callback) == 'function', 'missing callback for ' .. lhs)
  local ok, err = pcall(entry.callback)
  check(ok, lhs .. ' raised an error: ' .. tostring(err))
end
local scratch = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(scratch)
for _, key in ipairs({ ' dc', ' dt', ' dv', ' dh', ' tr', ' tt',
  ' gs', ' gp', ' gd', ' ca', ' cr', ' cf', ' uh', ' w' }) do
  invoke(key)
end
check(pcall(vim.cmd.BuildStop), 'BuildStop failed without an active task')
vim.bo[scratch].filetype = 'rust'
invoke(' xe')
vim.bo[scratch].filetype = 'lua'
check(vim.fn.maparg(' xe', 'n') == '', 'Rust mapping survived filetype change')
vim.notify = old_notify

local d = require('diagnostic_presentation')
local a = { source = 'rust-analyzer', code = 'E0425', severity = 1,
  lnum = 0, col = 2, end_lnum = 0, end_col = 2, message = 'first error' }
local b = vim.tbl_extend('force', {}, a, { source = 'rustc', message = 'different error' })
check(d.visible(a, { a, b }), 'distinct compiler error was hidden')
b.message = a.message
check(not d.visible(a, { a, b }), 'same zero-width diagnostic was not deduplicated')
b.severity = 2
check(d.visible(a, { a, b }), 'warning hid an error')
local presentation_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(presentation_buf)
vim.bo[presentation_buf].filetype = 'rust'
vim.api.nvim_buf_set_lines(presentation_buf, 0, -1, false, { 'first', 'second' })
local hidden_ns = vim.api.nvim_create_namespace('TestHiddenVirtualText')
local shown_ns = vim.api.nvim_create_namespace('TestShownVirtualText')
vim.diagnostic.config({ virtual_text = false }, hidden_ns)
vim.diagnostic.set(hidden_ns, presentation_buf, { { lnum = 0, col = 0,
  severity = 1, message = 'hidden virtual text' } })
vim.diagnostic.set(shown_ns, presentation_buf, { { lnum = 1, col = 0,
  severity = 1, message = 'shown virtual text' } })
vim.wait(50)
local marks = vim.api.nvim_buf_get_extmarks(presentation_buf, -1, 0, -1,
  { details = true })
local virtual_rows = {}
for _, mark in ipairs(marks) do
  if mark[4].virt_text then virtual_rows[mark[2]] = true end
end
check(not virtual_rows[0] and virtual_rows[1],
  'per-namespace virtual text setting was ignored')
check(#vim.diagnostic.get(presentation_buf) == 2, 'presentation changed stored diagnostics')
vim.diagnostic.enable(false, { bufnr = presentation_buf })
vim.wait(50)
local disabled_marks = vim.api.nvim_buf_get_extmarks(presentation_buf, -1, 0, -1,
  { details = true })
local still_visible = false
for _, mark in ipairs(disabled_marks) do
  if mark[4].virt_text or mark[4].sign_text or mark[4].hl_group then still_visible = true end
end
check(not still_visible,
  'disabled diagnostics were redisplayed')
vim.diagnostic.enable(true, { bufnr = presentation_buf })
vim.api.nvim_buf_delete(presentation_buf, { force = true })

local rustup = require('rust_analyzer')
local old_system, old_executable = vim.system, vim.fn.executable
local dirs = {}
local function directory()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, 'p')
  dirs[#dirs + 1] = path
  return path
end
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
vim.fn.executable = function(path)
  if path == 'rustup' or path == '/bin/sh' or path == '/bin/true' then return 1 end
  return 0
end
local calls = 0
local function fake(result)
  vim.system = function()
    calls = calls + 1
    return { wait = function() return result end }
  end
end
fake({ code = 124, signal = 9 })
check(rustup.resolve(directory()) == nil, 'timed-out rustup returned a command')
fake({ code = 1, stderr = 'toolchain missing' })
check(rustup.resolve(directory()) == nil, 'missing toolchain returned a command')
fake({ code = 0, stdout = '/missing/rust-analyzer\n' })
check(rustup.resolve(directory()) == nil, 'invalid analyzer path accepted')
vim.system = function() error('spawn failed') end
check(rustup.resolve(directory()) == nil, 'spawn failure propagated')
fake({ code = 0, stdout = '/bin/sh\n' })
local first = directory()
check(rustup.resolve(first) == '/bin/sh', 'valid analyzer path rejected')
local source = first .. '/main.rs'
vim.fn.writefile({ 'fn main() {}' }, source)
local other_client = vim.lsp.get_clients
vim.lsp.get_clients = function() return { { config = { cmd = { '/bin/true' } } } } end
local source_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(source_buf, source)
check(not rustup.auto_attach(source_buf), 'second toolchain attached to wrong analyzer')
vim.api.nvim_buf_delete(source_buf, { force = true })
vim.lsp.get_clients = other_client
local before = calls
check(rustup.resolve(first) == '/bin/sh' and calls == before, 'resolution cache missed')
fake({ code = 0, stdout = '/bin/true\n' })
check(rustup.resolve(directory()) == '/bin/true', 'second project used stale toolchain')
vim.fn.executable = function(path)
  if path == 'rustup' then return 0 end
  return old_executable(path)
end
check(rustup.resolve(directory()) == nil, 'missing rustup returned a command')
check(rustup.resolve('/definitely/missing/nvim-project') == nil, 'missing project accepted')
local invalid_settings = directory()
vim.fn.writefile({ '{invalid json' }, invalid_settings .. '/rust-analyzer.json')
local defaults = { ['rust-analyzer'] = { check = { command = 'check' } } }
local settings = vim.g.rustaceanvim.server.settings(invalid_settings, defaults)
check(vim.deep_equal(settings, defaults), 'invalid rust-analyzer.json replaced defaults')
vim.fn.executable, vim.system, vim.notify = old_executable, old_system, old_notify
for _, path in ipairs(dirs) do vim.fn.delete(path, 'rf') end

local process = vim.system({ 'sh', '-c', 'sleep 2' })
local timed = process:wait(20)
check(timed.code == 124 and timed.signal == 9, 'vim.system timeout semantics changed')

local formatting = require('formatting')
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '.txt')
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'old' })
local edit = { { range = { start = { line = 0, character = 0 },
  ['end'] = { line = 0, character = 3 } }, newText = 'new' } }
local old_clients = vim.lsp.get_clients
local client = { id = 10, name = 'test-formatter', offset_encoding = 'utf-8' }
local preferred = { id = 11, name = 'clangd', offset_encoding = 'utf-8' }
vim.lsp.get_clients = function() return { client, preferred } end
preferred.request_sync = function() return { result = edit } end
client.request_sync = function() error('less preferred formatter ran') end
check(formatting.format(buf, false), 'preferred formatter selection failed')
check(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'new',
  'preferred formatter edits missing')
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'old' })
vim.lsp.get_clients = function() return { client } end
client.request_sync = function() return { result = edit } end
check(formatting.format(buf, false), 'synchronous formatting failed')
check(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'new', 'format edits not applied')
client.request_sync = function()
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'newer edit' })
  return { result = edit }
end
check(not formatting.format(buf, false), 'stale formatting result was applied')
check(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'newer edit', 'newer edit overwritten')
local callback
client.request = function(_, _, _, cb) callback = cb; return true end
check(formatting.format(buf, true), 'asynchronous formatting did not start')
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'latest edit' })
vim.notify = function() end
callback(nil, edit)
vim.notify = old_notify
check(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'latest edit',
  'asynchronous formatter overwrote newer edits')
vim.bo[buf].readonly = true
check(not formatting.eligible(buf), 'read-only buffer was eligible for formatting')
vim.bo[buf].readonly = false
check(formatting.format(buf, true), 'second asynchronous format did not start')
vim.lsp.get_clients = function() return {} end
callback(nil, edit)
check(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'latest edit',
  'detached formatter applied edits')
vim.lsp.get_clients = function() return { client } end
client.request = function() return false, 'disconnected' end
check(not formatting.format(buf, true), 'failed format request was accepted')
client.request = function(_, _, _, cb) callback = cb; return true end
check(formatting.format(buf, true), 'third asynchronous format did not start')
vim.api.nvim_buf_delete(buf, { force = true })
check(pcall(callback, nil, edit), 'formatter callback failed after buffer deletion')
vim.lsp.get_clients = old_clients

local nav_root = vim.fn.tempname()
vim.fn.mkdir(nav_root .. '/src', 'p')
local source_file = nav_root .. '/src/my config é.rs'
vim.fn.writefile({ 'fn main() { let é = 1; panic!("x"); }' }, source_file)
local output = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(output)
vim.api.nvim_buf_set_name(output, nav_root .. '/output.txt')
vim.api.nvim_buf_set_lines(output, 0, -1, false,
  { '1: main::main', '   at ./src/my config é.rs:1:25' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local original_cwd = vim.fn.getcwd()
vim.api.nvim_set_current_dir(nav_root)
require('workflows').jump_to_compiler_location()
check(vim.api.nvim_buf_get_name(0) == source_file, 'backtrace frame opened wrong file')
check(vim.api.nvim_win_get_cursor(0)[2] == 24, 'backtrace byte column converted incorrectly')
check(vim.api.nvim_buf_is_valid(output) and vim.bo[output].modified,
  'navigation discarded modified terminal-style output')
vim.api.nvim_buf_delete(output, { force = true })
vim.api.nvim_buf_delete(vim.api.nvim_get_current_buf(), { force = true })
vim.api.nvim_set_current_dir(original_cwd)
vim.fn.delete(nav_root, 'rf')

local special = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(special)
vim.bo[special].buftype = 'nofile'
vim.notify = function() end
for _, key in ipairs({ ' db', ' dc', ' dt', ' dv', ' dh', ' tt', ' tr',
  ' gs', ' gp', ' gd', ' ca', ' cr', ' cf', ' uh', ' w' }) do
  invoke(key)
end
vim.notify = old_notify
local save_mapping = vim.fn.maparg('<C-s>', 'n', false, true)
check(pcall(save_mapping.callback), 'Ctrl+S failed in a special buffer')
vim.fn.setqflist({ { text = 'sample output' } }, 'r')
vim.cmd.copen()
check(vim.bo.buftype == 'quickfix', 'quickfix test window did not open')
vim.notify = function() end
for _, key in ipairs({ ' gs', ' gp', ' gd', ' cf', ' ca', ' cr', ' uh', ' tt', ' tr' }) do
  invoke(key)
end
vim.notify = old_notify
vim.cmd.cclose()
vim.cmd.copen()
vim.cmd.cclose()
check(pcall(vim.cmd.Oil), 'Oil did not open in headless Neovim')
check(vim.bo.filetype == 'oil', 'Oil test buffer did not open')
vim.notify = function() end
for _, key in ipairs({ ' gs', ' gp', ' gd', ' cf', ' ca', ' cr', ' uh', ' tt', ' tr' }) do
  invoke(key)
end
vim.notify = old_notify
vim.cmd.enew()
vim.cmd.Oil()
vim.cmd.enew()
check(pcall(vim.cmd.Git), 'Fugitive status did not open')
check(vim.bo.filetype == 'fugitive', 'Fugitive test buffer did not open')
vim.notify = function() end
for _, key in ipairs({ ' gs', ' gp', ' gd', ' cf', ' ca', ' cr', ' uh', ' tt', ' tr' }) do
  invoke(key)
end
vim.notify = old_notify
vim.cmd.enew()
vim.cmd('Telescope find_files')
check(vim.bo.filetype == 'TelescopePrompt', 'Telescope prompt did not open')
local prompt_buf = vim.api.nvim_get_current_buf()
vim.notify = function() end
for _, key in ipairs({ ' gs', ' gp', ' gd', ' cf', ' ca', ' cr', ' uh', ' tt', ' tr' }) do
  invoke(key)
end
vim.notify = old_notify
require('telescope.actions').close(prompt_buf)
vim.cmd('botright new')
local terminal_buf = vim.api.nvim_get_current_buf()
vim.fn.termopen({ 'sh', '-c', 'true' })
check(vim.bo[terminal_buf].buftype == 'terminal', 'terminal test did not open')
check(pcall(save_mapping.callback), 'Ctrl+S failed in terminal Normal mode')
vim.api.nvim_buf_delete(terminal_buf, { force = true })
local autosave_file = vim.fn.tempname() .. '.txt'
local autosave_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(autosave_buf)
vim.api.nvim_buf_set_name(autosave_buf, autosave_file)
vim.api.nvim_buf_set_lines(autosave_buf, 0, -1, false, { 'pending' })
vim.g.auto_format_save = true
vim.api.nvim_exec_autocmds('InsertLeave', { buffer = autosave_buf })
vim.g.auto_format_save = false
vim.wait(30)
check(vim.fn.filereadable(autosave_file) == 0, 'disabled pending automatic save still wrote')
local writes = 0
local write_group = vim.api.nvim_create_augroup('TestAutoSaveWrites', { clear = true })
vim.api.nvim_create_autocmd('BufWritePost', {
  group = write_group, buffer = autosave_buf, callback = function() writes = writes + 1 end,
})
vim.g.auto_format_save = true
vim.api.nvim_exec_autocmds('InsertLeave', { buffer = autosave_buf })
vim.api.nvim_exec_autocmds('InsertLeave', { buffer = autosave_buf })
vim.wait(50)
vim.g.auto_format_save = false
check(writes == 1 and vim.fn.filereadable(autosave_file) == 1,
  'rapid InsertLeave caused repeated or missing saves')
vim.api.nvim_del_augroup_by_id(write_group)
vim.api.nvim_buf_delete(autosave_buf, { force = true })
vim.fn.delete(autosave_file)

local old_overseer = package.loaded.overseer
local attempts = 0
package.loaded.overseer = {
  new_task = function()
    attempts = attempts + 1
    return { subscribe = function() end, start = function() return false end }
  end,
}
vim.notify = function() end
require('workflows').build('true')
require('workflows').build('true')
vim.notify = old_notify
package.loaded.overseer = old_overseer
check(attempts == 2, 'failed Overseer startup left build runner busy')
attempts = 0
package.loaded.overseer = {
  new_task = function()
    attempts = attempts + 1
    return { subscribe = function() error('subscription failed') end }
  end,
}
vim.notify = function() end
require('workflows').build('true')
require('workflows').build('true')
vim.notify = old_notify
check(attempts == 2, 'failed task subscription left build runner busy')
package.loaded.overseer = old_overseer

local dap = require('dap')
local old_exepath = vim.fn.exepath
vim.fn.exepath = function(name)
  if name == 'lldb-dap' then return '' end
  return old_exepath(name)
end
local adapter_called = false
vim.notify = function() end
dap.adapters.lldb(function() adapter_called = true end)
vim.notify = old_notify
vim.fn.exepath = old_exepath
check(not adapter_called, 'missing LLDB returned an invalid adapter')
local old_input = vim.fn.input
vim.fn.input = function() return '/definitely/missing/debug-executable' end
check(dap.configurations.rust[1].program() == dap.ABORT,
  'invalid executable path started the debugger')
vim.fn.input = old_input
dap.repl.open()
for _, win in ipairs(vim.api.nvim_list_wins()) do
  if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'dap-repl' then
    vim.api.nvim_set_current_win(win)
    break
  end
end
check(vim.bo.filetype == 'dap-repl', 'debugger console did not open')
vim.notify = function() end
for _, key in ipairs({ ' gs', ' gp', ' gd', ' cf', ' ca', ' cr', ' uh', ' tt', ' tr',
  ' dv', ' dh' }) do
  invoke(key)
end
vim.notify = old_notify
dap.repl.close()
dap.repl.open()
dap.repl.close()

local ui = require('ui')
local fake_tree = {}
local current_line, updates = 1, 0
local previous_lib, previous_navic = package.loaded['nvim-navic.lib'], package.loaded['nvim-navic']
package.loaded['nvim-navic.lib'] = {
  get_tree = function() return fake_tree end,
  update_context = function(_, cursor) current_line = cursor[1]; updates = updates + 1 end,
  clear_buffer_data = function() end,
}
package.loaded['nvim-navic'] = {
  is_available = function() return true end,
  get_data = function() return { { kind = 12, name = current_line == 1 and 'first%' or 'second' } } end,
}
local symbol_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(symbol_buf)
vim.api.nvim_buf_set_name(symbol_buf, vim.fn.tempname() .. '/é%source.rs')
vim.api.nvim_buf_set_lines(symbol_buf, 0, -1, false, { 'one', 'two' })
local first_win = vim.api.nvim_get_current_win()
vim.cmd.vsplit()
local second_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(first_win, { 1, 0 })
vim.api.nvim_win_set_cursor(second_win, { 2, 0 })
vim.g.statusline_winid = first_win
check(ui.context():find('first%%%%', 1, false) ~= nil, 'first window context wrong')
vim.g.statusline_winid = second_win
check(ui.context() == 'second', 'second window context wrong')
vim.g.statusline_winid = first_win
check(ui.context():find('first%%%%', 1, false) ~= nil and updates == 2,
  'per-window Navic context cache missed')
check(ui.path():find('%%%%', 1, false) ~= nil, 'percent path was not escaped')
fake_tree = {}
check(ui.context() ~= '' and updates == 3, 'symbol refresh did not invalidate context')
package.loaded['nvim-navic.lib'].update_context = nil
check(ui.context() == '', 'missing private Navic API caused an error')
package.loaded['nvim-navic.lib'].update_context = function(_, cursor)
  current_line = cursor[1]; updates = updates + 1
end
vim.api.nvim_buf_set_name(symbol_buf, vim.fn.tempname() .. '/renamed%.rs')
check(ui.path():find('renamed', 1, true) ~= nil,
  'renamed file left stale winbar path')
vim.api.nvim_win_set_width(first_win, 8)
check(type(ui.path()) == 'string' and type(ui.context()) == 'string',
  'narrow winbar rendering failed')
vim.api.nvim_win_close(second_win, true)
vim.g.statusline_winid = nil
vim.api.nvim_buf_delete(symbol_buf, { force = true })
package.loaded['nvim-navic.lib'], package.loaded['nvim-navic'] = previous_lib, previous_navic
audit_registered_mappings()

print('edge-case tests passed')
