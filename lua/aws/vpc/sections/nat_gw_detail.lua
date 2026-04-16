--- aws.nvim – NAT Gateway detail buffer
--- Shows full metadata for a single NAT gateway.
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-vpc"
local _state = {}

local function buf_name(id)
  return "aws://vpc/detail/nat_gw/" .. id
end

local function kv(key, value)
  return string.format("  %-30s  %s", key, tostring(value or "—"))
end

local function section(title)
  return { "", title, string.rep("-", #title) }
end

local function tag_name(tags, fallback)
  if type(tags) == "table" then
    for _, t in ipairs(tags) do
      if t.Key == "Name" then
        return t.Value or fallback
      end
    end
  end
  return fallback
end

local function render(buf, id)
  local st = _state[id]
  if not st then
    return
  end

  local km = config.values.keymaps.vpc
  local hint = (km.detail_refresh or "R") .. " refresh"
  local sep = string.rep("-", 72)

  local title = id
  if st.nat then
    local n = tag_name(st.nat.Tags, nil)
    if n then
      title = n .. "  (" .. id .. ")"
    end
  end

  local lines = { "", "NAT Gateway:  " .. title, "", sep, hint, sep }

  for _, l in ipairs(section("General")) do
    table.insert(lines, l)
  end
  if st.nat then
    local n = st.nat
    table.insert(lines, kv("NAT Gateway ID", n.NatGatewayId))
    table.insert(lines, kv("Name", tag_name(n.Tags, "—")))
    table.insert(lines, kv("State", n.State))
    table.insert(lines, kv("VPC ID", n.VpcId))
    table.insert(lines, kv("Subnet ID", n.SubnetId))
    table.insert(lines, kv("Connectivity Type", n.ConnectivityType))
    table.insert(lines, kv("Created", n.CreateTime))

    -- addresses
    if type(n.NatGatewayAddresses) == "table" and #n.NatGatewayAddresses > 0 then
      for i, addr in ipairs(n.NatGatewayAddresses) do
        local prefix = "Address " .. i .. (addr.IsPrimary and " (primary)" or "")
        table.insert(lines, kv(prefix .. " – Public IP", addr.PublicIp))
        table.insert(lines, kv(prefix .. " – Private IP", addr.PrivateIp))
        if addr.AllocationId then
          table.insert(lines, kv(prefix .. " – Alloc ID", addr.AllocationId))
        end
      end
    end
  elseif st.nat == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  for _, l in ipairs(section("Tags")) do
    table.insert(lines, l)
  end
  if st.nat then
    local tags = st.nat.Tags or {}
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
  elseif st.nat == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

local function fetch(id, buf, call_opts)
  _state[id] = { nat = nil }
  buf_mod.set_loading(buf)
  spawn.run({ "ec2", "describe-nat-gateways", "--nat-gateway-ids", id, "--output", "json" }, function(ok, out)
    local st = _state[id]
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(out, "\n"))
      st.nat = (ok2 and type(data) == "table" and type(data.NatGateways) == "table" and data.NatGateways[1]) or false
    else
      st.nat = false
    end
    render(buf, id)
  end, call_opts)
end

---@param id        string  NAT gateway ID
---@param call_opts AwsCallOpts|nil
function M.open(id, call_opts)
  local buf = buf_mod.get_or_create(buf_name(id), FILETYPE)
  buf_mod.open_vsplit(buf)
  keymaps.apply_vpc_section(buf, {
    refresh = function()
      fetch(id, buf, call_opts)
    end,
  })
  fetch(id, buf, call_opts)
end

return M
