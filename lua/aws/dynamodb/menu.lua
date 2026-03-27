--- aws.nvim – DynamoDB per-table section menu
--- Opens a buffer listing the sections available for a single DynamoDB table.
--- <CR> navigates into the selected section buffer.
local M = {}

local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-dynamodb"

local _bufs = {}  -- table_name -> bufnr

local function buf_name(table_name)
  return "aws://dynamodb/menu/" .. table_name
end

local ENTRIES = {
  { key = "detail", label = "General / Indexes", desc = "Schema, throughput, GSIs, LSIs, streams, tags" },
  { key = "scan",   label = "Scan / Query",       desc = "Scan or query items with optional filter expression" },
}

local function render(buf, table_name, call_opts)
  local region  = config.resolve_region(call_opts)
  local profile = config.resolve_profile(call_opts)

  local title = "DynamoDB:  " .. table_name
    .. "   [region: " .. region .. "]"
    .. (profile and ("   [profile: " .. profile .. "]") or "")

  local km   = config.values.keymaps.dynamodb
  local hint = (km.menu_open or "<CR>") .. " open"
    .. "  |  " .. (km.menu_refresh or "R") .. " refresh"

  local sep   = string.rep("-", 72)
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

---@param table_name string
---@param call_opts  AwsCallOpts|nil
function M.open(table_name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(table_name), FILETYPE)
  _bufs[table_name] = buf
  buf_mod.open_vsplit(buf)

  keymaps.apply_dynamodb_menu(buf, {
    open_section = function()
      local entry = entry_under_cursor()
      if not entry then
        vim.notify("aws.nvim: no section under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.dynamodb." .. entry.key).open(table_name, call_opts)
    end,
    refresh = function()
      render(buf, table_name, call_opts)
    end,
  })

  render(buf, table_name, call_opts)
end

return M
