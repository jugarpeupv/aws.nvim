--- aws.nvim – CloudFormation stack events viewer
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-cloudformation"

local function buf_name(stack_name)
  return "aws://cloudformation/events/" .. stack_name
end

--- Fetch and render events for a stack.
---@param stack_name string
---@param buf        integer
---@param call_opts  AwsCallOpts|nil
local function fetch(stack_name, buf, call_opts)
  buf_mod.set_loading(buf)
  spawn.run({
    "cloudformation", "describe-stack-events",
    "--stack-name", stack_name,
    "--query", table.concat({
      "StackEvents[*].{",
      "Time:Timestamp,",
      "Resource:LogicalResourceId,",
      "Type:ResourceType,",
      "Status:ResourceStatus,",
      "Reason:ResourceStatusReason}",
    }, ""),
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

    local sep = "  " .. string.rep("-", 110)
    local region = config.resolve_region(call_opts)
    local title  = "  Events  >>  " .. stack_name
    if region then title = title .. "   [region: " .. region .. "]" end
    local out = {
      title,
      sep,
      "",
      string.format("  %-26s  %-40s  %-36s  %s", "Time (UTC)", "Resource", "Status", "Reason"),
      sep,
    }

    for _, ev in ipairs(data) do
      local time     = (ev.Time     or ""):gsub("T", " "):gsub("%.%d+Z$", ""):gsub("Z$", "")
      local resource = ev.Resource  or ""
      local status   = ev.Status    or ""
      local reason   = ev.Reason    or ""
      table.insert(out, string.format(
        "  %-26s  %-40s  %-36s  %s",
        time, resource, status, reason
      ))
    end

    table.insert(out, "")
    table.insert(out, sep)
    table.insert(out, "  R refresh")

    buf_mod.set_lines(buf, out)
  end, call_opts)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

--- Open (or focus) the events split for a given stack.
---@param stack_name string
---@param call_opts  AwsCallOpts|nil
function M.open(stack_name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(stack_name), FILETYPE)
  buf_mod.open_split(buf)

  keymaps.apply_cloudformation_events(buf, {
    refresh = function() fetch(stack_name, buf, call_opts) end,
    close   = function() buf_mod.close_split(buf) end,
  })

  fetch(stack_name, buf, call_opts)
end

return M
