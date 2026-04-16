--- aws.nvim – API Gateway REST API detail view (vsplit)
--- Fires three parallel AWS CLI calls: get-stages, get-resources, get-authorizers.
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-apigateway"

local function buf_name(id)
  return "aws://apigateway/detail/" .. id
end

--- Per-ID state keyed by REST API ID
---@class AgwDetailState
---@field api         table           result of get-rest-api
---@field stages      table[]|nil     result of get-stages .item[]
---@field resources   table[]|nil     result of get-resources .items[]
---@field authorizers table[]|nil     result of get-authorizers .items[]
---@field region      string
---@field profile     string|nil
local _state = {} -- id -> AgwDetailState

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

--- Truncate to at most `max` display columns.
---@param s   string
---@param max integer
---@return string
local function truncate(s, max)
  if vim.fn.strdisplaywidth(s) <= max then
    return s
  end
  local result = ""
  local cols = 0
  local nchars = vim.fn.strchars(s)
  for i = 0, nchars - 1 do
    local ch = vim.fn.strcharpart(s, i, 1)
    local w = vim.fn.strdisplaywidth(ch)
    if cols + w > max - 1 then
      break
    end
    result = result .. ch
    cols = cols + w
  end
  return result .. "…"
end

--- Format an epoch-number date (API Gateway returns numbers, not strings).
---@param value number|string|nil
---@return string
local function fmt_date(value)
  if not value then
    return "—"
  end
  if type(value) == "number" then
    return os.date("%Y-%m-%d %H:%M:%S UTC", math.floor(value))
  elseif type(value) == "string" then
    -- ISO-8601 fallback just in case
    local date, time = value:match("^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d:%d%d)")
    if date and time then
      return date .. " " .. time .. " UTC"
    end
    return value
  end
  return tostring(value)
end

