--- aws.nvim – S3 buckets list, filter, and render
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local BUF_NAME = "aws://s3/buckets"
local FILETYPE = "aws-s3"

local _buckets  = {}
local _filter   = ""
local _line_map = {}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

--- Left-pad `s` with spaces to at least `width` characters (no 99-char limit).
---@param s     string
---@param width integer
---@return string
local function pad_right(s, width)
  local len = #s
  if len >= width then return s end
  return s .. string.rep(" ", width - len)
end

local function hint_line()
  local km = config.values.keymaps.s3
  local hints = {}
  if km.empty        then table.insert(hints, km.empty        .. " empty")   end
  if km.delete       then table.insert(hints, km.delete       .. " delete")  end
  if km.filter       then table.insert(hints, km.filter       .. " filter")  end
  if km.clear_filter then table.insert(hints, km.clear_filter .. " clear")   end
  if km.refresh      then table.insert(hints, km.refresh      .. " refresh") end
  return table.concat(hints, "  |  ")
end

--- Build the 5-line header block given the name column width.
---@param col_width integer
---@return string[]
local function make_header(col_width)
  local sep = string.rep("-", col_width + 22)
  return {
    sep,
    hint_line(),
    sep,
    pad_right("Name", col_width) .. "  " .. "Created",
    string.rep("-", col_width + 22),
  }
end

local function render(buf)
  local col_width = 10
  for _, b in ipairs(_buckets) do
    local name = b.Name or ""
    if _filter == "" or name:lower():find(_filter:lower(), 1, true) then
      if #name > col_width then col_width = #name end
    end
  end
  col_width = col_width + 4   -- breathing room (no 99-char cap)

  local title = "S3 Buckets"
    .. (_filter ~= "" and ("   [filter: " .. _filter .. "]") or "")

  -- Header lines (normal buffer lines, not a float)
  local header = make_header(col_width)

  local lines = { "", title, "" }
  for _, h in ipairs(header) do
    table.insert(lines, h)
  end

  _line_map = {}

  for _, b in ipairs(_buckets) do
    local name    = b.Name or ""
    local created = (b.CreationDate or ""):gsub("T", " "):gsub("%.%d+Z$", ""):gsub("Z$", "")
    if _filter == "" or name:lower():find(_filter:lower(), 1, true) then
      table.insert(lines, pad_right(name, col_width) .. "  " .. created)
      _line_map[#lines] = name
    end
  end

  if not next(_line_map) then
    table.insert(lines, "(no buckets match)")
  end

  buf_mod.set_lines(buf, lines)
end

---@param buf       integer
---@param call_opts AwsCallOpts|nil
local function fetch(buf, call_opts)
  buf_mod.set_loading(buf)

  spawn.run({ "s3api", "list-buckets",
    "--query", "Buckets[*].{Name:Name,CreationDate:CreationDate}",
    "--output", "json",
  }, function(ok, lines)
    if not ok then
      buf_mod.set_error(buf, lines)
      return
    end

    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if not ok2 or type(data) ~= "table" then
      buf_mod.set_error(buf, { "Failed to parse JSON response", raw })
      return
    end

    table.sort(data, function(a, b) return (a.Name or "") < (b.Name or "") end)
    _buckets = data
    render(buf)
  end, call_opts)
end

-------------------------------------------------------------------------------
-- Cursor helper
-------------------------------------------------------------------------------

local function bucket_under_cursor()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return _line_map[row]
end

--- Return the names of all buckets whose buffer lines fall inside [r1, r2].
---@param r1 integer
---@param r2 integer
---@return string[]
local function buckets_in_range(r1, r2)
  local names = {}
  local seen  = {}
  for row = r1, r2 do
    local name = _line_map[row]
    if name and not seen[name] then
      seen[name] = true
      table.insert(names, name)
    end
  end
  return names
end

--- Remove `names` from `_buckets` in-place, then re-render.
---@param names table<string, boolean>  set of names to remove
---@param buf   integer
local function remove_from_state(names, buf)
  local out = {}
  for _, b in ipairs(_buckets) do
    if not names[b.Name] then
      table.insert(out, b)
    end
  end
  _buckets = out
  render(buf)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param call_opts AwsCallOpts|nil
function M.open(call_opts)
  local buf = buf_mod.get_or_create(BUF_NAME, FILETYPE)
  buf_mod.open_split(buf)

  local empty_mod  = require("aws.s3.empty")
  local delete_mod = require("aws.s3.delete")

  -- Single-line delete (normal mode dd)
  local function delete_one()
    local name = bucket_under_cursor()
    if not name then
      vim.notify("aws.nvim: no bucket under cursor", vim.log.levels.WARN)
      return
    end
    empty_mod.confirm(name, function()
      delete_mod.run(name, function()
        remove_from_state({ [name] = true }, buf)
      end, call_opts)
    end, call_opts)
  end

  -- Multi-line delete (visual mode dd) — confirm once, empty+delete sequentially
  local function delete_visual()
    local r1 = vim.fn.line("'<")
    local r2 = vim.fn.line("'>")
    local names = buckets_in_range(r1, r2)
    if #names == 0 then
      vim.notify("aws.nvim: no buckets in selection", vim.log.levels.WARN)
      return
    end
    local label = #names == 1
      and ("Yes, delete " .. names[1])
      or  ("Yes, delete " .. #names .. " buckets")
    vim.ui.select(
      { label, "Cancel" },
      { prompt = "Empty and delete S3 buckets?" },
      function(_, idx)
        if not idx or idx ~= 1 then return end
        local removed = {}
        local function next_delete(i)
          if i > #names then
            remove_from_state(removed, buf)
            return
          end
          local name = names[i]
          empty_mod.run(name, function()
            delete_mod.run(name, function()
              removed[name] = true
              next_delete(i + 1)
            end, call_opts)
          end, call_opts)
        end
        next_delete(1)
      end
    )
  end

  keymaps.apply_s3(buf, {
    empty = function()
      local name = bucket_under_cursor()
      if not name then
        vim.notify("aws.nvim: no bucket under cursor", vim.log.levels.WARN)
        return
      end
      empty_mod.confirm(name, function()
        vim.defer_fn(function() fetch(buf, call_opts) end, 1000)
      end, call_opts)
    end,

    delete        = delete_one,
    delete_visual = delete_visual,

    filter = function()
      vim.ui.input({ prompt = "Filter buckets: ", default = _filter }, function(input)
        if input == nil then return end
        _filter = input
        render(buf)
      end)
    end,

    clear_filter = function()
      _filter = ""
      render(buf)
    end,

    refresh = function() fetch(buf, call_opts) end,

    close = function() buf_mod.close_split(buf) end,
  })

  fetch(buf, call_opts)
end

return M
