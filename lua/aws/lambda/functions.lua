--- aws.nvim – Lambda functions list, filter, and render
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-lambda"

---@class LambdaFnState
---@field functions table[]
---@field filter    string
---@field line_map  table<integer,string>
---@field cache     table[]|nil   full unfiltered list; nil = not yet fetched
---@field fetching  boolean       true while pages are still arriving
---@field fetch_gen integer       incremented on every new fetch; stale cbs check this
---@field region    string
---@field profile   string|nil

--- state keyed by identity string (e.g. "us-east-1" or "prod@eu-west-1")
local _state = {} -- identity -> LambdaFnState

local function buf_name(identity)
  return "aws://lambda/functions/" .. identity
end

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

---@param s     string
---@param width integer
---@return string
local function pad_right(s, width)
  local len = #s
  if len >= width then
    return s
  end
  return s .. string.rep(" ", width - len)
end

local function fmt_size(bytes)
  bytes = bytes or 0
  if bytes >= 1073741824 then
    return string.format("%.1f GB", bytes / 1073741824)
  elseif bytes >= 1048576 then
    return string.format("%.1f MB", bytes / 1048576)
  elseif bytes >= 1024 then
    return string.format("%.1f KB", bytes / 1024)
  end
  return bytes .. " B"
end

local function hint_line()
  local km = config.values.keymaps.lambda
  local hints = {}
  if km.open_detail then
    table.insert(hints, km.open_detail .. " detail")
  end
  if km.open_logs then
    table.insert(hints, km.open_logs .. " logs")
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
---@param rt_width   integer
---@return string[]
local function make_header(name_width, rt_width)
  local total = name_width + rt_width + 20
  local sep = string.rep("-", total)
  return {
    sep,
    hint_line(),
    sep,
    pad_right("Name", name_width)
      .. "  "
      .. pad_right("Runtime", rt_width)
      .. "  "
      .. pad_right("Memory", 8)
      .. "  "
      .. "Code size",
    string.rep("-", total),
  }
end

