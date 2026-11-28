local M = {}
local build_job
local last_commands = {}
local last_tests = {}
local terminal_cwd

-- The pinned Overseer system strategy exposes its vim.SystemObj as
-- task.strategy.handle. Keep the process-group check here so a future strategy
-- change cannot turn a negative PID into a signal to an unrelated group.
local function process_identity(pid)
  local file = io.open('/proc/' .. tostring(pid) .. '/stat', 'r')
  if not file then return nil end
  local line = file:read('*l')
  file:close()
  local rest = line and line:match('^%d+ %b() (.+)$')
  if not rest then return nil end
  local fields = vim.split(rest, '%s+', { trimempty = true })
  return { group = tonumber(fields[3]), session = tonumber(fields[4]),
    start = tonumber(fields[20]) }
end

local function original_group_member(group, members)
  for pid, start in pairs(members) do
    local identity = process_identity(pid)
    if identity and identity.group == group and identity.session == group
      and identity.start == start then return true end
  end
  return false
end

local function group_members(group)
  local members = {}
  local ok, iterator = pcall(vim.fs.dir, '/proc')
  if not ok then return members end
  for name in iterator do
    local pid = tonumber(name)
    if pid then
      local identity = process_identity(pid)
      if identity and identity.group == group and identity.session == group then
        members[pid] = identity.start
      end
    end
  end
  return members
end

local function current_list()
  if vim.bo.buftype ~= 'quickfix' then return nil end
  local is_loclist = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].loclist == 1
  if is_loclist then
    return vim.fn.getloclist(0, { items = 1, context = 1, title = 1, filewinid = 1 }), true
  end
  return vim.fn.getqflist({ items = 1, context = 1, title = 1 }), false
end

local function stop_build(exiting)
  local task = build_job
  if not task then return false end
  local handle = task.strategy and task.strategy.handle
  local group, members
  if handle and handle.pid then
    local identity = process_identity(handle.pid)
    if identity and identity.group == handle.pid and identity.session == handle.pid then
      group = handle.pid
      members = group_members(group)
      vim.uv.kill(-group, 15)
    else
      vim.notify('Build process group could not be verified; stopping its task process only',
        vim.log.levels.WARN)
    end
  end
  local stopped, stop_err = pcall(task.stop, task)
  if not stopped then
    -- Overseer's pinned system strategy passes "SIGTERM" to SystemObj:kill,
    -- which Neovim 0.12 rejects. Task:stop has already marked it canceled.
    if tostring(stop_err):find('Invalid Signal name', 1, true) and handle then
      handle:kill(15)
    else
      vim.notify('Could not stop build task: ' .. tostring(stop_err), vim.log.levels.ERROR)
    end
  end
  if build_job == task then build_job = nil end
  if group and members and next(members) then
    local force = function()
      if original_group_member(group, members) then vim.uv.kill(-group, 9) end
    end
    if exiting then
      vim.wait(1000, function() return not original_group_member(group, members) end, 25)
      force()
    else
      vim.defer_fn(force, 1000)
    end
  end
  return true
end

local function current_path()
  if vim.bo.buftype == 'terminal' then
    local cwd = terminal_cwd()
    if cwd then return cwd end
  end
  local name = vim.api.nvim_buf_get_name(0)
  if name:match('^oil://') then
    local ok, oil = pcall(require, 'oil')
    if ok then
      local cwd = oil.get_current_dir()
      if cwd then return cwd end
    end
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
  local kind = text:match('^%s*at%s+') and 'backtrace' or 'compiler'
  text = text:gsub('^%s*%-%->%s*', ''):gsub('^%s*:::%s*', '')
  text = text:gsub('^%s*at%s+', '')
  text = text:gsub('^.-panicked at%s+', '')
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
  if path ~= '' and line and column and line > 0 and column > 0
    and line < math.huge and column < math.huge then
    return path, line, column, kind
  end
end
M.source_location = source_location

