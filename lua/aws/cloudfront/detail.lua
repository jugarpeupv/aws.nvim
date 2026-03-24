--- aws.nvim – CloudFront distribution detail view (vsplit)
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-cloudfront"

local function buf_name(id)
  return "aws://cloudfront/detail/" .. id
end

-- Per-ID state keyed by distribution ID
---@class CfDetailState
---@field data       table           result of get-distribution
---@field region     string
---@field profile    string|nil
local _state = {}  -- id -> CfDetailState

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

---@param s     string
---@param width integer
---@return string
local function pad_right(s, width)
  local len = #s
  if len >= width then return s end
  return s .. string.rep(" ", width - len)
end

--- Format a date value from CloudFront JSON.
--- CloudFront returns ISO-8601 strings (e.g. "2024-01-15T10:23:45.000Z").
--- Handles both string and number (epoch) just in case.
---@param value number|string|nil
---@return string
local function fmt_date(value)
  if not value then return "—" end
  local t = type(value)
  if t == "number" then
    return os.date("%Y-%m-%d %H:%M:%S UTC", math.floor(value))
  elseif t == "string" then
    local date, time = value:match("^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d:%d%d)")
    if date and time then return date .. " " .. time .. " UTC" end
    return value
  end
  return tostring(value)
end

--- Return a human-readable origin type label.
---@param origin table
---@return string
local function origin_type(origin)
  if type(origin.S3OriginConfig) == "table" then return "S3" end
  if type(origin.CustomOriginConfig) == "table" then return "Custom" end
  return "Unknown"
end

--- Return the viewer protocol policy of a cache behaviour, normalised.
---@param cb table
---@return string
local function viewer_protocol(cb)
  if type(cb) ~= "table" then return "—" end
  return cb.ViewerProtocolPolicy or "—"
end

