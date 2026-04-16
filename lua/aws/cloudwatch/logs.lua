--- aws.nvim – CloudWatch log events viewer for a specific stream
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-cloudwatch"

local function buf_name(group_name, stream_name)
  return "aws://cloudwatch/logs/" .. group_name .. "/" .. stream_name
end

---@param group_name  string
---@param stream_name string
---@param buf         integer
---@param call_opts   AwsCallOpts|nil
local function fetch(group_name, stream_name, buf, call_opts)
  buf_mod.set_loading(buf)

  spawn.run({
    "logs",
    "get-log-events",
    "--log-group-name",
    group_name,
    "--log-stream-name",
    stream_name,
    "--start-from-head",
    "--output",
    "json",
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

    local events = type(data.events) == "table" and data.events or {}

    local sep = string.rep("-", 100)
    local region = config.resolve_region(call_opts)
    local title = "Log Events  >>  " .. group_name .. "  /  " .. stream_name
    if region then
      title = title .. "   [region: " .. region .. "]"
    end
    local out = {
      sep,
      "R refresh",
      sep,
      "",
      title,
      "",
    }

    if #events == 0 then
      table.insert(out, "(no events)")
    else
      for _, ev in ipairs(events) do
        local ts = ev.timestamp
        local time = ts and os.date("%Y-%m-%d %H:%M:%S", math.floor(ts / 1000)) or "?"
        -- Each event message may contain embedded newlines — split and indent them
        local msg = ev.message or ""
        msg = msg:gsub("\n$", "") -- strip trailing newline
        local first = true
        for part in (msg .. "\n"):gmatch("([^\n]*)\n") do
          if first then
            table.insert(out, string.format("[%s]  %s", time, part))
            first = false
          else
            table.insert(out, string.format("                     %s", part))
          end
        end
      end
    end

    table.insert(out, "")
    table.insert(out, sep)
    table.insert(out, string.format("(%d events)", #events))

    buf_mod.set_lines(buf, out)
  end, call_opts)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param group_name  string
---@param stream_name string
---@param call_opts   AwsCallOpts|nil
function M.open(group_name, stream_name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(group_name, stream_name), FILETYPE)
  buf_mod.open_vsplit(buf)

  keymaps.apply_cloudwatch_logs(buf, {
    refresh = function()
      fetch(group_name, stream_name, buf, call_opts)
    end,
    close = function()
      buf_mod.close_vsplit(buf)
    end,
  })

  fetch(group_name, stream_name, buf, call_opts)
end

return M
