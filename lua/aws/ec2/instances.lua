--- aws.nvim – EC2 instances list, filter, and render
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-ec2"

---@class Ec2InstancesState
---@field items      table[]               describe-instances Reservations flattened to instances
---@field filter     string                current name/id filter
---@field line_map   table<integer,string> line -> instance id
---@field cache      table[]|nil           full unfiltered list; nil = not yet fetched
---@field fetching   boolean               true while pages are still arriving
---@field fetch_gen  integer               incremented on every new fetch; stale cbs check this
---@field region     string
---@field profile    string|nil

--- State keyed by identity string (e.g. "us-east-1" or "prod@eu-west-1")
local _state = {}  -- identity -> Ec2InstancesState

local function buf_name(identity)
  return "aws://ec2/instances/" .. identity
end

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

---@param s     string
---@param width integer
---@return string
local function pad_right(s, width)
  local display_len = vim.fn.strdisplaywidth(s)
  if display_len >= width then return s end
  return s .. string.rep(" ", width - display_len)
end

---@param s   string
---@param max integer
---@return string
local function truncate(s, max)
  if vim.fn.strdisplaywidth(s) <= max then return s end
  local result = ""
  local cols   = 0
  local nchars = vim.fn.strchars(s)
  for i = 0, nchars - 1 do
    local ch = vim.fn.strcharpart(s, i, 1)
    local w  = vim.fn.strdisplaywidth(ch)
    if cols + w > max - 1 then break end
    result = result .. ch
    cols   = cols + w
  end
  return result .. "…"
end

--- Extract the Name tag value from a list of tags, or return fallback.
---@param tags table[]|nil
---@param fallback string
---@return string
local function name_tag(tags, fallback)
  if type(tags) ~= "table" then return fallback end
  for _, t in ipairs(tags) do
    if t.Key == "Name" and t.Value and t.Value ~= "" then
      return t.Value
    end
  end
  return fallback
end

--- Map EC2 state codes to short labels.
local STATE_LABELS = {
  ["0"]  = "pending",
  ["16"] = "running",
  ["32"] = "shutting-down",
  ["48"] = "terminated",
  ["64"] = "stopping",
  ["80"] = "stopped",
}

---@param instance table
---@return string
local function instance_state(instance)
  local s = type(instance.State) == "table" and instance.State or {}
  return s.Name or STATE_LABELS[tostring(s.Code or "")] or "unknown"
end

local function hint_line()
  local km = config.values.keymaps.ec2
  local hints = {}
  if km.open_detail  then table.insert(hints, km.open_detail  .. " detail")  end
  if km.filter       then table.insert(hints, km.filter       .. " filter")  end
  if km.clear_filter then table.insert(hints, km.clear_filter .. " clear")   end
  if km.refresh      then table.insert(hints, km.refresh      .. " refresh") end
  if km.close        then table.insert(hints, km.close        .. " close")   end
  return table.concat(hints, "  |  ")
end

