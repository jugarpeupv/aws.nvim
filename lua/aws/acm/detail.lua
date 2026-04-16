--- aws.nvim – ACM certificate detail view (vsplit)
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-acm"

--- Extract the certificate ID (last segment) from an ARN for use in buffer names.
--- e.g. "arn:aws:acm:us-east-1:123:certificate/abc-123" -> "abc-123"
---@param arn string
---@return string
local function cert_id(arn)
  return arn:match("[^/]+$") or arn
end

local function buf_name(arn)
  return "aws://acm/detail/" .. cert_id(arn)
end

-- Per-ARN state keyed by certificate ARN
local _state = {} -- arn -> { data, region, profile }

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

--- Format a Unix epoch float (from ACM JSON) to a readable datetime string.
---@param epoch number|nil
---@return string
--- Format a date value from ACM JSON.
--- ACM can return either a Unix epoch number (e.g. 1703123456.789) or an
--- ISO-8601 string (e.g. "2024-01-15T10:23:45+00:00") depending on the CLI
--- version and output format.
---@param value number|string|nil
---@return string
local function fmt_epoch(value)
  if not value then
    return "—"
  end
  local t = type(value)
  if t == "number" then
    return os.date("%Y-%m-%d %H:%M:%S UTC", math.floor(value))
  elseif t == "string" then
    -- Normalize ISO-8601: "2024-01-15T10:23:45+00:00" -> "2024-01-15 10:23:45 UTC"
    local date, time = value:match("^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d:%d%d)")
    if date and time then
      return date .. " " .. time .. " UTC"
    end
    return value
  end
  return tostring(value)
end

---@param buf integer
---@param arn string
local function render(buf, arn)
  local st = _state[arn]
  if not st then
    return
  end

  local d = st.data
  local region = st.region
  local profile = st.profile
  local km = config.values.keymaps.acm
  local icons = config.values.icons

  local domain = d.DomainName or cert_id(arn)

  local lines = {}

  -- Title
  table.insert(lines, "")
  local title = "ACM  >>  "
    .. domain
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
  if #hints > 0 then
    table.insert(lines, table.concat(hints, "  |  "))
    table.insert(lines, sep)
  end

  local function row(label, value)
    table.insert(lines, "  " .. pad_right(label, 20) .. (value or "—"))
  end

  -- Identifiers
  table.insert(lines, "Identifiers")
  table.insert(lines, string.rep("-", sep_len))
  row("ARN", d.CertificateArn)
  row("Certificate ID", cert_id(d.CertificateArn or ""))

  -- General
  table.insert(lines, "")
  table.insert(lines, "General")
  table.insert(lines, string.rep("-", sep_len))

  local status_icon
  local s = d.Status or ""
  if s == "ISSUED" then
    status_icon = icons.complete
  elseif s == "PENDING_VALIDATION" then
    status_icon = icons.in_progress
  elseif s == "EXPIRED" or s == "REVOKED" or s == "FAILED" then
    status_icon = icons.failed
  else
    status_icon = icons.stack
  end

  row("Domain", d.DomainName)
  row("Type", d.Type)
  row("Status", status_icon .. " " .. s)
  row("Key Algorithm", d.KeyAlgorithm)
  row("Created", fmt_epoch(d.CreatedAt))
  row("Issued", fmt_epoch(d.IssuedAt))
  row("Expiry", fmt_epoch(d.NotAfter))
  row("Renewal Elig.", d.RenewalEligibility)

  -- Subject / Issuer / Serial
  table.insert(lines, "")
  table.insert(lines, "Certificate Details")
  table.insert(lines, string.rep("-", sep_len))
  row("Subject", d.Subject)
  row("Issuer", d.Issuer)
  row("Serial", d.Serial)

  -- Subject Alternative Names
  if type(d.SubjectAlternativeNames) == "table" and #d.SubjectAlternativeNames > 0 then
    table.insert(lines, "")
    table.insert(lines, "Subject Alternative Names")
    table.insert(lines, string.rep("-", sep_len))
    for _, san in ipairs(d.SubjectAlternativeNames) do
      table.insert(lines, "  " .. san)
    end
  end

  -- Domain Validation Options
  if type(d.DomainValidationOptions) == "table" and #d.DomainValidationOptions > 0 then
    table.insert(lines, "")
    table.insert(lines, "Domain Validation")
    table.insert(lines, string.rep("-", sep_len))
    for _, opt in ipairs(d.DomainValidationOptions) do
      local vdomain = opt.DomainName or "?"
      local method = opt.ValidationMethod or "?"
      local vstatus = opt.ValidationStatus or "?"
      table.insert(lines, "  " .. vdomain)
      table.insert(lines, "    " .. pad_right("Method", 16) .. method)
      table.insert(lines, "    " .. pad_right("Status", 16) .. vstatus)
      -- DNS CNAME record (very useful for users to copy)
      if type(opt.ResourceRecord) == "table" then
        local rr = opt.ResourceRecord
        table.insert(lines, "    " .. pad_right("CNAME Name", 16) .. (rr.Name or "—"))
        table.insert(lines, "    " .. pad_right("CNAME Value", 16) .. (rr.Value or "—"))
      end
    end
  end

  -- In-use resources
  if type(d.InUseBy) == "table" and #d.InUseBy > 0 then
    table.insert(lines, "")
    table.insert(lines, "In Use By")
    table.insert(lines, string.rep("-", sep_len))
    for _, resource in ipairs(d.InUseBy) do
      table.insert(lines, "  " .. resource)
    end
  else
    table.insert(lines, "")
    table.insert(lines, "In Use By")
    table.insert(lines, string.rep("-", sep_len))
    table.insert(lines, "  (not attached to any resource)")
  end

  table.insert(lines, "")

  buf_mod.set_lines(buf, lines)
end

---@param arn       string
---@param buf       integer
---@param call_opts AwsCallOpts|nil
local function fetch(arn, buf, call_opts)
  buf_mod.set_loading(buf)

  spawn.run({
    "acm",
    "describe-certificate",
    "--certificate-arn",
    arn,
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

    -- describe-certificate wraps result in { Certificate: { ... } }
    local cert = (type(data.Certificate) == "table") and data.Certificate or data

    _state[arn] = {
      data = cert,
      region = config.resolve_region(call_opts),
      profile = config.resolve_profile(call_opts),
    }
    render(buf, arn)
  end, call_opts)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param arn       string
---@param call_opts AwsCallOpts|nil
function M.open(arn, call_opts)
  local buf = buf_mod.get_or_create(buf_name(arn), FILETYPE)
  buf_mod.open_vsplit(buf)

  keymaps.apply_acm_detail(buf, {
    refresh = function()
      fetch(arn, buf, call_opts)
    end,
  })

  fetch(arn, buf, call_opts)
end

return M
