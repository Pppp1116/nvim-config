local M = { declarations = {} }

function M.set(mode, lhs, rhs, opts)
  opts = opts or {}
  if not opts.buffer then
    local modes = type(mode) == 'table' and mode or { mode }
    for _, one_mode in ipairs(modes) do
      local key = one_mode .. '\0' .. lhs:gsub('<leader>', vim.g.mapleader)
      if M.declarations[key] then
        error('Duplicate custom mapping: ' .. one_mode .. ' ' .. lhs, 2)
      end
      M.declarations[key] = opts.desc or false
    end
  end
  vim.keymap.set(mode, lhs, rhs, opts)
end

return M
