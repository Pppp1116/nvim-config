local M = {}
local cache = {}
local last_notice = {}
local start_cwd

local function notify_once(cwd, message)
  local key = cwd .. '\0' .. message
  local now = vim.uv.now()
  if not last_notice[key] or now - last_notice[key] > 10000 then
    last_notice[key] = now
    vim.notify('Rust Analyzer: ' .. message .. ' (' .. cwd .. ')', vim.log.levels.ERROR)
  end
end

function M.resolve(cwd)
  cwd = cwd or vim.fn.getcwd()
  local now = vim.uv.now()
  local cached = cache[cwd]
  if cached and now - cached.time < 5000
    and (not cached.path or vim.fn.executable(cached.path) == 1) then
    return cached.path
  end
  local path, message
  if not vim.uv.fs_stat(cwd) then
    message = 'project directory does not exist'
  elseif vim.fn.executable('rustup') ~= 1 then
    message = 'rustup is unavailable'
  else
    local ok, process = pcall(vim.system, { 'rustup', 'which', 'rust-analyzer' },
      { cwd = cwd, text = true })
    if not ok then
      message = 'could not start rustup: ' .. tostring(process)
    else
      -- wait(timeout) returns code 124 and kills the process on timeout.
      local waited, result = pcall(process.wait, process, 2000)
      if not waited then
        message = 'rustup failed: ' .. tostring(result)
      elseif not result or result.code == 124 then
        message = 'rustup timed out after 2 seconds'
      elseif result.code ~= 0 then
        message = 'rustup could not find rust-analyzer for this toolchain: '
          .. vim.trim(result.stderr or '')
      else
        local candidate = vim.trim(result.stdout or '')
        if candidate:match('^/') and vim.fn.executable(candidate) == 1 then
          path = candidate
        else
          message = 'rustup returned an invalid rust-analyzer path'
        end
      end
    end
  end
  cache[cwd] = { path = path, time = now }
  if message then notify_once(cwd, message) end
  return path
end

function M.auto_attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= '' then return false end
  local file = vim.api.nvim_buf_get_name(buf)
  if file == '' then return false end
  if not vim.uv.fs_stat(file) then
    -- Rustaceanvim only calls auto_attach when its ftplugin first loads. A
    -- newly named file can become a real project file after the first save.
    vim.api.nvim_create_autocmd('BufWritePost', {
      buffer = buf, once = true,
      callback = function()
        if M.auto_attach(buf) then
          local ok, err = pcall(function() require('rustaceanvim.lsp').start(buf) end)
          if not ok then vim.notify('Rust Analyzer: could not attach after save: '
            .. tostring(err), vim.log.levels.ERROR) end
        end
      end,
    })
    return false
  end
  local cwd = vim.fs.dirname(file)
  local path = M.resolve(cwd)
  if not path then return false end
  -- Rustaceanvim shares a running client with additional workspaces before
  -- evaluating cmd. Do not attach a project that requires another binary.
  for _, client in ipairs(vim.lsp.get_clients({ name = 'rust-analyzer' })) do
    if type(client.config.cmd) == 'table' and client.config.cmd[1] ~= path then
      notify_once(cwd, 'another Rust toolchain is already active; open this project in another Neovim instance')
      return false
    end
  end
  return true
end

function M.set_start_root(root)
  start_cwd = root
end

function M.command()
  local cwd = start_cwd or vim.fn.expand('%:p:h')
  start_cwd = nil
  if cwd == '' then cwd = vim.fn.getcwd() end
  local path = M.resolve(cwd)
  -- Rustaceanvim 8 checks an empty command and returns before vim.lsp.start.
  return path and { path } or {}
end

return M
