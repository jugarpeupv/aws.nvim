--- aws.nvim – CloudFormation stacks list, filter, and render
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-cloudformation"

--- One entry per profile+region identity.
---@class CfStacksState
---@field stacks   table[]
---@field filter   string
---@field line_map table<integer,string>
---@field region   string
---@field profile  string|nil

--- state keyed by identity string (e.g. "us-east-1" or "prod@eu-west-1")
local _state = {} -- identity -> CfStacksState

local function buf_name(identity)
  return "aws://cloudformation/stacks/" .. identity
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
  if len >= width then
    return s
  end
  return s .. string.rep(" ", width - len)
end

local function status_icon(status)
  local ic = config.values.icons
  if status:find("DELETE") then
    return ic.deleted
  end
  if status:find("FAILED") then
    return ic.failed
  end
  if status:find("IN_PROGRESS") then
    return ic.in_progress
  end
  if status:find("COMPLETE") then
    return ic.complete
  end
  return ic.stack
end

local function hint_line()
  local km = config.values.keymaps.cloudformation
  local hints = {}
  if km.open_resources then
    table.insert(hints, km.open_resources .. " resources")
  end
  if km.open_events then
    table.insert(hints, km.open_events .. " events")
  end
  if km.delete then
    table.insert(hints, km.delete .. " delete")
  end
  if km.filter then
    table.insert(hints, km.filter .. " filter")
  end
  if km.clear_filter then
    table.insert(hints, km.clear_filter .. " clear")
  end
  if km.refresh then
    table.insert(hints, km.refresh .. " refresh")
  end
  return table.concat(hints, "  |  ")
end

--- Build the 5-line header block given the name column width.
---@param col_width integer
---@return string[]
local function make_header(col_width)
  local sep = string.rep("-", col_width + 30)
  return {
    sep,
    hint_line(),
    sep,
    pad_right("Stack name", col_width) .. "  " .. "Status",
    string.rep("-", col_width + 30),
  }
end

