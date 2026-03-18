--- aws.nvim – CloudWatch log streams list for a given log group
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-cloudwatch"

local function buf_name(group_name)
  return "aws://cloudwatch/streams/" .. group_name
end

-- Per-buffer state keyed by group name
local _state = {}  -- group_name -> { streams, line_map }

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
  if km.open_logs then table.insert(hints, km.open_logs .. " open logs") end
  if km.refresh   then table.insert(hints, km.refresh   .. " refresh")   end
  if km.close     then table.insert(hints, km.close     .. " close")     end
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
    pad_right("Stream name", col_width) .. "  " .. "Last event (UTC)",
    string.rep("-", col_width + 22),
  }
end

local function render(buf, group_name)
  local st = _state[group_name] or { streams = {}, line_map = {} }

  local col_width = 11  -- len("Stream name")
  for _, s in ipairs(st.streams) do
    local name = s.logStreamName or ""
    if #name > col_width then col_width = #name end
  end
  col_width = col_width + 2   -- breathing room (no 99-char cap)

  -- Header lines (normal buffer lines, not a float)
  local header = make_header(col_width)

  local lines = { "", "Log Streams  >>  " .. group_name, "" }
  for _, h in ipairs(header) do
    table.insert(lines, h)
  end

  st.line_map = {}

  for _, s in ipairs(st.streams) do
    local name = s.logStreamName or "?"
    local last = s.lastEventTimestamp
    local ts   = last and os.date("%Y-%m-%d %H:%M:%S", math.floor(last / 1000)) or "—"
    table.insert(lines, pad_right(name, col_width) .. "  " .. ts)
    st.line_map[#lines] = s.logStreamName
  end

  if #st.streams == 0 then
    table.insert(lines, "(no log streams)")
  end

  _state[group_name] = st
  buf_mod.set_lines(buf, lines)
end

---@param group_name string
---@param buf        integer
---@param call_opts  AwsCallOpts|nil
local function fetch(group_name, buf, call_opts)
  buf_mod.set_loading(buf)

  spawn.run({
    "logs", "describe-log-streams",
    "--log-group-name", group_name,
    "--order-by", "LastEventTime",
    "--descending",
    "--output", "json",
  }, function(ok, lines)
    if not ok then
      buf_mod.set_error(buf, lines)
      return
    end

    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if not ok2 or type(data) ~= "table" then
      buf_mod.set_error(buf, { "Failed to parse JSON", raw })
      return
    end

    local streams = type(data.logStreams) == "table" and data.logStreams or {}
    _state[group_name] = { streams = streams, line_map = {} }
    render(buf, group_name)
  end, call_opts)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param group_name string
---@param call_opts  AwsCallOpts|nil
function M.open(group_name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(group_name), FILETYPE)
  buf_mod.open_vsplit(buf)

  local function stream_under_cursor()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local st  = _state[group_name]
    return st and st.line_map[row]
  end

  keymaps.apply_cloudwatch_streams(buf, {
    open_logs = function()
      local stream = stream_under_cursor()
      if not stream then
        vim.notify("aws.nvim: no log stream under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.cloudwatch.logs").open(group_name, stream, call_opts)
    end,

    refresh = function() fetch(group_name, buf, call_opts) end,

    close = function() buf_mod.close_vsplit(buf) end,
  })

  fetch(group_name, buf, call_opts)
end

return M
