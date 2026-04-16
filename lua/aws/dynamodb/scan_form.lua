--- aws.nvim – DynamoDB scan/query: form UI (AWS-console-style)
---
--- Renders a form at the top of the scan buffer:
---
---   ┌──────────────────────────────────────────────────────────┐
---   │  Scan or query items                                      │
---   │  ( ) Scan   ( ) Query                                     │
---   │                                                           │
---   │  Table / Index:  [ Table - my-table          ▾ ]         │
---   │                                                           │
---   │  Filters – optional                                       │
---   │  Attribute name   Condition        Type      Value        │
---   │  [ status      ]  [ Equal to    ] [String] [ ERROR     ] │
---   │  [Add filter]                   [Run]  [Reset]            │
---   └──────────────────────────────────────────────────────────┘
---
--- Every interactive element is on a known line.  The orchestrator keeps a
--- "hotspot" table that maps buffer line numbers → action callbacks so that
--- pressing <CR> on any line does the right thing.
---
local M = {}

local ss = require("aws.dynamodb.scan_state")

-------------------------------------------------------------------------------
-- Layout constants
-------------------------------------------------------------------------------

local COL_ATTR = 4 -- start column of Attribute field
local W_ATTR = 20 -- width of Attribute field (inside brackets)
local COL_COND = COL_ATTR + W_ATTR + 5 -- "[ attr ]  "
local W_COND = 20
local COL_TYPE = COL_COND + W_COND + 3
local W_TYPE = 8
local COL_VAL = COL_TYPE + W_TYPE + 3 -- luacheck: ignore 211
local W_VAL = 18

-------------------------------------------------------------------------------
-- Tiny string helpers
-------------------------------------------------------------------------------

local function pad(s, w)
  local d = vim.fn.strdisplaywidth(tostring(s))
  if d >= w then
    return tostring(s):sub(1, w)
  end
  return tostring(s) .. string.rep(" ", w - d)
end

local function field(value, width)
  return "[ " .. pad(value, width) .. " ]"
end

local function radio(active, label)
  return (active and "(x) " or "( ) ") .. label
end

local function button(label)
  return "[" .. label .. "]"
end

-------------------------------------------------------------------------------
-- Form renderer
-------------------------------------------------------------------------------