---@param buf integer
---@param st  Ec2InstancesState
local function render(buf, st)
  local id_width    = 11  -- "Instance ID"   i-0123456789abcdef0 = 19 chars; col header shorter
  local name_width  = 4   -- "Name"
  local type_width  = 4   -- "Type"
  local state_width = 5   -- "State"
  local az_width    = 2   -- "AZ"
  local ip_width    = 10  -- "Private IP"

  -- First pass: measure column widths for visible rows
  for _, inst in ipairs(st.items) do
    local id    = inst.InstanceId or ""
    local nm    = name_tag(inst.Tags, "")
    local itype = inst.InstanceType or ""
    local state = instance_state(inst)
    local az    = (type(inst.Placement) == "table" and inst.Placement.AvailabilityZone) or ""
    local ip    = inst.PrivateIpAddress or ""

    -- apply filter on name OR id
    local display_name = nm ~= "" and nm or id
    local matches = st.filter == ""
      or display_name:lower():find(st.filter:lower(), 1, true)
      or id:lower():find(st.filter:lower(), 1, true)

    if matches then
      local nw = vim.fn.strdisplaywidth(id)
      if nw > id_width    then id_width    = nw end
      nw = vim.fn.strdisplaywidth(nm)
      if nw > name_width  then name_width  = nw end
      nw = vim.fn.strdisplaywidth(itype)
      if nw > type_width  then type_width  = nw end
      nw = vim.fn.strdisplaywidth(state)
      if nw > state_width then state_width = nw end
      nw = vim.fn.strdisplaywidth(az)
      if nw > az_width    then az_width    = nw end
      nw = vim.fn.strdisplaywidth(ip)
      if nw > ip_width    then ip_width    = nw end
    end
  end
  id_width    = id_width    + 2
  name_width  = name_width  + 2
  type_width  = type_width  + 2
  state_width = state_width + 2
  az_width    = az_width    + 2
  ip_width    = ip_width    + 2

  local title = "EC2  Instances"
    .. "   [region: " .. st.region .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")
    .. (st.filter ~= "" and ("   [filter: " .. st.filter .. "]") or "")

  local total = id_width + name_width + type_width + state_width + az_width + ip_width + 16
  local sep   = string.rep("-", total)

  local lines = { "", title, "", sep, hint_line(), sep,
    pad_right("Instance ID",  id_width)
      .. pad_right("Name",       name_width)
      .. pad_right("Type",       type_width)
      .. pad_right("State",      state_width)
      .. pad_right("AZ",         az_width)
      .. pad_right("Private IP", ip_width)
      .. "Public IP",
    sep,
  }

  st.line_map = {}

  for _, inst in ipairs(st.items) do
    local id    = inst.InstanceId or ""
    local nm    = name_tag(inst.Tags, "")
    local itype = inst.InstanceType or "—"
    local state = instance_state(inst)
    local az    = (type(inst.Placement) == "table" and inst.Placement.AvailabilityZone) or "—"
    local ip    = inst.PrivateIpAddress or "—"
    local pub   = inst.PublicIpAddress  or "—"

    local display_name = nm ~= "" and nm or id
    local matches = st.filter == ""
      or display_name:lower():find(st.filter:lower(), 1, true)
      or id:lower():find(st.filter:lower(), 1, true)

    if matches then
      table.insert(lines,
        pad_right(id,                                        id_width)
        .. pad_right(truncate(nm, name_width - 2),          name_width)
        .. pad_right(itype,                                  type_width)
        .. pad_right(state,                                  state_width)
        .. pad_right(az,                                     az_width)
        .. pad_right(ip,                                     ip_width)
        .. pub
      )
      st.line_map[#lines] = id
    end
  end

  if not next(st.line_map) then
    table.insert(lines, "(no instances match)")
  end

  buf_mod.set_lines(buf, lines)
end

-------------------------------------------------------------------------------
-- Fetch: describe-instances (paginated), flatten reservations → instances
-------------------------------------------------------------------------------

---@param buf       integer
---@param st        Ec2InstancesState
---@param call_opts AwsCallOpts|nil
local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  st.fetching  = true
  st.fetch_gen = st.fetch_gen + 1
  local my_gen = st.fetch_gen
  local all_instances = {}

  local function page(next_token)
    local args = { "ec2", "describe-instances", "--output", "json" }
    if next_token then
      vim.list_extend(args, { "--next-token", next_token })
    end
    spawn.run(args, function(ok, lines)
      if my_gen ~= st.fetch_gen then return end
      if not ok then
        st.fetching = false
        buf_mod.set_error(buf, lines)
        return
      end
      local raw = table.concat(lines, "\n")
      local ok2, data = pcall(vim.json.decode, raw)
      if not ok2 or type(data) ~= "table" then
        st.fetching = false
        buf_mod.set_error(buf, { "Failed to parse JSON", raw })
        return
      end
      -- Flatten Reservations → Instances
      local reservations = type(data.Reservations) == "table" and data.Reservations or {}
      for _, res in ipairs(reservations) do
        local instances = type(res.Instances) == "table" and res.Instances or {}
        for _, inst in ipairs(instances) do
          table.insert(all_instances, inst)
        end
      end
      local token = type(data.NextToken) == "string" and data.NextToken or nil
      if token then
        page(token)
      else
        -- Sort: running first, then by Name tag / instance-id
        table.sort(all_instances, function(a, b)
          local sa = instance_state(a)
          local sb = instance_state(b)
          if sa ~= sb then
            -- running > stopped > terminated > everything else
            local order = { running = 0, stopped = 1, terminated = 2 }
            local oa = order[sa] or 3
            local ob = order[sb] or 3
            if oa ~= ob then return oa < ob end
          end
          local na = name_tag(a.Tags, a.InstanceId or "")
          local nb = name_tag(b.Tags, b.InstanceId or "")
          return na:lower() < nb:lower()
        end)
        st.fetching = false
        st.items    = all_instances
        st.cache    = all_instances
        render(buf, st)
      end
    end, call_opts)
  end

  page(nil)
end

-------------------------------------------------------------------------------
-- Cursor helpers
-------------------------------------------------------------------------------

---@param st Ec2InstancesState
---@return string|nil
local function id_under_cursor(st)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return st.line_map[row]
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

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

  keymaps.apply_ec2(buf, {
    open_detail = function()
      local id = id_under_cursor(st)
      if not id then
        vim.notify("aws.nvim: no instance under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.ec2.detail").open(id, call_opts)
    end,

    filter = function()
      vim.ui.input({ prompt = "Filter instances (name/id): ", default = st.filter }, function(input)
        if input == nil then return end
        st.filter = input
        if input == "" then
          if st.cache then
            st.items = st.cache
            render(buf, st)
          else
            fetch(buf, st, call_opts)
          end
        else
          if st.cache then st.items = st.cache end
          render(buf, st)
        end
      end)
    end,

    clear_filter = function()
      st.filter = ""
      if st.cache then
        st.items = st.cache
        render(buf, st)
      else
        fetch(buf, st, call_opts)
      end
    end,

    refresh = function()
      st.cache = nil
      fetch(buf, st, call_opts)
    end,

    close = function()
      buf_mod.close_split(buf)
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
