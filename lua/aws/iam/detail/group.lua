--- aws.nvim – IAM Group detail view
--- Parallel fetches: get-group (members), list-attached-group-policies, list-group-policies
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-iam"

local _state = {}

local function buf_name(name)
  return "aws://iam/detail/group/" .. name
end

local function kv(key, value)
  return string.format("  %-24s  %s", key, tostring(value or "—"))
end

local function section(title)
  return { "", title, string.rep("-", #title) }
end

local function render(buf, name)
  local st = _state[name]
  if not st then
    return
  end

  local km = config.values.keymaps.iam
  local hint = (km.detail_refresh or "R") .. " refresh"
  local sep = string.rep("-", 72)
  local lines = { "", "IAM  Group: " .. name, "", sep, hint, sep }

  -- General
  for _, l in ipairs(section("General")) do
    table.insert(lines, l)
  end
  if st.group then
    table.insert(lines, kv("GroupName", st.group.GroupName))
    table.insert(lines, kv("GroupId", st.group.GroupId))
    table.insert(lines, kv("ARN", st.group.Arn))
    table.insert(lines, kv("Path", st.group.Path))
    table.insert(lines, kv("Created", st.group.CreateDate))
  else
    table.insert(lines, st.group == false and "  (error)" or "  [loading…]")
  end

  -- Members
  for _, l in ipairs(section("Members")) do
    table.insert(lines, l)
  end
  if st.members then
    if #st.members == 0 then
      table.insert(lines, "  (none)")
    else
      for _, u in ipairs(st.members) do
        table.insert(lines, "  " .. (u.UserName or ""))
      end
    end
  else
    table.insert(lines, st.members == false and "  (error)" or "  [loading…]")
  end

  -- Attached Policies
  for _, l in ipairs(section("Attached Policies")) do
    table.insert(lines, l)
  end
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
  for _, l in ipairs(section("Inline Policies")) do
    table.insert(lines, l)
  end
  if st.inline then
    if #st.inline == 0 then
      table.insert(lines, "  (none)")
    else
      for _, n in ipairs(st.inline) do
        table.insert(lines, "  " .. n)
      end
    end
  else
    table.insert(lines, st.inline == false and "  (error)" or "  [loading…]")
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

local function fetch(name, buf, call_opts)
  buf_mod.set_loading(buf)
  local st = { group = nil, members = nil, attached = nil, inline = nil }
  _state[name] = st
  local pending = 3

  local function on_done()
    pending = pending - 1
    if pending > 0 then
      return
    end
    render(buf, name)
  end

  -- get-group returns both group metadata and member list
  spawn.run({ "iam", "get-group", "--group-name", name, "--output", "json" }, function(ok, lines)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
      if ok2 and type(data) == "table" then
        st.group = data.Group or false
        st.members = type(data.Users) == "table" and data.Users or {}
      else
        st.group = false
        st.members = false
      end
    else
      st.group = false
      st.members = false
    end
    on_done()
  end, call_opts)

  spawn.run({ "iam", "list-attached-group-policies", "--group-name", name, "--output", "json" }, function(ok, lines)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
      st.attached = (ok2 and type(data) == "table" and type(data.AttachedPolicies) == "table" and data.AttachedPolicies)
        or {}
    else
      st.attached = false
    end
    on_done()
  end, call_opts)

  spawn.run({ "iam", "list-group-policies", "--group-name", name, "--output", "json" }, function(ok, lines)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
      st.inline = (ok2 and type(data) == "table" and type(data.PolicyNames) == "table" and data.PolicyNames) or {}
    else
      st.inline = false
    end
    on_done()
  end, call_opts)
end

---@param name       string
---@param call_opts  AwsCallOpts|nil
function M.open(name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(name), FILETYPE)
  buf_mod.open_vsplit(buf)
  keymaps.apply_iam_detail(buf, {
    refresh = function()
      fetch(name, buf, call_opts)
    end,
  })
  fetch(name, buf, call_opts)
end

return M
