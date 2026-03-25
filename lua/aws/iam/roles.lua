--- aws.nvim – IAM Roles list
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-iam"

local _state = {}

local function buf_name(identity)
  return "aws://iam/roles/" .. identity
end

local function pad_right(s, width)
  local dw = vim.fn.strdisplaywidth(s)
  if dw >= width then return s end
  return s .. string.rep(" ", width - dw)
end

local function hint_line()
  local km = config.values.keymaps.iam
  local parts = {}
  if km.open_detail  then table.insert(parts, km.open_detail  .. " detail") end
  if km.filter       then table.insert(parts, km.filter       .. " filter") end
  if km.clear_filter then table.insert(parts, km.clear_filter .. " clear")  end
  if km.refresh      then table.insert(parts, km.refresh      .. " refresh") end
  return table.concat(parts, "  |  ")
end

local function render(buf, st)
  local name_w = 4
  local desc_w = 11  -- "Description"
  local date_w = 25

  for _, item in ipairs(st.items) do
    local n = item.RoleName   or ""
    local d = item.Description or ""
    if st.filter == "" or n:lower():find(st.filter:lower(), 1, true) then
      local nw = vim.fn.strdisplaywidth(n)
      local dw = vim.fn.strdisplaywidth(d)
      if nw > name_w then name_w = nw end
      if dw > desc_w then desc_w = dw end
    end
  end
  name_w = name_w + 2
  date_w = date_w + 2

  local title = "IAM  Roles"
    .. "   [region: " .. st.region .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")
    .. (st.filter ~= "" and ("   [filter: " .. st.filter .. "]") or "")

  local sep = string.rep("-", name_w + date_w + desc_w + 8)
  local lines = { "", title, "", sep, hint_line(), sep,
    pad_right("Name", name_w) .. "  "
      .. pad_right("Created", date_w) .. "  "
      .. "Description",
    sep,
  }

  st.line_map = {}

  for _, item in ipairs(st.items) do
    local name    = item.RoleName    or ""
    local created = item.CreateDate  or "—"
    local desc    = item.Description or "—"

    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      table.insert(lines,
        pad_right(name,    name_w) .. "  "
        .. pad_right(created, date_w) .. "  "
        .. desc
      )
      st.line_map[#lines] = name
    end
  end

  if not next(st.line_map) then table.insert(lines, "(no roles match)") end
  buf_mod.set_lines(buf, lines)
end

local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  local all = {}
  st.fetching  = true
  st.fetch_gen = st.fetch_gen + 1
  local my_gen = st.fetch_gen

  local function fetch_page(marker)
    local args = { "iam", "list-roles", "--output", "json" }
    if marker then vim.list_extend(args, { "--marker", marker }) end
    spawn.run(args, function(ok, lines)
      if my_gen ~= st.fetch_gen then return end
      if not ok then st.fetching = false; buf_mod.set_error(buf, lines); return end
      local raw = table.concat(lines, "\n")
      local ok2, data = pcall(vim.json.decode, raw)
      if not ok2 or type(data) ~= "table" then
        st.fetching = false; buf_mod.set_error(buf, { "Failed to parse JSON", raw }); return
      end
      local items = type(data.Roles) == "table" and data.Roles or {}
      for _, v in ipairs(items) do table.insert(all, v) end
      local next_marker = data.IsTruncated and data.Marker or nil
      st.fetching = next_marker ~= nil
      st.items    = all
      render(buf, st)
      if next_marker then fetch_page(next_marker) else st.cache = all end
    end, call_opts)
  end

  fetch_page(nil)
end

local function name_under_cursor(st)
  return st.line_map[vim.api.nvim_win_get_cursor(0)[1]]
end

---@param call_opts AwsCallOpts|nil
function M.open(call_opts)
  local identity = config.identity(call_opts)
  local buf = buf_mod.get_or_create(buf_name(identity), FILETYPE)
  buf_mod.open_split(buf)

  if not _state[identity] then
    _state[identity] = {
      items = {}, filter = "", line_map = {}, cache = nil,
      fetching = false, fetch_gen = 0,
      region  = config.resolve_region(call_opts),
      profile = config.resolve_profile(call_opts),
    }
  end
  local st = _state[identity]

  keymaps.apply_iam_list(buf, {
    open_detail = function()
      local name = name_under_cursor(st)
      if not name then vim.notify("aws.nvim: no role under cursor", vim.log.levels.WARN); return end
      require("aws.iam.detail.role").open(name, call_opts)
    end,
    filter = function()
      vim.ui.input({ prompt = "Filter roles: ", default = st.filter }, function(input)
        if input == nil then return end
        st.filter = input
        if st.cache then st.items = st.cache end
        render(buf, st)
      end)
    end,
    clear_filter = function()
      st.filter = ""
      if st.cache then st.items = st.cache; render(buf, st)
      else fetch(buf, st, call_opts) end
    end,
    refresh = function() st.cache = nil; fetch(buf, st, call_opts) end,
  })

  if st.cache then st.items = st.cache; render(buf, st)
  else fetch(buf, st, call_opts) end
end

return M
