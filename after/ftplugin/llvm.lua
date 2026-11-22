-- llvm-as catches IR syntax and type errors without creating a .bc file.
vim.bo.commentstring = '; %s'
vim.bo.shiftwidth = 2
vim.bo.softtabstop = 2

local buf = vim.api.nvim_get_current_buf()
local ns = vim.api.nvim_create_namespace('UserLLVMAs')
local run = 0

local function check()
  if vim.fn.executable('llvm-as') ~= 1 then
    vim.notify('llvm-as is not on PATH', vim.log.levels.WARN)
    return
  end
  run = run + 1
  local this_run = run
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local source = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. '\n'
  vim.system({ 'llvm-as', '--disable-output', '-' }, { stdin = source, text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'llvm' or this_run ~= run
          or vim.api.nvim_buf_get_changedtick(buf) ~= tick then return end
      local diagnostics = {}
      for line in (result.stderr or ''):gmatch('[^\r\n]+') do
        local row, col, severity, message = line:match('^llvm%-as: <stdin>:(%d+):(%d+): (%w+): (.+)$')
        if row then
          diagnostics[#diagnostics + 1] = {
            lnum = tonumber(row) - 1,
            col = tonumber(col) - 1,
            severity = severity == 'warning' and vim.diagnostic.severity.WARN or vim.diagnostic.severity.ERROR,
            message = message,
            source = 'llvm-as',
          }
        end
      end
      vim.diagnostic.set(ns, buf, diagnostics)
      if result.code ~= 0 and #diagnostics == 0 then
        vim.notify('llvm-as failed: ' .. vim.trim(result.stderr or ''), vim.log.levels.WARN)
      end
    end)
  end)
end

vim.api.nvim_buf_create_user_command(buf, 'LLVMCheck', check, { desc = 'Validate LLVM IR with llvm-as' })
vim.keymap.set('n', '<leader>lc', check, { buffer = buf, desc = 'Validate LLVM IR' })
local check_autocmd = vim.api.nvim_create_autocmd('BufWritePost', {
  buffer = buf, callback = check, desc = 'Validate saved LLVM IR',
})
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '')
  .. (' | call nvim_del_autocmd(%d)'):format(check_autocmd)
  .. (" | call luaeval('vim.diagnostic.reset(_A[1], _A[2])', [%d, %d])"):format(ns, buf)
  .. ' | silent! delcommand LLVMCheck | silent! nunmap <buffer> <leader>lc'
  .. ' | setlocal commentstring< shiftwidth< softtabstop<'