-- rustc columns count Unicode characters; the cursor API expects a byte offset.
function M.source_byte_column(text, column, rust, exact_byte)
  if type(column) ~= 'number' or column < 1 or column ~= math.floor(column) then return 0 end
  local offset = column - 1
  if exact_byte then return math.min(offset, #text) end
  if rust then
    local ok, byte = pcall(vim.str_byteindex, text, 'utf-32', offset, false)
    if ok then return math.min(byte, #text) end
  end
  -- Clang prints byte columns, while GCC prints character columns. With no
  -- reliable producer tag, prefer the candidate at a token start.
  local ok, character_byte = pcall(vim.str_byteindex, text, 'utf-32', offset, false)
  if ok and character_byte ~= offset then
    local function word_start(pos)
      return text:sub(pos + 1, pos + 1):match('[%w_]') ~= nil
        and text:sub(pos, pos):match('[%w_]') == nil
    end
    if word_start(character_byte) and not word_start(offset) then
      return math.min(character_byte, #text)
    end
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
  local output_buf = vim.api.nvim_get_current_buf()
  local count = vim.api.nvim_buf_line_count(output_buf)
  local function output_line(index)
    if index < 1 or index > count then return '' end
    return vim.api.nvim_buf_get_lines(output_buf, index - 1, index, false)[1] or ''
  end
  local path, line, column, kind = source_location(output_line(row))
  local list, is_loclist = current_list()
  if list then
    local items = list.items
    local function select_item(index)
      local item = items[index]
      if item and item.valid == 1 and item.bufnr > 0 then
        local filename = vim.api.nvim_buf_get_name(item.bufnr)
        if vim.fn.filereadable(filename) == 1 then
          path, line, column, kind = filename, item.lnum, item.col,
            list.title == 'Diagnostics' and 'diagnostic' or 'quickfix'
          return true
        end
        local parsed_path, parsed_line, parsed_column, parsed_kind = source_location(output_line(index))
        if parsed_path then
          path, line, column, kind = parsed_path, parsed_line, parsed_column, parsed_kind
          return true
        end
      end
    end
    if select_item(row) then goto open_location end
    if not diagnostic_heading(output_line(row)) then
      for index = row - 1, math.max(1, row - 12), -1 do
        if diagnostic_heading(output_line(index)) then break end
        if select_item(index) then goto open_location end
      end
    end
    for index = row + 1, math.min(#items, row + 12) do
      if diagnostic_heading(output_line(index)) then break end
      if select_item(index) then goto open_location end
    end
  end

  if not path then
    local heading = output_line(row)
    local forward_only = diagnostic_heading(heading) or heading:match('^%s*%d+:%s+')
    local search_backward, search_forward = not forward_only, true
    for distance = 1, 12 do
      local found = {}
      for _, direction in ipairs({ -1, 1 }) do
        if (direction == -1 and search_backward) or (direction == 1 and search_forward) then
          local index = row + distance * direction
          if index >= 1 and index <= count then
            local text = output_line(index)
            if diagnostic_heading(text) then
              if direction == -1 then search_backward = false else search_forward = false end
            else
              local candidate = { source_location(text) }
              if candidate[1] then found[#found + 1] = candidate end
            end
          end
        end
      end
      if #found > 1 and found[1][1] ~= found[2][1] then
        vim.notify('Multiple source locations are equally close', vim.log.levels.WARN)
        return
      end
      if #found > 0 then
        path, line, column, kind = unpack(found[1])
        break
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
        and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ''
    end
    if not editor_window(target) then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if editor_window(win) then target = win; break end
      end
    end
    if editor_window(target) then vim.api.nvim_set_current_win(target)
    else vim.cmd('botright new') end
  elseif vim.bo.buftype ~= '' then
    vim.cmd('botright new')
  end
  if vim.bo.modified and vim.api.nvim_buf_get_name(0) ~= filename then
    vim.cmd('botright new')
  end
  if vim.api.nvim_buf_get_name(0) ~= filename then
    vim.cmd.edit(vim.fn.fnameescape(filename))
  end
  local target = math.max(1, math.min(line or 1, vim.api.nvim_buf_line_count(0)))
  local text = vim.api.nvim_buf_get_lines(0, target - 1, target, false)[1]
  local byte_col = M.source_byte_column(text, column or 1,
    filename:match('%.rs$') ~= nil and kind ~= 'backtrace' and kind ~= 'diagnostic',
    kind == 'diagnostic')
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
    cmd = { vim.o.shell, '-c', command },
    cwd = root,
    strategy = { 'system', wrap_opts = { detach = true } },
    components = {
      { 'on_output_quickfix', errorformat = efm, relative_file_root = root,
        tail = false, open_on_exit = 'failure', open_on_match = true, close = true },
      'default',
    },
  })
  if not created or not task then
    vim.notify('Could not create ' .. label:lower() .. ' task: ' .. tostring(task), vim.log.levels.ERROR)
    return false
  end
  build_job = task
  local subscribed, subscribe_err = pcall(function()
    task:subscribe('on_complete', function(_, status)
      if build_job ~= task then return end
      build_job = nil
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
  end)
  if not subscribed then
    build_job = nil
    vim.notify('Could not subscribe to ' .. label:lower() .. ' task: ' ..
      tostring(subscribe_err), vim.log.levels.ERROR)
    return false
  end
  local started, result = pcall(function() return task:start() end)
  if not started or result ~= true then
    build_job = nil
    vim.notify('Could not start ' .. label:lower() .. ': ' ..
      (started and 'Overseer rejected the task; see :OverseerOpen' or tostring(result)), vim.log.levels.ERROR)
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
      -- nvim-dap requires a valid adapter table in the callback. Returning
      -- aborts this launch before it creates a session.
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
        path = vim.fn.fnamemodify(path, ':p')
        if vim.fn.executable(path) ~= 1 then
          vim.notify('Debug executable is missing or not executable: ' .. path, vim.log.levels.WARN)
          return dap.ABORT
        end
        return path
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
    stop_build(true)
  end })
  vim.api.nvim_create_user_command('Build', function(opts) M.build(opts.args) end, { nargs = '*', force = true })
  vim.api.nvim_create_user_command('BuildStop', function() stop_build(false) end, { force = true })
  vim.api.nvim_create_user_command('Test', function(opts) M.test(opts.args) end,
    { nargs = '?', complete = 'file', force = true })
  vim.api.nvim_create_user_command('TestRepeat', M.repeat_test, { force = true })
  local map = require('mappings').set
  local function git_command(name, command)
    return function()
      if vim.fn.executable('git') ~= 1 then
        vim.notify('Git is unavailable', vim.log.levels.WARN); return
      end
      if vim.fn.exists(':' .. name) == 0 then
        vim.notify(name .. ' plugin command is unavailable', vim.log.levels.WARN); return
      end
      vim.cmd(command)
    end
  end
  map('n', '<leader>gg', git_command('Git', 'Git'), { desc = 'Git status' })
  map('n', '<leader>gb', git_command('Telescope', 'Telescope git_branches'), { desc = 'Git branches' })
  map('n', '<leader>gl', git_command('Telescope', 'Telescope git_commits'), { desc = 'Git commit log' })
  map('n', '<leader>gc', git_command('Git', 'Git commit'), { desc = 'Git commit' })
  map('n', '<leader>gB', git_command('Git', 'Git blame'), { desc = 'Blame current file' })
  local function signs_plugin()
    local ok, signs = pcall(require, 'gitsigns')
    if not ok then vim.notify('Gitsigns is unavailable', vim.log.levels.WARN); return end
    return signs
  end
  map('n', '<leader>gu', function()
    local signs = signs_plugin()
    if signs then signs.toggle_signs() end
  end, { desc = 'Toggle Git signs' })
  map('n', '<leader>gi', function()
    local signs = signs_plugin()
    if signs then signs.toggle_current_line_blame() end
  end,
    { desc = 'Toggle inline Git blame' })
  map('n', ']h', function() require('gitsigns').nav_hunk('next') end, { desc = 'Next Git hunk' })
  map('n', '[h', function() require('gitsigns').nav_hunk('prev') end, { desc = 'Previous Git hunk' })
  local function git_action(method, hunk_required, opts)
    local signs = signs_plugin()
    if not signs then return end
    local hunks = vim.bo.buftype == '' and signs.get_hunks(0) or nil
    if not hunks then
      vim.notify('Git signs are unavailable for this buffer', vim.log.levels.WARN); return
    end
    if hunk_required and #hunks == 0 then
      vim.notify('No Git hunk in this file', vim.log.levels.INFO); return
    end
    signs[method](opts)
  end
  map('n', '<leader>gs', function() git_action('stage_hunk', true) end, { desc = 'Stage hunk' })
  map('n', '<leader>gp', function() git_action('preview_hunk', true) end, { desc = 'Preview hunk' })
  map('n', '<leader>gh', function() git_action('blame_line', false, { full = true }) end, { desc = 'Blame line' })
  map('n', '<leader>gd', function() git_action('diffthis', false) end, { desc = 'Diff file against Git index' })
  map('n', '<leader>bb', function() M.build() end, { desc = 'Build / repeat build' })
  map('n', '<leader>bc', function()
    vim.ui.input({ prompt = 'Build command: ' }, function(input) if input and input ~= '' then M.build(input) end end)
  end, { desc = 'Set and run build command' })
  map('n', '<leader>bs', '<cmd>BuildStop<cr>', { desc = 'Stop build' })
  map('n', '<leader>bo', '<cmd>copen<cr>', { desc = 'Open build quickfix' })
  map('n', '<leader>tt', function()
    if vim.bo.filetype == 'rust' then
      if #vim.lsp.get_clients({ bufnr = 0, name = 'rust-analyzer' }) == 0 then
        vim.notify('Rust Analyzer is not attached', vim.log.levels.WARN); return
      end
      vim.cmd('RustLsp testables')
    elseif vim.bo.filetype == 'llvm' then M.test()
    else vim.notify('No test selector for this filetype', vim.log.levels.WARN) end
  end, { desc = 'Select Rust tests or run current LLVM lit test' })
  map('n', '<leader>tr', function()
    if vim.bo.filetype == 'rust' then
      if #vim.lsp.get_clients({ bufnr = 0, name = 'rust-analyzer' }) == 0 then
        vim.notify('Rust Analyzer is not attached', vim.log.levels.WARN); return
      end
      vim.cmd('RustLsp! testables')
    elseif vim.bo.filetype == 'llvm' then M.repeat_test()
    else vim.notify('No repeatable test for this filetype', vim.log.levels.WARN) end
  end, { desc = 'Repeat previous Rust or LLVM test' })
  map('n', ']q', '<cmd>cnext<cr>', { desc = 'Next quickfix error' })
  map('n', '[q', '<cmd>cprevious<cr>', { desc = 'Previous quickfix error' })
  local function debug_key(key, method, description)
    map('n', key, function()
      local available, dap = pcall(require, 'dap')
      if not available then vim.notify('Debugger plugin is unavailable', vim.log.levels.WARN); return end
      if method == 'continue' and not dap.session() then
        if not dap.configurations[vim.bo.filetype] then
          vim.notify('No debugger configured for this filetype', vim.log.levels.WARN); return
        end
        if vim.fn.exepath('lldb-dap') == '' then
          vim.notify('lldb-dap is not on PATH', vim.log.levels.ERROR); return
        end
      elseif method == 'terminate' and not dap.session() then
        return
      elseif method == 'toggle_breakpoint' and (vim.bo.buftype ~= ''
        or vim.api.nvim_buf_get_name(0) == '') then
        vim.notify('Open a source file before setting a breakpoint', vim.log.levels.WARN)
        return
      elseif (method == 'step_over' or method == 'step_into' or method == 'step_out')
        and not dap.session() then
        vim.notify('No debugger session is active', vim.log.levels.WARN); return
      end
      dap[method]()
    end, { desc = description })
  end
  debug_key('<F10>', 'step_over', 'Debug step over')
  debug_key('<F11>', 'step_into', 'Debug step into')
  debug_key('<F12>', 'step_out', 'Debug step out')
  debug_key('<leader>db', 'toggle_breakpoint', 'Toggle breakpoint')
  debug_key('<leader>dc', 'continue', 'Debug start / continue')
  debug_key('<leader>dt', 'terminate', 'Terminate debugger')
  map('n', '<leader>dr', function()
    local available, dap = pcall(require, 'dap')
    if not available then vim.notify('Debugger plugin is unavailable', vim.log.levels.WARN); return end
    dap.repl.toggle()
  end, { desc = 'Debug console' })
  map('n', '<leader>dv', function()
    local available, dap = pcall(require, 'dap')
    if not available then vim.notify('Debugger plugin is unavailable', vim.log.levels.WARN); return end
    local session = dap.session()
    if not session or not session.current_frame then
      vim.notify('Pause the debugger to inspect variables', vim.log.levels.WARN); return
    end
    local widgets = require('dap.ui.widgets')
    widgets.centered_float(widgets.scopes)
  end, { desc = 'Debug variables / scopes' })
  map('n', '<leader>dh', function()
    local available, dap = pcall(require, 'dap')
    if not available then vim.notify('Debugger plugin is unavailable', vim.log.levels.WARN); return end
    local session = dap.session()
    if not session or not session.current_frame then
      vim.notify('Pause the debugger to inspect a value', vim.log.levels.WARN); return
    end
    require('dap.ui.widgets').hover()
  end, { desc = 'Debug value under cursor' })
end

return M
