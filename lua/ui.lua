local M = {}

local paths = {}
local contexts = {}
local context_kinds = { [2] = true, [3] = true, [4] = true, [5] = true,
  [6] = true, [9] = true, [10] = true, [11] = true, [12] = true, [23] = true }
local function display_window()
  local win = tonumber(vim.g.statusline_winid)
  return win and vim.api.nvim_win_is_valid(win) and win or vim.api.nvim_get_current_win()
end

-- Navic's public get_data() uses one context cache per buffer. A winbar needs
-- each window's cursor, so use this guarded adapter until Navic exposes that.
local function symbol_data(buf, win)
  local ok, lib = pcall(require, 'nvim-navic.lib')
  if not ok or type(lib.update_context) ~= 'function' or type(lib.get_tree) ~= 'function' then
    return nil
  end
  local tree = lib.get_tree(buf)
  if not tree then return nil end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local cached = contexts[win]
  if cached and cached.buf == buf and cached.tree == tree
    and cached.line == cursor[1] and cached.col == cursor[2] then return cached.data end
  if not pcall(lib.update_context, buf, cursor) then return nil end
  local available, navic = pcall(require, 'nvim-navic')
  if not available then return nil end
  local data = navic.get_data(buf)
  contexts[win] = { buf = buf, tree = tree, line = cursor[1], col = cursor[2], data = data }
  return data
end

local function source_buffer()
  local win = display_window()
  if vim.api.nvim_win_get_config(win).relative ~= '' then return nil end
  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= '' or name == '' or name:find('://', 1, true) then return nil end
  return buf, name, win
end

local function shorten_left(value, limit)
  if limit <= 0 then return '' end
  if vim.fn.strdisplaywidth(value) <= limit then return value end
  while vim.fn.strdisplaywidth(value) > limit - 1 do
    value = vim.fn.strcharpart(value, 1)
  end
  return '…' .. value
end

local function shorten_right(value, limit)
  if limit <= 0 then return '' end
  if vim.fn.strdisplaywidth(value) <= limit then return value end
  while vim.fn.strdisplaywidth(value) > limit - 1 do
    value = vim.fn.strcharpart(value, 0, vim.fn.strchars(value) - 1)
  end
  return value .. '…'
end

function M.path()
  local buf, name, win = source_buffer()
  if not buf then return '' end
  local cached = paths[buf]
  local cwd = vim.fn.getcwd()
  if not cached or cached.name ~= name or (not cached.root and cached.base ~= cwd) then
    local root = vim.fs.root(name, '.git')
    local base = root or cwd
    paths[buf] = { name = name, root = root, base = base,
      path = vim.fs.relpath(base, name) or vim.fn.fnamemodify(name, ':t') }
    cached = paths[buf]
  end
  local path = shorten_left(cached.path, math.max(1, math.floor(vim.api.nvim_win_get_width(win) * 0.5)))
  return path:gsub('%%', '%%%%')
end

function M.context()
  local buf, _, win = source_buffer()
  if not buf then return '' end
  local available, navic = pcall(require, 'nvim-navic')
  if not available then return '' end
  if not navic.is_available(buf) then return '' end
  local names = {}
  for _, item in ipairs(symbol_data(buf, win) or {}) do
    if context_kinds[item.kind] then names[#names + 1] = item.name:gsub('[\r\n]', ' ') end
  end
  local limit = math.floor(vim.api.nvim_win_get_width(win) * 0.5)
  local result = ''
  for index = #names, 1, -1 do
    local candidate = names[index] .. (result ~= '' and ' > ' .. result or '')
    if vim.fn.strdisplaywidth(candidate) > limit then break end
    result = candidate
  end
  local context = result ~= '' and result or shorten_right(names[#names] or '', limit)
  return context:gsub('%%', '%%%%')
end

function M.setup()
  local group = vim.api.nvim_create_augroup('UserWinbarData', { clear = true })
  vim.api.nvim_create_autocmd('BufDelete', {
    group = group, callback = function(event)
      paths[event.buf] = nil
      for win, entry in pairs(contexts) do
        if entry.buf == event.buf then contexts[win] = nil end
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group, callback = function(event) contexts[tonumber(event.match)] = nil end,
  })
  vim.api.nvim_create_autocmd('LspDetach', {
    group = group, callback = function(event)
      if vim.b[event.buf].navic_client_id ~= event.data.client_id then return end
      for win, entry in pairs(contexts) do
        if entry.buf == event.buf then contexts[win] = nil end
      end
      vim.b[event.buf].navic_client_id = nil
      vim.b[event.buf].navic_client_name = nil
      local ok, lib = pcall(require, 'nvim-navic.lib')
      if ok and type(lib.clear_buffer_data) == 'function' then
        pcall(lib.clear_buffer_data, event.buf)
      end
      -- Navic 455808f keeps its buffer-local symbol requests after detach.
      -- Its next attach recreates them, so remove the old client's callbacks.
      pcall(vim.api.nvim_clear_autocmds, { group = 'navic', buffer = event.buf })
    end,
  })
end

return M
