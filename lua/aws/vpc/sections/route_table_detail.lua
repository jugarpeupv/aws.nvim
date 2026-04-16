--- aws.nvim – Route Table detail buffer
--- Shows full route list and subnet associations for a single route table.
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-vpc"
local _state = {}

local function buf_name(id)
  return "aws://vpc/detail/route_table/" .. id
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
  if st.rt then
    local n = tag_name(st.rt.Tags, nil)
    if n then
      title = n .. "  (" .. id .. ")"
    end
  end

  local lines = { "", "Route Table:  " .. title, "", sep, hint, sep }

  for _, l in ipairs(section("General")) do
    table.insert(lines, l)
  end
  if st.rt then
    local rt = st.rt
    table.insert(lines, kv("Route Table ID", rt.RouteTableId))
    table.insert(lines, kv("Name", tag_name(rt.Tags, "—")))
    table.insert(lines, kv("VPC ID", rt.VpcId))
    table.insert(lines, kv("Owner ID", rt.OwnerId))
  elseif st.rt == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  for _, l in ipairs(section("Routes")) do
    table.insert(lines, l)
  end
  if st.rt then
    local routes = {}
    if type(st.rt.Routes) == "table" then
      for _, r in ipairs(st.rt.Routes) do
        local dest = r.DestinationCidrBlock or r.DestinationIpv6CidrBlock or r.DestinationPrefixListId or "?"
        local target = r.GatewayId
          or r.NatGatewayId
          or r.TransitGatewayId
          or r.VpcPeeringConnectionId
          or r.NetworkInterfaceId
          or r.InstanceId
          or "?"
        table.insert(routes, { dest = dest, target = target, state = r.State or "?" })
      end
      table.sort(routes, function(a, b)
        return a.dest < b.dest
      end)
    end
    if #routes == 0 then
      table.insert(lines, "  (none)")
    else
      table.insert(lines, string.format("  %-30s  %-34s  %s", "Destination", "Target", "State"))
      table.insert(lines, "  " .. string.rep("-", 74))
      for _, r in ipairs(routes) do
        table.insert(lines, string.format("  %-30s  %-34s  %s", r.dest, r.target, r.state))
      end
    end
  elseif st.rt == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  for _, l in ipairs(section("Subnet Associations")) do
    table.insert(lines, l)
  end
  if st.rt then
    local subs = {}
    local main_assoc = false
    if type(st.rt.Associations) == "table" then
      for _, a in ipairs(st.rt.Associations) do
        if a.SubnetId then
          table.insert(subs, a.SubnetId)
        elseif a.Main then
          main_assoc = true
        end
      end
    end
    if main_assoc then
      table.insert(lines, "  (main route table for VPC)")
    end
    if #subs == 0 and not main_assoc then
      table.insert(lines, "  (none)")
    else
      for _, sub in ipairs(subs) do
        table.insert(lines, "  " .. sub)
      end
    end
  elseif st.rt == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  for _, l in ipairs(section("Tags")) do
    table.insert(lines, l)
  end
  if st.rt then
    local tags = st.rt.Tags or {}
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
  elseif st.rt == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

local function fetch(id, vpc_id, buf, call_opts)
  _state[id] = { rt = nil }
  buf_mod.set_loading(buf)
  local args = { "ec2", "describe-route-tables", "--route-table-ids", id, "--output", "json" }
  spawn.run(args, function(ok, out)
    local st = _state[id]
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(out, "\n"))
      st.rt = (ok2 and type(data) == "table" and type(data.RouteTables) == "table" and data.RouteTables[1]) or false
    else
      st.rt = false
    end
    render(buf, id)
  end, call_opts)
end

---@param id        string  route table ID
---@param vpc_id    string
---@param call_opts AwsCallOpts|nil
function M.open(id, vpc_id, call_opts)
  local buf = buf_mod.get_or_create(buf_name(id), FILETYPE)
  buf_mod.open_vsplit(buf)
  keymaps.apply_vpc_section(buf, {
    refresh = function()
      fetch(id, vpc_id, buf, call_opts)
    end,
  })
  fetch(id, vpc_id, buf, call_opts)
end

return M
