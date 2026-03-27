--- aws.nvim – DynamoDB tables list, filter, delete
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-dynamodb"

---@class DynamoDbTablesState
---@field items      table[]               describe-table result items (trimmed)
---@field filter     string
---@field line_map   table<integer,string> line -> table name
---@field cache      table[]|nil           full unfiltered list; nil = not yet fetched
---@field fetching   boolean
---@field fetch_gen  integer
---@field region     string
---@field profile    string|nil

--- State keyed by identity string (e.g. "us-east-1" or "prod@eu-west-1")
local _state = {}  -- identity -> DynamoDbTablesState

local function buf_name(identity)
  return "aws://dynamodb/tables/" .. identity
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

local function fmt_bytes(n)
  n = n or 0
  if n >= 1073741824 then return string.format("%.1f GB", n / 1073741824)
  elseif n >= 1048576 then return string.format("%.1f MB", n / 1048576)
  elseif n >= 1024    then return string.format("%.1f KB", n / 1024)
  end
  return n .. " B"
end

local function hint_line()
  local km = config.values.keymaps.dynamodb
  local hints = {}
  if km.open_menu    then table.insert(hints, km.open_menu    .. " menu")    end
  if km.delete       then table.insert(hints, km.delete       .. " delete")  end
  if km.filter       then table.insert(hints, km.filter       .. " filter")  end
  if km.clear_filter then table.insert(hints, km.clear_filter .. " clear")   end
  if km.refresh      then table.insert(hints, km.refresh      .. " refresh") end
  return table.concat(hints, "  |  ")
end

---@param buf integer
---@param st  DynamoDbTablesState
local function render(buf, st)
  local name_width   = 4   -- "Name"
  local status_width = 6   -- "Status"
  local class_width  = 7   -- "Class"
  local billing_width = 7  -- "Billing"

  for _, item in ipairs(st.items) do
    local name = item.TableName or ""
    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      local nw = vim.fn.strdisplaywidth(name)
      if nw > name_width then name_width = nw end
    end
  end
  name_width    = name_width    + 2
  status_width  = status_width  + 2
  class_width   = class_width   + 2
  billing_width = billing_width + 2

  local title = "DynamoDB  Tables"
    .. "   [region: " .. st.region .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")
    .. (st.filter ~= "" and ("   [filter: " .. st.filter .. "]") or "")

  local total = name_width + status_width + class_width + billing_width + 22
  local sep   = string.rep("-", total)

  local lines = { "", title, "", sep, hint_line(), sep,
    pad_right("Name",    name_width)
      .. pad_right("Status",  status_width)
      .. pad_right("Class",   class_width)
      .. pad_right("Billing", billing_width)
      .. pad_right("Items",   10)
      .. "Size",
    sep,
  }

  st.line_map = {}

  for _, item in ipairs(st.items) do
    local name    = item.TableName or ""
    local status  = item.TableStatus or "—"
    local class   = item.TableClassSummary
      and (item.TableClassSummary.TableClass or "STANDARD")
      or "STANDARD"
    -- Shorten class labels for display
    if class == "STANDARD_INFREQUENT_ACCESS" then class = "STD_IA" end
    local billing = "—"
    if item.BillingModeSummary then
      billing = item.BillingModeSummary.BillingMode or "—"
    elseif item.ProvisionedThroughput then
      billing = "PROVISIONED"
    end
    local item_count = tostring(item.ItemCount or "—")
    local size       = item.TableSizeBytes and fmt_bytes(item.TableSizeBytes) or "—"

    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      table.insert(lines,
        pad_right(truncate(name, name_width - 2), name_width)
        .. pad_right(status,     status_width)
        .. pad_right(class,      class_width)
        .. pad_right(billing,    billing_width)
        .. pad_right(item_count, 10)
        .. size
      )
      st.line_map[#lines] = name
    end
  end

  if not next(st.line_map) then
    table.insert(lines, "(no tables match)")
  end

  buf_mod.set_lines(buf, lines)
end

-------------------------------------------------------------------------------
-- Fetch: list-tables (paginated) then describe-table per table in parallel
-------------------------------------------------------------------------------

---@param buf       integer
---@param st        DynamoDbTablesState
---@param call_opts AwsCallOpts|nil
local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  st.fetching  = true
  st.fetch_gen = st.fetch_gen + 1
  local my_gen   = st.fetch_gen
  local all_names = {}

  -- Step 2: describe all collected table names in parallel (one call each)
  local function describe_all(names)
    if #names == 0 then
      st.fetching = false
      st.items    = {}
      st.cache    = {}
      render(buf, st)
      return
    end

    local results     = {}
    local pending     = #names
    local desc_gen    = my_gen

    for _, name in ipairs(names) do
      spawn.run({ "dynamodb", "describe-table", "--table-name", name, "--output", "json" },
        function(ok, lines)
          if desc_gen ~= st.fetch_gen then return end
          if ok then
            local raw = table.concat(lines, "\n")
            local ok2, data = pcall(vim.json.decode, raw)
            if ok2 and type(data) == "table" and type(data.Table) == "table" then
              table.insert(results, data.Table)
            end
          end
          pending = pending - 1
          if pending == 0 then
            -- Sort results by table name for stable ordering
            table.sort(results, function(a, b)
              return (a.TableName or "") < (b.TableName or "")
            end)
            st.fetching = false
            st.items    = results
            st.cache    = results
            render(buf, st)
          end
        end, call_opts)
    end
  end

  -- Step 1: paginate list-tables to collect all names
  local function list_page(last_name)
    local args = { "dynamodb", "list-tables", "--output", "json" }
    if last_name then
      vim.list_extend(args, { "--exclusive-start-table-name", last_name })
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
      local names = type(data.TableNames) == "table" and data.TableNames or {}
      for _, n in ipairs(names) do
        table.insert(all_names, n)
      end
      local token = type(data.LastEvaluatedTableName) == "string"
        and data.LastEvaluatedTableName or nil
      if token then
        list_page(token)
      else
        describe_all(all_names)
      end
    end, call_opts)
  end

  all_names = {}
  list_page(nil)
