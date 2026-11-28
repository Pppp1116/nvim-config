local M = {}
local build_job
local last_commands = {}
local last_tests = {}
local terminal_cwd

local function current_list()
  if vim.bo.buftype ~= 'quickfix' then return nil end
  local is_loclist = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].loclist == 1
  if is_loclist then
    return vim.fn.getloclist(0, { items = 1, context = 1, filewinid = 1 }), true
  end
  return vim.fn.getqflist({ items = 1, context = 1 }), false
end

local function stop_build()
  local task = build_job
  if not task then return end
  local handle = task.strategy and task.strategy.handle
  if handle and handle.pid then
    -- Detached system tasks lead their process group; stop compiler children too.
    pcall(vim.uv.kill, -handle.pid, 15)
  end
  task:stop()
  if build_job == task then build_job = nil end
end

local function current_path()
  if vim.bo.buftype == 'terminal' then
    local cwd = terminal_cwd()
    if cwd then return cwd end
  end
  local name = vim.api.nvim_buf_get_name(0)
  if name:match('^oil://') then
    local cwd = require('oil').get_current_dir()
    if cwd then return cwd end
  end
  local list = current_list()
  if list then
    local context = list.context
    if type(context) == 'table' and type(context.cwd) == 'string'
        and vim.fn.isdirectory(context.cwd) == 1 then
      return context.cwd
    end
    local item = list.items[vim.fn.line('.')]
    if not item or item.valid ~= 1 then
      for _, candidate in ipairs(list.items) do
        if candidate.valid == 1 then item = candidate; break end
      end
    end
    if item and item.bufnr > 0 then
      local filename = vim.api.nvim_buf_get_name(item.bufnr)
      if filename ~= '' then
        return vim.fs.dirname(filename)
      end
    end
  end
  return name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd()
end

function M.project_root()
  local start = current_path()
  return vim.fs.root(start, '.git') or M.build_root(start)
end

function M.build_root(start)
  start = start or current_path()
  local git_root = vim.fs.root(start, '.git')
  local markers = { 'Cargo.toml', 'CMakeLists.txt', 'Makefile' }
  -- A repository-level build or configured build directory wins over nested CMakeLists.txt files.
  if git_root then
    if vim.fn.filereadable(vim.fs.joinpath(git_root, 'build/CMakeCache.txt')) == 1
        or vim.fn.filereadable(vim.fs.joinpath(git_root, 'llvm/CMakeLists.txt')) == 1 then
      return git_root
    end
    for _, marker in ipairs(markers) do
      if vim.fn.filereadable(vim.fs.joinpath(git_root, marker)) == 1 then return git_root end
    end
  end
  local dir = start
  while dir do
    for _, marker in ipairs(markers) do
      if vim.fn.filereadable(vim.fs.joinpath(dir, marker)) == 1 then return dir end
    end
    if dir == git_root then break end
    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then break end
    dir = parent
  end
  return git_root or start
end

