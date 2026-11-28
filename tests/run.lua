local function check(condition, message)
  if not condition then error(message, 2) end
end

local workflows = require('workflows')
local diagnostics = require('diagnostic_presentation')
local map = vim.fn.maparg
local expected = { 'ff', 'fg', 'fb', 'fh', 'fs', 'fS', 'ca', 'cr', 'cf',
  'xd', 'xq', 'xt', 'xa', 'gg', 'gb', 'gl', 'gc', 'gB', 'gs', 'gp', 'gh',
  'gd', 'gu', 'gi', 'bb', 'bc', 'bs', 'bo', 'tt', 'tr', 'db', 'dc',
  'dt', 'dr', 'dv', 'dh', 'uh', 'uf' }
for _, key in ipairs(expected) do
  check(map(' ' .. key, 'n') ~= '', 'missing mapping: ' .. key)
end
local seen = {}
for _, entry in ipairs(vim.api.nvim_get_keymap('n')) do
  if entry.lhs:sub(1, 1) == ' ' then
    check(not seen[entry.lhs], 'duplicate leader mapping: ' .. entry.lhs)
    check(entry.desc and entry.desc ~= '', 'undocumented leader mapping: ' .. entry.lhs)
    seen[entry.lhs] = true
  end
end
for lhs in pairs(seen) do
  for n = 2, #lhs - 1 do
    check(not seen[lhs:sub(1, n)], 'ambiguous leader prefix: ' .. lhs)
  end
end
for _, key in ipairs({ 'f', 'd', 'q', 'rn', 'ud', 'ua', 'ug', 'ub',
  'hs', 'hp', 'hb', 'hd', 'rt', 're', 'ih' }) do
  check(map(' ' .. key, 'n') == '', 'obsolete mapping: ' .. key)
end
check(vim.o.swapfile and vim.o.undofile, 'recovery options disabled')
check(not vim.g.auto_format_save, 'automatic save should default off')

local error_diagnostic = { source = 'rustc', code = 'unused_variables',
  severity = vim.diagnostic.severity.ERROR, lnum = 0, col = 0, end_lnum = 0, end_col = 1 }
local warning = vim.tbl_extend('force', {}, error_diagnostic,
  { severity = vim.diagnostic.severity.WARN, source = 'rust-analyzer' })
check(not diagnostics.quiet(error_diagnostic), 'promoted Rust error hidden')
check(diagnostics.quiet(warning), 'low priority warning visible')
check(diagnostics.visible(error_diagnostic, { error_diagnostic, warning }), 'error deduplicated')
vim.diagnostic.enable(false)
check(not vim.diagnostic.is_enabled(), 'diagnostics did not disable')
vim.diagnostic.enable(true)
check(vim.diagnostic.is_enabled(), 'diagnostics did not enable')

for _, input in ipairs({ 'at ./src/config.rs:42:24',
  'at /absolute/path/src/config.rs:42:24', 'src/config.rs:42:24',
  '--> src/config.rs:42:24', '::: src/config.rs:42:24' }) do
  local path, line, column = workflows.source_location(input)
  check(path and path:match('config.rs$') and line == 42 and column == 24,
    'bad location: ' .. input)
end
local spaced = workflows.source_location('at ./src/my config.rs:42:24')
check(spaced == './src/my config.rs', 'filename spaces lost')
check(workflows.source_byte_column('éx', 2, true) == 2, 'Unicode column conversion wrong')
check(workflows.source_byte_column('éx', 2, false) == 1, 'byte column conversion wrong')

local temp = vim.fn.tempname()
vim.fn.mkdir(temp, 'p')
local good = temp .. '/good.txt'
local bad = temp .. '/missing/bad.txt'
local one = vim.api.nvim_create_buf(true, false)
local two = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(one, bad)
vim.api.nvim_buf_set_name(two, good)
vim.api.nvim_buf_set_lines(one, 0, -1, false, { 'bad' })
vim.api.nvim_buf_set_lines(two, 0, -1, false, { 'good' })
local old_notify = vim.notify
vim.notify = function() end
local saved, failures = workflows.save_all()
vim.notify = old_notify
check(not saved and #failures == 1 and failures[1]:find('bad.txt', 1, true), 'save failure not reported')
check(vim.fn.filereadable(good) == 1, 'later buffer not saved')
check(vim.bo[one].modified, 'failed save discarded changes')
local old_overseer = package.loaded.overseer
local launched = false
package.loaded.overseer = { new_task = function() launched = true end }
vim.notify = function() end
workflows.build('echo should-not-run')
vim.notify = old_notify
package.loaded.overseer = old_overseer
check(not launched, 'build ran after a failed save')
vim.api.nvim_buf_delete(one, { force = true })
vim.api.nvim_buf_delete(two, { force = true })
vim.fn.delete(temp, 'rf')

local test_map = vim.fn.maparg(' tt', 'n', false, true).callback
local repeat_map = vim.fn.maparg(' tr', 'n', false, true).callback
local old_cmd, old_test, old_repeat = vim.cmd, workflows.test, workflows.repeat_test
local calls = {}
vim.cmd = function(command) calls[#calls + 1] = command end
workflows.test = function() calls[#calls + 1] = 'llvm-test' end
workflows.repeat_test = function() calls[#calls + 1] = 'llvm-repeat' end
vim.bo.filetype = 'rust'
test_map(); repeat_map()
vim.bo.filetype = 'llvm'
test_map(); repeat_map()
vim.cmd, workflows.test, workflows.repeat_test = old_cmd, old_test, old_repeat
check(vim.deep_equal(calls, { 'RustLsp testables', 'RustLsp! testables',
  'llvm-test', 'llvm-repeat' }), 'language test dispatch wrong')

local rust = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(rust)
vim.bo[rust].filetype = 'rust'
check(map(' rr', 'n') ~= '' and map(' xe', 'n') ~= '', 'Rust mappings missing')
vim.bo[rust].filetype = 'lua'
check(map(' rr', 'n') == '', 'Rust mapping leaked after filetype change')
local llvm = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(llvm)
vim.bo[llvm].filetype = 'llvm'
check(map(' lc', 'n') ~= '', 'LLVM mapping missing')
local old_executable, old_system = vim.fn.executable, vim.system
local notifications = {}
old_notify = vim.notify
vim.notify = function(message) notifications[#notifications + 1] = message end
vim.fn.executable = function(name)
  if name == 'rustup' then return 0 end
  return old_executable(name)
end
local rust_cmd = vim.g.rustaceanvim.server.cmd
check(vim.deep_equal(rust_cmd(), {}), 'missing rustup launched a fallback')
vim.fn.executable = old_executable
check(#notifications > 0, 'missing rustup did not notify')
local callback
vim.system = function(_, _, cb) callback = cb end
vim.api.nvim_buf_set_lines(llvm, 0, -1, false, { 'define void @f() {}' })
vim.fn.maparg(' lc', 'n', false, true).callback()
check(type(callback) == 'function', 'LLVM check did not start asynchronously')
vim.api.nvim_buf_delete(llvm, { force = true })
callback({ code = 1, stderr = 'llvm-as: <stdin>:1:1: error: bad IR' })
vim.wait(50)
vim.system, vim.notify = old_system, old_notify
print('configuration tests passed')
