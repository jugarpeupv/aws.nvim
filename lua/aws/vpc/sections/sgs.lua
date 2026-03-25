--- aws.nvim – VPC Security Groups section buffer
--- Lists security groups for a VPC with filter + <CR> to open SG detail.
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-vpc"

local _state = {}

local function buf_name(vpc_id)
  return "aws://vpc/sections/sgs/" .. vpc_id
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

  local title = "VPC  Security Groups:  " .. vpc_id
    .. (st.filter ~= "" and ("   [filter:" .. st.filter .. "]") or "")
    .. (st.fetching and "   [loading…]" or "")

  local lines = { "", title, "", sep, hint, sep }

  st.line_map = {}
  local items = st.items or {}
  local visible = {}
  if st.filter ~= "" then
    local pat = st.filter:lower()
    for _, sg in ipairs(items) do
      if sg.id:lower():find(pat, 1, true)
        or sg.name:lower():find(pat, 1, true)
        or sg.desc:lower():find(pat, 1, true)
      then
        table.insert(visible, sg)
      end
    end
  else
    visible = items
  end

  if #visible == 0 and not st.fetching then
    table.insert(lines, st.filter ~= "" and "  (no matches)" or "  (none)")
  else
    local w_id   = 8
    local w_name = 4
    for _, sg in ipairs(visible) do
      w_id   = math.max(w_id,   tonumber(vim.fn.strdisplaywidth(sg.id))   or 0)
      w_name = math.max(w_name, tonumber(vim.fn.strdisplaywidth(sg.name)) or 0)
    end
    w_id   = math.min(w_id,   40)
    w_name = math.min(w_name, 40)

    local fmt = string.format("  %%-%ds  %%-%ds  %%s", w_id, w_name)
    table.insert(lines, string.format(fmt, "Group ID", "Name", "Description"))
    table.insert(lines, "  " .. string.rep("-", w_id + w_name + 30))

    for _, sg in ipairs(visible) do
      table.insert(lines, string.format(fmt, sg.id, sg.name, sg.desc))
      st.line_map[#lines] = sg.id
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
    { "ec2", "describe-security-groups",
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
      if not ok2 or type(data) ~= "table" or type(data.SecurityGroups) ~= "table" then
        buf_mod.set_error(buf, { "Failed to parse describe-security-groups output" })
        return
      end
      local result = {}
      for _, sg in ipairs(data.SecurityGroups) do
        table.insert(result, {
          id   = sg.GroupId    or "?",
          name = sg.GroupName  or "?",
          desc = sg.Description or "—",
          tags = sg.Tags or {},
        })
      end
      table.sort(result, function(a, b) return a.name < b.name end)
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
    _state[vpc_id] = { items = {}, filter = "", line_map = {}, cache = nil, fetching = false, fetch_gen = 0 }
  end
  local st = _state[vpc_id]

  keymaps.apply_vpc_section(buf, {
    open_detail = function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local id  = st.line_map[row]
      if id then
        require("aws.vpc.sg_detail").open(id, call_opts)
      end
    end,
    filter = function()
      vim.ui.input({ prompt = "Filter security groups: ", default = st.filter }, function(input)
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
