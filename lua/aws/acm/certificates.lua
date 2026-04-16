--- aws.nvim – ACM certificates list, filter, and render
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-acm"

---@class AcmCertState
---@field certs     table[]
---@field filter    string
---@field line_map  table<integer,{arn:string,domain:string}>
---@field cache     table[]|nil   full unfiltered list; nil = not yet fetched
---@field fetching  boolean       true while pages are still arriving
---@field fetch_gen integer       incremented on every new fetch; stale cbs check this
---@field region    string
---@field profile   string|nil

--- state keyed by identity string (e.g. "us-east-1" or "prod@eu-west-1")
local _state = {} -- identity -> AcmCertState

local function buf_name(identity)
  return "aws://acm/certificates/" .. identity
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

--- Map ACM status to a display icon.
---@param status string|nil
---@return string
local function status_icon(status)
  local icons = config.values.icons
  if status == "ISSUED" then
    return icons.complete
  elseif status == "PENDING_VALIDATION" then
    return icons.in_progress
  elseif status == "EXPIRED" or status == "REVOKED" or status == "FAILED" then
    return icons.failed
  else
    return icons.stack
  end
end

--- Format a date value from ACM JSON.
--- ACM can return either a Unix epoch number (e.g. 1703123456.789) or an
--- ISO-8601 string (e.g. "2024-01-15T10:23:45+00:00") depending on the CLI
--- version and output format.
---@param value number|string|nil
---@return string
local function fmt_epoch(value)
  if not value then
    return "—"
  end
  local t = type(value)
  if t == "number" then
    return os.date("%Y-%m-%d", math.floor(value))
  elseif t == "string" then
    -- Extract YYYY-MM-DD from any ISO-8601-like string
    local date = value:match("^(%d%d%d%d%-%d%d%-%d%d)")
    return date or value
  end
  return tostring(value)
end

local function hint_line()
  local km = config.values.keymaps.acm
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

---@param domain_width integer
---@param status_width  integer
---@param type_width    integer
---@return string[]
local function make_header(domain_width, status_width, type_width)
  local total = domain_width + status_width + type_width + 15
  local sep = string.rep("-", total)
  return {
    sep,
    hint_line(),
    sep,
    pad_right("Domain", domain_width) .. "  " .. pad_right("Status", status_width) .. "  " .. pad_right(
      "Type",
      type_width
    ) .. "  " .. "Expiry",
    string.rep("-", total),
  }
end