--- Re-render the stacks buffer for a given identity.
---@param buf      integer
---@param st       CfStacksState
local function render(buf, st)
  local col_width = 10
  for _, s in ipairs(st.stacks) do
    local name = s.StackName or ""
    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      if #name > col_width then
        col_width = #name
      end
    end
  end
  col_width = col_width + 2

  local title = "CloudFormation Stacks"
    .. "   [region: "
    .. st.region
    .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.filter ~= "" and ("   [filter: " .. st.filter .. "]") or "")

  local header = make_header(col_width)
  local lines = { "", title, "" }
  for _, h in ipairs(header) do
    table.insert(lines, h)
  end

  st.line_map = {}

  for _, s in ipairs(st.stacks) do
    local name = s.StackName or ""
    local status = s.StackStatus or "UNKNOWN"
    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      table.insert(lines, status_icon(status) .. " " .. pad_right(name, col_width) .. "  " .. status)
      st.line_map[#lines] = name
    end
  end

  if not next(st.line_map) then
    table.insert(lines, "(no stacks match)")
  end

  buf_mod.set_lines(buf, lines)
end

--- Fetch stacks from AWS, paginating incrementally and re-rendering each page.
---@param buf       integer
---@param st        CfStacksState
---@param call_opts AwsCallOpts|nil
local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  local all = {}

  local function fetch_page(next_token)
    local args = {
      "cloudformation",
      "describe-stacks",
      "--output",
      "json",
      "--no-paginate",
    }
    if next_token then
      vim.list_extend(args, { "--starting-token", next_token })
    end

    spawn.run(args, function(ok, lines)
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

      for _, s in ipairs(type(data.Stacks) == "table" and data.Stacks or {}) do
        table.insert(all, { StackName = s.StackName, StackStatus = s.StackStatus })
      end

      table.sort(all, function(a, b)
        return (a.StackName or "") < (b.StackName or "")
      end)
      st.stacks = all
      render(buf, st)

      if type(data.NextToken) == "string" then
        fetch_page(data.NextToken)
      end
    end, call_opts)
  end

  all = {}
  fetch_page(nil)
end

-------------------------------------------------------------------------------
-- Cursor helpers (operate on the focused buffer's state)
-------------------------------------------------------------------------------

local function stack_under_cursor(st)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return st.line_map[row]
end

---@param st CfStacksState
---@param r1 integer
---@param r2 integer
---@return string[]
local function stacks_in_range(st, r1, r2)
  local names = {}
  local seen = {}
  for row = r1, r2 do
    local name = st.line_map[row]
    if name and not seen[name] then
      seen[name] = true
      table.insert(names, name)
    end
  end
  return names
end

---@param st    CfStacksState
---@param names table<string, boolean>
---@param buf   integer
local function remove_from_state(st, names, buf)
  local out = {}
  for _, s in ipairs(st.stacks) do
    if not names[s.StackName] then
      table.insert(out, s)
    end
  end
  st.stacks = out
  render(buf, st)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param call_opts AwsCallOpts|nil
function M.open(call_opts)
  local identity = config.identity(call_opts)
  local buf = buf_mod.get_or_create(buf_name(identity), FILETYPE)
  buf_mod.open_split(buf)

  -- Initialise state for this identity if this is the first open.
  if not _state[identity] then
    _state[identity] = {
      stacks = {},
      filter = "",
      line_map = {},
      region = config.resolve_region(call_opts),
      profile = config.resolve_profile(call_opts),
    }
  end
  local st = _state[identity]

  local delete_mod = require("aws.cloudformation.delete")

  local function delete_one()
    local name = stack_under_cursor(st)
    if not name then
      vim.notify("aws.nvim: no stack under cursor", vim.log.levels.WARN)
      return
    end
    delete_mod.confirm(name, function()
      remove_from_state(st, { [name] = true }, buf)
    end, call_opts)
  end

  local function delete_visual(r1, r2)
    local names = stacks_in_range(st, r1, r2)
    if #names == 0 then
      vim.notify("aws.nvim: no stacks in selection", vim.log.levels.WARN)
      return
    end
    local label = #names == 1 and ("Yes, delete " .. names[1]) or ("Yes, delete " .. #names .. " stacks")
    vim.ui.select({ label, "Cancel" }, { prompt = "Delete CloudFormation stacks?" }, function(_, idx)
      if not idx or idx ~= 1 then
        return
      end
      local removed = {}
      local function next_delete(i)
        if i > #names then
          remove_from_state(st, removed, buf)
          return
        end
        local name = names[i]
        delete_mod.run(name, function()
          removed[name] = true
          next_delete(i + 1)
        end, call_opts)
      end
      next_delete(1)
    end)
  end

  keymaps.apply_cloudformation(buf, {
    open_resources = function()
      local name = stack_under_cursor(st)
      if not name then
        vim.notify("aws.nvim: no stack under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.cloudformation.resources").open(name, call_opts)
    end,

    open_events = function()
      local name = stack_under_cursor(st)
      if not name then
        vim.notify("aws.nvim: no stack under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.cloudformation.events").open(name, call_opts)
    end,

    delete = delete_one,
    delete_visual = delete_visual,

    filter = function()
      vim.ui.input({ prompt = "Filter stacks: ", default = st.filter }, function(input)
        if input == nil then
          return
        end
        st.filter = input
        render(buf, st)
      end)
    end,

    clear_filter = function()
      st.filter = ""
      render(buf, st)
    end,

    refresh = function()
      fetch(buf, st, call_opts)
    end,

    close = function()
      buf_mod.close_split(buf)
    end,
  })

  fetch(buf, st, call_opts)
end

---@param call_opts AwsCallOpts|nil
function M.refresh(call_opts)
  local identity = config.identity(call_opts)
  local buf = buf_mod.get_or_create(buf_name(identity), FILETYPE)
  local st = _state[identity]
  if st then
    fetch(buf, st, call_opts)
  end
end

return M
