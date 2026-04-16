--- aws.nvim – buffer and horizontal-split window helpers
local M = {}

---@type table<string, integer>  buf_name -> bufnr
local registry = {}

-------------------------------------------------------------------------------
-- Buffer management
-------------------------------------------------------------------------------

--- Return an existing valid buffer by name, or create a fresh scratch buffer.
---@param name     string  unique buffer name (shown in statusline / :ls)
---@param filetype string  value for &filetype
---@return integer bufnr
function M.get_or_create(name, filetype)
  local existing = registry[name]
  if existing and vim.api.nvim_buf_is_valid(existing) then
    return existing
  end

  local buf = vim.api.nvim_create_buf(true, true) -- listed=true, scratch=true
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide" -- keep buffer alive when window closes
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = filetype or "aws"

  -- Remove from registry when the buffer is wiped
  vim.api.nvim_buf_attach(buf, false, {
    on_detach = function()
      registry[name] = nil
    end,
  })

  registry[name] = buf
  return buf
end

--- Replace all content in a buffer (temporarily unlocks modifiable).
---@param buf   integer
---@param lines string[]
function M.set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- Write a "loading..." placeholder into the buffer.
---@param buf integer
function M.set_loading(buf)
  M.set_lines(buf, { "", "  Loading...", "" })
end

--- Write CLI error lines verbatim into the buffer.
---@param buf   integer
---@param lines string[]  raw stderr lines from the aws CLI
function M.set_error(buf, lines)
  local out = { "", "  [aws error]", "" }
  for _, l in ipairs(lines) do
    table.insert(out, "  " .. l)
  end
  M.set_lines(buf, out)
end

-------------------------------------------------------------------------------
-- Window / split management
-------------------------------------------------------------------------------

--- Open `buf` in a horizontal split, or focus the existing window showing it.
--- The split is opened at the bottom (`:split` + `:wincmd J`).
---@param buf integer
---@return integer winid
function M.open_split(buf)
  -- If a window already shows this buffer, just focus it.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_set_current_win(win)
      return win
    end
  end

  -- Create a new horizontal split and load the buffer into it.
  vim.cmd("split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.cmd("wincmd J") -- move to the very bottom

  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].signcolumn = "no"

  return win
end

--- Close the split window that is currently showing `buf`, if any.
---@param buf integer
function M.close_split(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_win_close(win, true)
      return
    end
  end
end

--- Open `buf` in a vertical split to the right, or focus the existing window.
---@param buf integer
---@return integer winid
function M.open_vsplit(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_set_current_win(win)
      return win
    end
  end

  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].signcolumn = "no"

  return win
end

--- Close the vsplit window showing `buf`, if any (alias for close_split).
---@param buf integer
function M.close_vsplit(buf)
  M.close_split(buf)
end

--- Return the window currently showing `buf`, or nil.
---@param buf integer
---@return integer|nil
function M.find_win(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
end

return M
