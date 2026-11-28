if vim.fn.executable('cargo') ~= 1 or vim.fn.executable('rustup') ~= 1
  or vim.fn.system({ 'rustup', 'which', 'rust-analyzer' }):match('^/') == nil then
  print('Rust integration skipped: project toolchain is unavailable')
  return
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/src', 'p')
vim.fn.writefile({ '[package]', 'name = "nvim-config-test"', 'version = "0.1.0"',
  'edition = "2021"' }, root .. '/Cargo.toml')
local source = root .. '/src/lib.rs'
vim.fn.writefile({ '#[test]', 'fn works() { assert!(true); }' }, source)
local old_select = vim.ui.select
vim.ui.select = function(_, _, callback) callback(nil) end
local second_root
local second_checked = false
local ok, err = xpcall(function()
  vim.cmd.edit(vim.fn.fnameescape(source))
  assert(vim.wait(8000, function()
    return #vim.lsp.get_clients({ bufnr = 0, name = 'rust-analyzer' }) > 0
  end, 50), 'Rust Analyzer did not attach to a temporary project')
  assert(vim.fn.exists(':RustLsp') ~= 0, 'RustLsp command was not registered')
  vim.cmd('RustLsp! testables')
  vim.wait(500)
  local new_source = root .. '/src/new_file.rs'
  vim.cmd.edit(vim.fn.fnameescape(new_source))
  assert(#vim.lsp.get_clients({ bufnr = 0, name = 'rust-analyzer' }) == 0,
    'nonexistent Rust file attached before its first save')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'pub fn new_file() {}' })
  vim.cmd.write()
  assert(vim.wait(8000, function()
    return #vim.lsp.get_clients({ bufnr = 0, name = 'rust-analyzer' }) > 0
  end, 50), 'Rust Analyzer did not attach after first save')
  second_root = vim.fn.tempname()
  vim.fn.mkdir(second_root .. '/src', 'p')
  vim.fn.writefile({ '[toolchain]', 'channel = "nightly"' }, second_root .. '/rust-toolchain.toml')
  local nightly = vim.system({ 'rustup', 'which', 'rust-analyzer' },
    { cwd = second_root, text = true }):wait(1000)
  if nightly.code == 0 and vim.trim(nightly.stdout or '')
    ~= vim.lsp.get_clients({ bufnr = 0, name = 'rust-analyzer' })[1].config.cmd[1] then
    second_checked = true
    vim.fn.writefile({ '[package]', 'name = "nvim-config-second-test"',
      'version = "0.1.0"', 'edition = "2021"' }, second_root .. '/Cargo.toml')
    local second_source = second_root .. '/src/lib.rs'
    vim.fn.writefile({ 'pub fn second() {}' }, second_source)
    local notices, old_notify = {}, vim.notify
    vim.notify = function(message) notices[#notices + 1] = tostring(message) end
    vim.cmd.edit(vim.fn.fnameescape(second_source))
    vim.wait(200)
    vim.notify = old_notify
    assert(#vim.lsp.get_clients({ bufnr = 0, name = 'rust-analyzer' }) == 0,
      'second toolchain attached to first project analyzer')
    assert(table.concat(notices, '\n'):find('another Rust toolchain', 1, true),
      'toolchain mismatch was not reported')
  end
end, debug.traceback)
vim.ui.select = old_select
vim.cmd('silent! bdelete!')
local first_buf = vim.fn.bufnr(source)
if first_buf > 0 and vim.api.nvim_buf_is_valid(first_buf) then
  vim.api.nvim_buf_delete(first_buf, { force = true })
end
vim.fn.delete(root, 'rf')
if second_root then vim.fn.delete(second_root, 'rf') end
if not ok then error(err) end
print('Rustaceanvim repeat command integration passed; second toolchain check: '
  .. (second_checked and 'passed' or 'skipped'))
