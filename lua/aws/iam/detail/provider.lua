--- aws.nvim – IAM Identity Provider detail view
--- OIDC: get-open-id-connect-provider
--- SAML: get-saml-provider
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-iam"

local _state = {}

local function buf_name(arn)
  return "aws://iam/detail/provider/" .. arn:gsub("[:/]", "_")
end

local function kv(key, value)
  return string.format("  %-30s  %s", key, tostring(value or "—"))
end

local function section(title)
  return { "", title, string.rep("-", #title) }
end

local function render(buf, arn)
  local st = _state[arn]
  if not st then
    return
  end

  local km = config.values.keymaps.iam
  local hint = (km.detail_refresh or "R") .. " refresh"
  local sep = string.rep("-", 72)
  local short = arn:match("/([^/]+)$") or arn
  local lines = { "", "IAM  Identity Provider: " .. short, "", sep, hint, sep }

  -- OIDC
  if st.kind == "OIDC" then
    for _, l in ipairs(section("OIDC Provider")) do
      table.insert(lines, l)
    end
    if st.data then
      table.insert(lines, kv("ARN", arn))
      table.insert(lines, kv("URL", st.data.Url))
      table.insert(lines, kv("Created", st.data.CreateDate))
      -- Client IDs
      for _, l in ipairs(section("Client IDs")) do
        table.insert(lines, l)
      end
      local cids = type(st.data.ClientIDList) == "table" and st.data.ClientIDList or {}
      if #cids == 0 then
        table.insert(lines, "  (none)")
      else
        for _, id in ipairs(cids) do
          table.insert(lines, "  " .. id)
        end
      end
      -- Thumbprints
      for _, l in ipairs(section("Thumbprints")) do
        table.insert(lines, l)
      end
      local tps = type(st.data.ThumbprintList) == "table" and st.data.ThumbprintList or {}
      if #tps == 0 then
        table.insert(lines, "  (none)")
      else
        for _, tp in ipairs(tps) do
          table.insert(lines, "  " .. tp)
        end
      end
    else
      table.insert(lines, st.data == false and "  (error)" or "  [loading…]")
    end

  -- SAML
  elseif st.kind == "SAML" then
    for _, l in ipairs(section("SAML Provider")) do
      table.insert(lines, l)
    end
    if st.data then
      table.insert(lines, kv("ARN", arn))
      table.insert(lines, kv("ValidUntil", st.data.ValidUntil))
      table.insert(lines, kv("Created", st.data.CreateDate))
      -- The SAML metadata XML is very long; show only a summary
      local doc = st.data.SAMLMetadataDocument
      if doc then
        table.insert(lines, "")
        table.insert(lines, "SAML Metadata Document  (" .. #doc .. " bytes)")
        table.insert(lines, string.rep("-", 40))
        -- Show first 10 lines of the XML
        local n = 0
        for line in (doc .. "\n"):gmatch("([^\n]*)\n") do
          table.insert(lines, line)
          n = n + 1
          if n >= 10 then
            table.insert(lines, "  … (truncated)")
            break
          end
        end
      end
    else
      table.insert(lines, st.data == false and "  (error)" or "  [loading…]")
    end
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

local function fetch(arn, kind, buf, call_opts)
  buf_mod.set_loading(buf)
  local st = { kind = kind, data = nil }
  _state[arn] = st

  local cmd, key -- luacheck: ignore 231
  if kind == "OIDC" then
    cmd = { "iam", "get-open-id-connect-provider", "--open-id-connect-provider-arn", arn, "--output", "json" }
    key = nil -- full object is the provider
  else
    cmd = { "iam", "get-saml-provider", "--saml-provider-arn", arn, "--output", "json" }
    key = nil
  end

  spawn.run(cmd, function(ok, lines)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
      st.data = (ok2 and type(data) == "table") and data or false
    else
      st.data = false
    end
    render(buf, arn)
  end, call_opts)
end

---@param arn        string
---@param kind       string  "OIDC"|"SAML"
---@param call_opts  AwsCallOpts|nil
function M.open(arn, kind, call_opts)
  local buf = buf_mod.get_or_create(buf_name(arn), FILETYPE)
  buf_mod.open_vsplit(buf)
  keymaps.apply_iam_detail(buf, {
    refresh = function()
      fetch(arn, kind, buf, call_opts)
    end,
  })
  fetch(arn, kind, buf, call_opts)
end

return M
