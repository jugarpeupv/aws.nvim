--- aws.nvim – ECS clusters list, filter, and render
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-ecs"

---@class EcsClustersState
---@field items      table[]               describe-clusters result items
---@field filter     string
---@field line_map   table<integer,string> line -> cluster ARN
---@field cache      table[]|nil           full unfiltered list; nil = not yet fetched
---@field fetching   boolean               true while pages are still arriving
---@field fetch_gen  integer               incremented on every new fetch; stale cbs check this
---@field region     string
---@field profile    string|nil

--- State keyed by identity string (e.g. "us-east-1" or "prod@eu-west-1")
local _state = {} -- identity -> EcsClustersState

local function buf_name(identity)
  return "aws://ecs/clusters/" .. identity
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

---@param s   string
---@param max integer
---@return string
local function truncate(s, max)
  if vim.fn.strdisplaywidth(s) <= max then
    return s
  end
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

--- Extract the short cluster name from a full ARN or return as-is.
---@param arn string
---@return string
local function cluster_name(arn)
  return arn:match("/([^/]+)$") or arn
end

local function hint_line()
  local km = config.values.keymaps.ecs
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

---@param buf integer
---@param st  EcsClustersState
local function render(buf, st)
  local name_width = 4 -- "Name"
  local status_width = 6 -- "Status"
  local reg_width = 4 -- "Reg."  (registered container instances)
  local run_width = 4 -- "Run."  (running tasks)
  local pend_width = 5 -- "Pend." (pending tasks)

  -- First pass: measure column widths for visible rows
  for _, item in ipairs(st.items) do
    local name = cluster_name(item.clusterArn or "")
    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      local nw = vim.fn.strdisplaywidth(name)
      if nw > name_width then
        name_width = nw
      end
    end
  end
  name_width = name_width + 2
  status_width = status_width + 2
  reg_width = reg_width + 2
  run_width = run_width + 2
  pend_width = pend_width + 2

  local title = "ECS  Clusters"
    .. "   [region: "
    .. st.region
    .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")
    .. (st.filter ~= "" and ("   [filter: " .. st.filter .. "]") or "")

  local total = name_width + status_width + reg_width + run_width + pend_width + 20
  local sep = string.rep("-", total)

  local lines = {
    "",
    title,
    "",
    sep,
    hint_line(),
    sep,
    pad_right("Name", name_width) .. pad_right("Status", status_width) .. pad_right("Inst", reg_width) .. pad_right(
      "Run",
      run_width
    ) .. pad_right("Pend", pend_width) .. "Active Svc  Pending Svc",
    sep,
  }

  st.line_map = {}

  for _, item in ipairs(st.items) do
    local arn = item.clusterArn or ""
    local name = cluster_name(arn)
    local status = item.status or "—"
    local reg = tostring(item.registeredContainerInstancesCount or 0)
    local run = tostring(item.runningTasksCount or 0)
    local pend = tostring(item.pendingTasksCount or 0)
    local active = tostring(item.activeServicesCount or 0)
    local psvc = tostring(item.statistics and (function()
      for _, s in ipairs(item.statistics) do
        if s.name == "pendingServiceCount" then
          return s.value
        end
      end
      return "0"
    end)() or "0")

    if st.filter == "" or name:lower():find(st.filter:lower(), 1, true) then
      table.insert(
        lines,
        pad_right(truncate(name, name_width - 2), name_width)
          .. pad_right(status, status_width)
          .. pad_right(reg, reg_width)
          .. pad_right(run, run_width)
          .. pad_right(pend, pend_width)
          .. active
          .. "  /  "
          .. psvc
      )
      st.line_map[#lines] = arn
    end
  end

  if not next(st.line_map) then
    table.insert(lines, "(no clusters match)")
  end

  buf_mod.set_lines(buf, lines)
end

-------------------------------------------------------------------------------
-- Fetch: list-clusters (paginated) then describe-clusters in one shot
-------------------------------------------------------------------------------

---@param buf       integer
---@param st        EcsClustersState
---@param call_opts AwsCallOpts|nil
local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  st.fetching = true
  st.fetch_gen = st.fetch_gen + 1
  local my_gen = st.fetch_gen
  local all_arns = {}

  -- Step 2: describe all collected ARNs (max 100 per call – well within typical cluster counts)
  local function describe(arns)
    local args = { "ecs", "describe-clusters", "--clusters" }
    vim.list_extend(args, arns)
    vim.list_extend(args, { "--include", "STATISTICS", "--output", "json" })
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
      local clusters = type(data.clusters) == "table" and data.clusters or {}
      st.fetching = false
      st.items = clusters
      st.cache = clusters
      render(buf, st)
    end, call_opts)
  end

  -- Step 1: paginate list-clusters to collect all ARNs
  local function list_page(next_token)
    local args = { "ecs", "list-clusters", "--output", "json" }
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
      local arns = type(data.clusterArns) == "table" and data.clusterArns or {}
      for _, arn in ipairs(arns) do
        table.insert(all_arns, arn)
      end
      local token = type(data.nextToken) == "string" and data.nextToken or nil
      if token then
        list_page(token)
      elseif #all_arns == 0 then
        st.fetching = false
        st.items = {}
        st.cache = {}
        render(buf, st)
      else
        describe(all_arns)
      end
    end, call_opts)
  end

  all_arns = {}
  list_page(nil)
end

-------------------------------------------------------------------------------
-- Cursor helpers
-------------------------------------------------------------------------------

---@param st EcsClustersState
---@return string|nil
local function arn_under_cursor(st)
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

  keymaps.apply_ecs(buf, {
    open_detail = function()
      local arn = arn_under_cursor(st)
      if not arn then
        vim.notify("aws.nvim: no cluster under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.ecs.detail").open(arn, call_opts)
    end,

    filter = function()
      vim.ui.input({ prompt = "Filter clusters: ", default = st.filter }, function(input)
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