--- Render the form section into `lines`, populate `hotspots`.
---
--- hotspots[line_number] = { kind = "...", ... }
--- Kinds: "mode_scan", "mode_query", "index", "filter_attr", "filter_cond",
---        "filter_type", "filter_val", "filter_remove", "add_filter",
---        "pk_name","pk_val","pk_type","sk_op","sk_name","sk_val","sk_type",
---        "sk_val2", "run", "reset"
---
---@param st        DynamoDbScanState
---@param lines     string[]     append to this list
---@param hotspots  table<integer,table>   line_number (1-based) -> action descriptor
function M.render_form(st, lines, hotspots)
  local function L(s)
    table.insert(lines, s or "")
    return #lines -- returns 1-based line index just added
  end

  -- ── Title ─────────────────────────────────────────────────────────────────
  L("")
  L(
    "  Scan or query items  ──  "
      .. st.table_name
      .. "   [region: "
      .. st.region
      .. "]"
      .. (st.profile and ("  [profile: " .. st.profile .. "]") or "")
      .. (st.fetching and "  [loading…]" or "")
  )
  L("  " .. string.rep("─", 72))

  -- ── Mode radio ────────────────────────────────────────────────────────────
  L("")
  local ln_scan = L("  " .. radio(st.mode == "scan", "Scan ") .. "   " .. radio(st.mode == "query", "Query"))
  hotspots[ln_scan] = { kind = "mode_toggle" }
  L("")

  -- ── Table / Index selector ────────────────────────────────────────────────
  local idx_label = st.index_name and ("Index - " .. st.index_name) or ("Table - " .. st.table_name)
  local ln_idx = L("  Table / Index:  " .. field(idx_label, 36))
  hotspots[ln_idx] = { kind = "index" }
  L("")

  -- ── Query key fields (only when mode == "query") ──────────────────────────
  if st.mode == "query" then
    L(
      "  ── Key condition ──────────────────────────────────────────────────────"
    )
    L("")

    -- Schema hint: show the real PK/SK names from describe-table (read-only info)
    if st.schema_loaded then
      local pk_hint = st.schema_pk
          and ("  Table partition key:  " .. st.schema_pk.name .. "  (" .. (ss.TYPE_LABEL[st.schema_pk.type] or st.schema_pk.type) .. ")")
        or "  Table partition key:  —"
      L(pk_hint)
      local sk_hint = st.schema_sk
          and ("  Table sort key:       " .. st.schema_sk.name .. "  (" .. (ss.TYPE_LABEL[st.schema_sk.type] or st.schema_sk.type) .. ")")
        or "  Table sort key:       (none)"
      L(sk_hint)
    else
      L("  Table key schema:  [loading…]")
    end
    L("")

    -- Editable PK value row
    -- Pre-fill name/type from schema if not yet set by the user
    local pk_name_display = st.pk_name or (st.schema_pk and st.schema_pk.name or "")
    local pk_type_display = ss.TYPE_LABEL[st.pk_type] or "String"
    local ln_pk = L(
      "  Partition key:  "
        .. field(pk_name_display, 22)
        .. "  Type: "
        .. field(pk_type_display, 8)
        .. "  Value: "
        .. field(st.pk_value or "", 18)
    )
    hotspots[ln_pk] = { kind = "pk_row" }
    L("  (press <CR> to edit partition key value)")
    L("")

    -- Editable SK row
    local sk_op_label = st.sk_op or "-- skip --"
    local sk_name_display = st.sk_name or (st.schema_sk and st.schema_sk.name or "")
    local sk_type_display = ss.TYPE_LABEL[st.sk_type] or "String"
    local ln_sk = L(
      "  Sort key:       "
        .. field(sk_op_label, 14)
        .. "  "
        .. field(sk_name_display, 16)
        .. "  Type: "
        .. field(sk_type_display, 8)
        .. "  Value: "
        .. field(st.sk_value or "", 14)
        .. (st.sk_op == "between" and ("  and: " .. field(st.sk_value2 or "", 14)) or "")
    )
    hotspots[ln_sk] = { kind = "sk_row" }
    L("  (press <CR> to edit sort key condition)")
    L("")
  end

  -- ── Filters ───────────────────────────────────────────────────────────────
  L("  Filters – optional")
  L("  " .. pad("Attribute name", W_ATTR + 4) .. pad("Condition", W_COND + 4) .. pad("Type", W_TYPE + 4) .. "Value")

  for i, f in ipairs(st.filters) do
    local row = "  "
      .. field(f.attr, W_ATTR)
      .. "  "
      .. field(f.condition, W_COND)
      .. "  "
      .. field(f.type, W_TYPE)
      .. "  "
      .. field(f.value, W_VAL)
      .. "  "
      .. button(" Remove ")
    local ln = L(row)
    hotspots[ln] = { kind = "filter_row", idx = i }
  end

  if #st.filters == 0 then
    L("  (no filters — press [Add filter] to add one)")
  end

  L("")
  local action_line = "  "
    .. button(" Add filter ")
    .. "                    "
    .. button(" Run ")
    .. "   "
    .. button(" Reset ")
  local ln_actions = L(action_line)
  hotspots[ln_actions] = { kind = "action_bar" }
  L("")
  L("  " .. string.rep("─", 72))
end

-------------------------------------------------------------------------------
-- Action resolver: given cursor line, return what <CR> should do
-------------------------------------------------------------------------------

---@param hotspots  table<integer,table>
---@param line      integer   1-based cursor line
---@return table|nil
function M.resolve_action(hotspots, line)
  return hotspots[line]
end

-------------------------------------------------------------------------------
-- Interactive handlers (called by scan.lua when user presses <CR>)
-------------------------------------------------------------------------------

--- Toggle between Scan and Query mode.
---@param st DynamoDbScanState
---@param on_change fun()  called after mode is toggled
function M.toggle_mode(st, on_change)
  st.mode = (st.mode == "scan") and "query" or "scan"
  on_change()
end

--- Prompt for index name (or clear to use base table).
---@param st        DynamoDbScanState
---@param on_change fun()
function M.edit_index(st, on_change)
  vim.ui.input({ prompt = "GSI / LSI name (leave blank for base table): ", default = st.index_name or "" }, function(v)
    if v == nil then
      return
    end
    st.index_name = (v ~= "") and v or nil
    on_change()
  end)
end

--- Edit the partition key row (name, type, value) in sequence.
--- The name and type are pre-seeded from the table schema when available.
---@param st        DynamoDbScanState
---@param on_change fun()
function M.edit_pk_row(st, on_change)
  -- Default name and type come from the real key schema when the user hasn't
  -- overridden them yet (e.g. when querying a GSI with different keys).
  local default_name = st.pk_name or (st.schema_pk and st.schema_pk.name or "")
  local default_type = st.pk_type or (st.schema_pk and st.schema_pk.type or "S")

  vim.ui.input({ prompt = "Partition key name: ", default = default_name }, function(name)
    if name == nil then
      return
    end
    st.pk_name = (name ~= "") and name or (default_name ~= "" and default_name or nil)
    vim.ui.select(ss.TYPES, { prompt = "Partition key type:" }, function(choice)
      if choice then
        st.pk_type = ss.TYPE_CODE[choice] or "S"
      else
        st.pk_type = default_type
      end
      vim.ui.input({ prompt = "Partition key value: ", default = st.pk_value or "" }, function(val)
        if val == nil then
          return
        end
        st.pk_value = (val ~= "") and val or st.pk_value
        on_change()
      end)
    end)
  end)
