--- aws.nvim – Secrets Manager secrets list, filter, and render
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-secretsmanager"

---@class SmSecretState
---@field secrets   table[]
---@field filter    string
---@field line_map  table<integer,string>  line -> secret name
---@field cache     table[]|nil   full unfiltered list; nil = not yet fetched
---@field fetching  boolean       true while pages are still arriving
---@field fetch_gen integer       incremented on every new fetch; stale cbs check this
---@field region    string
---@field profile   string|nil

--- state keyed by identity string (e.g. "us-east-1" or "prod@eu-west-1")
local _state = {} -- identity -> SmSecretState

local function buf_name(identity)
  return "aws://secretsmanager/secrets/" .. identity
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

--- Truncate a string to at most `max` display columns, appending "…" if cut.
---@param s   string
---@param max integer
---@return string
local function truncate(s, max)
  if vim.fn.strdisplaywidth(s) <= max then
    return s
  end
  -- Walk codepoints via vim.fn until we fit within max-1 display cols.
  local result = ""
  local cols = 0
  local nchars = vim.fn.strchars(s)
  for i = 0, nchars - 1 do
    local ch = vim.fn.strcharpart(s, i, 1)
    local w = vim.fn.strdisplaywidth(ch)
    if cols + w > max - 1 then
      break
    end
    result = result .. ch
    cols = cols + w
  end
  return result .. "…"
end

--- Format a date value from Secrets Manager JSON.
--- The API returns ISO-8601 strings (e.g. "2024-01-15T10:23:45+00:00").
--- Handles both string and number (epoch) just in case.
---@param value number|string|nil
---@return string
local function fmt_date(value)
  if not value then
    return "—"
  end
  local t = type(value)
  if t == "number" then
    return os.date("%Y-%m-%d", math.floor(value))
  elseif t == "string" then
    local date = value:match("^(%d%d%d%d%-%d%d%-%d%d)")
    return date or value
  end
  return tostring(value)
end

local function hint_line()
  local km = config.values.keymaps.secretsmanager
  local hints = {}
  if km.open_detail then
    table.insert(hints, km.open_detail .. " detail")
  end
  if km.delete then
    table.insert(hints, km.delete .. " delete")
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

---@param name_width integer
---@param desc_width integer
---@param changed_width integer
---@return string[]
local function make_header(name_width, desc_width, changed_width)
  local total = name_width + desc_width + changed_width + 16
  local sep = string.rep("-", total)
  return {
    sep,
    hint_line(),
    sep,
    pad_right("Name", name_width) .. "  " .. pad_right("Description", desc_width) .. "  " .. pad_right(
      "Last Changed",
      changed_width
    ) .. "  " .. "Last Rotated",
    string.rep("-", total),
  }
end

