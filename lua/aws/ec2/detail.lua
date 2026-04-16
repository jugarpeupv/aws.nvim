--- aws.nvim – EC2 instance detail view (vsplit)
--- Shows all key attributes: network, storage, security groups, tags, etc.
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-ec2"

local function buf_name(instance_id)
  return "aws://ec2/detail/" .. instance_id
end

---@class Ec2DetailState
---@field instance table|nil
---@field region   string
---@field profile  string|nil

local _state = {} -- instance_id -> Ec2DetailState

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

---@param s     string
---@param width integer
---@return string
local function pad_right(s, width)
  local display_len = vim.fn.strdisplaywidth(s)
  if display_len >= width then
    return s
  end
  return s .. string.rep(" ", width - display_len)
end

---@param tags table[]|nil
---@param fallback string
---@return string
local function name_tag(tags, fallback)
  if type(tags) ~= "table" then
    return fallback
  end
  for _, t in ipairs(tags) do
    if t.Key == "Name" and t.Value and t.Value ~= "" then
      return t.Value
    end
  end
  return fallback
end

---@param instance table
---@return string
local function instance_state(instance)
  local s = type(instance.State) == "table" and instance.State or {}
  return s.Name or "unknown"
end

---@param buf         integer
---@param instance_id string
local function render(buf, instance_id)
  local st = _state[instance_id]
  if not st then
    return
  end

  local inst = st.instance or {}
  local region = st.region
  local profile = st.profile
  local km = config.values.keymaps.ec2

  local lines = {}
  local LABEL = 30

  local function row(label, value)
    table.insert(lines, "  " .. pad_right(label, LABEL) .. (value or "—"))
  end

  local display_name = name_tag(inst.Tags, instance_id)

  -- ── Title ──────────────────────────────────────────────────────────────────
  table.insert(lines, "")
  local title = "EC2  >>  "
    .. display_name
    .. "   [region: "
    .. region
    .. "]"
    .. (profile and ("   [profile: " .. profile .. "]") or "")
  table.insert(lines, title)
  table.insert(lines, "")

  local sep_len = math.max(vim.fn.strdisplaywidth(title), 72)
  local sep = string.rep("-", sep_len)
  table.insert(lines, sep)

  -- ── Hint line ──────────────────────────────────────────────────────────────
  local hints = {}
  if km.detail_refresh then
    table.insert(hints, km.detail_refresh .. " refresh")
  end
  if #hints > 0 then
    table.insert(lines, table.concat(hints, "  |  "))
    table.insert(lines, sep)
  end

  -- ── General ────────────────────────────────────────────────────────────────
  table.insert(lines, "General")
  table.insert(lines, sep)
  row("Instance ID", inst.InstanceId or instance_id)
  row("Name", name_tag(inst.Tags, "—"))
  row("State", instance_state(inst))
  row("Instance Type", inst.InstanceType or "—")
  row("AMI ID", inst.ImageId or "—")
  row("Key Pair", inst.KeyName or "—")
  row("Platform", inst.Platform or "linux")
  row("Architecture", inst.Architecture or "—")
  row("Virtualization", inst.VirtualizationType or "—")
  row("Hypervisor", inst.Hypervisor or "—")

  -- Launch time
  local lt = inst.LaunchTime or "—"
  row("Launch Time", lt)

  -- ── Placement ─────────────────────────────────────────────────────────────
  table.insert(lines, "")
  table.insert(lines, "Placement")
  table.insert(lines, sep)
  local placement = type(inst.Placement) == "table" and inst.Placement or {}
  row("Availability Zone", placement.AvailabilityZone or "—")
  row("Tenancy", placement.Tenancy or "—")
  row("Host ID", placement.HostId or "—")

  -- ── Networking ────────────────────────────────────────────────────────────
  table.insert(lines, "")
  table.insert(lines, "Networking")
  table.insert(lines, sep)
  row("VPC ID", inst.VpcId or "—")
  row("Subnet ID", inst.SubnetId or "—")
  row("Private IP", inst.PrivateIpAddress or "—")
  row("Private DNS", inst.PrivateDnsName or "—")
  row("Public IP", inst.PublicIpAddress or "—")
  row("Public DNS", inst.PublicDnsName or "—")

  -- Network interfaces
  local ifaces = type(inst.NetworkInterfaces) == "table" and inst.NetworkInterfaces or {}
  if #ifaces > 0 then
    table.insert(lines, "")
    table.insert(lines, "  Network Interfaces (" .. #ifaces .. ")")
    for _, iface in ipairs(ifaces) do
      local ifa_id = iface.NetworkInterfaceId or "—"
      local ifa_ip = iface.PrivateIpAddress or "—"
      local ifa_mac = iface.MacAddress or "—"
      local ifa_sub = iface.SubnetId or "—"
      table.insert(lines, "    " .. ifa_id .. "  ip=" .. ifa_ip .. "  mac=" .. ifa_mac .. "  subnet=" .. ifa_sub)
    end
  end

  -- ── Security Groups ───────────────────────────────────────────────────────
  table.insert(lines, "")
  table.insert(lines, "Security Groups")
  table.insert(lines, sep)
  local sgs = type(inst.SecurityGroups) == "table" and inst.SecurityGroups or {}
  if #sgs == 0 then
    table.insert(lines, "  (none)")
  else
    for _, sg in ipairs(sgs) do
      table.insert(lines, "  " .. pad_right(sg.GroupId or "—", 24) .. (sg.GroupName or "—"))
    end
  end

  -- ── Storage ───────────────────────────────────────────────────────────────
  table.insert(lines, "")
  table.insert(lines, "Storage")
  table.insert(lines, sep)
  local root_dev = inst.RootDeviceName or "—"
  local root_type = inst.RootDeviceType or "—"
  row("Root Device", root_dev .. "  (" .. root_type .. ")")

  local bdms = type(inst.BlockDeviceMappings) == "table" and inst.BlockDeviceMappings or {}
  if #bdms > 0 then
    table.insert(lines, "")
    table.insert(lines, "  Block Devices")
    for _, bdm in ipairs(bdms) do
      local dev_name = bdm.DeviceName or "—"
      local ebs = type(bdm.Ebs) == "table" and bdm.Ebs or {}
      local vol_id = ebs.VolumeId or "—"
      local vol_st = ebs.Status or "—"
      table.insert(
        lines,
        "    "
          .. pad_right(dev_name, 18)
          .. "volume="
          .. vol_id
          .. "  status="
          .. vol_st
          .. (ebs.DeleteOnTermination == true and "  delete-on-termination" or "")
      )
    end
  end

  -- ── IAM ───────────────────────────────────────────────────────────────────
  local iam_profile = type(inst.IamInstanceProfile) == "table" and inst.IamInstanceProfile or nil
  if iam_profile then
    table.insert(lines, "")
    table.insert(lines, "IAM Instance Profile")
    table.insert(lines, sep)
    row("ARN", iam_profile.Arn or "—")
    row("ID", iam_profile.Id or "—")
  end

  -- ── Monitoring & Metadata ─────────────────────────────────────────────────
  table.insert(lines, "")
  table.insert(lines, "Monitoring & Metadata")
  table.insert(lines, sep)
  local mon = type(inst.Monitoring) == "table" and inst.Monitoring or {}
  row("Monitoring", mon.State or "—")
  row("Source/Dest Check", tostring(inst.SourceDestCheck ~= false))
  local meta = type(inst.MetadataOptions) == "table" and inst.MetadataOptions or {}
  row("Metadata HTTP", meta.HttpEndpoint or "—")
  row("Metadata IMDSv2", meta.HttpTokens or "—")

  -- ── Tags ──────────────────────────────────────────────────────────────────
  local tags = type(inst.Tags) == "table" and inst.Tags or {}
  if #tags > 0 then
    table.insert(lines, "")
    table.insert(lines, "Tags (" .. #tags .. ")")
    table.insert(lines, sep)
    -- Sort tags by key
    local sorted_tags = vim.deepcopy(tags)
    table.sort(sorted_tags, function(a, b)
      return (a.Key or "") < (b.Key or "")
    end)
    for _, t in ipairs(sorted_tags) do
      row("  " .. (t.Key or "?"), t.Value or "—")
    end
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

-------------------------------------------------------------------------------
-- Fetch
-------------------------------------------------------------------------------

---@param instance_id string
---@param buf         integer
---@param call_opts   AwsCallOpts|nil
local function fetch(instance_id, buf, call_opts)
  buf_mod.set_loading(buf)

  spawn.run({
    "ec2",
    "describe-instances",
    "--instance-ids",
    instance_id,
    "--output",
    "json",
  }, function(ok, lines)
    if not ok then
      buf_mod.set_error(buf, lines)
      return
    end
    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if not ok2 or type(data) ~= "table" then
      buf_mod.set_error(buf, { "Failed to parse JSON", raw })
      return
    end
    local reservations = type(data.Reservations) == "table" and data.Reservations or {}
    local inst = (reservations[1] and type(reservations[1].Instances) == "table" and reservations[1].Instances[1])
      or nil

    _state[instance_id] = {
      instance = inst or { InstanceId = instance_id },
      region = config.resolve_region(call_opts),
      profile = config.resolve_profile(call_opts),
    }
    render(buf, instance_id)
  end, call_opts)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param instance_id string
---@param call_opts   AwsCallOpts|nil
function M.open(instance_id, call_opts)
  local buf = buf_mod.get_or_create(buf_name(instance_id), FILETYPE)
  buf_mod.open_vsplit(buf)

  keymaps.apply_ec2_detail(buf, {
    refresh = function()
      fetch(instance_id, buf, call_opts)
    end,
  })

  fetch(instance_id, buf, call_opts)
end

return M
