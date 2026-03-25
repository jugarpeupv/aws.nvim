--- aws.nvim – VPC Route Tables section buffer
--- Lists route tables for a VPC with <CR> to open route table detail.
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-vpc"

local _state = {}

local function buf_name(vpc_id)
  return "aws://vpc/sections/route_tables/" .. vpc_id
end

local function tag_name(tags, fallback)
  if type(tags) == "table" then
    for _, t in ipairs(tags) do
      if t.Key == "Name" then return t.Value or fallback end
    end
  end
  return fallback
end

local function render(buf, vpc_id)
  local st = _state[vpc_id]
  if not st then return end

  local km  = config.values.keymaps.vpc
  local hint = table.concat({
    (km.open_detail    or "<CR>") .. " detail",
    (km.detail_refresh or "R")   .. " refresh",
  }, "   ")
  local sep = string.rep("-", 72)

  local title = "VPC  Route Tables:  " .. vpc_id
    .. (st.fetching and "   [loading…]" or "")

  local lines = { "", title, "", sep, hint, sep }

  st.line_map = {}
  local items = st.items or {}

  if #items == 0 and not st.fetching then
    table.insert(lines, "  (none)")
  else
    local w_id   = 12
    local w_name = 4
    for _, rt in ipairs(items) do
      w_id   = math.max(w_id,   tonumber(vim.fn.strdisplaywidth(rt.id))   or 0)
      w_name = math.max(w_name, tonumber(vim.fn.strdisplaywidth(rt.name)) or 0)
    end
    w_id   = math.min(w_id,   30)
    w_name = math.min(w_name, 40)

    local fmt = string.format("  %%-%ds  %%-%ds  %%s", w_id, w_name)
    table.insert(lines, string.format(fmt, "Route Table ID", "Name", "Subnet Associations"))
    table.insert(lines, "  " .. string.rep("-", w_id + w_name + 30))

    for _, rt in ipairs(items) do
      local assoc_str = #rt.associations > 0
        and table.concat(rt.associations, ", ")
        or  "(main)"
      table.insert(lines, string.format(fmt, rt.id,
        rt.name ~= rt.id and rt.name or "—", assoc_str))
      st.line_map[#lines] = rt.id
    end
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

local function fetch(vpc_id, buf, call_opts)
  local st = _state[vpc_id]
  st.fetching  = true
  st.fetch_gen = (st.fetch_gen or 0) + 1
  local my_gen = st.fetch_gen
  buf_mod.set_loading(buf)

  spawn.run(
    { "ec2", "describe-route-tables",
      "--filters", "Name=vpc-id,Values=" .. vpc_id,
      "--output", "json" },
    function(ok, out)
      if my_gen ~= st.fetch_gen then return end
      st.fetching = false
      if not ok then
        buf_mod.set_error(buf, out)
        return
      end
      local ok2, data = pcall(vim.json.decode, table.concat(out, "\n"))
      if not ok2 or type(data) ~= "table" or type(data.RouteTables) ~= "table" then
        buf_mod.set_error(buf, { "Failed to parse describe-route-tables output" })
        return
      end
      local result = {}
      for _, rt in ipairs(data.RouteTables) do
        local routes = {}
        if type(rt.Routes) == "table" then
          for _, r in ipairs(rt.Routes) do
            local dest = r.DestinationCidrBlock
              or r.DestinationIpv6CidrBlock
              or r.DestinationPrefixListId
              or "?"
            local target = r.GatewayId
              or r.NatGatewayId
              or r.TransitGatewayId
              or r.VpcPeeringConnectionId
              or r.NetworkInterfaceId
              or r.InstanceId
              or "?"
            table.insert(routes, { dest = dest, target = target, state = r.State or "?" })
          end
          table.sort(routes, function(a, b) return a.dest < b.dest end)
        end
        local assoc_subnets = {}
        if type(rt.Associations) == "table" then
          for _, a in ipairs(rt.Associations) do
            if a.SubnetId then table.insert(assoc_subnets, a.SubnetId) end
          end
        end
        table.insert(result, {
          id           = rt.RouteTableId or "?",
          name         = tag_name(rt.Tags, rt.RouteTableId or "?"),
          routes       = routes,
          associations = assoc_subnets,
          tags         = rt.Tags or {},
        })
      end
      st.items = result
      st.cache = result
      render(buf, vpc_id)
    end, call_opts)
end

---@param vpc_id    string
---@param call_opts AwsCallOpts|nil
function M.open(vpc_id, call_opts)
  local buf = buf_mod.get_or_create(buf_name(vpc_id), FILETYPE)
  buf_mod.open_vsplit(buf)

  if not _state[vpc_id] then
    _state[vpc_id] = { items = {}, line_map = {}, cache = nil, fetching = false, fetch_gen = 0 }
  end
  local st = _state[vpc_id]

  keymaps.apply_vpc_section(buf, {
    open_detail = function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local id  = st.line_map[row]
      if id then
        require("aws.vpc.sections.route_table_detail").open(id, vpc_id, call_opts)
      end
    end,
    refresh = function()
      st.cache = nil
      fetch(vpc_id, buf, call_opts)
    end,
  })

  if st.cache then
    st.items = st.cache
    render(buf, vpc_id)
  else
    fetch(vpc_id, buf, call_opts)
  end
end

return M
