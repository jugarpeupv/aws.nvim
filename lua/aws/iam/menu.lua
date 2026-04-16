--- aws.nvim – IAM service menu
--- Opens a buffer listing the 5 IAM resource types. <CR> navigates into the
--- selected resource list.
local M = {}

local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-iam"

--- State keyed by identity (menu is stateless beyond the buffer itself)
local _bufs = {} -- luacheck: ignore 241

local function buf_name(identity)
  return "aws://iam/menu/" .. identity
end

local ENTRIES = {
  {
    key = "users",
    label = "Users",
    desc = "IAM users — details, groups, policies, access keys, MFA",
  },
  { key = "groups", label = "Groups", desc = "IAM groups — members, attached & inline policies" },
  { key = "roles", label = "Roles", desc = "IAM roles — trust policy, attached & inline policies" },
  {
    key = "policies",
    label = "Policies",
    desc = "Customer-managed policies — versions, attached entities",
  },
  { key = "providers", label = "Identity Providers", desc = "OIDC and SAML identity providers" },
}

local function render(buf, identity, call_opts)
  local region = config.resolve_region(call_opts)
  local profile = config.resolve_profile(call_opts)

  local title = "IAM" .. "   [region: " .. region .. "]" .. (profile and ("   [profile: " .. profile .. "]") or "")

  local km = config.values.keymaps.iam
  local hint = (km.open_list or "<CR>") .. " open" .. "  |  " .. (km.refresh or "R") .. " refresh"

  local sep = string.rep("-", 72)
  local lines = { "", title, "", sep, hint, sep, "" }

  for i, e in ipairs(ENTRIES) do
    table.insert(lines, string.format("  %d.  %-22s  %s", i, e.label, e.desc))
  end

  table.insert(lines, "")

  buf_mod.set_lines(buf, lines)
end

--- Return the ENTRIES index for the current cursor line, or nil.
local function entry_under_cursor(buf)
  -- Entries start at line 8 (1-indexed): lines 1-7 are header.
  local row = vim.api.nvim_win_get_cursor(0)[1]
  -- Header is 7 lines (blank, title, blank, sep, hint, sep, blank) + entries
  local idx = row - 7
  if idx >= 1 and idx <= #ENTRIES then
    return ENTRIES[idx]
  end
  return nil
end

---@param call_opts AwsCallOpts|nil
function M.open(call_opts)
  local identity = config.identity(call_opts)
  local buf = buf_mod.get_or_create(buf_name(identity), FILETYPE)
  _bufs[identity] = buf
  buf_mod.open_split(buf)

  keymaps.apply_iam_menu(buf, {
    open_list = function()
      local entry = entry_under_cursor(buf)
      if not entry then
        vim.notify("aws.nvim: no IAM resource type under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.iam." .. entry.key).open(call_opts)
    end,
    refresh = function()
      render(buf, identity, call_opts)
    end,
  })

  render(buf, identity, call_opts)
end

return M
