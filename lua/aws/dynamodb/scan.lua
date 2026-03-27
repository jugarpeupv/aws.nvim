--- aws.nvim – DynamoDB scan / query buffer (orchestrator)
---
--- UI resembles the AWS console "Scan or query items" panel:
---
---   • Scan / Query radio toggle
---   • Table / Index selector
---   • Query key fields (PK + optional SK) — only visible in Query mode
---   • Filter rows  (Attribute | Condition | Type | Value | [Remove])
---   • Action bar   [Add filter]   [Run]   [Reset]
---   • Results section with pagination
---
--- Navigation: j / k to move, <CR> to activate the element on the cursor line.
--- R = re-run last query, n = next page, J = toggle JSON/table view.
---
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")
local ss      = require("aws.dynamodb.scan_state")
local form    = require("aws.dynamodb.scan_form")
local results = require("aws.dynamodb.scan_results")

local FILETYPE = "aws-dynamodb"

-- per-table state: table_name -> DynamoDbScanState
local _state = {}
-- per-buffer hotspot map rebuilt on every render: buf -> { line -> descriptor }
local _hotspots = {}
-- line offset where results section starts (after the form), per buffer
local _results_line = {}

local function buf_name(tn) return "aws://dynamodb/scan/" .. tn end

-------------------------------------------------------------------------------
-- Full buffer render
-------------------------------------------------------------------------------

local function render(buf, st)
  local lines    = {}
  local hotspots = {}

  form.render_form(st, lines, hotspots)

  -- Remember where results start (1-based line after form separator)
  _results_line[buf] = #lines + 1

  results.render_results(st, lines)

  _hotspots[buf] = hotspots
  buf_mod.set_lines(buf, lines)
end

-------------------------------------------------------------------------------
-- CLI argument builder
-------------------------------------------------------------------------------

local function build_eav(st, filter_eav)
  local eav = {}
  if st.mode == "query" and st.pk_name and st.pk_value then
    eav[":pk"] = { [st.pk_type] = st.pk_value }
  end
  if st.mode == "query" and st.sk_name and st.sk_op and st.sk_value then
    eav[":sk"] = { [st.sk_type] = st.sk_value }
    if st.sk_op == "between" and st.sk_value2 then
      eav[":sk2"] = { [st.sk_type] = st.sk_value2 }
    end
  end
  for k, v in pairs(filter_eav) do eav[k] = v end
  if not next(eav) then return nil end
  local ok, enc = pcall(vim.json.encode, eav)
  return ok and enc or nil
end

local function build_ean(st, filter_ean)
  local ean = {}
  if st.mode == "query" and st.pk_name then
    ean["#pk"] = st.pk_name
    if st.sk_name then ean["#sk"] = st.sk_name end
  end
  for k, v in pairs(filter_ean) do ean[k] = v end
  if not next(ean) then return nil end
  local ok, enc = pcall(vim.json.encode, ean)
  return ok and enc or nil
end

local function build_kce(st)
  if not st.pk_name or not st.pk_value then return nil end
  local expr = "#pk = :pk"
  if st.sk_name and st.sk_op and st.sk_value then
    if st.sk_op == "begins_with" then
      expr = expr .. " AND begins_with(#sk, :sk)"
    elseif st.sk_op == "between" and st.sk_value2 then
      expr = expr .. " AND #sk BETWEEN :sk AND :sk2"
    else
      expr = expr .. " AND #sk " .. st.sk_op .. " :sk"
    end
  end
  return expr
end

local function build_args(st, last_key)
  local filter_expr, filter_ean, filter_eav =
    ss.build_filter_expression(st.filters)

  local args
  if st.mode == "query" then
    args = { "dynamodb", "query", "--table-name", st.table_name }
    local kce = build_kce(st)
    if kce then vim.list_extend(args, { "--key-condition-expression", kce }) end
    local ean = build_ean(st, filter_ean)
    if ean then vim.list_extend(args, { "--expression-attribute-names", ean }) end
    if filter_expr then
      vim.list_extend(args, { "--filter-expression", filter_expr })
    end
  else
    args = { "dynamodb", "scan", "--table-name", st.table_name }
    if filter_expr then
      vim.list_extend(args, { "--filter-expression", filter_expr })
      local ean = build_ean(st, filter_ean)
      if ean then vim.list_extend(args, { "--expression-attribute-names", ean }) end
    end
  end

  if st.index_name and st.index_name ~= "" then
    vim.list_extend(args, { "--index-name", st.index_name })
  end

  local eav = build_eav(st, filter_eav)
  if eav then vim.list_extend(args, { "--expression-attribute-values", eav }) end

  vim.list_extend(args, { "--max-items", "50", "--output", "json" })
  if last_key then vim.list_extend(args, { "--starting-token", last_key }) end

  return args
end

-------------------------------------------------------------------------------
-- Schema fetch (describe-table → extract PK/SK names + types)
-------------------------------------------------------------------------------

