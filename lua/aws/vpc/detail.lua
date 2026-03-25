--- aws.nvim – VPC General / Tags detail buffer
--- Fetches metadata for a single VPC via describe-vpcs --vpc-ids.
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-vpc"

local _state = {}

local function buf_name(vpc_id)
  return "aws://vpc/detail/" .. vpc_id
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
      if t.Key == "Name" then return t.Value or fallback end
    end
  end
  return fallback
end

local function fmt_tags(tags)
  local lines = {}
  if type(tags) == "table" and #tags > 0 then
    local sorted = vim.deepcopy(tags)
    table.sort(sorted, function(a, b) return (a.Key or "") < (b.Key or "") end)
    for _, t in ipairs(sorted) do
      if t.Key ~= "Name" then
        table.insert(lines, kv(t.Key, t.Value))
      end
    end
  end
  return #lines > 0 and lines or { "  (none)" }
end

local function render(buf, vpc_id)
  local st = _state[vpc_id]
  if not st then return end

  local km  = config.values.keymaps.vpc
  local hint = (km.detail_refresh or "R") .. " refresh"
  local sep  = string.rep("-", 72)

  local title = vpc_id
  if st.vpc then
    local n = tag_name(st.vpc.Tags, nil)
    if n then title = n .. "  (" .. vpc_id .. ")" end
  end

  local lines = { "", "VPC:  " .. title, "", sep, hint, sep }

  -- ── General ────────────────────────────────────────────────────────────────
  for _, l in ipairs(section("General")) do table.insert(lines, l) end
  if st.vpc then
    local v = st.vpc
    local cidrs = {}
    if type(v.CidrBlockAssociationSet) == "table" then
      for _, a in ipairs(v.CidrBlockAssociationSet) do
        if a.CidrBlock then table.insert(cidrs, a.CidrBlock) end
      end
    end
    if #cidrs == 0 and v.CidrBlock then cidrs = { v.CidrBlock } end

    table.insert(lines, kv("VPC ID",          v.VpcId))
    table.insert(lines, kv("Name",            tag_name(v.Tags, "—")))
    table.insert(lines, kv("State",           v.State))
    table.insert(lines, kv("CIDR Block(s)",   table.concat(cidrs, ", ")))
    table.insert(lines, kv("Default VPC",     v.IsDefault and "yes" or "no"))
    table.insert(lines, kv("Tenancy",         v.InstanceTenancy))
    table.insert(lines, kv("Owner ID",        v.OwnerId))
    table.insert(lines, kv("DHCP Options ID", v.DhcpOptionsId))
  elseif st.vpc == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  -- ── Tags ───────────────────────────────────────────────────────────────────
  for _, l in ipairs(section("Tags")) do table.insert(lines, l) end
  if st.vpc then
    for _, l in ipairs(fmt_tags(st.vpc.Tags)) do table.insert(lines, l) end
  elseif st.vpc == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

local function fetch(vpc_id, buf, call_opts)
  _state[vpc_id] = { vpc = nil }
  buf_mod.set_loading(buf)

  spawn.run(
    { "ec2", "describe-vpcs", "--vpc-ids", vpc_id, "--output", "json" },
    function(ok, out)
      local st = _state[vpc_id]
      if ok then
        local ok2, data = pcall(vim.json.decode, table.concat(out, "\n"))
        st.vpc = (ok2 and type(data) == "table"
          and type(data.Vpcs) == "table"
          and data.Vpcs[1]) or false
      else
        st.vpc = false
      end
      render(buf, vpc_id)
    end, call_opts)
end

---@param vpc_id    string
---@param call_opts AwsCallOpts|nil
function M.open(vpc_id, call_opts)
  local buf = buf_mod.get_or_create(buf_name(vpc_id), FILETYPE)
  buf_mod.open_vsplit(buf)
  keymaps.apply_vpc_section(buf, {
    refresh = function() fetch(vpc_id, buf, call_opts) end,
  })
  fetch(vpc_id, buf, call_opts)
end

return M
