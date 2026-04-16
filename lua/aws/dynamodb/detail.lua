--- aws.nvim – DynamoDB table detail view (general info + keys + indexes + tags)
--- Fires a single describe-table call and renders everything.
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-dynamodb"

local _state = {} -- table_name -> { data, region, profile }

local function buf_name(table_name)
  return "aws://dynamodb/detail/" .. table_name
end

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

---@param s     string
---@param width integer
---@return string
local function pad_right(s, width)
  local display_len = vim.fn.strdisplaywidth(s)
  if display_len >= width then
    return s
  end
  return s .. string.rep(" ", width - display_len)
end

local function fmt_bytes(n)
  n = n or 0
  if n >= 1073741824 then
    return string.format("%.1f GB", n / 1073741824)
  elseif n >= 1048576 then
    return string.format("%.1f MB", n / 1048576)
  elseif n >= 1024 then
    return string.format("%.1f KB", n / 1024)
  end
  return n .. " B"
end

--- Convert a list of AttributeDefinitions into a name->type lookup.
local function attr_types(definitions)
  local t = {}
  for _, a in ipairs(definitions or {}) do
    t[a.AttributeName] = a.AttributeType
  end
  return t
end

--- Format a key schema list into e.g. "pk (S, HASH)  sk (S, RANGE)".
local function fmt_key_schema(schema, attr_map)
  if not schema or #schema == 0 then
    return "—"
  end
  local parts = {}
  for _, k in ipairs(schema) do
    local name = k.AttributeName or "?"
    local atype = attr_map[name] or "?"
    local ktype = k.KeyType or "?"
    table.insert(parts, name .. " (" .. atype .. ", " .. ktype .. ")")
  end
  return table.concat(parts, "   ")
end

