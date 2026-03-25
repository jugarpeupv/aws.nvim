--- aws.nvim – IAM User detail view
--- Parallel fetches: get-user, list-groups-for-user, list-attached-user-policies,
---                   list-user-policies (inline), list-mfa-devices, list-access-keys
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-iam"

local _state = {}  -- username -> state

local function buf_name(username)
  return "aws://iam/detail/user/" .. username
end

local function kv(key, value)
  return string.format("  %-24s  %s", key, tostring(value or "—"))
end

local function section(title)
  return { "", title, string.rep("-", #title) }
end

local function render(buf, username)
  local st = _state[username]
  if not st then return end

  local km = config.values.keymaps.iam
  local hint = (km.detail_refresh or "R") .. " refresh"
  local sep  = string.rep("-", 72)

  local lines = { "", "IAM  User: " .. username, "", sep, hint, sep }

  -- General
  for _, l in ipairs(section("General")) do table.insert(lines, l) end
  if st.user then
    local u = st.user
    table.insert(lines, kv("UserName",   u.UserName))
    table.insert(lines, kv("UserId",     u.UserId))
    table.insert(lines, kv("ARN",        u.Arn))
    table.insert(lines, kv("Path",       u.Path))
    table.insert(lines, kv("Created",    u.CreateDate))
    table.insert(lines, kv("PasswordLastUsed", u.PasswordLastUsed))
  else
    table.insert(lines, st.user == false and "  (error loading user)" or "  [loading…]")
  end

  -- Groups
  for _, l in ipairs(section("Groups")) do table.insert(lines, l) end
  if st.groups then
    if #st.groups == 0 then
      table.insert(lines, "  (none)")
    else
      for _, g in ipairs(st.groups) do
        table.insert(lines, "  " .. (g.GroupName or g))
      end
    end
  else
    table.insert(lines, st.groups == false and "  (error loading groups)" or "  [loading…]")
  end

  -- Attached Policies
  for _, l in ipairs(section("Attached Policies")) do table.insert(lines, l) end
  if st.attached then
    if #st.attached == 0 then
      table.insert(lines, "  (none)")
    else
      for _, p in ipairs(st.attached) do
        table.insert(lines, "  " .. (p.PolicyName or "") .. "   " .. (p.PolicyArn or ""))
      end
    end
  else
    table.insert(lines, st.attached == false and "  (error)" or "  [loading…]")
  end

  -- Inline Policies
  for _, l in ipairs(section("Inline Policies")) do table.insert(lines, l) end
  if st.inline then
    if #st.inline == 0 then
      table.insert(lines, "  (none)")
    else
      for _, name in ipairs(st.inline) do
        table.insert(lines, "  " .. name)
      end
    end
  else
    table.insert(lines, st.inline == false and "  (error)" or "  [loading…]")
  end

  -- Access Keys
  for _, l in ipairs(section("Access Keys")) do table.insert(lines, l) end
  if st.access_keys then
    if #st.access_keys == 0 then
      table.insert(lines, "  (none)")
    else
      for _, k in ipairs(st.access_keys) do
        table.insert(lines,
          string.format("  %-22s  %-10s  %s", k.AccessKeyId or "", k.Status or "", k.CreateDate or ""))
      end
    end
  else
    table.insert(lines, st.access_keys == false and "  (error)" or "  [loading…]")
  end

  -- MFA Devices
  for _, l in ipairs(section("MFA Devices")) do table.insert(lines, l) end
  if st.mfa then
    if #st.mfa == 0 then
      table.insert(lines, "  (none)")
    else
      for _, d in ipairs(st.mfa) do
        table.insert(lines, "  " .. (d.SerialNumber or "") .. "   enabled: " .. tostring(d.EnableDate or "?"))
      end
    end
  else
    table.insert(lines, st.mfa == false and "  (error)" or "  [loading…]")
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

local function fetch(username, buf, call_opts)
  buf_mod.set_loading(buf)
  local st = { user = nil, groups = nil, attached = nil, inline = nil, mfa = nil, access_keys = nil }
  _state[username] = st
  local pending = 5

  local function on_done()
    pending = pending - 1
    if pending > 0 then return end
    render(buf, username)
  end

  -- get-user
  spawn.run({ "iam", "get-user", "--user-name", username, "--output", "json" },
    function(ok, lines)
      if ok then
        local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
        st.user = (ok2 and type(data) == "table" and data.User) or false
      else
        st.user = false
      end
      on_done()
    end, call_opts)

  -- list-groups-for-user
  spawn.run({ "iam", "list-groups-for-user", "--user-name", username, "--output", "json" },
    function(ok, lines)
      if ok then
        local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
        st.groups = (ok2 and type(data) == "table" and type(data.Groups) == "table" and data.Groups) or {}
      else
        st.groups = false
      end
      on_done()
    end, call_opts)

  -- list-attached-user-policies
  spawn.run({ "iam", "list-attached-user-policies", "--user-name", username, "--output", "json" },
    function(ok, lines)
      if ok then
        local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
        st.attached = (ok2 and type(data) == "table" and type(data.AttachedPolicies) == "table" and data.AttachedPolicies) or {}
      else
        st.attached = false
      end
      on_done()
    end, call_opts)

  -- list-user-policies (inline)
  spawn.run({ "iam", "list-user-policies", "--user-name", username, "--output", "json" },
    function(ok, lines)
      if ok then
        local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
        st.inline = (ok2 and type(data) == "table" and type(data.PolicyNames) == "table" and data.PolicyNames) or {}
      else
        st.inline = false
      end
      on_done()
    end, call_opts)

  -- list-access-keys + list-mfa-devices combined into one pending slot each
  pending = pending + 1  -- add one more for mfa

  spawn.run({ "iam", "list-access-keys", "--user-name", username, "--output", "json" },
    function(ok, lines)
      if ok then
        local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
        st.access_keys = (ok2 and type(data) == "table" and type(data.AccessKeyMetadata) == "table" and data.AccessKeyMetadata) or {}
      else
        st.access_keys = false
      end
      on_done()
    end, call_opts)

  spawn.run({ "iam", "list-mfa-devices", "--user-name", username, "--output", "json" },
    function(ok, lines)
      if ok then
        local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
        st.mfa = (ok2 and type(data) == "table" and type(data.MFADevices) == "table" and data.MFADevices) or {}
      else
        st.mfa = false
      end
      on_done()
    end, call_opts)
end

---@param username   string
---@param call_opts  AwsCallOpts|nil
function M.open(username, call_opts)
  local buf = buf_mod.get_or_create(buf_name(username), FILETYPE)
  buf_mod.open_vsplit(buf)

  keymaps.apply_iam_detail(buf, {
    refresh = function() fetch(username, buf, call_opts) end,
  })

  fetch(username, buf, call_opts)
end

return M
