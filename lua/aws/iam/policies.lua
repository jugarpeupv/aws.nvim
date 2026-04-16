--- aws.nvim – IAM Policies list (customer-managed by default; T toggles All)
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-iam"

---@class IamPoliciesState
---@field items      table[]
---@field filter     string
---@field scope      string   "Local"|"All"
---@field line_map   table<integer,string>  line -> PolicyArn
---@field cache      table<string, table[]>  scope -> list
---@field fetching   boolean
---@field fetch_gen  integer
---@field region     string
---@field profile    string|nil

local _state = {}

local function buf_name(identity)
  return "aws://iam/policies/" .. identity
end

local function pad_right(s, width)
  local dw = vim.fn.strdisplaywidth(s)
  if dw >= width then
    return s
  end
  return s .. string.rep(" ", width - dw)
end

local function hint_line()
  local km = config.values.keymaps.iam
  local parts = {}
  if km.open_detail then
    table.insert(parts, km.open_detail .. " detail")
  end
  if km.filter then
    table.insert(parts, km.filter .. " filter")
  end
  if km.clear_filter then
    table.insert(parts, km.clear_filter .. " clear")
  end
  if km.toggle_scope then
    table.insert(parts, km.toggle_scope .. " scope")
  end
  if km.refresh then
    table.insert(parts, km.refresh .. " refresh")
  end
  return table.concat(parts, "  |  ")
end

local function render(buf, st)
  local name_w = 4
  local arn_w = 3 -- "ARN"
  local date_w = 25

  for _, item in ipairs(st.items) do
    local n = item.PolicyName or ""
    local a = item.Arn or ""
    if st.filter == "" or n:lower():find(st.filter:lower(), 1, true) or a:lower():find(st.filter:lower(), 1, true) then
      local nw = vim.fn.strdisplaywidth(n)
      local aw = vim.fn.strdisplaywidth(a)
      if nw > name_w then
        name_w = nw
      end
      if aw > arn_w then
        arn_w = aw
      end
    end
  end
  name_w = name_w + 2
  arn_w = arn_w + 2
  date_w = date_w + 2

  local scope_label = st.scope == "All" and "[scope: All]" or "[scope: Local]"
  local title = "IAM  Policies  "
    .. scope_label
    .. "   [region: "
    .. st.region
    .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")
    .. (st.filter ~= "" and ("   [filter: " .. st.filter .. "]") or "")

  local sep = string.rep("-", name_w + date_w + arn_w + 8)
  local lines = {
    "",
    title,
    "",
    sep,
    hint_line(),
    sep,
    pad_right("Name", name_w) .. "  " .. pad_right("Updated", date_w) .. "  " .. "ARN",
    sep,
  }

  st.line_map = {}

  for _, item in ipairs(st.items) do
    local name = item.PolicyName or ""
    local updated = item.UpdatedDate or item.CreateDate or "—"
    local arn = item.Arn or "—"

    if
      st.filter == ""
      or name:lower():find(st.filter:lower(), 1, true)
      or arn:lower():find(st.filter:lower(), 1, true)
    then
      table.insert(lines, pad_right(name, name_w) .. "  " .. pad_right(updated, date_w) .. "  " .. arn)
      st.line_map[#lines] = arn
    end
  end

  if not next(st.line_map) then
    table.insert(lines, "(no policies match)")
  end
  buf_mod.set_lines(buf, lines)
end

local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  local all = {}
  st.fetching = true
  st.fetch_gen = st.fetch_gen + 1
  local my_gen = st.fetch_gen
  local scope = st.scope

  local function fetch_page(marker)
    local args = { "iam", "list-policies", "--scope", scope, "--output", "json" }
    if marker then
      vim.list_extend(args, { "--marker", marker })
    end
    spawn.run(args, function(ok, lines)
      if my_gen ~= st.fetch_gen then
        return
      end
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
      local items = type(data.Policies) == "table" and data.Policies or {}
      for _, v in ipairs(items) do
        table.insert(all, v)
      end
      local next_marker = data.IsTruncated and data.Marker or nil
      st.fetching = next_marker ~= nil
      st.items = all
      render(buf, st)
      if next_marker then
        fetch_page(next_marker)
      else
        st.cache[scope] = all
      end
    end, call_opts)
  end

  fetch_page(nil)
end

local function arn_under_cursor(st)
  return st.line_map[vim.api.nvim_win_get_cursor(0)[1]]
end

---@param call_opts AwsCallOpts|nil
function M.open(call_opts)
  local identity = config.identity(call_opts)
  local buf = buf_mod.get_or_create(buf_name(identity), FILETYPE)
  buf_mod.open_split(buf)

  if not _state[identity] then
    _state[identity] = {
      items = {},
      filter = "",
      scope = "Local",
      line_map = {},
      cache = {},
      fetching = false,
      fetch_gen = 0,
      region = config.resolve_region(call_opts),
      profile = config.resolve_profile(call_opts),
    }
  end
  local st = _state[identity]

  keymaps.apply_iam_list(buf, {
    open_detail = function()
      local arn = arn_under_cursor(st)
      if not arn then
        vim.notify("aws.nvim: no policy under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.iam.detail.policy").open(arn, call_opts)
    end,
    filter = function()
      vim.ui.input({ prompt = "Filter policies: ", default = st.filter }, function(input)
        if input == nil then
          return
        end
        st.filter = input
        if st.cache[st.scope] then
          st.items = st.cache[st.scope]
        end
        render(buf, st)
      end)
    end,
    clear_filter = function()
      st.filter = ""
      if st.cache[st.scope] then
        st.items = st.cache[st.scope]
        render(buf, st)
      else
        fetch(buf, st, call_opts)
      end
    end,
    toggle_scope = function()
      st.scope = (st.scope == "Local") and "All" or "Local"
      if st.cache[st.scope] then
        st.items = st.cache[st.scope]
        render(buf, st)
      else
        fetch(buf, st, call_opts)
      end
    end,
    refresh = function()
      st.cache[st.scope] = nil
      fetch(buf, st, call_opts)
    end,
  })

  if st.cache[st.scope] then
    st.items = st.cache[st.scope]
    render(buf, st)
  else
    fetch(buf, st, call_opts)
  end
end

return M
