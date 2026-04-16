--- aws.nvim – Secrets Manager secret detail view (vsplit)
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-secretsmanager"

local function buf_name(name)
  -- Sanitise the secret name for use in a buffer name (replace slashes).
  local safe = name:gsub("/", "_")
  return "aws://secretsmanager/detail/" .. safe
end

-- Per-name state keyed by secret name
---@class SmDetailState
---@field data       table           result of describe-secret
---@field region     string
---@field profile    string|nil
---@field revealed   boolean         true when secret value is currently shown
---@field secret_val string|nil      cached SecretString (nil = not yet fetched)
---@field secret_err string|nil      error message from get-secret-value, if any
---@field secret_bin boolean         true when the secret is binary (not a string)
local _state = {} -- name -> SmDetailState

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

--- Format a date value from Secrets Manager JSON.
--- The API returns ISO-8601 strings (e.g. "2024-01-15T10:23:45+00:00").
--- Handles both string and number (epoch) just in case.
---@param value number|string|nil
---@return string
local function fmt_date(value)
  if not value then
    return "—"
  end
  local t = type(value)
  if t == "number" then
    return os.date("%Y-%m-%d %H:%M:%S UTC", math.floor(value))
  elseif t == "string" then
    local date, time = value:match("^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d:%d%d)")
    if date and time then
      return date .. " " .. time .. " UTC"
    end
    return value
  end
  return tostring(value)
end

--- Try to pretty-print a string as JSON.  If it is not valid JSON, return it
--- split into plain lines (handles multi-line secrets gracefully).
---@param s string
---@return string[]
local function format_secret_value(s)
  local ok, decoded = pcall(vim.json.decode, s)
  if ok and type(decoded) == "table" then
    -- Pretty-print: one key per line
    local out = {}
    -- Sort keys for stable output
    local keys = {}
    for k in pairs(decoded) do
      table.insert(keys, k)
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local v = decoded[k]
      local vs = type(v) == "string" and v or vim.json.encode(v)
      table.insert(out, "  " .. k .. " = " .. vs)
    end
    return out
  end
  -- Not a JSON object — split by newline and indent
  local out = {}
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(out, "  " .. line)
  end
  return out
end

