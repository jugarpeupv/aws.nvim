--- aws.nvim – CloudWatch log groups list, filter, and render
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-cloudwatch"

---@class CwGroupsState
---@field groups    table[]
---@field filter    string
---@field line_map  table<integer,string>
---@field cache     table[]|nil   full unfiltered list; nil = not yet fetched
---@field fetching  boolean       true while pages are still arriving
---@field fetch_gen integer       incremented on every new fetch; stale cbs check this
---@field region    string
---@field profile   string|nil

--- state keyed by identity string (e.g. "us-east-1" or "prod@eu-west-1")
local _state = {}  -- identity -> CwGroupsState

local function buf_name(identity)
  return "aws://cloudwatch/groups/" .. identity
end

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

---@param buf integer
---@param st  CwGroupsState
local function render(buf, st)
  local col_width = 10
  for _, g in ipairs(st.groups) do
    local name = g.logGroupName or ""
    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      if #name > col_width then col_width = #name end
    end
  end
  col_width = col_width + 2

  local title = "CloudWatch Log Groups"
    .. "   [region: " .. st.region .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")
    .. (st.filter ~= "" and ("   [server filter: " .. st.filter .. "]") or "")

  local header = make_header(col_width)
  local lines = { "", title, "" }
  for _, h in ipairs(header) do
    table.insert(lines, h)
  end

  st.line_map = {}

  for _, g in ipairs(st.groups) do
    local name     = g.logGroupName    or ""
    local retained = g.retentionInDays and (g.retentionInDays .. "d") or "never"
    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      table.insert(lines,
        pad_right(name, col_width) .. "  " .. pad_right(retained, 10) .. "  " .. fmt_size(g.storedBytes)
      )
      st.line_map[#lines] = name
    end
  end

  if not next(st.line_map) then
    table.insert(lines, "(no log groups match)")
  end

  buf_mod.set_lines(buf, lines)
end

---@param buf       integer
---@param st        CwGroupsState
---@param call_opts AwsCallOpts|nil
---@param pattern   string|nil
local function fetch(buf, st, call_opts, pattern)
  buf_mod.set_loading(buf)
  local all = {}
  st.fetching  = true
  st.fetch_gen = st.fetch_gen + 1
  local my_gen = st.fetch_gen

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
      if my_gen ~= st.fetch_gen then return end

      if not ok then
        st.fetching = false
        buf_mod.set_error(buf, lines)
        return
      end

      local raw = table.concat(lines, "\n")
      local ok2, data = pcall(vim.json.decode, raw)
      if not ok2 or type(data) ~= "table" then
        st.fetching = false
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
      st.fetching = has_more
      st.groups   = all
      render(buf, st)

      if has_more then
        fetch_page(data.nextToken)
      else
        if not pattern or pattern == "" then
          st.cache = all
        end
      end
    end, call_opts)
  end

  all = {}
  fetch_page(nil)
end

-------------------------------------------------------------------------------
-- Cursor helpers
-------------------------------------------------------------------------------

local function group_under_cursor(st)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return st.line_map[row]
end

---@param st CwGroupsState
---@param r1 integer
---@param r2 integer
---@return string[]
local function groups_in_range(st, r1, r2)
  local names = {}
  local seen  = {}
  for row = r1, r2 do
    local name = st.line_map[row]
    if name and not seen[name] then
      seen[name] = true
      table.insert(names, name)
    end
  end
  return names
end

---@param st    CwGroupsState
---@param names table<string, boolean>
---@param buf   integer
local function remove_from_state(st, names, buf)
  local function filter_list(list)
    local out = {}
    for _, g in ipairs(list) do
      if not names[g.logGroupName] then
        table.insert(out, g)
      end
    end
    return out
  end
  st.groups = filter_list(st.groups)
  if st.cache then st.cache = filter_list(st.cache) end
  render(buf, st)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param call_opts AwsCallOpts|nil
---@param fresh     boolean|nil  when true, bypass cache and re-fetch from AWS
function M.open(call_opts, fresh)
  local identity = config.identity(call_opts)
  local buf = buf_mod.get_or_create(buf_name(identity), FILETYPE)
  buf_mod.open_split(buf)

  if not _state[identity] then
    _state[identity] = {
      groups    = {},
      filter    = "",
      line_map  = {},
      cache     = nil,
      fetching  = false,
      fetch_gen = 0,
      region    = config.resolve_region(call_opts),
      profile   = config.resolve_profile(call_opts),
    }
  end
  local st = _state[identity]

  local function delete_one()
    local name = group_under_cursor(st)
    if not name then
      vim.notify("aws.nvim: no log group under cursor", vim.log.levels.WARN)
      return
    end
    require("aws.cloudwatch.delete").confirm(name, function()
      remove_from_state(st, { [name] = true }, buf)
    end, call_opts)
  end

  local function delete_visual()
    local r1 = vim.fn.line("'<")
    local r2 = vim.fn.line("'>")
    local names = groups_in_range(st, r1, r2)
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
            remove_from_state(st, removed, buf)
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
      local name = group_under_cursor(st)
      if not name then
        vim.notify("aws.nvim: no log group under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.cloudwatch.streams").open(name, call_opts)
    end,

    delete        = delete_one,
    delete_visual = delete_visual,

    filter = function()
      vim.ui.input({ prompt = "Filter log groups: ", default = st.filter }, function(input)
        if input == nil then return end
        if input == "" then
          st.filter = ""
          if st.cache then
            st.groups = st.cache
            render(buf, st)
          else
            fetch(buf, st, call_opts)
          end
        else
          st.filter = input
          fetch(buf, st, call_opts, input)
        end
      end)
    end,

    clear_filter = function()
      st.filter = ""
      if st.cache then
        st.groups = st.cache
        render(buf, st)
      else
        fetch(buf, st, call_opts)
      end
    end,

    refresh = function()
      fetch(buf, st, call_opts, st.filter ~= "" and st.filter or nil)
    end,

    close = function() buf_mod.close_split(buf) end,
  })

  if st.cache and not fresh then
    st.groups = st.cache
    render(buf, st)
  else
    fetch(buf, st, call_opts)
  end
end

return M