---@param buf integer
---@param st  SmSecretState
local function render(buf, st)
  local DESC_MAX = 40
  local name_width = 4 -- len("Name")
  local desc_width = 11 -- len("Description")
  local changed_width = 12 -- len("Last Changed")

  for _, s in ipairs(st.secrets) do
    local name = s.Name or ""
    local desc = truncate(s.Description or "", DESC_MAX)
    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      local nw = vim.fn.strdisplaywidth(name)
      local dw = vim.fn.strdisplaywidth(desc)
      if nw > name_width then
        name_width = nw
      end
      if dw > desc_width then
        desc_width = dw
      end
    end
  end
  name_width = name_width + 2
  desc_width = desc_width + 2
  changed_width = changed_width + 2

  local title = "Secrets Manager"
    .. "   [region: "
    .. st.region
    .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")
    .. (st.filter ~= "" and ("   [filter: " .. st.filter .. "]") or "")

  local header = make_header(name_width, desc_width, changed_width)
  local lines = { "", title, "" }
  for _, h in ipairs(header) do
    table.insert(lines, h)
  end

  st.line_map = {}

  for _, s in ipairs(st.secrets) do
    local name = s.Name or ""
    local desc = truncate(s.Description or "—", DESC_MAX)
    local changed = fmt_date(s.LastChangedDate)
    local rotated = fmt_date(s.LastRotatedDate)
    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      table.insert(
        lines,
        pad_right(name, name_width)
          .. "  "
          .. pad_right(desc, desc_width)
          .. "  "
          .. pad_right(changed, changed_width)
          .. "  "
          .. rotated
      )
      st.line_map[#lines] = name
    end
  end

  if not next(st.line_map) then
    table.insert(lines, "(no secrets match)")
  end

  buf_mod.set_lines(buf, lines)
end

---@param buf       integer
---@param st        SmSecretState
---@param call_opts AwsCallOpts|nil
local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  local all = {}
  st.fetching = true
  st.fetch_gen = st.fetch_gen + 1
  local my_gen = st.fetch_gen

  local function fetch_page(next_token)
    local args = { "secretsmanager", "list-secrets", "--output", "json" }
    if next_token then
      vim.list_extend(args, { "--next-token", next_token })
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

      local list = type(data.SecretList) == "table" and data.SecretList or {}
      for _, s in ipairs(list) do
        table.insert(all, {
          Name = s.Name,
          ARN = s.ARN,
          Description = s.Description,
          LastChangedDate = s.LastChangedDate,
          LastRotatedDate = s.LastRotatedDate,
          LastAccessedDate = s.LastAccessedDate,
        })
      end

      local has_more = type(data.NextToken) == "string"
      st.fetching = has_more
      st.secrets = all
      render(buf, st)

      if has_more then
        fetch_page(data.NextToken)
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

--- Return the secret name under the cursor, or nil.
---@param st SmSecretState
---@return string|nil
local function name_under_cursor(st)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return st.line_map[row]
end

---@param st SmSecretState
---@param r1 integer
---@param r2 integer
---@return string[]
local function names_in_range(st, r1, r2)
  local names = {}
  local seen = {}
  for row = r1, r2 do
    local n = st.line_map[row]
    if n and not seen[n] then
      seen[n] = true
      table.insert(names, n)
    end
  end
  return names
end

---@param st    SmSecretState
---@param names table<string,boolean>  set of names to remove
---@param buf   integer
local function remove_from_state(st, names, buf)
  local function filter_list(list)
    local out = {}
    for _, s in ipairs(list) do
      if not names[s.Name] then
        table.insert(out, s)
      end
    end
    return out
  end
  st.secrets = filter_list(st.secrets)
  if st.cache then
    st.cache = filter_list(st.cache)
  end
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
      secrets = {},
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

  local function delete_one()
    local name = name_under_cursor(st)
    if not name then
      vim.notify("aws.nvim: no secret under cursor", vim.log.levels.WARN)
      return
    end
    require("aws.secretsmanager.delete").confirm(name, function()
      remove_from_state(st, { [name] = true }, buf)
    end, call_opts)
  end

  local function delete_visual(r1, r2)
    local names = names_in_range(st, r1, r2)
    if #names == 0 then
      vim.notify("aws.nvim: no secrets in selection", vim.log.levels.WARN)
      return
    end
    local label = #names == 1 and "Yes, delete immediately (no recovery window)"
      or ("Yes, delete " .. #names .. " secrets immediately (no recovery window)")
    vim.ui.select(
      { label, "Cancel" },
      { prompt = "Delete " .. (#names == 1 and ("secret '" .. names[1] .. "'") or (#names .. " secrets")) .. "?" },
      function(_, idx)
        if not idx or idx ~= 1 then
          return
        end
        local del = require("aws.secretsmanager.delete")
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

  keymaps.apply_secretsmanager(buf, {
    open_detail = function()
      local name = name_under_cursor(st)
      if not name then
        vim.notify("aws.nvim: no secret under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.secretsmanager.detail").open(name, call_opts)
    end,

    delete = delete_one,
    delete_visual = delete_visual,

    filter = function()
      vim.ui.input({ prompt = "Filter secrets: ", default = st.filter }, function(input)
        if input == nil then
          return
        end
        st.filter = input
        if input == "" then
          if st.cache then
            st.secrets = st.cache
            render(buf, st)
          else
            fetch(buf, st, call_opts)
          end
        else
          if st.cache then
            st.secrets = st.cache
          end
          render(buf, st)
        end
      end)
    end,

    clear_filter = function()
      st.filter = ""
      if st.cache then
        st.secrets = st.cache
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
    st.secrets = st.cache
    render(buf, st)
  else
    fetch(buf, st, call_opts)
  end
end

return M
