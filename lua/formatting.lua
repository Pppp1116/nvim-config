local M = {}
local busy = {}
local generation = {}

function M.eligible(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
    and vim.bo[buf].buftype == '' and vim.bo[buf].modifiable and not vim.bo[buf].readonly
    and vim.api.nvim_buf_get_name(buf) ~= ''
end

local function formatter(buf)
  local clients = vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/formatting' })
  table.sort(clients, function(a, b)
    local preferred = { ['rust-analyzer'] = 1, clangd = 1 }
    local ap, bp = preferred[a.name] or 2, preferred[b.name] or 2
    if ap ~= bp then return ap < bp end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  return clients[1]
end

function M.format(buf, asynchronous, timeout_ms)
  if not M.eligible(buf) then return false, 'Current buffer is not a writable named file' end
  local client = formatter(buf)
  if not client then return false, 'No formatter is attached' end
  if busy[buf] then return false, 'Formatting is already in progress' end
  busy[buf] = true
  generation[buf] = (generation[buf] or 0) + 1
  local token = generation[buf]
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local params = vim.lsp.util.make_formatting_params()
  local method = 'textDocument/formatting'
  local function apply(err, result)
    if generation[buf] ~= token then return end
    busy[buf] = nil
    if err then return false, 'Formatting failed: ' .. tostring(err) end
    if not M.eligible(buf) or vim.api.nvim_buf_get_name(buf) ~= name then return false end
    if #vim.lsp.get_clients({ bufnr = buf, id = client.id }) == 0 then
      return false, 'Formatting result skipped because the language server detached'
    end
    if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
      return false, 'Formatting result skipped because the buffer changed'
    end
    if result then
      local applied, apply_err = pcall(vim.lsp.util.apply_text_edits,
        result, buf, client.offset_encoding)
      if not applied then return false, 'Could not apply formatting: ' .. tostring(apply_err) end
    end
    return true
  end
  if asynchronous then
    local ok, requested, request_err = pcall(function()
      return client:request(method, params, function(err, result)
        local applied, message = apply(err, result)
        if message then vim.notify(message, vim.log.levels.WARN) end
      end, buf)
    end)
    if not ok or not requested then
      busy[buf] = nil
      generation[buf] = token + 1
      return false, tostring(ok and request_err or requested)
    end
    return true
  end
  local ok, result, err = pcall(client.request_sync, client, method, params, timeout_ms or 2000, buf)
  if not ok then busy[buf] = nil; return false, tostring(result) end
  return apply(err or (result and result.err), result and result.result)
end

function M.cancel(buf)
  generation[buf] = (generation[buf] or 0) + 1
  busy[buf] = nil
end

return M
