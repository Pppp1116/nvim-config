local M = {}
M.show_all = false

-- Only known, low-priority Rust codes are quiet. New compiler/Clippy codes
-- remain visible until deliberately classified here.
local quiet = {
  unused_imports = true,
  unused_variables = true,
  unused_mut = true,
  unused_assignments = true,
  dead_code = true,
  non_snake_case = true,
  non_camel_case_types = true,
  non_upper_case_globals = true,
  clippy_unnecessary_cast = true,
  clippy_needless_return = true,
  clippy_redundant_clone = true,
}

local function code(d)
  local value = d.code
  if type(value) == 'table' then value = value.value end
  if type(value) ~= 'string' then return nil end
  return value:lower():gsub('^clippy::', 'clippy_'):gsub('%-', '_')
end

function M.quiet(d)
  return (d.source == 'rustc' or d.source == 'rust-analyzer') and quiet[code(d)] == true
end

-- A compiler diagnostic wins over a live analyzer diagnostic for the same
-- coded span. Both originals remain in Neovim's diagnostic store.
local function overlaps(a, b)
  if a.lnum ~= b.lnum then return false end
  local a_end = a.end_lnum == a.lnum and a.end_col or a.col + 1
  local b_end = b.end_lnum == b.lnum and b.end_col or b.col + 1
  return a.col < b_end and b.col < a_end
end

function M.visible(d, all)
  if M.quiet(d) then return false end
  local key = code(d)
  if d.source == 'rustc' and d.severity == vim.diagnostic.severity.HINT and key
    and not vim.tbl_get(d, 'user_data', 'lsp', 'data', 'rendered') then
    -- rust-analyzer also publishes rustc's secondary spans as hint diagnostics.
    -- Their primary diagnostic contains the full rendered note and related span.
    local related = vim.tbl_get(d, 'user_data', 'lsp', 'relatedInformation')
    for _, info in ipairs(type(related) == 'table' and related or {}) do
      local start = vim.tbl_get(info, 'location', 'range', 'start')
      if start then
        for _, other in ipairs(all) do
          if other ~= d and other.source == 'rustc' and code(other) == key
            and other.lnum == start.line and other.col == start.character
            and vim.tbl_get(other, 'user_data', 'lsp', 'data', 'rendered') then
            return false
          end
        end
      end
    end
  end
  if d.source ~= 'rust-analyzer' or not key then return true end
  for _, other in ipairs(all) do
    if other.source == 'rustc' and code(other) == key and overlaps(d, other) then
      return false
    end
  end
  return true
end

local function short_message(d)
  local message = d.message:match('^[^\n]*') or d.message
  if d.severity == vim.diagnostic.severity.ERROR then
    local detail = d.message:match('^[^\n]*\n([^\n]+)')
    if detail then message = message .. ' — ' .. detail end
  end
  local key = d.code
  if type(key) == 'table' then key = key.value end
  if key and key ~= '' then return ('[%s] %s'):format(key, message) end
  return message
end

function M.setup()
  -- Native handlers receive an aggregate Rust view. They never change the
  -- stored diagnostics, so floats, navigation, code actions and loclists see
  -- the full LSP result. Non-Rust buffers retain the native handlers.
  local display_ns = vim.api.nvim_create_namespace('rust-diagnostic-presentation')
  local handlers = {}
  local pending = {}
  local names = { 'virtual_text', 'signs', 'underline' }

  local function redraw(bufnr)
    pending[bufnr] = nil
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    if vim.bo[bufnr].filetype ~= 'rust' then return end
    if not vim.diagnostic.is_enabled({ bufnr = bufnr }) then
      for _, name in ipairs(names) do handlers[name].hide(display_ns, bufnr) end
      return
    end
    -- Native handlers defer until load, but their deferred callback would use
    -- positions captured here. Wait so we can clamp against the actual lines.
    if not vim.api.nvim_buf_is_loaded(bufnr) then return end
    local all = vim.diagnostic.get(bufnr, { enabled = true })
    local visible = {}
    for _, d in ipairs(all) do
      if M.show_all or M.visible(d, all) then visible[#visible + 1] = d end
    end
    -- vim.diagnostic.show() clamps cached positions before invoking handlers.
    -- Calling the handlers directly requires the same adjustment after filtering.
    local last_line = vim.api.nvim_buf_line_count(bufnr) - 1
    for _, d in ipairs(visible) do
      d.lnum = math.max(0, math.min(d.lnum, last_line))
      d.end_lnum = math.max(0, math.min(d.end_lnum, last_line))
      d.col = math.max(0, d.col)
      d.end_col = math.max(0, d.end_col)
    end
    local prominent = {}
    for _, d in ipairs(visible) do
      if d.severity == vim.diagnostic.severity.ERROR or d.severity == vim.diagnostic.severity.WARN then
        prominent[#prominent + 1] = d
      end
    end
    local config = vim.diagnostic.config()
    for _, name in ipairs(names) do
      handlers[name].hide(display_ns, bufnr)
      local enabled = config[name]
      if enabled then
        local opts = vim.tbl_extend('force', config, {
          [name] = type(enabled) == 'table' and vim.deepcopy(enabled) or {},
        })
        if name == 'virtual_text' then
          opts.virtual_text.format = short_message
        end
        handlers[name].show(display_ns, bufnr,
          name == 'underline' and not M.show_all and prominent or visible, opts)
      end
    end
  end

  local function schedule(bufnr)
    if pending[bufnr] then return end
    pending[bufnr] = true
    vim.schedule(function() redraw(bufnr) end)
  end

  function M.toggle_all()
    M.show_all = not M.show_all
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'rust' then
        schedule(bufnr)
      end
    end
  end

  for _, name in ipairs(names) do
    local original = vim.diagnostic.handlers[name]
    handlers[name] = original
    vim.diagnostic.handlers[name] = {
      show = function(ns, bufnr, diagnostics, opts)
        if vim.bo[bufnr].filetype == 'rust' then
          original.hide(ns, bufnr)
          schedule(bufnr)
        else
          original.show(ns, bufnr, diagnostics, opts)
        end
      end,
      hide = function(ns, bufnr)
        original.hide(ns, bufnr)
        if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == 'rust' then
          schedule(bufnr)
        end
      end,
    }
  end

  local group = vim.api.nvim_create_augroup('RustDiagnosticPresentation', { clear = true })
  vim.api.nvim_create_autocmd('BufReadPost', {
    group = group,
    callback = function(event)
      if vim.bo[event.buf].filetype == 'rust' then schedule(event.buf) end
    end,
  })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    callback = function(event)
      if vim.bo[event.buf].filetype == 'rust' then
        schedule(event.buf)
      else
        for _, name in ipairs(names) do handlers[name].hide(display_ns, event.buf) end
        vim.diagnostic.show(nil, event.buf)
      end
    end,
  })
end

return M
