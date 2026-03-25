--- aws.nvim – VPC list buffer
--- Lists all VPCs in the region with Name tag, CIDR, state, and default flag.
--- Pagination: nextToken pattern (ec2 describe-vpcs).
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-vpc"

local _state = {}

local function buf_name(identity)
  return "aws://vpc/vpcs/" .. identity
end

--- Extract the value of tag "Name" from a Tags array, or return fallback.
local function tag_name(tags, fallback)
  if type(tags) == "table" then
    for _, t in ipairs(tags) do
      if t.Key == "Name" then return t.Value or fallback end
    end
  end
  return fallback
end

local function render(buf, st)
  local region  = st.region  or "unknown"
  local profile = st.profile
  local badge   = "[region:" .. region .. "]"
    .. (profile and "  [profile:" .. profile .. "]" or "")

  local km     = config.values.keymaps.vpc
  local hints  = table.concat({
    (km.open_detail  or "<CR>") .. " detail",
    (km.filter       or "F")   .. " filter",
    (km.clear_filter or "C")   .. " clear",
    (km.refresh      or "R")   .. " refresh",
  }, "   ")
  local sep = string.rep("-", 72)

  local items = st.items or {}
  -- apply client-side filter
  local visible = {}
  if st.filter and st.filter ~= "" then
    local pat = st.filter:lower()
    for _, v in ipairs(items) do
      if v.name:lower():find(pat, 1, true)
        or v.vpc_id:lower():find(pat, 1, true)
        or v.cidr:lower():find(pat, 1, true)
      then
        table.insert(visible, v)
      end
    end
  else
    visible = items
  end

  -- column widths
  local w_name  = 8
  local w_id    = 8
  local w_cidr  = 9
  for _, v in ipairs(visible) do
    w_name = math.max(w_name, tonumber(vim.fn.strdisplaywidth(v.name))   or 0)
    w_id   = math.max(w_id,   tonumber(vim.fn.strdisplaywidth(v.vpc_id)) or 0)
    w_cidr = math.max(w_cidr, tonumber(vim.fn.strdisplaywidth(v.cidr))   or 0)
  end
  -- LuaJIT string.format rejects widths > 99
  w_name = math.min(w_name, 60)
  w_id   = math.min(w_id,   30)
  w_cidr = math.min(w_cidr, 20)

  local fmt = string.format("%%-%ds  %%-%ds  %%-%ds  %%-9s  %%s", w_name, w_id, w_cidr)

  local lines = {
    "",
    "VPCs  " .. badge,
    (st.filter ~= "" and "  [filter:" .. st.filter .. "]" or ""),
    "",
    sep,
    hints,
    sep,
    string.format(fmt, "Name", "VPC ID", "CIDR", "State", "Default"),
    string.rep("-", w_name + w_id + w_cidr + 30),
  }

  st.line_map = {}
  for _, v in ipairs(visible) do
    local default_flag = v.is_default and "yes" or "no"
    local line = string.format(fmt, v.name, v.vpc_id, v.cidr, v.state, default_flag)
    table.insert(lines, line)
    st.line_map[#lines] = v.vpc_id
  end

  if #visible == 0 then
    table.insert(lines, st.filter ~= "" and "  (no matches)" or "  (no VPCs found)")
  end
  table.insert(lines, "")

  buf_mod.set_lines(buf, lines)
end

local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  st.items    = {}
  st.fetching = true
  st.fetch_gen = (st.fetch_gen or 0) + 1
  local my_gen = st.fetch_gen

  local function list_page(next_token)
    local args = { "ec2", "describe-vpcs", "--output", "json" }
    if next_token then
      vim.list_extend(args, { "--next-token", next_token })
    end

    spawn.run(args, function(ok, lines_out)
      if my_gen ~= st.fetch_gen then return end
      if not ok then
        buf_mod.set_error(buf, lines_out)
        st.fetching = false
        return
      end

      local ok2, data = pcall(vim.json.decode, table.concat(lines_out, "\n"))
      if not ok2 or type(data) ~= "table" or type(data.Vpcs) ~= "table" then
        buf_mod.set_error(buf, { "Failed to parse describe-vpcs output" })
        st.fetching = false
        return
      end

      for _, v in ipairs(data.Vpcs) do
        -- collect all CIDR blocks (primary + associations)
        local cidrs = {}
        if type(v.CidrBlockAssociationSet) == "table" then
          for _, assoc in ipairs(v.CidrBlockAssociationSet) do
            if assoc.CidrBlock then table.insert(cidrs, assoc.CidrBlock) end
          end
        end
        if #cidrs == 0 and v.CidrBlock then cidrs = { v.CidrBlock } end

        table.insert(st.items, {
          vpc_id     = v.VpcId or "?",
          name       = tag_name(v.Tags, v.VpcId or "—"),
          cidr       = cidrs[1] or "—",
          extra_cidrs = (function()
            local extra = {}
            for i = 2, #cidrs do table.insert(extra, cidrs[i]) end
            return extra
          end)(),
          state      = v.State or "?",
          is_default = v.IsDefault or false,
          tenancy    = v.InstanceTenancy or "?",
          owner_id   = v.OwnerId or "?",
          tags       = v.Tags or {},
        })
      end

      -- render incrementally after each page
      render(buf, st)

      local token = type(data.NextToken) == "string" and data.NextToken or nil
      if token then
        list_page(token)
      else
        st.cache    = st.items
        st.fetching = false
      end
    end, call_opts)
  end

  list_page(nil)
end

---@param call_opts AwsCallOpts|nil
function M.open(call_opts)
  local identity = config.identity(call_opts)
  local buf = buf_mod.get_or_create(buf_name(identity), FILETYPE)
  buf_mod.open_split(buf)

  if not _state[identity] then
    _state[identity] = {
      items     = {},
      filter    = "",
      line_map  = {},
      cache     = nil,
      fetching  = false,
      fetch_gen = 0,
      region    = config.resolve_region(call_opts),
      profile   = config.resolve_profile(call_opts),
    }
  end
  local st = _state[identity]

  keymaps.apply_vpc(buf, {
    open_detail = function()
      local row  = vim.api.nvim_win_get_cursor(0)[1]
      local id   = st.line_map[row]
      if id then
        -- find the vpc_name from items for the menu title
        local vpc_name
        for _, v in ipairs(st.items) do
          if v.vpc_id == id then
            vpc_name = (v.name ~= id) and v.name or nil
            break
          end
        end
        require("aws.vpc.menu").open(id, vpc_name, call_opts)
      end
    end,
    filter = function()
      vim.ui.input({ prompt = "Filter VPCs: ", default = st.filter }, function(input)
        if input == nil then return end
        st.filter = input
        render(buf, st)
      end)
    end,
    clear_filter = function()
      st.filter = ""
      render(buf, st)
    end,
    refresh = function()
      st.cache = nil
      fetch(buf, st, call_opts)
    end,
  })

  if st.cache then
    st.items = st.cache
    render(buf, st)
  else
    fetch(buf, st, call_opts)
  end
end

return M