--- Fire a lightweight describe-table call, populate st.schema_pk / st.schema_sk,
--- then re-render.  Only called once per buffer lifetime (schema_loaded guard).
---@param table_name string
---@param buf        integer
---@param call_opts  AwsCallOpts|nil
local function fetch_schema(table_name, buf, call_opts)
  local st = _state[table_name]
  if not st or st.schema_loaded then return end

  spawn.run(
    { "dynamodb", "describe-table", "--table-name", table_name, "--output", "json" },
    function(ok, lines)
      local cur = _state[table_name]
      if not cur or cur ~= st then return end
      if not ok then
        st.schema_loaded = true   -- mark done even on error so we don't retry forever
        render(buf, st)
        return
      end

      local raw = table.concat(lines, "\n")
      local ok2, data = pcall(vim.json.decode, raw)
      if not ok2 or type(data) ~= "table" or type(data.Table) ~= "table" then
        st.schema_loaded = true
        render(buf, st)
        return
      end

      local tbl = data.Table

      -- Build attr-name -> type lookup
      local attr_types = {}
      for _, a in ipairs(type(tbl.AttributeDefinitions) == "table" and tbl.AttributeDefinitions or {}) do
        attr_types[a.AttributeName] = a.AttributeType
      end

      -- Walk KeySchema to find HASH and RANGE keys
      for _, k in ipairs(type(tbl.KeySchema) == "table" and tbl.KeySchema or {}) do
        local name = k.AttributeName
        local t    = attr_types[name] or "S"
        if k.KeyType == "HASH" then
          st.schema_pk = { name = name, type = t }
        elseif k.KeyType == "RANGE" then
          st.schema_sk = { name = name, type = t }
        end
      end

      st.schema_loaded = true

      -- Auto-seed pk_name / pk_type / sk_type from schema on first open
      -- (only when the user hasn't already set them manually)
      if not st.pk_name and st.schema_pk then
        st.pk_name = st.schema_pk.name
        st.pk_type = st.schema_pk.type
      end
      if not st.sk_type and st.schema_sk then
        st.sk_type = st.schema_sk.type
      end

      render(buf, st)
    end,
    call_opts
  )
end

-------------------------------------------------------------------------------
-- Fetch
-------------------------------------------------------------------------------

---@param table_name string
---@param buf        integer
---@param call_opts  AwsCallOpts|nil
---@param last_key   string|nil
local function fetch(table_name, buf, call_opts, last_key)
  local st = _state[table_name]
  if not st then return end

  st.fetching = true
  render(buf, st)

  local args = build_args(st, last_key)

  spawn.run(args, function(ok, lines)
    if _state[table_name] ~= st then return end
    st.fetching = false
    if not ok then buf_mod.set_error(buf, lines); return end

    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if not ok2 or type(data) ~= "table" then
      buf_mod.set_error(buf, { "Failed to parse JSON", raw }); return
    end

    st.items    = type(data.Items) == "table" and data.Items or {}
    st.last_key = type(data.NextToken) == "string" and data.NextToken
      or (type(data.LastEvaluatedKey) == "table"
          and vim.json.encode(data.LastEvaluatedKey) or nil)
    render(buf, st)
  end, call_opts)
end

-------------------------------------------------------------------------------
-- <CR> handler — dispatches based on hotspot under cursor
-------------------------------------------------------------------------------

local function make_cr_handler(table_name, buf, call_opts)
  return function()
    local st       = _state[table_name]
    local hotspots = _hotspots[buf] or {}
    local line     = vim.api.nvim_win_get_cursor(0)[1]  -- 1-based
    local hs       = form.resolve_action(hotspots, line)

    if not hs then return end

    local on_change = function()
      render(buf, st)
    end
    local on_run = function()
      st.last_key = nil
      st.page     = 1
      fetch(table_name, buf, call_opts, nil)
    end

    local kind = hs.kind

    if kind == "mode_toggle" then
      form.toggle_mode(st, on_change)

    elseif kind == "index" then
      form.edit_index(st, on_change)

    elseif kind == "pk_row" then
      form.edit_pk_row(st, on_change)

    elseif kind == "sk_row" then
      form.edit_sk_row(st, on_change)

    elseif kind == "filter_row" then
      -- Determine sub-action: click on Remove vs the field cells.
      -- Since we cannot detect column easily in normal mode, offer a choice.
      local f = st.filters[hs.idx]
      if not f then return end
      vim.ui.select(
        { "Edit filter", "Remove filter" },
        { prompt = "Filter row #" .. hs.idx .. " (" .. (f.attr ~= "" and f.attr or "empty") .. "):" },
        function(choice)
          if not choice then return end
          if choice == "Edit filter" then
            form.edit_filter_row(st, hs.idx, on_change)
          else
            form.remove_filter(st, hs.idx, on_change)
          end
        end
      )

    elseif kind == "action_bar" then
      form.action_bar_select(st, on_run, on_change)
    end
  end
end

-------------------------------------------------------------------------------
-- Public entry point
-------------------------------------------------------------------------------

---@param table_name string
---@param call_opts  AwsCallOpts|nil
function M.open(table_name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(table_name), FILETYPE)
  buf_mod.open_split(buf)

  if not _state[table_name] then
    _state[table_name] = ss.new_state(
      table_name,
      config.resolve_region(call_opts),
      config.resolve_profile(call_opts)
    )
  end

  local st = _state[table_name]
  local cr = make_cr_handler(table_name, buf, call_opts)

  keymaps.apply_dynamodb_section(buf, {
    refresh = cr,   -- R re-runs through the same <CR> path on action bar

    scan_run = function()
      -- R key: directly run without going through the menu
      st.last_key = nil
      st.page     = 1
      fetch(table_name, buf, call_opts, nil)
    end,

    scan_next = function()
      if not st.last_key then
        vim.notify("aws.nvim: no more pages", vim.log.levels.INFO)
        return
      end
      st.page = st.page + 1
      fetch(table_name, buf, call_opts, st.last_key)
    end,

    scan_json = function()
      st.json_view = not st.json_view
      render(buf, st)
    end,
  })

  -- Wire <CR> as a buffer-local normal-mode mapping
  vim.keymap.set("n", "<CR>", cr, {
    buffer  = buf,
    noremap = true,
    silent  = true,
    desc    = "aws.nvim: activate DynamoDB form element",
  })

  -- Initial render + schema fetch (async, re-renders when done) + full-table scan
  render(buf, st)
  fetch_schema(table_name, buf, call_opts)
  fetch(table_name, buf, call_opts, nil)
end

return M
