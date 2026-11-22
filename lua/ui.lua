local M = {}

local paths = {}
local contexts = {}
local winbar = "%!v:lua.require'ui'.winbar()"
local context_kinds = { [2] = true, [3] = true, [4] = true, [5] = true,
  [6] = true, [9] = true, [10] = true, [11] = true, [12] = true, [23] = true }

local function source_buffer(win)
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative ~= '' then return nil end
  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= '' or name == '' or name:find('://', 1, true)
    or vim.bo[buf].filetype == 'oil' then return nil end
  return buf, name
end

local function display_path(buf, name)
  local cached = paths[buf]
  if cached and cached.name == name then return cached.path end
  -- Resolve once per buffer name, never while measuring or drawing the winbar.
  local root = vim.fs.root(name, '.git')
  local base = root or vim.fn.getcwd()
  local relative = vim.fs.relpath(base, name)
  local path = relative or vim.fn.fnamemodify(name, ':t')
  paths[buf] = { name = name, path = path }
  return path
end

local function shorten_left(value, limit)
  if limit <= 0 then return '' end
  if vim.fn.strdisplaywidth(value) <= limit then return value end
  if limit == 1 then return '…' end
  while vim.fn.strdisplaywidth(value) > limit - 1 do
    value = vim.fn.strcharpart(value, 1)
  end
  return '…' .. value
end

local function shorten_right(value, limit)
  if limit <= 0 then return '' end
  if vim.fn.strdisplaywidth(value) <= limit then return value end
  if limit == 1 then return '…' end
  while vim.fn.strdisplaywidth(value) > limit - 1 do
    value = vim.fn.strcharpart(value, 0, vim.fn.strchars(value) - 1)
  end
  return value .. '…'
end

local function context_for(win, buf)
  local navic = require('nvim-navic')
  if not navic.is_available(buf) then return '' end
  local lib = require('nvim-navic.lib')
  local tree = lib.get_tree(buf)
  if not tree then return '' end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local cached = contexts[win]
  if cached and cached.buf == buf and cached.tree == tree
    and cached.line == cursor[1] and cached.col == cursor[2] then return cached.value end
  -- Navic caches context per buffer; set it for this window's cursor before reading it.
  lib.update_context(buf, cursor)
  local names = {}
  for _, item in ipairs(navic.get_data(buf) or {}) do
    if context_kinds[item.kind] then names[#names + 1] = item.name:gsub('[\r\n]', ' ') end
  end
  local value = table.concat(names, ' > ')
  contexts[win] = { buf = buf, tree = tree, line = cursor[1], col = cursor[2], value = value }
  return value
end

local function fit_context(value, limit)
  if value == '' or limit <= 0 then return '' end
  local parts = vim.split(value, ' > ', { plain = true })
  local result = shorten_right(parts[#parts], limit)
  for index = #parts - 1, 1, -1 do
    local candidate = parts[index] .. ' > ' .. result
    if vim.fn.strdisplaywidth(candidate) > limit then break end
    result = candidate
  end
  return result
end

local function escape(value)
  return value:gsub('%%', '%%%%')
end

function M.winbar()
  local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local buf, name = source_buffer(win)
  if not buf then return '' end
  local path = display_path(buf, name)
  local width = vim.api.nvim_win_get_width(win) - 2
  if width <= 0 then return '' end
  local context = context_for(win, buf)
  local separator = ' > '
  local context_limit = math.min(math.floor(width * 0.5),
    width - math.min(vim.fn.strdisplaywidth(vim.fn.fnamemodify(name, ':t')), width) - #separator)
  context = fit_context(context, context_limit)
  if context == '' then return '%#UserWinBarPath# ' .. escape(shorten_left(path, width)) .. ' ' end
  path = shorten_left(path, width - vim.fn.strdisplaywidth(context) - #separator)
  return '%#UserWinBarPath# ' .. escape(path) .. '%#UserWinBarSeparator# > '
    .. '%#UserWinBarContext#' .. escape(context) .. ' '
end

function M.setup()
  local palette = require('catppuccin.palettes').get_palette('mocha')
  vim.api.nvim_set_hl(0, 'UserWinBarPath', { fg = palette.text, bg = palette.mantle })
  vim.api.nvim_set_hl(0, 'UserWinBarSeparator', { fg = palette.overlay1, bg = palette.mantle })
  vim.api.nvim_set_hl(0, 'UserWinBarContext', { fg = palette.subtext1, bg = palette.mantle })
  local group = vim.api.nvim_create_augroup('UserWinbar', { clear = true })
  local function update_window()
    local win = vim.api.nvim_get_current_win()
    local desired = source_buffer(win) and winbar or ''
    if vim.wo[win].winbar ~= desired then vim.wo[win].winbar = desired end
  end
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter', 'FileType', 'TermOpen' }, {
    group = group, callback = update_window,
  })
  vim.api.nvim_create_autocmd('BufDelete', {
    group = group, callback = function(event) paths[event.buf] = nil end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group, callback = function(event) contexts[tonumber(event.match)] = nil end,
  })
  vim.api.nvim_create_autocmd('LspDetach', {
    group = group, callback = function(event)
      if vim.b[event.buf].navic_client_id ~= event.data.client_id then return end
      vim.b[event.buf].navic_client_id = nil
      vim.b[event.buf].navic_client_name = nil
      require('nvim-navic.lib').clear_buffer_data(event.buf)
    end,
  })
  update_window()
end

return M