---@param buf  integer
---@param id   string
local function render(buf, id)
  local st = _state[id]
  if not st then return end

  local d       = st.data
  local dist    = type(d.Distribution) == "table" and d.Distribution or d
  local cfg     = type(dist.DistributionConfig) == "table" and dist.DistributionConfig or {}
  local region  = st.region
  local profile = st.profile
  local km      = config.values.keymaps.cloudfront

  local lines = {}

  -- ── Title ─────────────────────────────────────────────────────────────────
  table.insert(lines, "")
  local title = "CloudFront  >>  " .. id
    .. "   [region: " .. region .. "]"
    .. (profile and ("   [profile: " .. profile .. "]") or "")
  table.insert(lines, title)
  table.insert(lines, "")

  -- ── Hint line ─────────────────────────────────────────────────────────────
  local sep_len = math.max(#title, 72)
  local sep     = string.rep("-", sep_len)
  table.insert(lines, sep)
  local hints = {}
  if km.detail_refresh    then table.insert(hints, km.detail_refresh    .. " refresh")    end
  if km.detail_invalidate then table.insert(hints, km.detail_invalidate .. " invalidate") end
  if #hints > 0 then
    table.insert(lines, table.concat(hints, "  |  "))
    table.insert(lines, sep)
  end

  local LABEL = 28
  local function row(label, value)
    table.insert(lines, "  " .. pad_right(label, LABEL) .. (value or "—"))
  end

  -- ── General ───────────────────────────────────────────────────────────────
  table.insert(lines, "General")
  table.insert(lines, sep)
  row("Distribution ID",  dist.Id)
  row("Domain Name",      dist.DomainName)
  row("Status",           dist.Status)
  row("Enabled",          cfg.Enabled ~= nil and tostring(cfg.Enabled) or "—")
  row("Comment",          cfg.Comment and cfg.Comment ~= "" and cfg.Comment or "—")
  row("HTTP Version",     cfg.HttpVersion)
  row("Price Class",      cfg.PriceClass)
  row("Last Modified",    fmt_date(dist.LastModifiedTime))

  -- ── Aliases (CNAMEs) ──────────────────────────────────────────────────────
  local aliases_cfg = type(cfg.Aliases) == "table" and cfg.Aliases or {}
  local alias_items = type(aliases_cfg.Items) == "table" and aliases_cfg.Items or {}
  if #alias_items > 0 then
    table.insert(lines, "")
    table.insert(lines, "Aliases (CNAMEs)")
    table.insert(lines, sep)
    for _, a in ipairs(alias_items) do
      table.insert(lines, "  " .. a)
    end
  end

  -- ── Origins ───────────────────────────────────────────────────────────────
  local origins_cfg = type(cfg.Origins) == "table" and cfg.Origins or {}
  local origin_items = type(origins_cfg.Items) == "table" and origins_cfg.Items or {}
  if #origin_items > 0 then
    table.insert(lines, "")
    table.insert(lines, "Origins")
    table.insert(lines, sep)
    for i, o in ipairs(origin_items) do
      if i > 1 then table.insert(lines, "") end
      row("  Origin ID",     o.Id)
      row("  Domain",        o.DomainName)
      row("  Type",          origin_type(o))
      row("  Path Prefix",   (o.OriginPath and o.OriginPath ~= "") and o.OriginPath or "—")
      if type(o.CustomOriginConfig) == "table" then
        local coc = o.CustomOriginConfig
        row("  HTTP Port",          tostring(coc.HTTPPort  or "—"))
        row("  HTTPS Port",         tostring(coc.HTTPSPort or "—"))
        row("  Protocol Policy",    coc.OriginProtocolPolicy)
        if type(coc.OriginSSLProtocols) == "table"
          and type(coc.OriginSSLProtocols.Items) == "table" then
          row("  SSL Protocols", table.concat(coc.OriginSSLProtocols.Items, ", "))
        end
      end
    end
  end

  -- ── Default Cache Behaviour ───────────────────────────────────────────────
  local dcb = type(cfg.DefaultCacheBehavior) == "table" and cfg.DefaultCacheBehavior or nil
  if dcb then
    table.insert(lines, "")
    table.insert(lines, "Default Cache Behaviour")
    table.insert(lines, sep)
    row("  Target Origin",       dcb.TargetOriginId)
    row("  Viewer Protocol",     viewer_protocol(dcb))
    -- Allowed methods
    local am = type(dcb.AllowedMethods) == "table" and dcb.AllowedMethods or {}
    if type(am.Items) == "table" then
      row("  Allowed Methods", table.concat(am.Items, ", "))
    end
    -- Cached methods
    if type(am.CachedMethods) == "table" and type(am.CachedMethods.Items) == "table" then
      row("  Cached Methods", table.concat(am.CachedMethods.Items, ", "))
    end
    -- TTLs
    if dcb.DefaultTTL then row("  Default TTL (s)",  tostring(dcb.DefaultTTL)) end
    if dcb.MinTTL     then row("  Min TTL (s)",      tostring(dcb.MinTTL))     end
    if dcb.MaxTTL     then row("  Max TTL (s)",      tostring(dcb.MaxTTL))     end
    row("  Compress",             dcb.Compress ~= nil and tostring(dcb.Compress) or "—")
  end

  -- ── Additional Cache Behaviours ───────────────────────────────────────────
  local cbs_cfg = type(cfg.CacheBehaviors) == "table" and cfg.CacheBehaviors or {}
  local cb_items = type(cbs_cfg.Items) == "table" and cbs_cfg.Items or {}
  if #cb_items > 0 then
    table.insert(lines, "")
    table.insert(lines, "Cache Behaviours (" .. #cb_items .. ")")
    table.insert(lines, sep)
    for i, cb in ipairs(cb_items) do
      if i > 1 then table.insert(lines, "") end
      row("  Path Pattern",    cb.PathPattern)
      row("  Target Origin",   cb.TargetOriginId)
      row("  Viewer Protocol", viewer_protocol(cb))
      if cb.DefaultTTL then row("  Default TTL (s)", tostring(cb.DefaultTTL)) end
    end
  end

  -- ── SSL / Viewer Certificate ──────────────────────────────────────────────
  local vc = type(cfg.ViewerCertificate) == "table" and cfg.ViewerCertificate or nil
  if vc then
    table.insert(lines, "")
    table.insert(lines, "SSL / Viewer Certificate")
    table.insert(lines, sep)
    if vc.CloudFrontDefaultCertificate then
      row("  Certificate",         "CloudFront default (*.cloudfront.net)")
    elseif vc.ACMCertificateArn then
      row("  Certificate",         "ACM")
      row("  ACM ARN",             vc.ACMCertificateArn)
    elseif vc.IAMCertificateId then
      row("  Certificate",         "IAM")
      row("  IAM Cert ID",         vc.IAMCertificateId)
    end
    row("  Min Protocol Version", vc.MinimumProtocolVersion)
    row("  SSL Support Method",   vc.SSLSupportMethod)
  end

  table.insert(lines, "")

  buf_mod.set_lines(buf, lines)
end

---@param id        string
---@param buf       integer
---@param call_opts AwsCallOpts|nil
local function fetch(id, buf, call_opts)
  buf_mod.set_loading(buf)

  spawn.run({
    "cloudfront", "get-distribution",
    "--id", id,
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

    _state[id] = {
      data    = data,
      region  = config.resolve_region(call_opts),
      profile = config.resolve_profile(call_opts),
    }
    render(buf, id)
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

  keymaps.apply_cloudfront_detail(buf, {
    refresh = function()
      fetch(id, buf, call_opts)
    end,

    invalidate = function()
      require("aws.cloudfront.invalidate").prompt(id, nil, call_opts)
    end,
  })

  fetch(id, buf, call_opts)
end

return M
