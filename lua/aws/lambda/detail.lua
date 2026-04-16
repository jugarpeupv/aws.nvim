--- aws.nvim – Lambda function detail view (vsplit)
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-lambda"

local function buf_name(fn_name)
  return "aws://lambda/detail/" .. fn_name
end

-- Per-buffer state keyed by function name
local _state = {} -- fn_name -> { data, region, profile }

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

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

--- Trim an ARN to show only the last segment for readability.
---@param arn string|nil
---@return string
local function short_arn(arn)
  if not arn then
    return "—"
  end
  local last = arn:match("[^/]+$") or arn:match("[^:]+$") or arn
  return last
end

--- Format a timestamp string from Lambda (ISO-8601-like) to something readable.
---@param ts string|nil
---@return string
local function fmt_ts(ts)
  if not ts then
    return "—"
  end
  -- Lambda returns e.g. "2024-01-15T10:23:45.000+0000"
  return ts:match("^([%d%-]+T[%d:]+)") or ts
end

--- Format bytes to human-readable.
---@param bytes integer|nil
---@return string
local function fmt_size(bytes)
  bytes = bytes or 0
  if bytes >= 1048576 then
    return string.format("%.1f MB", bytes / 1048576)
  elseif bytes >= 1024 then
    return string.format("%.1f KB", bytes / 1024)
  end
  return bytes .. " B"
end

---@param buf    integer
---@param fn_name string
local function render(buf, fn_name)
  local st = _state[fn_name]
  if not st then
    return
  end

  local d = st.data
  local region = st.region
  local profile = st.profile
  local km = config.values.keymaps.lambda

  local lines = {}

  -- Title
  table.insert(lines, "")
  local title = "Lambda  >>  "
    .. fn_name
    .. "   [region: "
    .. region
    .. "]"
    .. (profile and ("   [profile: " .. profile .. "]") or "")
  table.insert(lines, title)
  table.insert(lines, "")

  -- Hint
  local hints = {}
  if km.detail_logs then
    table.insert(hints, km.detail_logs .. " open logs")
  end
  if km.refresh then
    table.insert(hints, km.refresh .. " refresh")
  end
  local sep_len = math.max(#title, 60)
  local sep = string.rep("-", sep_len)
  table.insert(lines, sep)
  if #hints > 0 then
    table.insert(lines, table.concat(hints, "  |  "))
    table.insert(lines, sep)
  end

  -- Configuration section
  table.insert(lines, "Configuration")
  table.insert(lines, string.rep("-", sep_len))

  local function row(label, value)
    table.insert(lines, "  " .. pad_right(label, 16) .. (value or "—"))
  end

  row("Runtime", d.Runtime)
  row("Handler", d.Handler)
  row("Memory", d.MemorySize and (d.MemorySize .. " MB") or nil)
  row("Timeout", d.Timeout and (d.Timeout .. "s") or nil)
  row("Code size", fmt_size(d.CodeSize))
  row("Last mod", fmt_ts(d.LastModified))
  row("Role", short_arn(d.Role))

  if d.Description and d.Description ~= "" then
    row("Description", d.Description)
  end

  -- Architecture
  if type(d.Architectures) == "table" and #d.Architectures > 0 then
    row("Arch", table.concat(d.Architectures, ", "))
  end

  -- VPC
  if type(d.VpcConfig) == "table" and d.VpcConfig.VpcId and d.VpcConfig.VpcId ~= "" then
    row("VPC", d.VpcConfig.VpcId)
  end

  -- Environment variables
  if type(d.Environment) == "table" and type(d.Environment.Variables) == "table" and next(d.Environment.Variables) then
    table.insert(lines, "")
    table.insert(lines, "Environment Variables")
    table.insert(lines, string.rep("-", sep_len))
    for k, v in pairs(d.Environment.Variables) do
      table.insert(lines, "  " .. pad_right(k, 24) .. v)
    end
  end

  -- Layers
  if type(d.Layers) == "table" and #d.Layers > 0 then
    table.insert(lines, "")
    table.insert(lines, "Layers")
    table.insert(lines, string.rep("-", sep_len))
    for _, layer in ipairs(d.Layers) do
      local arn = layer.Arn or "?"
      table.insert(lines, "  " .. arn)
    end
  end

  -- Log group link
  table.insert(lines, "")
  table.insert(lines, "CloudWatch Logs")
  table.insert(lines, string.rep("-", sep_len))
  table.insert(lines, "  Log group:  /aws/lambda/" .. fn_name)
  if km.detail_logs then
    table.insert(lines, "  Press " .. km.detail_logs .. " to open log streams in a split.")
  end
  table.insert(lines, "")

  buf_mod.set_lines(buf, lines)
end

---@param fn_name   string
---@param buf       integer
---@param call_opts AwsCallOpts|nil
local function fetch(fn_name, buf, call_opts)
  buf_mod.set_loading(buf)

  spawn.run({
    "lambda",
    "get-function-configuration",
    "--function-name",
    fn_name,
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

    _state[fn_name] = {
      data = data,
      region = config.resolve_region(call_opts),
      profile = config.resolve_profile(call_opts),
    }
    render(buf, fn_name)
  end, call_opts)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param fn_name   string
---@param call_opts AwsCallOpts|nil
function M.open(fn_name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(fn_name), FILETYPE)
  buf_mod.open_vsplit(buf)

  keymaps.apply_lambda_detail(buf, {
    open_logs = function()
      local log_group = "/aws/lambda/" .. fn_name
      require("aws.cloudwatch.streams").open(log_group, call_opts)
    end,

    refresh = function()
      fetch(fn_name, buf, call_opts)
    end,
  })

  fetch(fn_name, buf, call_opts)
end

return M
