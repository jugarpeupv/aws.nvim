--- aws.nvim – IAM Policy detail view
--- Parallel fetches: get-policy, list-policy-versions, list-entities-for-policy
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-iam"

local _state = {}

local function buf_name(arn)
  -- Replace slashes and colons with underscores for a valid buffer name
  return "aws://iam/detail/policy/" .. arn:gsub("[:/]", "_")
end

local function kv(key, value)
  return string.format("  %-24s  %s", key, tostring(value or "—"))
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
  local lines = { "", "IAM  Policy: " .. arn, "", sep, hint, sep }

  -- General
  for _, l in ipairs(section("General")) do
    table.insert(lines, l)
  end
  if st.policy then
    local p = st.policy
    table.insert(lines, kv("PolicyName", p.PolicyName))
    table.insert(lines, kv("PolicyId", p.PolicyId))
    table.insert(lines, kv("ARN", p.Arn))
    table.insert(lines, kv("Path", p.Path))
    table.insert(lines, kv("Description", p.Description))
    table.insert(lines, kv("DefaultVersion", p.DefaultVersionId))
    table.insert(lines, kv("AttachmentCount", tostring(p.AttachmentCount or 0)))
    table.insert(lines, kv("Created", p.CreateDate))
    table.insert(lines, kv("Updated", p.UpdateDate))
  else
    table.insert(lines, st.policy == false and "  (error)" or "  [loading…]")
  end

  -- Versions
  for _, l in ipairs(section("Versions")) do
    table.insert(lines, l)
  end
  if st.versions then
    if #st.versions == 0 then
      table.insert(lines, "  (none)")
    else
      for _, v in ipairs(st.versions) do
        local def = v.IsDefaultVersion and " [default]" or ""
        table.insert(lines, string.format("  %-8s  %s%s", v.VersionId or "", v.CreateDate or "", def))
      end
    end
  else
    table.insert(lines, st.versions == false and "  (error)" or "  [loading…]")
  end

  -- Attached to (users / groups / roles)
  for _, l in ipairs(section("Attached To")) do
    table.insert(lines, l)
  end
  if st.entities then
    local any = false
    if st.entities.users and #st.entities.users > 0 then
      table.insert(lines, "  Users:")
      for _, u in ipairs(st.entities.users) do
        table.insert(lines, "    " .. (u.UserName or ""))
      end
      any = true
    end
    if st.entities.groups and #st.entities.groups > 0 then
      table.insert(lines, "  Groups:")
      for _, g in ipairs(st.entities.groups) do
        table.insert(lines, "    " .. (g.GroupName or ""))
      end
      any = true
    end
    if st.entities.roles and #st.entities.roles > 0 then
      table.insert(lines, "  Roles:")
      for _, r in ipairs(st.entities.roles) do
        table.insert(lines, "    " .. (r.RoleName or ""))
      end
      any = true
    end
    if not any then
      table.insert(lines, "  (none)")
    end
  else
    table.insert(lines, st.entities == false and "  (error)" or "  [loading…]")
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

local function fetch(arn, buf, call_opts)
  buf_mod.set_loading(buf)
  local st = { policy = nil, versions = nil, entities = nil }
  _state[arn] = st
  local pending = 3

  local function on_done()
    pending = pending - 1
    if pending > 0 then
      return
    end
    render(buf, arn)
  end

  spawn.run({ "iam", "get-policy", "--policy-arn", arn, "--output", "json" }, function(ok, lines)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
      st.policy = (ok2 and type(data) == "table" and data.Policy) or false
    else
      st.policy = false
    end
    on_done()
  end, call_opts)

  spawn.run({ "iam", "list-policy-versions", "--policy-arn", arn, "--output", "json" }, function(ok, lines)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
      st.versions = (ok2 and type(data) == "table" and type(data.Versions) == "table" and data.Versions) or {}
    else
      st.versions = false
    end
    on_done()
  end, call_opts)

  spawn.run({ "iam", "list-entities-for-policy", "--policy-arn", arn, "--output", "json" }, function(ok, lines)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
      if ok2 and type(data) == "table" then
        st.entities = {
          users = type(data.PolicyUsers) == "table" and data.PolicyUsers or {},
          groups = type(data.PolicyGroups) == "table" and data.PolicyGroups or {},
          roles = type(data.PolicyRoles) == "table" and data.PolicyRoles or {},
        }
      else
        st.entities = false
      end
    else
      st.entities = false
    end
    on_done()
  end, call_opts)
end

---@param arn        string
---@param call_opts  AwsCallOpts|nil
function M.open(arn, call_opts)
  local buf = buf_mod.get_or_create(buf_name(arn), FILETYPE)
  buf_mod.open_vsplit(buf)
  keymaps.apply_iam_detail(buf, {
    refresh = function()
      fetch(arn, buf, call_opts)
    end,
  })
  fetch(arn, buf, call_opts)
end

return M
