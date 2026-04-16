--- aws.nvim – Security Group detail buffer
--- Fetches full inbound + outbound rules for a single security group via
---   ec2 describe-security-groups --group-ids <id>
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-vpc"

local _state = {}

local function buf_name(sg_id)
  return "aws://vpc/sg/" .. sg_id
end

local function kv(key, value)
  return string.format("  %-26s  %s", key, tostring(value or "—"))
end

local function section(title)
  return { "", title, string.rep("-", #title) }
end

--- Format a single IP permission rule as a human-readable string.
--- Returns a list of lines (one per IP range / prefix list / user-id-group pair).
local function fmt_rule(perm)
  local proto = perm.IpProtocol or "?"
  local port_str
  if proto == "-1" then
    proto = "All"
    port_str = "All"
  elseif perm.FromPort ~= nil then
    if perm.FromPort == perm.ToPort then
      port_str = tostring(perm.FromPort)
    else
      port_str = perm.FromPort .. "-" .. perm.ToPort
    end
  else
    port_str = "—"
  end

  local prefix = string.format("  %-6s  %-9s  ", proto, port_str)
  local lines = {}

  -- IPv4 ranges
  if type(perm.IpRanges) == "table" then
    for _, r in ipairs(perm.IpRanges) do
      local src = r.CidrIp or "?"
      local desc = r.Description and ("  " .. r.Description) or ""
      table.insert(lines, prefix .. src .. desc)
    end
  end

  -- IPv6 ranges
  if type(perm.Ipv6Ranges) == "table" then
    for _, r in ipairs(perm.Ipv6Ranges) do
      local src = r.CidrIpv6 or "?"
      local desc = r.Description and ("  " .. r.Description) or ""
      table.insert(lines, prefix .. src .. desc)
    end
  end

  -- Prefix lists
  if type(perm.PrefixListIds) == "table" then
    for _, pl in ipairs(perm.PrefixListIds) do
      local src = pl.PrefixListId or "?"
      local desc = pl.Description and ("  " .. pl.Description) or ""
      table.insert(lines, prefix .. src .. desc)
    end
  end

  -- Security group references
  if type(perm.UserIdGroupPairs) == "table" then
    for _, pair in ipairs(perm.UserIdGroupPairs) do
      local src = pair.GroupId or "?"
      if pair.GroupName and pair.GroupName ~= "" then
        src = src .. "  (" .. pair.GroupName .. ")"
      end
      local desc = pair.Description and ("  " .. pair.Description) or ""
      table.insert(lines, prefix .. src .. desc)
    end
  end

  -- fallback if no sources were listed
  if #lines == 0 then
    table.insert(lines, prefix .. "—")
  end

  return lines
end

local function render(buf, sg_id)
  local st = _state[sg_id]
  if not st then
    return
  end

  local km = config.values.keymaps.vpc
  local hint = (km.detail_refresh or "R") .. " refresh"
  local sep = string.rep("-", 72)

  local title = sg_id
  if st.sg then
    local name = st.sg.GroupName
    if name and name ~= "" and name ~= sg_id then
      title = name .. "  (" .. sg_id .. ")"
    end
  end

  local lines = { "", "Security Group:  " .. title, "", sep, hint, sep }

  -- ── General ────────────────────────────────────────────────────────────────
  for _, l in ipairs(section("General")) do
    table.insert(lines, l)
  end
  if st.sg then
    local sg = st.sg
    table.insert(lines, kv("Group ID", sg.GroupId))
    table.insert(lines, kv("Name", sg.GroupName))
    table.insert(lines, kv("Description", sg.Description))
    table.insert(lines, kv("VPC ID", sg.VpcId))
    table.insert(lines, kv("Owner ID", sg.OwnerId))
  elseif st.sg == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  -- ── Tags ───────────────────────────────────────────────────────────────────
  for _, l in ipairs(section("Tags")) do
    table.insert(lines, l)
  end
  if st.sg then
    local tags = st.sg.Tags or {}
    if #tags == 0 then
      table.insert(lines, "  (none)")
    else
      local sorted = vim.deepcopy(tags)
      table.sort(sorted, function(a, b)
        return (a.Key or "") < (b.Key or "")
      end)
      for _, t in ipairs(sorted) do
        table.insert(lines, kv(t.Key, t.Value))
      end
    end
  elseif st.sg == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  -- ── Inbound Rules ─────────────────────────────────────────────────────────
  for _, l in ipairs(section("Inbound Rules")) do
    table.insert(lines, l)
  end
  if st.sg then
    local perms = st.sg.IpPermissions or {}
    if #perms == 0 then
      table.insert(lines, "  (none)")
    else
      table.insert(lines, "  Proto   Port       Source / Destination")
      table.insert(lines, "  " .. string.rep("-", 60))
      for _, perm in ipairs(perms) do
        for _, l in ipairs(fmt_rule(perm)) do
          table.insert(lines, l)
        end
      end
    end
  elseif st.sg == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  -- ── Outbound Rules ────────────────────────────────────────────────────────
  for _, l in ipairs(section("Outbound Rules")) do
    table.insert(lines, l)
  end
  if st.sg then
    local perms = st.sg.IpPermissionsEgress or {}
    if #perms == 0 then
      table.insert(lines, "  (none)")
    else
      table.insert(lines, "  Proto   Port       Source / Destination")
      table.insert(lines, "  " .. string.rep("-", 60))
      for _, perm in ipairs(perms) do
        for _, l in ipairs(fmt_rule(perm)) do
          table.insert(lines, l)
        end
      end
    end
  elseif st.sg == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

local function fetch(sg_id, buf, call_opts)
  buf_mod.set_loading(buf)
  _state[sg_id] = { sg = nil }
  local st = _state[sg_id]

  spawn.run({ "ec2", "describe-security-groups", "--group-ids", sg_id, "--output", "json" }, function(ok, out)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(out, "\n"))
      st.sg = (ok2 and type(data) == "table" and type(data.SecurityGroups) == "table" and data.SecurityGroups[1])
        or false
    else
      st.sg = false
    end
    render(buf, sg_id)
  end, call_opts)
end

---@param sg_id     string
---@param call_opts AwsCallOpts|nil
function M.open(sg_id, call_opts)
  local buf = buf_mod.get_or_create(buf_name(sg_id), FILETYPE)
  buf_mod.open_vsplit(buf)
  keymaps.apply_vpc_detail(buf, {
    refresh = function()
      fetch(sg_id, buf, call_opts)
    end,
  })
  fetch(sg_id, buf, call_opts)
end

return M
