--- aws.nvim – CloudWatch log groups list, filter, and render
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local BUF_NAME = "aws://cloudwatch/groups"
local FILETYPE = "aws-cloudwatch"

local _groups    = {}
local _filter    = ""
local _line_map  = {}
local _cache     = nil   -- persists for the Neovim session; nil = not yet fetched
local _fetching  = false -- true while pages are still being fetched
local _fetch_gen = 0     -- incremented on every new fetch; stale callbacks check this

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
  local km = config.values.keymaps.cloudwatch
  local hints = {}
  if km.open_streams then table.insert(hints, km.open_streams .. " streams")    end
  if km.delete       then table.insert(hints, km.delete       .. " delete")     end
  if km.filter       then table.insert(hints, km.filter       .. " filter")     end
  if km.clear_filter then table.insert(hints, km.clear_filter .. " clear")      end
  if km.refresh      then table.insert(hints, km.refresh      .. " refresh")    end
  return table.concat(hints, "  |  ")
end

local function fmt_size(bytes)
  bytes = bytes or 0
  if bytes >= 1073741824 then
    return string.format("%.1f GB", bytes / 1073741824)
  elseif bytes >= 1048576 then
    return string.format("%.1f MB", bytes / 1048576)
  elseif bytes >= 1024 then
    return string.format("%.1f KB", bytes / 1024)
  end
  return bytes .. " B"
end

--- Build the 5-line header block given the name column width.
---@param col_width integer
---@return string[]
local function make_header(col_width)
  local sep = string.rep("-", col_width + 24)
  return {
    sep,
    hint_line(),
    sep,
    pad_right("Name", col_width) .. "  " .. pad_right("Retention", 10) .. "  " .. "Stored",
    string.rep("-", col_width + 24),
  }
end

