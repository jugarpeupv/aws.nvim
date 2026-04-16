--- aws.nvim – API Gateway REST APIs list, filter, and render
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-apigateway"

---@class AgwApisState
---@field items      table[]
---@field filter     string
---@field line_map   table<integer,string>  line -> API ID
---@field cache      table[]|nil            full unfiltered list; nil = not yet fetched
---@field fetching   boolean                true while pages are still arriving
---@field fetch_gen  integer                incremented on every new fetch; stale cbs check this
---@field region     string
---@field profile    string|nil

--- State keyed by identity string (e.g. "us-east-1" or "prod@eu-west-1")
local _state = {} -- identity -> AgwApisState

local function buf_name(identity)
  return "aws://apigateway/apis/" .. identity
end

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

--- Return the creation date as-is from the API response.
---@param value number|string|nil
---@return string
local function fmt_date(value)
  if not value then
    return "—"
  end
  if type(value) == "number" then
    return os.date("%Y-%m-%dT%H:%M:%S", math.floor(value))
  end
  return tostring(value)
end

--- Return the first endpoint type from the configuration.
---@param item table
---@return string
local function fmt_endpoint_type(item)
  local ec = type(item.endpointConfiguration) == "table" and item.endpointConfiguration or {}
  local types = type(ec.types) == "table" and ec.types or {}
  if #types > 0 then
    return types[1]
  end
  return "—"
end

local function hint_line()
  local km = config.values.keymaps.apigateway
  local hints = {}
  if km.open_detail then
    table.insert(hints, km.open_detail .. " detail")
  end
  if km.filter then
    table.insert(hints, km.filter .. " filter")
  end
  if km.clear_filter then
    table.insert(hints, km.clear_filter .. " clear")
  end
  if km.refresh then
    table.insert(hints, km.refresh .. " refresh")
  end
  return table.concat(hints, "  |  ")
end

---@param id_width       integer
---@param name_width     integer
---@param endpoint_width integer
---@param date_width     integer
---@return string[]
local function make_header(id_width, name_width, endpoint_width, date_width)
  local total = id_width + name_width + endpoint_width + date_width + 36
  local sep = string.rep("-", total)
  return {
    sep,
    hint_line(),
    sep,
    pad_right("ID", id_width)
      .. "  "
      .. pad_right("Name", name_width)
      .. "  "
      .. pad_right("Endpoint", endpoint_width)
      .. "  "
      .. pad_right("Created", date_width)
      .. "  "
      .. "Description",
    string.rep("-", total),
  }
end

---@param buf integer
---@param st  AgwApisState
local function render(buf, st)
  local id_width = 2 -- "ID"
  local name_width = 4 -- "Name"
  local endpoint_width = 8 -- "Endpoint"
  local date_width = 25 -- "YYYY-MM-DDTHH:MM:SS+HH:MM"

  -- First pass: measure column widths for visible rows
  for _, item in ipairs(st.items) do
    local id = item.id or ""
    local name = item.name or ""
    if
      st.filter == ""
      or id:lower():find(st.filter:lower(), 1, true)
      or name:lower():find(st.filter:lower(), 1, true)
    then
      local iw = vim.fn.strdisplaywidth(id)
      local nw = vim.fn.strdisplaywidth(name)
      if iw > id_width then
        id_width = iw
      end
      if nw > name_width then
        name_width = nw
      end
    end
  end
  id_width = id_width + 2
  name_width = name_width + 2
  endpoint_width = endpoint_width + 2
  date_width = date_width + 2

  local title = "API Gateway  REST APIs"
    .. "   [region: "
    .. st.region
    .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")
    .. (st.filter ~= "" and ("   [filter: " .. st.filter .. "]") or "")

  local header = make_header(id_width, name_width, endpoint_width, date_width)
  local lines = { "", title, "" }
  for _, h in ipairs(header) do
    table.insert(lines, h)
  end

  st.line_map = {}

  for _, item in ipairs(st.items) do
    local id = item.id or ""
    local name = item.name or ""
    local endpoint = fmt_endpoint_type(item)
    local created = fmt_date(item.createdDate)
    local desc = item.description or "—"

    if
      st.filter == ""
      or id:lower():find(st.filter:lower(), 1, true)
      or name:lower():find(st.filter:lower(), 1, true)
    then
      table.insert(
        lines,
        pad_right(id, id_width)
          .. "  "
          .. pad_right(name, name_width)
          .. "  "
          .. pad_right(endpoint, endpoint_width)
          .. "  "
          .. pad_right(created, date_width)
          .. "  "
          .. desc
      )
      st.line_map[#lines] = id
    end
  end

  if not next(st.line_map) then
    table.insert(lines, "(no REST APIs match)")
  end

  buf_mod.set_lines(buf, lines)
end

---@param buf       integer
---@param st        AgwApisState
---@param call_opts AwsCallOpts|nil
local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  local all = {}
  st.fetching = true
  st.fetch_gen = st.fetch_gen + 1
  local my_gen = st.fetch_gen

  local function fetch_page(position)
    local args = { "apigateway", "get-rest-apis", "--output", "json" }
    if position then
      vim.list_extend(args, { "--position", position })
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

      local items = type(data.items) == "table" and data.items or {}
      for _, item in ipairs(items) do
        table.insert(all, item)
      end

      local next_pos = type(data.position) == "string" and data.position or nil
      st.fetching = next_pos ~= nil
      st.items = all
      render(buf, st)

      if next_pos then
        fetch_page(next_pos)
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

--- Return the API ID under the cursor, or nil.
---@param st AgwApisState
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
      items = {},
      filter = "",
      line_map = {},
      cache = nil,
      fetching = false,
      fetch_gen = 0,
      region = config.resolve_region(call_opts),
      profile = config.resolve_profile(call_opts),
    }
  end
  local st = _state[identity]

  keymaps.apply_apigateway(buf, {
    open_detail = function()
      local id = id_under_cursor(st)
      if not id then
        vim.notify("aws.nvim: no REST API under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.apigateway.detail").open(id, call_opts)
    end,

    filter = function()
      vim.ui.input({ prompt = "Filter REST APIs: ", default = st.filter }, function(input)
        if input == nil then
          return
        end
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
