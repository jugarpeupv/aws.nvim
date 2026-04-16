--- aws.nvim – VPC section menu
--- Opens a buffer listing the sections available for a single VPC.
--- <CR> navigates into the selected section buffer.
local M = {}

local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-vpc"

local _bufs = {} -- luacheck: ignore 241

local function buf_name(vpc_id)
  return "aws://vpc/menu/" .. vpc_id
end

local ENTRIES = {
  { key = "detail", label = "General / Tags", desc = "VPC metadata, CIDR blocks, tenancy, tags" },
  {
    key = "subnets",
    label = "Subnets",
    desc = "Subnets — AZ, CIDR, available IPs, public IP mapping",
  },
  { key = "igws", label = "Internet Gateways", desc = "Internet gateways attached to this VPC" },
  { key = "nat_gws", label = "NAT Gateways", desc = "NAT gateways — state, subnet, public/private IP" },
  { key = "route_tables", label = "Route Tables", desc = "Route tables — associations, routes and targets" },
  { key = "sgs", label = "Security Groups", desc = "Security groups — inbound and outbound rules" },
}

local function render(buf, vpc_id, vpc_name, call_opts)
  local region = config.resolve_region(call_opts)
  local profile = config.resolve_profile(call_opts)

  local title = "VPC:  "
    .. (vpc_name and (vpc_name .. "  (" .. vpc_id .. ")") or vpc_id)
    .. "   [region: "
    .. region
    .. "]"
    .. (profile and ("   [profile: " .. profile .. "]") or "")

  local km = config.values.keymaps.vpc
  local hint = (km.open_detail or "<CR>") .. " open"

  local sep = string.rep("-", 72)
  local lines = { "", title, "", sep, hint, sep, "" }

  for i, e in ipairs(ENTRIES) do
    table.insert(lines, string.format("  %d.  %-22s  %s", i, e.label, e.desc))
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

--- Return the ENTRIES entry for the current cursor line, or nil.
local function entry_under_cursor()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  -- Header is 7 lines (blank, title, blank, sep, hint, sep, blank)
  local idx = row - 7
  if idx >= 1 and idx <= #ENTRIES then
    return ENTRIES[idx]
  end
  return nil
end

---@param vpc_id    string
---@param vpc_name  string|nil  optional resolved Name tag (for the title)
---@param call_opts AwsCallOpts|nil
function M.open(vpc_id, vpc_name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(vpc_id), FILETYPE)
  _bufs[vpc_id] = buf
  buf_mod.open_vsplit(buf)

  keymaps.apply_vpc_menu(buf, {
    open_detail = function()
      local entry = entry_under_cursor()
      if not entry then
        vim.notify("aws.nvim: no section under cursor", vim.log.levels.WARN)
        return
      end
      if entry.key == "detail" then
        require("aws.vpc.detail").open(vpc_id, call_opts)
      else
        require("aws.vpc.sections." .. entry.key).open(vpc_id, call_opts)
      end
    end,
    refresh = function()
      render(buf, vpc_id, vpc_name, call_opts)
    end,
  })

  render(buf, vpc_id, vpc_name, call_opts)
end

return M
