local M = {}

-- Insert line into buffer:
-- If current line is empty, replace it. Otherwise, insert on the next line.
-- Moves cursor to end of the newly inserted line.
function M.insert_chapter_line(bufnr, text)
  bufnr = bufnr or 0
  local win = 0
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row = cursor[1] -- 1-indexed

  local current_line = (vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false))[1] or ""

  local target_row
  if current_line:match("^%s*$") then
    -- Current line is blank, replace it
    vim.api.nvim_buf_set_lines(bufnr, row - 1, row, false, { text })
    target_row = row
  else
    -- Insert below current line
    vim.api.nvim_buf_set_lines(bufnr, row, row, false, { text })
    target_row = row + 1
  end

  -- Move cursor to target_row, end of text
  vim.api.nvim_win_set_cursor(win, { target_row, #text })
end

-- Keymap management
local active_keymaps = {} -- bufnr -> list of lhs

local function resolve_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

function M.setup_keymaps(bufnr, keymaps)
  bufnr = resolve_bufnr(bufnr)
  M.clear_keymaps(bufnr)

  local bound_keys = {}
  for lhs, rhs in pairs(keymaps) do
    vim.keymap.set("n", lhs, rhs, {
      buffer = bufnr,
      nowait = true,
      silent = true,
      desc = "Video Analysis: " .. lhs,
    })
    table.insert(bound_keys, lhs)
  end

  active_keymaps[bufnr] = bound_keys
end

function M.clear_keymaps(bufnr)
  bufnr = resolve_bufnr(bufnr)
  local keys = active_keymaps[bufnr]
  if not keys then
    return
  end

  for _, lhs in ipairs(keys) do
    pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
  end

  active_keymaps[bufnr] = nil
end

return M