---@param buf integer
---@param st  LambdaFnState
local function render(buf, st)
  local name_width = 4 -- len("Name")
  local rt_width = 7 -- len("Runtime")

  for _, f in ipairs(st.functions) do
    local name = f.FunctionName or ""
    local rt = f.Runtime or ""
    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      if #name > name_width then
        name_width = #name
      end
      if #rt > rt_width then
        rt_width = #rt
      end
    end
  end
  name_width = name_width + 2
  rt_width = rt_width + 2

  local title = "Lambda Functions"
    .. "   [region: "
    .. st.region
    .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")
    .. (st.filter ~= "" and ("   [filter: " .. st.filter .. "]") or "")

  local header = make_header(name_width, rt_width)
  local lines = { "", title, "" }
  for _, h in ipairs(header) do
    table.insert(lines, h)
  end

  st.line_map = {}

  for _, f in ipairs(st.functions) do
    local name = f.FunctionName or ""
    local rt = f.Runtime or "—"
    local mem = f.MemorySize and (f.MemorySize .. " MB") or "—"
    local size = fmt_size(f.CodeSize)
    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      table.insert(
        lines,
        pad_right(name, name_width) .. "  " .. pad_right(rt, rt_width) .. "  " .. pad_right(mem, 8) .. "  " .. size
      )
      st.line_map[#lines] = name
    end
  end

  if not next(st.line_map) then
    table.insert(lines, "(no functions match)")
  end

  buf_mod.set_lines(buf, lines)
end

---@param buf       integer
---@param st        LambdaFnState
---@param call_opts AwsCallOpts|nil
local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  local all = {}
  st.fetching = true
  st.fetch_gen = st.fetch_gen + 1
  local my_gen = st.fetch_gen

  local function fetch_page(marker)
    local args = {
      "lambda",
      "list-functions",
      "--output",
      "json",
    }
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

      for _, f in ipairs(type(data.Functions) == "table" and data.Functions or {}) do
        table.insert(all, {
          FunctionName = f.FunctionName,
          Runtime = f.Runtime,
          MemorySize = f.MemorySize,
          Timeout = f.Timeout,
          CodeSize = f.CodeSize,
          LastModified = f.LastModified,
          Description = f.Description,
          Handler = f.Handler,
          Role = f.Role,
        })
      end

      local has_more = type(data.NextMarker) == "string"
      st.fetching = has_more
      st.functions = all
      render(buf, st)

      if has_more then
        fetch_page(data.NextMarker)
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

local function fn_under_cursor(st)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return st.line_map[row]
end

---@param st LambdaFnState
---@param r1 integer
---@param r2 integer
---@return string[]
local function fns_in_range(st, r1, r2)
  local names = {}
  local seen = {}
  for row = r1, r2 do
    local name = st.line_map[row]
    if name and not seen[name] then
      seen[name] = true
      table.insert(names, name)
    end
  end
  return names
end

---@param st    LambdaFnState
---@param names table<string, boolean>
---@param buf   integer
local function remove_from_state(st, names, buf)
  local function filter_list(list)
    local out = {}
    for _, f in ipairs(list) do
      if not names[f.FunctionName] then
        table.insert(out, f)
      end
    end
    return out
  end
  st.functions = filter_list(st.functions)
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
      functions = {},
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
    local name = fn_under_cursor(st)
    if not name then
      vim.notify("aws.nvim: no function under cursor", vim.log.levels.WARN)
      return
    end
    require("aws.lambda.delete").confirm(name, function()
      remove_from_state(st, { [name] = true }, buf)
    end, call_opts)
  end

  local function delete_visual(r1, r2)
    local names = fns_in_range(st, r1, r2)
    if #names == 0 then
      vim.notify("aws.nvim: no functions in selection", vim.log.levels.WARN)
      return
    end
    local label = #names == 1 and ("Yes, delete " .. names[1]) or ("Yes, delete " .. #names .. " functions")
    vim.ui.select({ label, "Cancel" }, { prompt = "Delete Lambda functions?" }, function(_, idx)
      if not idx or idx ~= 1 then
        return
      end
      local del = require("aws.lambda.delete")
      local removed = {}
      local function next_delete(i)
        if i > #names then
          remove_from_state(st, removed, buf)
          return
        end
        local name = names[i]
        del.run(name, function()
          removed[name] = true
          next_delete(i + 1)
        end, call_opts)
      end
      next_delete(1)
    end)
  end

  keymaps.apply_lambda(buf, {
    open_detail = function()
      local name = fn_under_cursor(st)
      if not name then
        vim.notify("aws.nvim: no function under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.lambda.detail").open(name, call_opts)
    end,

    open_logs = function()
      local name = fn_under_cursor(st)
      if not name then
        vim.notify("aws.nvim: no function under cursor", vim.log.levels.WARN)
        return
      end
      local log_group = "/aws/lambda/" .. name
      require("aws.cloudwatch.streams").open(log_group, call_opts)
    end,

    delete = delete_one,
    delete_visual = delete_visual,

    filter = function()
      vim.ui.input({ prompt = "Filter functions: ", default = st.filter }, function(input)
        if input == nil then
          return
        end
        st.filter = input
        if input == "" then
          if st.cache then
            st.functions = st.cache
            render(buf, st)
          else
            fetch(buf, st, call_opts)
          end
        else
          -- client-side filter against cache (or current list)
          if st.cache then
            st.functions = st.cache
          end
          render(buf, st)
        end
      end)
    end,

    clear_filter = function()
      st.filter = ""
      if st.cache then
        st.functions = st.cache
        render(buf, st)
      else
        fetch(buf, st, call_opts)
      end
    end,

    refresh = function()
      st.cache = nil
      fetch(buf, st, call_opts)
    end,

    close = function()
      buf_mod.close_split(buf)
    end,
  })

  if st.cache then
    st.functions = st.cache
    render(buf, st)
  else
    fetch(buf, st, call_opts)
  end
end

return M