end

-------------------------------------------------------------------------------
-- Cursor helpers
-------------------------------------------------------------------------------

---@param st DynamoDbTablesState
---@return string|nil
local function name_under_cursor(st)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return st.line_map[row]
end

---@param st DynamoDbTablesState
---@param r1 integer
---@param r2 integer
---@return string[]
local function names_in_range(st, r1, r2)
  local out  = {}
  local seen = {}
  for row = r1, r2 do
    local name = st.line_map[row]
    if name and not seen[name] then
      seen[name] = true
      table.insert(out, name)
    end
  end
  return out
end

---@param st    DynamoDbTablesState
---@param names table<string, boolean>  set of names to remove
---@param buf   integer
local function remove_from_state(st, names, buf)
  local function filter_list(list)
    local out = {}
    for _, item in ipairs(list) do
      if not names[item.TableName] then
        table.insert(out, item)
      end
    end
    return out
  end
  st.items = filter_list(st.items)
  if st.cache then st.cache = filter_list(st.cache) end
  render(buf, st)
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

  local function delete_one()
    local name = name_under_cursor(st)
    if not name then
      vim.notify("aws.nvim: no table under cursor", vim.log.levels.WARN)
      return
    end
    require("aws.dynamodb.delete").confirm(name, function()
      remove_from_state(st, { [name] = true }, buf)
    end, call_opts)
  end

  local function delete_visual(r1, r2)
    local names = names_in_range(st, r1, r2)
    if #names == 0 then
      vim.notify("aws.nvim: no tables in selection", vim.log.levels.WARN)
      return
    end
    local label = #names == 1
      and ("Yes, delete " .. names[1])
      or  ("Yes, delete " .. #names .. " tables")
    vim.ui.select(
      { label, "Cancel" },
      { prompt = "Delete DynamoDB tables?" },
      function(_, idx)
        if not idx or idx ~= 1 then return end
        local del     = require("aws.dynamodb.delete")
        local removed = {}
        local function next_delete(i)
          if i > #names then
            remove_from_state(st, removed, buf)
            return
          end
          local n = names[i]
          del.run(n, function()
            removed[n] = true
            next_delete(i + 1)
          end, call_opts)
        end
        next_delete(1)
      end
    )
  end

  keymaps.apply_dynamodb(buf, {
    open_menu = function()
      local name = name_under_cursor(st)
      if not name then
        vim.notify("aws.nvim: no table under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.dynamodb.menu").open(name, call_opts)
    end,

    delete        = delete_one,
    delete_visual = delete_visual,

    filter = function()
      vim.ui.input({ prompt = "Filter tables: ", default = st.filter }, function(input)
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
  })

  if st.cache then
    st.items = st.cache
    render(buf, st)
  else
    fetch(buf, st, call_opts)
  end
end

return M