end

--- Edit the sort key row.
--- The name and type are pre-seeded from the table schema when available.
---@param st        DynamoDbScanState
---@param on_change fun()
function M.edit_sk_row(st, on_change)
  local default_sk_name = st.sk_name or (st.schema_sk and st.schema_sk.name or "")
  local default_sk_type = st.sk_type or (st.schema_sk and st.schema_sk.type or "S")

  local ops_with_skip = vim.list_extend(vim.deepcopy(ss.SK_OPS), { "-- skip sort key --" })
  vim.ui.select(ops_with_skip, { prompt = "Sort key condition (or skip):" }, function(op, idx)
    if op == nil then
      return
    end
    if idx == #ops_with_skip then
      st.sk_op = nil
      st.sk_name = nil
      st.sk_value = nil
      st.sk_value2 = nil
      on_change()
      return
    end
    st.sk_op = op
    vim.ui.input({ prompt = "Sort key name: ", default = default_sk_name }, function(name)
      if name == nil then
        return
      end
      st.sk_name = (name ~= "") and name or (default_sk_name ~= "" and default_sk_name or nil)
      vim.ui.select(ss.TYPES, { prompt = "Sort key type:" }, function(choice)
        st.sk_type = (choice and ss.TYPE_CODE[choice]) or default_sk_type
        local prompt1 = (op == "between") and "Sort key value (lower bound): " or "Sort key value: "
        vim.ui.input({ prompt = prompt1, default = st.sk_value or "" }, function(val)
          if val == nil then
            return
          end
          if val ~= "" then
            st.sk_value = val
          end
          if op == "between" then
            vim.ui.input({ prompt = "Sort key upper bound: ", default = st.sk_value2 or "" }, function(v2)
              if v2 ~= nil and v2 ~= "" then
                st.sk_value2 = v2
              end
              on_change()
            end)
          else
            st.sk_value2 = nil
            on_change()
          end
        end)
      end)
    end)
  end)
end

--- Edit a specific filter row — each column is a separate prompt.
---@param st        DynamoDbScanState
---@param idx       integer   1-based index into st.filters
---@param on_change fun()
function M.edit_filter_row(st, idx, on_change)
  local f = st.filters[idx]
  if not f then
    return
  end

  vim.ui.input({ prompt = "Attribute name: ", default = f.attr }, function(attr)
    if attr == nil then
      return
    end
    if attr ~= "" then
      f.attr = attr
    end

    vim.ui.select(ss.CONDITIONS, { prompt = "Condition:" }, function(cond)
      if cond then
        f.condition = cond
      end

      vim.ui.select(ss.TYPES, { prompt = "Type:" }, function(typ)
        if typ then
          f.type = typ
        end

        vim.ui.input({ prompt = "Value: ", default = f.value }, function(val)
          if val == nil then
            return
          end
          if val ~= "" then
            f.value = val
          end
          on_change()
        end)
      end)
    end)
  end)
end

--- Remove a filter row.
---@param st        DynamoDbScanState
---@param idx       integer
---@param on_change fun()
function M.remove_filter(st, idx, on_change)
  table.remove(st.filters, idx)
  on_change()
end

--- Add a blank filter row, then immediately open the edit prompt.
---@param st        DynamoDbScanState
---@param on_change fun()
function M.add_filter(st, on_change)
  table.insert(st.filters, {
    attr = "",
    condition = "Equal to",
    type = "String",
    value = "",
  })
  M.edit_filter_row(st, #st.filters, on_change)
end

--- Reset all filter + key state (like AWS console "Reset").
---@param st        DynamoDbScanState
---@param on_change fun()
function M.reset(st, on_change)
  st.filters = {}
  st.pk_name = nil
  st.pk_value = nil
  st.pk_type = "S"
  st.sk_name = nil
  st.sk_op = nil
  st.sk_value = nil
  st.sk_value2 = nil
  st.sk_type = "S"
  st.index_name = nil
  st.last_key = nil
  st.page = 1
  on_change()
end

--- Handle a press on the action-bar line.
--- Detects which button the cursor is on by checking column position, but since
--- we can't reliably get column from normal mode without extmarks, we use a
--- secondary ui.select to disambiguate.
---@param st        DynamoDbScanState
---@param on_run    fun()
---@param on_change fun()
function M.action_bar_select(st, on_run, on_change)
  local choices = { "Add filter", "Run", "Reset" }
  vim.ui.select(choices, { prompt = "Action:" }, function(choice)
    if not choice then
      return
    end
    if choice == "Add filter" then
      M.add_filter(st, on_change)
    elseif choice == "Run" then
      on_run()
    elseif choice == "Reset" then
      M.reset(st, on_change)
    end
  end)
end

return M
