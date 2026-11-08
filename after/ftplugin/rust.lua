-- Apostrophes start lifetimes as well as character literals in Rust.
-- Override mini.pairs for this key only; keep other pairs unchanged.
vim.keymap.set('i', "'", "'", { buffer = true, desc = 'Insert literal Rust apostrophe' })
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '') .. " | silent! iunmap <buffer> '"