function M.save_all()
  local failures = {}
  for _, info in ipairs(vim.fn.getbufinfo({ bufloaded = 1, bufmodified = 1 })) do
    local bufnr = info.bufnr
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local buftype = vim.bo[bufnr].buftype
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= '' and not name:find('://', 1, true) and buftype == '' then
        local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd.write() end)
        if not ok then
          failures[#failures + 1] = name .. ': ' .. tostring(err):match('^[^\n]+')
        elseif vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified then
          failures[#failures + 1] = name .. ': buffer remains modified after write'
        end
      end
    end
  end
  if #failures > 0 then
    vim.notify('Failed to save:\n' .. table.concat(failures, '\n'), vim.log.levels.ERROR)
    return false, failures
  end
  return true
end

local function source_location(text)
  -- Keep spaces inside filenames; only trim diagnostic prefixes and outer padding.
  text = text:gsub('\27%[[%d;]*m', '')
  text = text:gsub('^%s*%-%->%s*', ''):gsub('^%s*:::%s*', '')
  text = text:gsub('^%s*at%s+', '')
  text = vim.trim(text)
  local path, line, column = text:match('^(.-)|(%d+)%s+col%s+(%d+)|')
  if not path then path, line, column = text:match('^(.-)|(%d+)|%s*(%d+)') end
  if not path then path, line, column = text:match('^(.-):(%d+):(%d+)') end
  if not path then path, line = text:match('^(.-)|(%d+)|') end
  if not path then path, line = text:match('^(.-):(%d+)') end
  if not path then return end
  path = vim.trim(path)
  if (path:sub(1, 1) == '"' and path:sub(-1) == '"')
      or (path:sub(1, 1) == "'" and path:sub(-1) == "'") then
    path = path:sub(2, -2)
  end
  line, column = tonumber(line), tonumber(column) or 1
  if path ~= '' and line > 0 and column > 0 then return path, line, column end
end
M.source_location = source_location

-- rustc columns count Unicode characters; the cursor API expects a byte offset.
function M.source_byte_column(text, column, rust)
  if type(column) ~= 'number' or column < 1 or column ~= math.floor(column) then return 0 end
  local offset = column - 1
  if rust then
    local ok, byte = pcall(vim.str_byteindex, text, 'utf-32', offset, false)
    if ok then return math.min(byte, #text) end
  end
  return math.min(offset, #text)
end

local function diagnostic_heading(text)
  return text:match('^%s*error') or text:match('^%s*warning')
end

terminal_cwd = function()
  if vim.bo.buftype ~= 'terminal' then return nil end
  local job = vim.b.terminal_job_id
  if job then
    local ok, pid = pcall(vim.fn.jobpid, job)
    if ok and pid > 0 then
      local cwd = vim.fn.resolve('/proc/' .. pid .. '/cwd')
      if vim.fn.isdirectory(cwd) == 1 then
        vim.b.compiler_terminal_cwd = cwd
        return cwd
      end
    end
  end
  return vim.b.compiler_terminal_cwd
end

-- Jump from a quickfix entry or a rustc output line to its source location.
function M.jump_to_compiler_location()
  local row = vim.fn.line('.')
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local path, line, column = source_location(lines[row] or '')
  local list, is_loclist = current_list()
  if list then
    local items = list.items
    local function select_item(index)
      local item = items[index]
      if item and item.valid == 1 and item.bufnr > 0 then
        local filename = vim.api.nvim_buf_get_name(item.bufnr)
        if vim.fn.filereadable(filename) == 1 then
          path, line, column = filename, item.lnum, item.col
          return true
        end
        local parsed_path, parsed_line, parsed_column = source_location(lines[index] or '')
        if parsed_path then
          path, line, column = parsed_path, parsed_line, parsed_column
          return true
        end
      end
    end
    if select_item(row) then goto open_location end
    if not diagnostic_heading(lines[row] or '') then
      for index = row - 1, math.max(1, row - 12), -1 do
        if diagnostic_heading(lines[index]) then break end
        if select_item(index) then goto open_location end
      end
    end
    for index = row + 1, math.min(#items, row + 12) do
      if diagnostic_heading(lines[index]) then break end
      if select_item(index) then goto open_location end
    end
  end

  if not path then
    if not diagnostic_heading(lines[row] or '') then
      for index = row - 1, math.max(1, row - 12), -1 do
        if diagnostic_heading(lines[index]) then break end
        path, line, column = source_location(lines[index])
        if path then break end
      end
    end
    if not path then
      for index = row + 1, math.min(#lines, row + 12) do
        if diagnostic_heading(lines[index]) then break end
        path, line, column = source_location(lines[index])
        if path then break end
      end
    end
  end
  if not path then
    vim.notify('No source location near this diagnostic', vim.log.levels.WARN)
    return
  end

  ::open_location::
  local root = M.project_root()
  local filename = path
  if not path:match('^/') then
    local cwd = terminal_cwd()
    local candidates = {}
    if cwd then
      table.insert(candidates, cwd)
      local project = vim.fs.root(cwd, '.git') or M.build_root(cwd)
      if project then table.insert(candidates, project) end
    end
    table.insert(candidates, root)
    table.insert(candidates, vim.fn.getcwd())
    for _, dir in ipairs(candidates) do
      local candidate = vim.fs.joinpath(dir, path)
      if vim.fn.filereadable(candidate) == 1 then filename = candidate; break end
    end
  end
  if vim.fn.filereadable(filename) == 0 then
    vim.notify('Source file not found: ' .. path, vim.log.levels.WARN)
    return
  end
  if list then
    local target = is_loclist and list.filewinid or vim.fn.win_getid(vim.fn.winnr('#'))
    local function editor_window(win)
      return win and win > 0 and vim.api.nvim_win_is_valid(win)
        and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
        and vim.fn.getwininfo(win)[1].quickfix == 0
    end
    if not editor_window(target) then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if editor_window(win) then target = win; break end
      end
    end
    if editor_window(target) then vim.api.nvim_set_current_win(target) end
  end
  vim.cmd.edit(vim.fn.fnameescape(filename))
  local target = math.max(1, math.min(line or 1, vim.api.nvim_buf_line_count(0)))
  local text = vim.api.nvim_buf_get_lines(0, target - 1, target, false)[1]
  local byte_col = M.source_byte_column(text, column or 1, vim.bo.filetype == 'rust')
  vim.api.nvim_win_set_cursor(0, { target, math.min(byte_col, #text) })
  vim.cmd('normal! zz')
end

local function run_command(command, root, label)
  if build_job then
    vim.notify('Command already running; :BuildStop cancels it', vim.log.levels.WARN)
    return
  end
  if not M.save_all() then return false end
  local loaded, overseer = pcall(require, 'overseer')
  if not loaded then
    vim.notify('Install Overseer with :Lazy install overseer.nvim', vim.log.levels.ERROR)
    return false
  end
  local efm = '%f:%l:%c: %m,%f:%l: %m,' .. vim.o.errorformat
  local created, task = pcall(overseer.new_task, {
    name = label .. ': ' .. command,
    cmd = command,
    cwd = root,
    strategy = { 'system', wrap_opts = { detach = true } },
    components = {
      { 'on_output_quickfix', errorformat = efm, relative_file_root = root,
        tail = false, open_on_exit = 'failure', open_on_match = true, close = true },
      'default',
    },
  })
  if not created then
    vim.notify('Could not create ' .. label:lower() .. ' task: ' .. tostring(task), vim.log.levels.ERROR)
    return false
  end
  build_job = task
  task:subscribe('on_complete', function(_, status)
    if build_job == task then build_job = nil end
    if status ~= overseer.STATUS.FAILURE then return end
    local list = vim.fn.getqflist({ context = 1, items = 1 })
    if list.context ~= task.id then return end
    local has_output = false
    for _, item in ipairs(list.items) do
      if item.valid == 1 then return end
      if vim.trim(item.text) ~= '' and not item.text:match('^%[Process exited %d+%]$') then
        has_output = true
      end
    end
    if not has_output then
      vim.fn.setqflist({}, 'r', { title = task.name, context = task.id,
        items = { { text = label .. ' failed (exit status ' .. tostring(task.exit_code or 'unknown') .. ')' } } })
    end
    vim.cmd.copen()
  end)
  local started, start_err = pcall(function() task:start() end)
  if not started then
    build_job = nil
    vim.notify('Could not start ' .. label:lower() .. ': ' .. tostring(start_err), vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.build(command)
  local root = M.build_root()
  if not command or command == '' then
    command = last_commands[root]
    if not command then
      if vim.fn.filereadable(root .. '/Cargo.toml') == 1 then
        command = 'cargo build --message-format=short'
      elseif vim.fn.filereadable(root .. '/build/CMakeCache.txt') == 1 then
        command = 'cmake --build build'
      elseif vim.fn.filereadable(root .. '/Makefile') == 1 then
        command = 'make'
      else
        vim.ui.input({ prompt = 'Build command: ' }, function(input)
          if input and input ~= '' then M.build(input) end
        end)
        return
      end
    end
  end
  if run_command(command, root, 'Build') then last_commands[root] = command end
end

function M.test(path)
  if (not path or path == '') and vim.bo.filetype ~= 'llvm' then
    vim.notify('Select a Rust test in a Rust buffer or pass an LLVM lit path to :Test', vim.log.levels.WARN)
    return false
  end
  local root = M.project_root()
  if not path or path == '' then path = vim.api.nvim_buf_get_name(0) end
  if path == '' then vim.notify('Choose a lit test with :Test path', vim.log.levels.WARN); return end
  local target = path:match('^/') and path or vim.fs.joinpath(root, path)
  if vim.fn.filereadable(target) == 0 and vim.fn.isdirectory(target) == 0 then
    vim.notify('Test path not found: ' .. target, vim.log.levels.ERROR)
    return
  end
  local lit = vim.fs.joinpath(root, 'build/bin/llvm-lit')
  if vim.fn.executable(lit) ~= 1 then lit = vim.fn.exepath('llvm-lit') end
  if lit == '' then vim.notify('llvm-lit is not available in build/bin or PATH', vim.log.levels.ERROR); return end
  local command = vim.fn.shellescape(lit) .. ' ' .. vim.fn.shellescape(target)
  if run_command(command, root, 'Test') then last_tests[root] = command end
end

function M.repeat_test()
  local root = M.project_root()
  local command = last_tests[root]
  if not command then vim.notify('No test to repeat for this project', vim.log.levels.WARN); return end
  run_command(command, root, 'Test')
end

function M.setup_debugger()
  local dap = require('dap')
  dap.adapters.lldb = function(callback)
    local command = vim.fn.exepath('lldb-dap')
    if command == '' then
      vim.notify('lldb-dap is not on PATH. Install the system LLDB package.', vim.log.levels.ERROR)
      return
    end
    callback({ type = 'executable', command = command })
  end
  for _, ft in ipairs({ 'rust', 'c', 'cpp', 'asm', 'nasm' }) do
    dap.configurations[ft] = { {
      name = 'Launch executable (system LLDB)', type = 'lldb', request = 'launch',
      program = function()
        local root = M.build_root()
        local prefix = ft == 'rust' and '/target/debug/' or '/build/'
        local path = vim.fn.input('Executable: ', root .. prefix, 'file')
        if path == '' then return dap.ABORT end
        return vim.fn.fnamemodify(path, ':p')
      end,
      cwd = M.build_root, stopOnEntry = false,
    } }
  end
  -- External tools are managed outside Neovim; loading DAP never downloads them.
end

function M.setup()
  vim.opt.autoread = true
  local group = vim.api.nvim_create_augroup('UserExternalReload', { clear = true })
  local jump_group = vim.api.nvim_create_augroup('UserCompilerOutputJump', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = jump_group,
    pattern = 'qf',
    callback = function(event)
      vim.keymap.set('n', 'gd', M.jump_to_compiler_location,
        { buffer = event.buf, desc = 'Go to compiler source location' })
    end,
  })
  vim.api.nvim_create_autocmd('TermOpen', {
    group = jump_group,
    callback = function(event)
      vim.b[event.buf].compiler_terminal_cwd = vim.fn.getcwd()
      vim.keymap.set('n', 'gd', M.jump_to_compiler_location,
        { buffer = event.buf, desc = 'Go to compiler source location' })
      if event.buf == vim.api.nvim_get_current_buf() then vim.cmd.startinsert() end
    end,
  })
  vim.api.nvim_create_autocmd('TermRequest', {
    group = jump_group,
    callback = function(event)
      if vim.bo[event.buf].buftype ~= 'terminal' then return end
      local host, encoded_path = event.data.sequence:match('^\27%]7;file://([^/]*)(/[^%c]*)')
      if not host or (host ~= '' and host ~= 'localhost' and host ~= vim.uv.os_gethostname()) then return end
      local cwd = vim.uri_decode(encoded_path)
      if vim.fn.isdirectory(cwd) == 1 then vim.b[event.buf].compiler_terminal_cwd = cwd end
    end,
    desc = 'Remember terminal shell directory from OSC 7',
  })
  vim.api.nvim_create_autocmd({ 'FocusGained', 'TermClose' }, {
    group = group, callback = function() vim.cmd('checktime') end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = function()
    stop_build()
  end })
  vim.api.nvim_create_user_command('Build', function(opts) M.build(opts.args) end, { nargs = '*', force = true })
  vim.api.nvim_create_user_command('BuildStop', stop_build, { force = true })
  vim.api.nvim_create_user_command('Test', function(opts) M.test(opts.args) end,
    { nargs = '?', complete = 'file', force = true })
  vim.api.nvim_create_user_command('TestRepeat', M.repeat_test, { force = true })
  local map = vim.keymap.set
  map('n', '<leader>gg', '<cmd>Git<cr>', { desc = 'Git status' })
  map('n', '<leader>gb', '<cmd>Telescope git_branches<cr>', { desc = 'Git branches' })
  map('n', '<leader>gl', '<cmd>Telescope git_commits<cr>', { desc = 'Git commit log' })
  map('n', '<leader>gc', '<cmd>Git commit<cr>', { desc = 'Git commit' })
  map('n', '<leader>gB', '<cmd>Git blame<cr>', { desc = 'Blame current file' })
  map('n', '<leader>gu', function() require('gitsigns').toggle_signs() end, { desc = 'Toggle Git signs' })
  map('n', '<leader>gi', function() require('gitsigns').toggle_current_line_blame() end,
    { desc = 'Toggle inline Git blame' })
  map('n', ']h', function() require('gitsigns').nav_hunk('next') end, { desc = 'Next Git hunk' })
  map('n', '[h', function() require('gitsigns').nav_hunk('prev') end, { desc = 'Previous Git hunk' })
  map('n', '<leader>gs', function() require('gitsigns').stage_hunk() end, { desc = 'Stage hunk' })
  map('n', '<leader>gp', function() require('gitsigns').preview_hunk() end, { desc = 'Preview hunk' })
  map('n', '<leader>gh', function() require('gitsigns').blame_line({ full = true }) end, { desc = 'Blame line' })
  map('n', '<leader>gd', function() require('gitsigns').diffthis() end, { desc = 'Diff file against Git index' })
  map('n', '<leader>bb', function() M.build() end, { desc = 'Build / repeat build' })
  map('n', '<leader>bc', function()
    vim.ui.input({ prompt = 'Build command: ' }, function(input) if input and input ~= '' then M.build(input) end end)
  end, { desc = 'Set and run build command' })
  map('n', '<leader>bs', '<cmd>BuildStop<cr>', { desc = 'Stop build' })
  map('n', '<leader>bo', '<cmd>copen<cr>', { desc = 'Open build quickfix' })
  map('n', '<leader>tt', function()
    if vim.bo.filetype == 'rust' then vim.cmd('RustLsp testables')
    elseif vim.bo.filetype == 'llvm' then M.test()
    else vim.notify('No test selector for this filetype', vim.log.levels.WARN) end
  end, { desc = 'Select Rust tests or run current LLVM lit test' })
  map('n', '<leader>tr', function()
    if vim.bo.filetype == 'rust' then vim.cmd('RustLsp! testables')
    elseif vim.bo.filetype == 'llvm' then M.repeat_test()
    else vim.notify('No repeatable test for this filetype', vim.log.levels.WARN) end
  end, { desc = 'Repeat previous Rust or LLVM test' })
  map('n', ']q', '<cmd>cnext<cr>', { desc = 'Next quickfix error' })
  map('n', '[q', '<cmd>cprevious<cr>', { desc = 'Previous quickfix error' })
  local function debug_key(key, method, description)
    map('n', key, function() require('dap')[method]() end, { desc = description })
  end
  debug_key('<F10>', 'step_over', 'Debug step over')
  debug_key('<F11>', 'step_into', 'Debug step into')
  debug_key('<F12>', 'step_out', 'Debug step out')
  debug_key('<leader>db', 'toggle_breakpoint', 'Toggle breakpoint')
  debug_key('<leader>dc', 'continue', 'Debug start / continue')
  debug_key('<leader>dt', 'terminate', 'Terminate debugger')
  map('n', '<leader>dr', function() require('dap').repl.toggle() end, { desc = 'Debug console' })
  map('n', '<leader>dv', function()
    local widgets = require('dap.ui.widgets')
    widgets.centered_float(widgets.scopes)
  end, { desc = 'Debug variables / scopes' })
  map('n', '<leader>dh', function() require('dap.ui.widgets').hover() end, { desc = 'Debug value under cursor' })
end

return M
