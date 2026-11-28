local function check(value, message)
  if not value then error(message, 2) end
end

local root = vim.fn.tempname()
local shell_dir = root .. '/nested'
vim.fn.mkdir(shell_dir .. '/src', 'p')
local source = shell_dir .. '/src/config.rs'
vim.fn.writefile({ 'fn main() {}' }, source)
vim.fn.writefile({ 'fn other() {}' }, shell_dir .. '/src/other.rs')
local old_cwd = vim.fn.getcwd()
local job, terminal
local ok, err = xpcall(function()
  vim.cmd('botright new')
  terminal = vim.api.nvim_get_current_buf()
  job = vim.fn.termopen({ 'sh', '-c', 'cd ' .. vim.fn.shellescape(shell_dir)
    .. '; printf "0: other\\n at ./src/other.rs:1:1\\n1: current\\n at ./src/config.rs:1:4\\n"; sleep 3' })
  check(job > 0, 'terminal job did not start')
  check(vim.wait(1000, function()
    return table.concat(vim.api.nvim_buf_get_lines(terminal, 0, -1, false), '\n')
      :find('at ./src/config.rs:1:4', 1, true) ~= nil
  end, 20), 'terminal backtrace output did not appear')
  local lines = vim.api.nvim_buf_get_lines(terminal, 0, -1, false)
  for index, line in ipairs(lines) do
    if line:find('1: current', 1, true) then
      vim.api.nvim_win_set_cursor(0, { index, 0 }); break
    end
  end
  local jump = vim.fn.maparg('gd', 'n', false, true).callback
  check(type(jump) == 'function', 'terminal source mapping missing')
  jump()
  check(vim.api.nvim_buf_get_name(0) == source, 'terminal cd path resolved incorrectly')
  check(vim.api.nvim_buf_is_valid(terminal), 'navigation closed terminal buffer')
  local source_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(source_buf, 0, 1, false, { 'unsaved source edit' })

  vim.fn.setqflist({}, 'r', { items = { { filename = source, lnum = 1, col = 4,
    text = 'sample compiler error' } } })
  vim.cmd.copen()
  local quickfix_jump = vim.fn.maparg('gd', 'n', false, true).callback
  check(type(quickfix_jump) == 'function', 'quickfix source mapping missing')
  quickfix_jump()
  check(vim.api.nvim_buf_get_name(0) == source, 'quickfix location opened wrong file')
  check(vim.bo[source_buf].modified
    and vim.api.nvim_buf_get_lines(source_buf, 0, 1, false)[1] == 'unsaved source edit',
    'quickfix navigation discarded source edits')
  vim.api.nvim_buf_set_lines(source_buf, 0, 1, false, { 'éx' })
  local ns = vim.api.nvim_create_namespace('NavigationTestDiagnostic')
  vim.diagnostic.set(ns, source_buf, { { lnum = 0, col = 2,
    severity = vim.diagnostic.severity.ERROR, message = 'byte-column diagnostic' } })
  vim.diagnostic.setloclist({ open = true })
  local diagnostic_jump = vim.fn.maparg('gd', 'n', false, true).callback
  check(type(diagnostic_jump) == 'function', 'diagnostic location mapping missing')
  diagnostic_jump()
  check(vim.api.nvim_win_get_cursor(0)[2] == 2,
    'diagnostic byte column was interpreted as a Rust character column')
end, debug.traceback)
if job and job > 0 then vim.fn.jobstop(job) end
if terminal and vim.api.nvim_buf_is_valid(terminal) then
  vim.api.nvim_buf_delete(terminal, { force = true })
end
vim.api.nvim_set_current_dir(old_cwd)
vim.cmd('silent! cclose')
local source_buf = vim.fn.bufnr(source)
if source_buf > 0 and vim.api.nvim_buf_is_valid(source_buf) then
  vim.api.nvim_buf_delete(source_buf, { force = true })
end
vim.fn.delete(root, 'rf')
if not ok then error(err) end
print('terminal and quickfix navigation integration passed')
