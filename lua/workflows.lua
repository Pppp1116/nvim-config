local M = {}
local build_job
local last_commands = {}
local terminal_cwd

local function current_list()
  if vim.bo.buftype ~= 'quickfix' then return nil end
  local is_loclist = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].loclist == 1
  if is_loclist then
    return vim.fn.getloclist(0, { items = 1, context = 1, filewinid = 1 }), true
  end
  return vim.fn.getqflist({ items = 1, context = 1 }), false
end

local function stop_build(force)
  local job = build_job
  if not job or (job.cancelled and not force) then return end
  job.cancelled = true
  -- Each build owns a process group, including compiler subprocesses.
  vim.uv.kill(-job.process.pid, force and 9 or 15)
  if not force then
    vim.defer_fn(function()
      if build_job == job then vim.uv.kill(-job.process.pid, 9) end
    end, 1000)
  end
end

function M.root()
  if vim.bo.buftype == 'terminal' then
    local cwd = terminal_cwd()
    if cwd then
      return vim.fs.root(cwd, { 'Cargo.toml', 'CMakeLists.txt', 'Makefile', '.git' }) or cwd
    end
  end
  local name = vim.api.nvim_buf_get_name(0)
  if name:match('^oil://') then
    local cwd = require('oil').get_current_dir()
    if cwd then
      return vim.fs.root(cwd, { 'Cargo.toml', 'CMakeLists.txt', 'Makefile', '.git' }) or cwd
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
        return vim.fs.root(filename, { 'Cargo.toml', 'CMakeLists.txt', 'Makefile', '.git' })
          or vim.fs.dirname(filename)
      end
    end
  end
  local start = name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd()
  return vim.fs.root(start, { 'Cargo.toml', 'CMakeLists.txt', 'Makefile', '.git' }) or vim.fn.getcwd()
end

function M.save_all()
  for _, info in ipairs(vim.fn.getbufinfo({ bufloaded = 1, bufmodified = 1 })) do
    local bufnr = info.bufnr
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local buftype = vim.bo[bufnr].buftype
      if vim.api.nvim_buf_get_name(bufnr) ~= '' and (buftype == '' or buftype == 'acwrite') then
        vim.api.nvim_buf_call(bufnr, function() vim.cmd.write() end)
      end
    end
  end
end

