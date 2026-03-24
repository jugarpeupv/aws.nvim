--- aws.nvim – CloudFront distributions list, filter, and render
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-cloudfront"

---@class CfDistState
---@field items      table[]
---@field filter     string
---@field line_map   table<integer,string>  line -> distribution ID
---@field cache      table[]|nil            full unfiltered list; nil = not yet fetched
---@field fetching   boolean                true while pages are still arriving
---@field fetch_gen  integer                incremented on every new fetch; stale cbs check this
---@field region     string
---@field profile    string|nil

--- state keyed by identity string (e.g. "us-east-1" or "prod@eu-west-1")
local _state = {}  -- identity -> CfDistState

local function buf_name(identity)
  return "aws://cloudfront/distributions/" .. identity
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

--- Truncate a string to at most `max` display columns, appending "…" if cut.
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

local function hint_line()
  local km = config.values.keymaps.cloudfront
  local hints = {}
  if km.open_detail  then table.insert(hints, km.open_detail  .. " detail")     end
  if km.invalidate   then table.insert(hints, km.invalidate   .. " invalidate") end
  if km.filter       then table.insert(hints, km.filter       .. " filter")     end
  if km.clear_filter then table.insert(hints, km.clear_filter .. " clear")      end
  if km.refresh      then table.insert(hints, km.refresh      .. " refresh")    end
  return table.concat(hints, "  |  ")
end

--- Return the first alias of a distribution or the count of aliases.
---@param item table
---@return string
local function fmt_aliases(item)
  local aliases = type(item.Aliases) == "table" and item.Aliases or {}
  local list    = type(aliases.Items) == "table" and aliases.Items or {}
  local qty     = (type(aliases.Quantity) == "number" and aliases.Quantity)
                  or #list
  if qty == 0 then return "—" end
  if #list >= 1 then return list[1] .. (qty > 1 and (" (+" .. (qty - 1) .. ")") or "") end
  return tostring(qty) .. " alias(es)"
end

--- Return "Enabled" or "Disabled" based on the item's Enabled field.
---@param item table
---@return string
local function fmt_status(item)
  return item.Enabled and "Enabled" or "Disabled"
end

---@param st CfDistState
---@return string[]
local function make_header(id_width, domain_width, alias_width, comment_width)
  local total = id_width + domain_width + alias_width + comment_width + 24
  local sep   = string.rep("-", total)
  return {
    sep,
    hint_line(),
    sep,
    pad_right("ID",      id_width)      .. "  "
      .. pad_right("Domain",  domain_width)  .. "  "
      .. pad_right("Status",  10)            .. "  "
      .. pad_right("Aliases", alias_width)   .. "  "
      .. "Comment",
    string.rep("-", total),
  }
end

---@param buf integer
---@param st  CfDistState
local function render(buf, st)
  local COMMENT_MAX = 40
  local id_width      = 2    -- "ID"
  local domain_width  = 6    -- "Domain"
  local alias_width   = 7    -- "Aliases"

  for _, item in ipairs(st.items) do
    local id      = item.Id or ""
    local domain  = item.DomainName or ""
    local aliases = fmt_aliases(item)
    if st.filter == "" or id:lower():find(st.filter:lower(), 1, true)
      or domain:lower():find(st.filter:lower(), 1, true) then
      local iw = vim.fn.strdisplaywidth(id)
      local dw = vim.fn.strdisplaywidth(domain)
      local aw = vim.fn.strdisplaywidth(aliases)
      if iw > id_width     then id_width     = iw end
      if dw > domain_width then domain_width = dw end
      if aw > alias_width  then alias_width  = aw end
    end
  end
  id_width      = id_width     + 2
  domain_width  = domain_width + 2
  alias_width   = alias_width  + 2
  local comment_width = COMMENT_MAX

  local title = "CloudFront Distributions"
    .. "   [region: " .. st.region .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")
    .. (st.filter ~= "" and ("   [filter: " .. st.filter .. "]") or "")

  local header = make_header(id_width, domain_width, alias_width, comment_width)
  local lines  = { "", title, "" }
  for _, h in ipairs(header) do
    table.insert(lines, h)
  end

  st.line_map = {}

  for _, item in ipairs(st.items) do
    local id      = item.Id or ""
    local domain  = item.DomainName or ""
    local status  = fmt_status(item)
    local aliases = fmt_aliases(item)
    local comment = truncate(item.Comment or "—", COMMENT_MAX)
    if st.filter == "" or id:lower():find(st.filter:lower(), 1, true)
      or domain:lower():find(st.filter:lower(), 1, true) then
      table.insert(lines,
        pad_right(id,      id_width)     .. "  "
        .. pad_right(domain,  domain_width) .. "  "
        .. pad_right(status,  10)           .. "  "
        .. pad_right(aliases, alias_width)  .. "  "
        .. comment
      )
      st.line_map[#lines] = id
    end
  end

  if not next(st.line_map) then
    table.insert(lines, "(no distributions match)")
  end

  buf_mod.set_lines(buf, lines)
end

---@param buf       integer
---@param st        CfDistState
---@param call_opts AwsCallOpts|nil
local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  local all = {}
  st.fetching  = true
  st.fetch_gen = st.fetch_gen + 1
  local my_gen = st.fetch_gen

  local function fetch_page(marker)
    local args = { "cloudfront", "list-distributions", "--output", "json" }
    if marker then
      vim.list_extend(args, { "--marker", marker })
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

      local dist_list = type(data.DistributionList) == "table" and data.DistributionList or {}
      local items     = type(dist_list.Items) == "table" and dist_list.Items or {}
      for _, item in ipairs(items) do
        table.insert(all, item)
      end

      local next_marker = type(dist_list.NextMarker) == "string" and dist_list.NextMarker or nil
      st.fetching = next_marker ~= nil
      st.items    = all
      render(buf, st)

      if next_marker then
        fetch_page(next_marker)
      else
        st.cache = all
      end
    end, call_opts)
  end

  all = {}
  fetch_page(nil)
end

-------------------------------------------------------------------------------
-- Cursor helpers
-------------------------------------------------------------------------------

--- Return the distribution ID under the cursor, or nil.
---@param st CfDistState
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

  keymaps.apply_cloudfront(buf, {
    open_detail = function()
      local id = id_under_cursor(st)
      if not id then
        vim.notify("aws.nvim: no distribution under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.cloudfront.detail").open(id, call_opts)
    end,

    invalidate = function()
      local id = id_under_cursor(st)
      if not id then
        vim.notify("aws.nvim: no distribution under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.cloudfront.invalidate").prompt(id, nil, call_opts)
    end,

    filter = function()
      vim.ui.input({ prompt = "Filter distributions: ", default = st.filter }, function(input)
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
          if st.cache then
            st.items = st.cache
          end
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
  })

  if st.cache then
    st.items = st.cache
    render(buf, st)
  else
    fetch(buf, st, call_opts)
  end
end

return M