local function render(buf)
  local col_width = 10
  for _, g in ipairs(_groups) do
    local name = g.logGroupName or ""
    if _filter == "" or name:lower():find(_filter:lower(), 1, true) then
      if #name > col_width then col_width = #name end
    end
  end
  col_width = col_width + 2   -- breathing room (no 99-char cap)

  local title = "CloudWatch Log Groups"
    .. (_fetching and "  [loading…]" or "")
    .. (_filter ~= "" and ("   [server filter: " .. _filter .. "]") or "")

  local header = make_header(col_width)
  local lines = { "", title, "" }
  for _, h in ipairs(header) do
    table.insert(lines, h)
  end

  _line_map = {}

  for _, g in ipairs(_groups) do
    local name     = g.logGroupName    or ""
    local retained = g.retentionInDays and (g.retentionInDays .. "d") or "never"
    if _filter == "" or name:lower():find(_filter:lower(), 1, true) then
      table.insert(lines,
        pad_right(name, col_width) .. "  " .. pad_right(retained, 10) .. "  " .. fmt_size(g.storedBytes)
      )
      _line_map[#lines] = name
    end
  end

  if not next(_line_map) then
    table.insert(lines, "(no log groups match)")
  end

  buf_mod.set_lines(buf, lines)
end

---@param buf       integer
---@param call_opts AwsCallOpts|nil
---@param pattern   string|nil  when set, pass --log-group-name-pattern (skips cache update)
local function fetch(buf, call_opts, pattern)
  buf_mod.set_loading(buf)
  local all = {}
  _fetching  = true
  _fetch_gen = _fetch_gen + 1
  local my_gen = _fetch_gen   -- captured; used to discard results from stale fetches

  local function fetch_page(next_token)
    local args = {
      "logs", "describe-log-groups",
      "--output", "json",
      "--no-paginate",
    }
    if pattern and pattern ~= "" then
      vim.list_extend(args, { "--log-group-name-pattern", pattern })
    end
    if next_token then
      vim.list_extend(args, { "--next-token", next_token })
    end

    spawn.run(args, function(ok, lines)
      -- Discard if a newer fetch has started.
      if my_gen ~= _fetch_gen then return end

      if not ok then
        _fetching = false
        buf_mod.set_error(buf, lines)
        return
      end

      local raw = table.concat(lines, "\n")
      local ok2, data = pcall(vim.json.decode, raw)
      if not ok2 or type(data) ~= "table" then
        _fetching = false
        buf_mod.set_error(buf, { "Failed to parse JSON", raw })
        return
      end

      for _, g in ipairs(type(data.logGroups) == "table" and data.logGroups or {}) do
        table.insert(all, {
          logGroupName    = g.logGroupName,
          storedBytes     = g.storedBytes,
          retentionInDays = g.retentionInDays,
        })
      end

      local has_more = type(data.nextToken) == "string"

      -- Render what we have so far; _fetching stays true until last page.
      _fetching = has_more
      _groups   = all
      render(buf)

      if has_more then
        fetch_page(data.nextToken)
      else
        -- Full (unfiltered) fetch only: update the session cache.
        if not pattern or pattern == "" then
          _cache = all
        end
      end
    end, call_opts)
  end

  all = {}
  fetch_page(nil)
end

-------------------------------------------------------------------------------
-- Cursor helper
-------------------------------------------------------------------------------

local function group_under_cursor()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return _line_map[row]
end

--- Return the names of all groups whose buffer lines fall inside [r1, r2].
---@param r1 integer
---@param r2 integer
---@return string[]
local function groups_in_range(r1, r2)
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

--- Remove `names` from `_groups` and `_cache` in-place, then re-render.
---@param names table<string, boolean>  set of names to remove
---@param buf   integer
local function remove_from_state(names, buf)
  local function filter_list(list)
    local out = {}
    for _, g in ipairs(list) do
      if not names[g.logGroupName] then
        table.insert(out, g)
      end
    end
    return out
  end
  _groups = filter_list(_groups)
  if _cache then _cache = filter_list(_cache) end
  render(buf)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param call_opts AwsCallOpts|nil
---@param fresh     boolean|nil  when true, bypass cache and re-fetch from AWS
function M.open(call_opts, fresh)
  local buf = buf_mod.get_or_create(BUF_NAME, FILETYPE)
  buf_mod.open_split(buf)

  -- Single-line delete (normal mode dd)
  local function delete_one()
    local name = group_under_cursor()
    if not name then
      vim.notify("aws.nvim: no log group under cursor", vim.log.levels.WARN)
      return
    end
    require("aws.cloudwatch.delete").confirm(name, function()
      remove_from_state({ [name] = true }, buf)
    end, call_opts)
  end

  -- Multi-line delete (visual mode dd) — confirm once, delete sequentially
  local function delete_visual()
    local r1 = vim.fn.line("'<")
    local r2 = vim.fn.line("'>")
    local names = groups_in_range(r1, r2)
    if #names == 0 then
      vim.notify("aws.nvim: no log groups in selection", vim.log.levels.WARN)
      return
    end
    local label = #names == 1
      and ("Yes, delete " .. names[1])
      or  ("Yes, delete " .. #names .. " log groups")
    vim.ui.select(
      { label, "Cancel" },
      { prompt = "Delete CloudWatch log groups?" },
      function(_, idx)
        if not idx or idx ~= 1 then return end
        local del = require("aws.cloudwatch.delete")
        local removed = {}
        local function next_delete(i)
          if i > #names then
            remove_from_state(removed, buf)
            return
          end
          local name = names[i]
          del.run(name, function()
            removed[name] = true
            next_delete(i + 1)
          end, call_opts)
        end
        next_delete(1)
      end
    )
  end

  keymaps.apply_cloudwatch(buf, {
    open_streams = function()
      local name = group_under_cursor()
      if not name then
        vim.notify("aws.nvim: no log group under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.cloudwatch.streams").open(name, call_opts)
    end,

    delete        = delete_one,
    delete_visual = delete_visual,

    filter = function()
      vim.ui.input({ prompt = "Filter log groups: ", default = _filter }, function(input)
        if input == nil then return end
        if input == "" then
          -- treat as clear
          _filter = ""
          if _cache then
            _groups = _cache
            render(buf)
          else
            fetch(buf, call_opts)
          end
        else
          _filter = input
          fetch(buf, call_opts, input)
        end
      end)
    end,

    clear_filter = function()
      _filter = ""
      if _cache then
        _groups = _cache
        render(buf)
      else
        fetch(buf, call_opts)
      end
    end,

    refresh = function()
      fetch(buf, call_opts, _filter ~= "" and _filter or nil)
    end,

    close = function() buf_mod.close_split(buf) end,
  })

  if _cache and not fresh then
    _groups = _cache
    render(buf)
  else
    fetch(buf, call_opts)
  end
end

return M
