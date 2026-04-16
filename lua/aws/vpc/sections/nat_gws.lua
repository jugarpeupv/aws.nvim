--- aws.nvim – VPC NAT Gateways section buffer
--- Lists NAT gateways for a VPC with <CR> to open NAT gateway detail.
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-vpc"

local _state = {}

local function buf_name(vpc_id)
  return "aws://vpc/sections/nat_gws/" .. vpc_id
end

local function render(buf, vpc_id)
  local st = _state[vpc_id]
  if not st then
    return
  end

  local km = config.values.keymaps.vpc
  local hint = table.concat({
    (km.open_detail or "<CR>") .. " detail",
    (km.detail_refresh or "R") .. " refresh",
  }, "   ")
  local sep = string.rep("-", 72)

  local title = "VPC  NAT Gateways:  " .. vpc_id .. (st.fetching and "   [loading…]" or "")

  local lines = { "", title, "", sep, hint, sep }

  st.line_map = {}
  local items = st.items or {}

  if #items == 0 and not st.fetching then
    table.insert(lines, "  (none)")
  else
    local w_id = 10
    local w_state = 5
    local w_subnet = 9
    for _, nat in ipairs(items) do
      w_id = math.max(w_id, tonumber(vim.fn.strdisplaywidth(nat.id)) or 0)
      w_state = math.max(w_state, tonumber(vim.fn.strdisplaywidth(nat.state)) or 0)
      w_subnet = math.max(w_subnet, tonumber(vim.fn.strdisplaywidth(nat.subnet_id)) or 0)
    end
    w_id = math.min(w_id, 30)
    w_state = math.min(w_state, 15)
    w_subnet = math.min(w_subnet, 30)

    local fmt = string.format("  %%-%ds  %%-%ds  %%-%ds  %%-16s  %%s", w_id, w_state, w_subnet)
    table.insert(lines, string.format(fmt, "NAT GW ID", "State", "Subnet", "Public IP", "Private IP"))
    table.insert(lines, "  " .. string.rep("-", w_id + w_state + w_subnet + 36))

    for _, nat in ipairs(items) do
      table.insert(
        lines,
        string.format(fmt, nat.id, nat.state, nat.subnet_id, nat.public_ip or "—", nat.private_ip or "—")
      )
      st.line_map[#lines] = nat.id
    end
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

local function fetch(vpc_id, buf, call_opts)
  local st = _state[vpc_id]
  st.fetching = true
  st.fetch_gen = (st.fetch_gen or 0) + 1
  local my_gen = st.fetch_gen
  buf_mod.set_loading(buf)

  spawn.run(
    { "ec2", "describe-nat-gateways", "--filter", "Name=vpc-id,Values=" .. vpc_id, "--output", "json" },
    function(ok, out)
      if my_gen ~= st.fetch_gen then
        return
      end
      st.fetching = false
      if not ok then
        buf_mod.set_error(buf, out)
        return
      end
      local ok2, data = pcall(vim.json.decode, table.concat(out, "\n"))
      if not ok2 or type(data) ~= "table" or type(data.NatGateways) ~= "table" then
        buf_mod.set_error(buf, { "Failed to parse describe-nat-gateways output" })
        return
      end
      local result = {}
      for _, nat in ipairs(data.NatGateways) do
        if nat.State ~= "deleted" then
          local public_ip, private_ip
          if type(nat.NatGatewayAddresses) == "table" then
            for _, addr in ipairs(nat.NatGatewayAddresses) do
              if addr.IsPrimary then
                public_ip = addr.PublicIp
                private_ip = addr.PrivateIp
                break
              end
            end
            if not public_ip and nat.NatGatewayAddresses[1] then
              public_ip = nat.NatGatewayAddresses[1].PublicIp
              private_ip = nat.NatGatewayAddresses[1].PrivateIp
            end
          end
          table.insert(result, {
            id = nat.NatGatewayId or "?",
            state = nat.State or "?",
            subnet_id = nat.SubnetId or "?",
            public_ip = public_ip,
            private_ip = private_ip,
            connectivity_type = nat.ConnectivityType or "?",
            tags = nat.Tags or {},
          })
        end
      end
      st.items = result
      st.cache = result
      render(buf, vpc_id)
    end,
    call_opts
  )
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
      local id = st.line_map[row]
      if id then
        require("aws.vpc.sections.nat_gw_detail").open(id, call_opts)
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