---@param buf  integer
---@param id   string
local function render(buf, id)
  local st = _state[id]
  if not st then
    return
  end

  local api = st.api
  local region = st.region
  local profile = st.profile
  local km = config.values.keymaps.apigateway

  local lines = {}
  local LABEL = 28

  local function row(label, value)
    table.insert(lines, "  " .. pad_right(label, LABEL) .. (value or "—"))
  end

  -- ── Title ──────────────────────────────────────────────────────────────────
  table.insert(lines, "")
  local title = "API Gateway  >>  "
    .. (api.id or id)
    .. "  /  "
    .. (api.name or "")
    .. "   [region: "
    .. region
    .. "]"
    .. (profile and ("   [profile: " .. profile .. "]") or "")
  table.insert(lines, title)
  table.insert(lines, "")

  -- ── Hint line ──────────────────────────────────────────────────────────────
  local sep_len = math.max(vim.fn.strdisplaywidth(title), 72)
  local sep = string.rep("-", sep_len)
  table.insert(lines, sep)
  local hints = {}
  if km.detail_refresh then
    table.insert(hints, km.detail_refresh .. " refresh")
  end
  if #hints > 0 then
    table.insert(lines, table.concat(hints, "  |  "))
    table.insert(lines, sep)
  end

  -- ── General ────────────────────────────────────────────────────────────────
  table.insert(lines, "General")
  table.insert(lines, sep)
  row("ID", api.id)
  row("Name", api.name)
  row("Description", (api.description and api.description ~= "") and api.description or "—")
  row("Created", fmt_date(api.createdDate))
  row("API Key Source", api.apiKeySource)

  -- Endpoint types
  local ec = type(api.endpointConfiguration) == "table" and api.endpointConfiguration or {}
  local types = type(ec.types) == "table" and ec.types or {}
  row("Endpoint Type(s)", #types > 0 and table.concat(types, ", ") or "—")

  -- Tags
  local tags = type(api.tags) == "table" and api.tags or {}
  local tag_parts = {}
  for k, v in pairs(tags) do
    table.insert(tag_parts, k .. "=" .. v)
  end
  table.sort(tag_parts)
  row("Tags", #tag_parts > 0 and table.concat(tag_parts, ", ") or "—")

  -- ── Stages ─────────────────────────────────────────────────────────────────
  if st.stages then
    table.insert(lines, "")
    table.insert(lines, "Stages (" .. #st.stages .. ")")
    table.insert(lines, sep)
    if #st.stages == 0 then
      table.insert(lines, "  (none)")
    else
      for i, stage in ipairs(st.stages) do
        if i > 1 then
          table.insert(lines, "")
        end
        row("  Stage Name", stage.stageName)
        row("  Description", (stage.description and stage.description ~= "") and stage.description or "—")
        row("  Deployment ID", stage.deploymentId)
        row("  Created", fmt_date(stage.createdDate))
        row("  Last Updated", fmt_date(stage.lastUpdatedDate))
        row("  Cache Enabled", stage.cacheClusterEnabled ~= nil and tostring(stage.cacheClusterEnabled) or "—")
        if stage.cacheClusterEnabled then
          row("  Cache Size", stage.cacheClusterSize and tostring(stage.cacheClusterSize) or "—")
        end
        row("  Tracing", stage.tracingEnabled ~= nil and tostring(stage.tracingEnabled) or "—")
        -- Stage variables
        local vars = type(stage.variables) == "table" and stage.variables or {}
        local var_parts = {}
        for k, v in pairs(vars) do
          table.insert(var_parts, k .. "=" .. v)
        end
        table.sort(var_parts)
        if #var_parts > 0 then
          row("  Variables", table.concat(var_parts, ", "))
        end
      end
    end
  else
    table.insert(lines, "")
    table.insert(lines, "Stages")
    table.insert(lines, sep)
    table.insert(lines, "  [loading…]")
  end

  -- ── Resources ──────────────────────────────────────────────────────────────
  if st.resources then
    -- Sort resources by path
    local sorted = vim.deepcopy(st.resources)
    table.sort(sorted, function(a, b)
      return (a.path or "") < (b.path or "")
    end)

    table.insert(lines, "")
    table.insert(lines, "Resources (" .. #sorted .. ")")
    table.insert(lines, sep)
    if #sorted == 0 then
      table.insert(lines, "  (none)")
    else
      for _, res in ipairs(sorted) do
        local path = res.path or res.pathPart or "/"
        table.insert(lines, "  " .. path)

        local methods = type(res.resourceMethods) == "table" and res.resourceMethods or {}
        -- Collect and sort method names
        local method_names = {}
        for method_name in pairs(methods) do
          table.insert(method_names, method_name)
        end
        table.sort(method_names)

        for _, method_name in ipairs(method_names) do
          local method = methods[method_name]
          if type(method) == "table" then
            local integration = type(method.methodIntegration) == "table" and method.methodIntegration or nil
            local int_type = integration and (integration.type or "—") or "—"
            local int_uri = integration and integration.uri or nil
            local line = "    "
              .. method_name
              .. "  ["
              .. method.authorizationType
              .. "]"
              .. "  integration: "
              .. int_type
            if int_uri then
              line = line .. "  " .. truncate(int_uri, 60)
            end
            table.insert(lines, line)
          end
        end
      end
    end
  else
    table.insert(lines, "")
    table.insert(lines, "Resources")
    table.insert(lines, sep)
    table.insert(lines, "  [loading…]")
  end

  -- ── Authorizers ────────────────────────────────────────────────────────────
  if st.authorizers then
    table.insert(lines, "")
    table.insert(lines, "Authorizers (" .. #st.authorizers .. ")")
    table.insert(lines, sep)
    if #st.authorizers == 0 then
      table.insert(lines, "  (none)")
    else
      for i, auth in ipairs(st.authorizers) do
        if i > 1 then
          table.insert(lines, "")
        end
        row("  Name", auth.name)
        row("  Type", auth.type)
        row("  Identity Source", auth.identitySource)
        row(
          "  TTL (s)",
          auth.authorizerResultTtlInSeconds ~= nil and tostring(auth.authorizerResultTtlInSeconds) or "—"
        )
        if auth.authorizerUri then
          row("  URI", truncate(auth.authorizerUri, 60))
        end
      end
    end
  else
    table.insert(lines, "")
    table.insert(lines, "Authorizers")
    table.insert(lines, sep)
    table.insert(lines, "  [loading…]")
  end

  table.insert(lines, "")

  buf_mod.set_lines(buf, lines)
end

-------------------------------------------------------------------------------
-- Fetch
-------------------------------------------------------------------------------

---@param id        string
---@param buf       integer
---@param call_opts AwsCallOpts|nil
local function fetch(id, buf, call_opts)
  buf_mod.set_loading(buf)

  -- Partial state for this fetch round; pending tracks how many sub-calls remain.
  local partial = {
    api = nil,
    stages = nil,
    resources = nil,
    authorizers = nil,
  }
  local pending = 4 -- api + stages + resources + authorizers

  local function on_done()
    pending = pending - 1
    if pending > 0 then
      return
    end
    -- All done – merge into _state and render.
    local existing = _state[id] or {}
    _state[id] = {
      api = partial.api or existing.api or {},
      stages = partial.stages or existing.stages or {},
      resources = partial.resources or existing.resources or {},
      authorizers = partial.authorizers or existing.authorizers or {},
      region = config.resolve_region(call_opts),
      profile = config.resolve_profile(call_opts),
    }
    render(buf, id)
  end

  -- ── get-rest-api ────────────────────────────────────────────────────────────
  spawn.run({
    "apigateway",
    "get-rest-api",
    "--rest-api-id",
    id,
    "--output",
    "json",
  }, function(ok, lines)
    if not ok then
      buf_mod.set_error(buf, lines)
      return
    end
    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if ok2 and type(data) == "table" then
      partial.api = data
    else
      partial.api = { id = id, name = id }
    end
    on_done()
  end, call_opts)

  -- ── get-stages ──────────────────────────────────────────────────────────────
  spawn.run({
    "apigateway",
    "get-stages",
    "--rest-api-id",
    id,
    "--output",
    "json",
  }, function(ok, lines)
    if not ok then
      partial.stages = {}
      on_done()
      return
    end
    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if ok2 and type(data) == "table" and type(data.item) == "table" then
      partial.stages = data.item
    else
      partial.stages = {}
    end
    on_done()
  end, call_opts)

  -- ── get-resources ───────────────────────────────────────────────────────────
  spawn.run({
    "apigateway",
    "get-resources",
    "--rest-api-id",
    id,
    "--include-value",
    "--output",
    "json",
  }, function(ok, lines)
    if not ok then
      partial.resources = {}
      on_done()
      return
    end
    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if ok2 and type(data) == "table" and type(data.items) == "table" then
      partial.resources = data.items
    else
      partial.resources = {}
    end
    on_done()
  end, call_opts)

  -- ── get-authorizers ─────────────────────────────────────────────────────────
  spawn.run({
    "apigateway",
    "get-authorizers",
    "--rest-api-id",
    id,
    "--output",
    "json",
  }, function(ok, lines)
    if not ok then
      partial.authorizers = {}
      on_done()
      return
    end
    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if ok2 and type(data) == "table" and type(data.items) == "table" then
      partial.authorizers = data.items
    else
      partial.authorizers = {}
    end
    on_done()
  end, call_opts)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param id        string
---@param call_opts AwsCallOpts|nil
function M.open(id, call_opts)
  local buf = buf_mod.get_or_create(buf_name(id), FILETYPE)
  buf_mod.open_vsplit(buf)

  keymaps.apply_apigateway_detail(buf, {
    refresh = function()
      fetch(id, buf, call_opts)
    end,
  })

  fetch(id, buf, call_opts)
end

return M