local function source_location(text)
  -- Keep spaces inside filenames; only trim diagnostic prefixes and outer padding.
  text = text:gsub('\27%[[%d;]*m', '')
  text = text:gsub('^%s*%-%->%s*', ''):gsub('^%s*:::%s*', '')
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
  local root = M.root()
  local filename = path
  if not path:match('^/') then
    local cwd = terminal_cwd()
    local candidates = {}
    if cwd then
      table.insert(candidates, cwd)
      local project = vim.fs.root(cwd, { 'Cargo.toml', 'CMakeLists.txt', 'Makefile', '.git' })
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
  local byte_col = math.max(0, (column or 1) - 1)
  local char_col = vim.str_byteindex(text, 'utf-32', byte_col, false)
  if char_col ~= byte_col then
    if vim.bo.filetype == 'rust' then
      byte_col = char_col
    else
      -- GCC counts characters; Clang counts bytes. Prefer the candidate at a token start.
      local function word_start(offset)
        return text:sub(offset + 1, offset + 1):match('[%w_]')
          and not text:sub(offset, offset):match('[%w_]')
      end
      if word_start(char_col) and not word_start(byte_col) then byte_col = char_col end
    end
  end
  vim.api.nvim_win_set_cursor(0, { target, math.min(byte_col, #text) })
  vim.cmd('normal! zz')
end

function M.build(command)
  if build_job then
    vim.notify('Build already running; :BuildStop cancels it', vim.log.levels.WARN)
    return
  end
  local root = M.root()
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
  local ok, err = pcall(M.save_all)
  if not ok then vim.notify(tostring(err), vim.log.levels.ERROR); return end
  last_commands[root] = command
  local efm = '%f:%l:%c: %m,%f:%l: %m,' .. vim.o.errorformat
  vim.notify('Building: ' .. command)
  local job = { cancelled = false }
  local started, process = pcall(vim.system, { vim.o.shell, '-c', command },
      { cwd = root, text = true, detach = true }, function(result)
    vim.schedule(function()
      if build_job == job then build_job = nil end
      if job.cancelled then
        vim.notify('Build cancelled', vim.log.levels.INFO)
        return
      end
      local succeeded = result.code == 0 and (result.signal or 0) == 0
      local stdout, stderr = result.stdout or '', result.stderr or ''
      local output = stdout .. (stdout ~= '' and stderr ~= '' and not stdout:match('\n$') and '\n' or '') .. stderr
      if not succeeded and output == '' then
        local reason = (result.signal or 0) ~= 0 and ('signal ' .. result.signal)
          or ('status ' .. tostring(result.code or 'unknown'))
        output = 'Build command ended with ' .. reason .. ' and produced no output'
      end
      local cwd = vim.fn.getcwd()
      -- Resolve relative compiler paths against the build directory.
      vim.fn.chdir(root)
      local parsed_ok, parsed_err = pcall(vim.fn.setqflist, {}, ' ', {
        title = command, lines = output == '' and {} or vim.split(output, '\n', { trimempty = true }), efm = efm,
        context = { cwd = root, exit_code = result.code },
      })
      vim.fn.chdir(cwd)
      if not parsed_ok then vim.notify(tostring(parsed_err), vim.log.levels.ERROR); return end
      if not succeeded or #vim.tbl_filter(function(item) return item.valid == 1 end, vim.fn.getqflist()) > 0 then
        vim.cmd.copen()
      else
        vim.cmd.cclose()
      end
      vim.notify(succeeded and 'Build succeeded' or 'Build failed; see quickfix',
        succeeded and vim.log.levels.INFO or vim.log.levels.WARN)
    end)
  end)
  if not started then
    vim.notify('Could not start build: ' .. tostring(process), vim.log.levels.ERROR)
    return
  end
  job.process = process
  build_job = job
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
        local root = M.root()
        local prefix = ft == 'rust' and '/target/debug/' or '/build/'
        local path = vim.fn.input('Executable: ', root .. prefix, 'file')
        if path == '' then return dap.ABORT end
        return vim.fn.fnamemodify(path, ':p')
      end,
      cwd = M.root, stopOnEntry = false,
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
  local map = vim.keymap.set
  map('n', '<leader>gg', '<cmd>Git<cr>', { desc = 'Git status' })
  map('n', '<leader>gb', '<cmd>Telescope git_branches<cr>', { desc = 'Git branches' })
  map('n', '<leader>gl', '<cmd>Telescope git_commits<cr>', { desc = 'Git commit log' })
  map('n', '<leader>gc', '<cmd>Git commit<cr>', { desc = 'Git commit' })
  map('n', '<leader>ug', function() require('gitsigns').toggle_signs() end, { desc = 'Toggle Git signs' })
  map('n', ']h', function() require('gitsigns').nav_hunk('next') end, { desc = 'Next Git hunk' })
  map('n', '[h', function() require('gitsigns').nav_hunk('prev') end, { desc = 'Previous Git hunk' })
  map('n', '<leader>hs', function() require('gitsigns').stage_hunk() end, { desc = 'Stage hunk' })
  map('n', '<leader>hp', function() require('gitsigns').preview_hunk() end, { desc = 'Preview hunk' })
  map('n', '<leader>hb', function() require('gitsigns').blame_line({ full = true }) end, { desc = 'Blame line' })
  map('n', '<leader>bb', function() M.build() end, { desc = 'Build / repeat build' })
  map('n', '<leader>bc', function()
    vim.ui.input({ prompt = 'Build command: ' }, function(input) if input and input ~= '' then M.build(input) end end)
  end, { desc = 'Set and run build command' })
  map('n', '<leader>bs', '<cmd>BuildStop<cr>', { desc = 'Stop build' })
  map('n', '<leader>bo', '<cmd>copen<cr>', { desc = 'Open build quickfix' })
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