---@param buf        integer
---@param table_name string
local function render(buf, table_name)
  local st = _state[table_name]
  if not st then
    return
  end

  local tbl = st.data or {}
  local region = st.region
  local profile = st.profile
  local km = config.values.keymaps.dynamodb

  local LABEL = 30
  local lines = {}

  local function row(label, value)
    table.insert(lines, "  " .. pad_right(label, LABEL) .. (value or "—"))
  end

  -- ── Title ─────────────────────────────────────────────────────────────────
  table.insert(lines, "")
  local title = "DynamoDB  >>  "
    .. table_name
    .. "   [region: "
    .. region
    .. "]"
    .. (profile and ("   [profile: " .. profile .. "]") or "")
  table.insert(lines, title)
  table.insert(lines, "")

  local sep_len = math.max(vim.fn.strdisplaywidth(title), 72)
  local sep = string.rep("-", sep_len)
  table.insert(lines, sep)

  -- ── Hint ──────────────────────────────────────────────────────────────────
  if km.detail_refresh then
    table.insert(lines, km.detail_refresh .. " refresh")
    table.insert(lines, sep)
  end

  -- ── General ───────────────────────────────────────────────────────────────
  table.insert(lines, "General")
  table.insert(lines, sep)

  local attr_map = attr_types(tbl.AttributeDefinitions)

  row("Table Name", tbl.TableName or table_name)
  row("Table ARN", tbl.TableArn or "—")
  row("Status", tbl.TableStatus or "—")
  row("Created", tbl.CreationDateTime and tostring(tbl.CreationDateTime) or "—")
  row("Item Count", tostring(tbl.ItemCount or 0))
  row("Table Size", fmt_bytes(tbl.TableSizeBytes))
  local class = tbl.TableClassSummary and (tbl.TableClassSummary.TableClass or "STANDARD") or "STANDARD"
  if class == "STANDARD_INFREQUENT_ACCESS" then
    class = "STANDARD_INFREQUENT_ACCESS (IA)"
  end
  row("Table Class", class)

  -- Billing
  local billing = "PROVISIONED"
  if tbl.BillingModeSummary then
    billing = tbl.BillingModeSummary.BillingMode or "PROVISIONED"
  end
  row("Billing Mode", billing)

  if tbl.ProvisionedThroughput then
    local pt = tbl.ProvisionedThroughput
    row("  Read Capacity", tostring(pt.ReadCapacityUnits or 0) .. " RCU")
    row("  Write Capacity", tostring(pt.WriteCapacityUnits or 0) .. " WCU")
  end

  -- ── Primary Key ───────────────────────────────────────────────────────────
  table.insert(lines, "")
  table.insert(lines, "Primary Key")
  table.insert(lines, sep)
  row("Key Schema", fmt_key_schema(tbl.KeySchema, attr_map))

  -- ── Attribute Definitions ─────────────────────────────────────────────────
  if tbl.AttributeDefinitions and #tbl.AttributeDefinitions > 0 then
    table.insert(lines, "")
    table.insert(lines, "Attribute Definitions")
    table.insert(lines, sep)
    for _, a in ipairs(tbl.AttributeDefinitions) do
      row(
        "  " .. (a.AttributeName or "?"),
        (a.AttributeType or "?")
          .. (
            a.AttributeType == "S" and " (String)"
            or a.AttributeType == "N" and " (Number)"
            or a.AttributeType == "B" and " (Binary)"
            or ""
          )
      )
    end
  end

  -- ── Global Secondary Indexes ──────────────────────────────────────────────
  local gsis = type(tbl.GlobalSecondaryIndexes) == "table" and tbl.GlobalSecondaryIndexes or {}
  if #gsis > 0 then
    table.insert(lines, "")
    table.insert(lines, "Global Secondary Indexes (" .. #gsis .. ")")
    table.insert(lines, sep)
    for _, gsi in ipairs(gsis) do
      row("  " .. (gsi.IndexName or "?"), "status: " .. (gsi.IndexStatus or "—"))
      row("    Key Schema", fmt_key_schema(gsi.KeySchema, attr_map))
      row("    Projection", gsi.Projection and (gsi.Projection.ProjectionType or "—") or "—")
      if gsi.ProvisionedThroughput then
        local pt = gsi.ProvisionedThroughput
        row(
          "    Read / Write",
          tostring(pt.ReadCapacityUnits or 0) .. " RCU  /  " .. tostring(pt.WriteCapacityUnits or 0) .. " WCU"
        )
      end
      if gsi.ItemCount then
        row("    Items", tostring(gsi.ItemCount))
      end
    end
  end

  -- ── Local Secondary Indexes ───────────────────────────────────────────────
  local lsis = type(tbl.LocalSecondaryIndexes) == "table" and tbl.LocalSecondaryIndexes or {}
  if #lsis > 0 then
    table.insert(lines, "")
    table.insert(lines, "Local Secondary Indexes (" .. #lsis .. ")")
    table.insert(lines, sep)
    for _, lsi in ipairs(lsis) do
      row("  " .. (lsi.IndexName or "?"), "")
      row("    Key Schema", fmt_key_schema(lsi.KeySchema, attr_map))
      row("    Projection", lsi.Projection and (lsi.Projection.ProjectionType or "—") or "—")
      if lsi.ItemCount then
        row("    Items", tostring(lsi.ItemCount))
      end
    end
  end

  -- ── Streams ───────────────────────────────────────────────────────────────
  if tbl.StreamSpecification then
    local ss = tbl.StreamSpecification
    table.insert(lines, "")
    table.insert(lines, "DynamoDB Streams")
    table.insert(lines, sep)
    row("  Enabled", tostring(ss.StreamEnabled or false))
    row("  View Type", ss.StreamViewType or "—")
    if tbl.LatestStreamArn then
      row("  Stream ARN", tbl.LatestStreamArn)
    end
  end

  -- ── Point-in-time Recovery ────────────────────────────────────────────────
  if tbl.PointInTimeRecoveryDescription then
    local pitr = tbl.PointInTimeRecoveryDescription
    table.insert(lines, "")
    table.insert(lines, "Point-in-Time Recovery")
    table.insert(lines, sep)
    row("  Status", pitr.PointInTimeRecoveryStatus or "—")
    row("  Earliest Restore", pitr.EarliestRestorableDateTime and tostring(pitr.EarliestRestorableDateTime) or "—")
    row("  Latest Restore", pitr.LatestRestorableDateTime and tostring(pitr.LatestRestorableDateTime) or "—")
  end

  -- ── Tags ──────────────────────────────────────────────────────────────────
  local tags = type(tbl.Tags) == "table" and tbl.Tags or {}
  if #tags > 0 then
    table.insert(lines, "")
    table.insert(lines, "Tags")
    table.insert(lines, sep)
    local sorted = vim.deepcopy(tags)
    table.sort(sorted, function(a, b)
      return (a.Key or "") < (b.Key or "")
    end)
    for _, tag in ipairs(sorted) do
      row("  " .. (tag.Key or "?"), tag.Value or "")
    end
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

-------------------------------------------------------------------------------
-- Fetch
-------------------------------------------------------------------------------

---@param table_name string
---@param buf        integer
---@param call_opts  AwsCallOpts|nil
local function fetch(table_name, buf, call_opts)
  buf_mod.set_loading(buf)

  spawn.run({ "dynamodb", "describe-table", "--table-name", table_name, "--output", "json" }, function(ok, lines)
    if not ok then
      buf_mod.set_error(buf, lines)
      return
    end
    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if not ok2 or type(data) ~= "table" or type(data.Table) ~= "table" then
      buf_mod.set_error(buf, { "Failed to parse JSON", raw })
      return
    end
    _state[table_name] = {
      data = data.Table,
      region = config.resolve_region(call_opts),
      profile = config.resolve_profile(call_opts),
    }
    render(buf, table_name)
  end, call_opts)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param table_name string
---@param call_opts  AwsCallOpts|nil
function M.open(table_name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(table_name), FILETYPE)
  buf_mod.open_split(buf)

  keymaps.apply_dynamodb_section(buf, {
    refresh = function()
      fetch(table_name, buf, call_opts)
    end,
  })

  fetch(table_name, buf, call_opts)
end

return M
