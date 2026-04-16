--- aws.nvim – Subnet detail buffer
--- Shows full metadata for a single subnet.
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-vpc"
local _state = {}

local function buf_name(id)
  return "aws://vpc/detail/subnet/" .. id
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
  if st.subnet then
    local n = tag_name(st.subnet.Tags, nil)
    if n then
      title = n .. "  (" .. id .. ")"
    end
  end

  local lines = { "", "Subnet:  " .. title, "", sep, hint, sep }

  for _, l in ipairs(section("General")) do
    table.insert(lines, l)
  end
  if st.subnet then
    local s = st.subnet
    table.insert(lines, kv("Subnet ID", s.SubnetId))
    table.insert(lines, kv("Name", tag_name(s.Tags, "—")))
    table.insert(lines, kv("State", s.State))
    table.insert(lines, kv("VPC ID", s.VpcId))
    table.insert(lines, kv("CIDR Block", s.CidrBlock))
    table.insert(lines, kv("Availability Zone", s.AvailabilityZone))
    table.insert(lines, kv("AZ ID", s.AvailabilityZoneId))
    table.insert(lines, kv("Available IPs", tostring(s.AvailableIpAddressCount or "?")))
    table.insert(lines, kv("Default for AZ", s.DefaultForAz and "yes" or "no"))
    table.insert(lines, kv("Map Public IP", s.MapPublicIpOnLaunch and "yes" or "no"))
    table.insert(lines, kv("Owner ID", s.OwnerId))
    table.insert(lines, kv("Subnet ARN", s.SubnetArn))
  elseif st.subnet == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  for _, l in ipairs(section("Tags")) do
    table.insert(lines, l)
  end
  if st.subnet then
    local tags = st.subnet.Tags or {}
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
  elseif st.subnet == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

local function fetch(id, buf, call_opts)
  _state[id] = { subnet = nil }
  buf_mod.set_loading(buf)
  spawn.run({ "ec2", "describe-subnets", "--subnet-ids", id, "--output", "json" }, function(ok, out)
    local st = _state[id]
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(out, "\n"))
      st.subnet = (ok2 and type(data) == "table" and type(data.Subnets) == "table" and data.Subnets[1]) or false
    else
      st.subnet = false
    end
    render(buf, id)
  end, call_opts)
end

---@param id        string  subnet ID
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