---@param buf integer
---@param st  AcmCertState
local function render(buf, st)
  local domain_width = 6 -- len("Domain")
  local status_width = 6 -- len("Status")
  local type_width = 4 -- len("Type")

  for _, c in ipairs(st.certs) do
    local domain = c.DomainName or ""
    local status = (status_icon(c.Status) .. " " .. (c.Status or ""))
    local ctype = c.Type or ""
    if st.filter == "" or domain:lower():find(st.filter:lower(), 1, true) then
      if #domain > domain_width then
        domain_width = #domain
      end
      if #status > status_width then
        status_width = #status
      end
      if #ctype > type_width then
        type_width = #ctype
      end
    end
  end
  domain_width = domain_width + 2
  status_width = status_width + 2
  type_width = type_width + 2

  local title = "ACM Certificates"
    .. "   [region: "
    .. st.region
    .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")
    .. (st.filter ~= "" and ("   [filter: " .. st.filter .. "]") or "")

  local header = make_header(domain_width, status_width, type_width)
  local lines = { "", title, "" }
  for _, h in ipairs(header) do
    table.insert(lines, h)
  end

  st.line_map = {}

  for _, c in ipairs(st.certs) do
    local domain = c.DomainName or ""
    local status = status_icon(c.Status) .. " " .. (c.Status or "—")
    local ctype = c.Type or "—"
    local expiry = fmt_epoch(c.NotAfter)
    if st.filter == "" or domain:lower():find(st.filter:lower(), 1, true) then
      table.insert(
        lines,
        pad_right(domain, domain_width)
          .. "  "
          .. pad_right(status, status_width)
          .. "  "
          .. pad_right(ctype, type_width)
          .. "  "
          .. expiry
      )
      st.line_map[#lines] = { arn = c.CertificateArn, domain = domain }
    end
  end

  if not next(st.line_map) then
    table.insert(lines, "(no certificates match)")
  end

  buf_mod.set_lines(buf, lines)
end

---@param buf       integer
---@param st        AcmCertState
---@param call_opts AwsCallOpts|nil
local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  local all = {}
  st.fetching = true
  st.fetch_gen = st.fetch_gen + 1
  local my_gen = st.fetch_gen

  local function fetch_page(next_token)
    local args = {
      "acm",
      "list-certificates",
      "--certificate-statuses",
      "PENDING_VALIDATION",
      "ISSUED",
      "INACTIVE",
      "EXPIRED",
      "VALIDATION_TIMED_OUT",
      "REVOKED",
      "FAILED",
      "--output",
      "json",
    }
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

      local list = type(data.CertificateSummaryList) == "table" and data.CertificateSummaryList or {}
      for _, c in ipairs(list) do
        table.insert(all, {
          CertificateArn = c.CertificateArn,
          DomainName = c.DomainName,
          Status = c.Status,
          Type = c.Type,
          NotAfter = c.NotAfter,
        })
      end

      local has_more = type(data.NextToken) == "string"
      st.fetching = has_more
      st.certs = all
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

local function entry_under_cursor(st)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return st.line_map[row]
end

---@param st AcmCertState
---@param r1 integer
---@param r2 integer
---@return {arn:string,domain:string}[]
local function entries_in_range(st, r1, r2)
  local entries = {}
  local seen = {}
  for row = r1, r2 do
    local e = st.line_map[row]
    if e and not seen[e.arn] then
      seen[e.arn] = true
      table.insert(entries, e)
    end
  end
  return entries
end

---@param st      AcmCertState
---@param arns    table<string, boolean>
---@param buf     integer
local function remove_from_state(st, arns, buf)
  local function filter_list(list)
    local out = {}
    for _, c in ipairs(list) do
      if not arns[c.CertificateArn] then
        table.insert(out, c)
      end
    end
    return out
  end
  st.certs = filter_list(st.certs)
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
      certs = {},
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
    local e = entry_under_cursor(st)
    if not e then
      vim.notify("aws.nvim: no certificate under cursor", vim.log.levels.WARN)
      return
    end
    require("aws.acm.delete").confirm(e.arn, e.domain, function()
      remove_from_state(st, { [e.arn] = true }, buf)
    end, call_opts)
  end

  local function delete_visual(r1, r2)
    local entries = entries_in_range(st, r1, r2)
    if #entries == 0 then
      vim.notify("aws.nvim: no certificates in selection", vim.log.levels.WARN)
      return
    end
    local label = #entries == 1 and ("Yes, delete " .. entries[1].domain)
      or ("Yes, delete " .. #entries .. " certificates")
    vim.ui.select({ label, "Cancel" }, { prompt = "Delete ACM certificates?" }, function(_, idx)
      if not idx or idx ~= 1 then
        return
      end
      local del = require("aws.acm.delete")
      local removed = {}
      local function next_delete(i)
        if i > #entries then
          remove_from_state(st, removed, buf)
          return
        end
        local e = entries[i]
        del.run(e.arn, function()
          removed[e.arn] = true
          next_delete(i + 1)
        end, call_opts)
      end
      next_delete(1)
    end)
  end

  keymaps.apply_acm(buf, {
    open_detail = function()
      local e = entry_under_cursor(st)
      if not e then
        vim.notify("aws.nvim: no certificate under cursor", vim.log.levels.WARN)
        return
      end
      require("aws.acm.detail").open(e.arn, call_opts)
    end,

    delete = delete_one,
    delete_visual = delete_visual,

    filter = function()
      vim.ui.input({ prompt = "Filter certificates: ", default = st.filter }, function(input)
        if input == nil then
          return
        end
        st.filter = input
        if input == "" then
          if st.cache then
            st.certs = st.cache
            render(buf, st)
          else
            fetch(buf, st, call_opts)
          end
        else
          if st.cache then
            st.certs = st.cache
          end
          render(buf, st)
        end
      end)
    end,

    clear_filter = function()
      st.filter = ""
      if st.cache then
        st.certs = st.cache
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
    st.certs = st.cache
    render(buf, st)
  else
    fetch(buf, st, call_opts)
  end
end

return M
