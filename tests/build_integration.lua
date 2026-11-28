local function check(value, message)
  if not value then error(message, 2) end
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local script = root .. '/stubborn.py'
local parent_file = root .. '/parent.pid'
local child_file = root .. '/child.pid'
vim.fn.writefile({
  'import os, signal, subprocess, sys, time',
  'signal.signal(signal.SIGTERM, signal.SIG_IGN)',
  'child = subprocess.Popen([sys.executable, "-c", "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)"])',
  'open(sys.argv[1], "w").write(str(os.getpid()))',
  'open(sys.argv[2], "w").write(str(child.pid))',
  'child.wait()',
}, script)

local old_cwd = vim.fn.getcwd()
local function running(pid)
  if not pid then return false end
  local file = io.open('/proc/' .. pid .. '/stat', 'r')
  if not file then return false end
  local line = file:read('*l') or ''
  file:close()
  return not line:match('^%d+ %b() Z ')
end
local parent, child
local ok, err = xpcall(function()
  vim.api.nvim_set_current_dir(root)
  local command = 'python3 ' .. vim.fn.shellescape(script) .. ' '
    .. vim.fn.shellescape(parent_file) .. ' ' .. vim.fn.shellescape(child_file)
  require('workflows').build(command)
  check(vim.wait(2000, function() return vim.fn.filereadable(child_file) == 1 end, 20),
    'build did not start a child process')
  parent = tonumber(vim.fn.readfile(parent_file)[1])
  child = tonumber(vim.fn.readfile(child_file)[1])
  check(running(parent) and running(child), 'build processes disappeared before cancellation')
  vim.cmd.BuildStop()
  vim.cmd.BuildStop()
  require('workflows').build('sleep 0.2')
  check(vim.wait(2500, function() return not running(parent) and not running(child) end, 25),
    'cancellation left a SIGTERM-ignoring build process alive')
  vim.wait(300)
  local overseer = require('overseer')
  local canceled = false
  local output_buf
  for _, task in ipairs(overseer.list_tasks()) do
    if task.name:find('stubborn.py', 1, true) and task.status == overseer.STATUS.CANCELED then
      canceled = true
    end
    if task.name == 'Build: sleep 0.2' then output_buf = task:get_bufnr() end
  end
  check(canceled, 'canceled task was reported as a failure')
  check(output_buf and vim.api.nvim_buf_is_valid(output_buf), 'Overseer output buffer missing')
  vim.api.nvim_set_current_buf(output_buf)
  local old_notify = vim.notify
  vim.notify = function() end
  for _, key in ipairs({ ' cf', ' ca', ' cr', ' gs', ' gp', ' gd', ' tt', ' tr' }) do
    local callback = vim.fn.maparg(key, 'n', false, true).callback
    check(type(callback) == 'function' and pcall(callback),
      'mapping failed in Overseer output: ' .. key)
  end
  vim.notify = old_notify
  require('workflows').build('false')
  check(vim.wait(1000, function()
    for _, task in ipairs(overseer.list_tasks()) do
      if task.name == 'Build: false' and task.status == overseer.STATUS.FAILURE then return true end
    end
    return false
  end, 20), 'failed task was not distinguishable from cancellation')
  local second_parent, second_child = root .. '/exit-parent.pid', root .. '/exit-child.pid'
  require('workflows').build('python3 ' .. vim.fn.shellescape(script) .. ' '
    .. vim.fn.shellescape(second_parent) .. ' ' .. vim.fn.shellescape(second_child))
  check(vim.wait(2000, function() return vim.fn.filereadable(second_child) == 1 end, 20),
    'exit test build did not start')
  parent, child = tonumber(vim.fn.readfile(second_parent)[1]),
    tonumber(vim.fn.readfile(second_child)[1])
  vim.api.nvim_exec_autocmds('VimLeavePre', {})
  check(vim.wait(500, function() return not running(parent) and not running(child) end, 20),
    'Neovim exit left a build subprocess alive')
end, debug.traceback)
if not ok then
  if running(parent) then vim.uv.kill(parent, 9) end
  if running(child) then vim.uv.kill(child, 9) end
end
vim.api.nvim_set_current_dir(old_cwd)
vim.fn.delete(root, 'rf')
if not ok then error(err) end
print('build cancellation integration passed')
