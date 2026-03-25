--- aws.nvim – VPC Subnets section buffer
--- Lists all subnets for a VPC with filter + <CR> to open subnet detail.
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-vpc"

local _state = {}  -- vpc_id -> state

local function buf_name(vpc_id)
  return "aws://vpc/sections/subnets/" .. vpc_id
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
    (km.open_detail  or "<CR>") .. " detail",
    (km.filter       or "F")   .. " filter",
    (km.clear_filter or "C")   .. " clear",
    (km.detail_refresh or "R") .. " refresh",
  }, "   ")
  local sep = string.rep("-", 72)

  local title = "VPC  Subnets:  " .. vpc_id
    .. (st.filter ~= "" and ("   [filter:" .. st.filter .. "]") or "")
    .. (st.fetching and "   [loading…]" or "")

  local lines = { "", title, "", sep, hint, sep }

  st.line_map = {}

  local items = st.items or {}
  local visible = {}
  if st.filter ~= "" then
    local pat = st.filter:lower()
    for _, s in ipairs(items) do
      if s.name:lower():find(pat, 1, true)
        or s.id:lower():find(pat, 1, true)
        or s.cidr:lower():find(pat, 1, true)
        or s.az:lower():find(pat, 1, true)
      then
        table.insert(visible, s)
      end
    end
  else
    visible = items
  end

  if #visible == 0 and not st.fetching then
    table.insert(lines, st.filter ~= "" and "  (no matches)" or "  (none)")
  else
    -- column widths
    local w_name = 4
    local w_id   = 9
    local w_cidr = 4
    local w_az   = 2
    for _, s in ipairs(visible) do
      w_name = math.max(w_name, tonumber(vim.fn.strdisplaywidth(s.name)) or 0)
      w_id   = math.max(w_id,   tonumber(vim.fn.strdisplaywidth(s.id))   or 0)
      w_cidr = math.max(w_cidr, tonumber(vim.fn.strdisplaywidth(s.cidr)) or 0)
      w_az   = math.max(w_az,   tonumber(vim.fn.strdisplaywidth(s.az))   or 0)
    end
    w_name = math.min(w_name, 50)
    w_id   = math.min(w_id,   30)
    w_cidr = math.min(w_cidr, 20)
    w_az   = math.min(w_az,   30)

    local fmt = string.format("  %%-%ds  %%-%ds  %%-%ds  %%-%ds  %%-5s  %%s",
      w_name, w_id, w_cidr, w_az)
    table.insert(lines, string.format(fmt, "Name", "Subnet ID", "CIDR", "AZ", "IPs", "Public IP"))
    table.insert(lines, "  " .. string.rep("-", w_name + w_id + w_cidr + w_az + 20))

    for _, s in ipairs(visible) do
      table.insert(lines, string.format(fmt,
        s.name, s.id, s.cidr, s.az,
        tostring(s.available_ips), s.map_public_ip and "yes" or "no"))
      st.line_map[#lines] = s.id
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
    { "ec2", "describe-subnets",
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
      if not ok2 or type(data) ~= "table" or type(data.Subnets) ~= "table" then
        buf_mod.set_error(buf, { "Failed to parse describe-subnets output" })
        return
      end
      local result = {}
      for _, s in ipairs(data.Subnets) do
        table.insert(result, {
          id            = s.SubnetId or "?",
          name          = tag_name(s.Tags, s.SubnetId or "?"),
          cidr          = s.CidrBlock or "?",
          az            = s.AvailabilityZone or "?",
          available_ips = s.AvailableIpAddressCount or 0,
          map_public_ip = s.MapPublicIpOnLaunch or false,
          state         = s.State or "?",
          vpc_id        = s.VpcId or vpc_id,
          owner_id      = s.OwnerId or "?",
          default_for_az = s.DefaultForAz or false,
          tags          = s.Tags or {},
        })
      end
      table.sort(result, function(a, b)
        if a.az ~= b.az then return a.az < b.az end
        return a.cidr < b.cidr
      end)
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
    _state[vpc_id] = {
      items     = {},
      filter    = "",
      line_map  = {},
      cache     = nil,
      fetching  = false,
      fetch_gen = 0,
    }
  end
  local st = _state[vpc_id]

  keymaps.apply_vpc_section(buf, {
    open_detail = function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local id  = st.line_map[row]
      if id then
        require("aws.vpc.sections.subnet_detail").open(id, call_opts)
      end
    end,
    filter = function()
      vim.ui.input({ prompt = "Filter subnets: ", default = st.filter }, function(input)
        if input == nil then return end
        st.filter = input
        render(buf, vpc_id)
      end)
    end,
    clear_filter = function()
      st.filter = ""
      render(buf, vpc_id)
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