---@param buf  integer
---@param name string
local function render(buf, name)
  local st = _state[name]
  if not st then
    return
  end

  local d = st.data
  local region = st.region
  local profile = st.profile
  local km = config.values.keymaps.secretsmanager

  local lines = {}

  -- Title
  table.insert(lines, "")
  local title = "Secrets Manager  >>  "
    .. name
    .. "   [region: "
    .. region
    .. "]"
    .. (profile and ("   [profile: " .. profile .. "]") or "")
  table.insert(lines, title)
  table.insert(lines, "")

  -- Hint line
  local sep_len = math.max(#title, 72)
  local sep = string.rep("-", sep_len)
  table.insert(lines, sep)
  local hints = {}
  if km.detail_refresh then
    table.insert(hints, km.detail_refresh .. " refresh")
  end
  if km.reveal then
    local label = st.revealed and "hide secret" or "reveal secret"
    table.insert(hints, km.reveal .. " " .. label)
  end
  if #hints > 0 then
    table.insert(lines, table.concat(hints, "  |  "))
    table.insert(lines, sep)
  end

  local function row(label, value)
    table.insert(lines, "  " .. pad_right(label, 22) .. (value or "—"))
  end

  -- Identifiers
  table.insert(lines, "Identifiers")
  table.insert(lines, string.rep("-", sep_len))
  row("ARN", d.ARN)
  row("Name", d.Name)

  -- General
  table.insert(lines, "")
  table.insert(lines, "General")
  table.insert(lines, string.rep("-", sep_len))
  row("Description", d.Description)
  row("Created", fmt_date(d.CreatedDate))
  row("Last Changed", fmt_date(d.LastChangedDate))
  row("Last Accessed", fmt_date(d.LastAccessedDate))
  row("Last Rotated", fmt_date(d.LastRotatedDate))

  -- Rotation
  table.insert(lines, "")
  table.insert(lines, "Rotation")
  table.insert(lines, string.rep("-", sep_len))
  local rot_enabled = d.RotationEnabled and "yes" or "no"
  row("Rotation Enabled", rot_enabled)
  if d.RotationLambdaARN and d.RotationLambdaARN ~= "" then
    row("Lambda ARN", d.RotationLambdaARN)
  end
  if type(d.RotationRules) == "table" then
    local days = d.RotationRules.AutomaticallyAfterDays
    if days then
      row("Auto Rotate (days)", tostring(days))
    end
  end

  -- Tags
  if type(d.Tags) == "table" and #d.Tags > 0 then
    table.insert(lines, "")
    table.insert(lines, "Tags")
    table.insert(lines, string.rep("-", sep_len))
    for _, tag in ipairs(d.Tags) do
      local k = tag.Key or "?"
      local v = tag.Value or "—"
      row(k, v)
    end
  end

  -- Version IDs
  if type(d.VersionIdsToStages) == "table" and next(d.VersionIdsToStages) then
    table.insert(lines, "")
    table.insert(lines, "Versions")
    table.insert(lines, string.rep("-", sep_len))
    for ver_id, stages in pairs(d.VersionIdsToStages) do
      local stage_str = type(stages) == "table" and table.concat(stages, ", ") or tostring(stages)
      table.insert(lines, "  " .. ver_id)
      table.insert(lines, "    Stages: " .. stage_str)
    end
  end

  -- Secret Value (only when revealed)
  table.insert(lines, "")
  table.insert(lines, "Secret Value")
  table.insert(lines, string.rep("-", sep_len))
  if not st.revealed then
    table.insert(lines, "  (press " .. (km.reveal or "gS") .. " to reveal)")
  elseif st.secret_err then
    table.insert(lines, "  [error] " .. st.secret_err)
  elseif st.secret_bin then
    table.insert(lines, "  (binary secret — not displayable as text)")
  elseif st.secret_val then
    for _, l in ipairs(format_secret_value(st.secret_val)) do
      table.insert(lines, l)
    end
  else
    table.insert(lines, "  (loading…)")
  end

  table.insert(lines, "")

  buf_mod.set_lines(buf, lines)
end

---@param name      string
---@param buf       integer
---@param call_opts AwsCallOpts|nil
local function fetch(name, buf, call_opts)
  buf_mod.set_loading(buf)

  spawn.run({
    "secretsmanager",
    "describe-secret",
    "--secret-id",
    name,
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

    -- Preserve reveal state across refreshes; reset secret cache on refresh.
    local prev = _state[name]
    _state[name] = {
      data = data,
      region = config.resolve_region(call_opts),
      profile = config.resolve_profile(call_opts),
      revealed = prev and prev.revealed or false,
      secret_val = prev and prev.secret_val or nil,
      secret_err = prev and prev.secret_err or nil,
      secret_bin = prev and prev.secret_bin or false,
    }
    render(buf, name)
  end, call_opts)
end

--- Fetch the secret value and re-render.  Caches the result so subsequent
--- reveal toggles (hide → show) don't make another network call.
---@param name      string
---@param buf       integer
---@param call_opts AwsCallOpts|nil
local function fetch_secret_value(name, buf, call_opts)
  local st = _state[name]
  if not st then
    return
  end

  -- Already cached — just re-render.
  if st.secret_val or st.secret_err or st.secret_bin then
    render(buf, name)
    return
  end

  -- Mark as loading and render the "loading…" placeholder.
  render(buf, name)

  spawn.run({
    "secretsmanager",
    "get-secret-value",
    "--secret-id",
    name,
    "--output",
    "json",
  }, function(ok, lines)
    local s = _state[name]
    if not s then
      return
    end

    if not ok then
      s.secret_err = table.concat(lines, " ")
      render(buf, name)
      return
    end

    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if not ok2 or type(data) ~= "table" then
      s.secret_err = "Failed to parse get-secret-value response"
      render(buf, name)
      return
    end

    if type(data.SecretString) == "string" then
      s.secret_val = data.SecretString
    elseif data.SecretBinary ~= nil then
      s.secret_bin = true
    else
      s.secret_err = "Response contained neither SecretString nor SecretBinary"
    end
    render(buf, name)
  end, call_opts)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param name      string
---@param call_opts AwsCallOpts|nil
function M.open(name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(name), FILETYPE)
  buf_mod.open_vsplit(buf)

  keymaps.apply_secretsmanager_detail(buf, {
    refresh = function()
      -- On explicit refresh: clear the cached secret value so it is re-fetched
      -- if currently revealed.
      local st = _state[name]
      if st then
        st.secret_val = nil
        st.secret_err = nil
        st.secret_bin = false
      end
      fetch(name, buf, call_opts)
    end,

    reveal = function()
      local st = _state[name]
      if not st then
        return
      end
      st.revealed = not st.revealed
      if st.revealed then
        fetch_secret_value(name, buf, call_opts)
      else
        render(buf, name)
      end
    end,
  })

  fetch(name, buf, call_opts)
end

return M
