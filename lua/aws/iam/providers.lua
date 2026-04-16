--- aws.nvim – IAM Identity Providers list (OIDC + SAML)
--- IAM has no pagination for providers; both list calls return the full list.
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-iam"

local _state = {}

local function buf_name(identity)
  return "aws://iam/providers/" .. identity
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
  if km.refresh then
    table.insert(parts, km.refresh .. " refresh")
  end
  return table.concat(parts, "  |  ")
end

--- Merge OIDC and SAML providers into a unified list.
--- Each entry: { arn, type }
local function merge(oidc, saml)
  local out = {}
  for _, v in ipairs(oidc) do
    table.insert(out, { arn = v.Arn or v, kind = "OIDC" })
  end
  for _, v in ipairs(saml) do
    table.insert(out, {
      arn = v.Arn,
      kind = "SAML",
      name = v.SAMLMetadataDocument and v.Arn:match("/([^/]+)$") or v.Arn:match("/([^/]+)$"),
    })
  end
  return out
end

local function render(buf, st)
  local arn_w = 3 -- "ARN"
  local kind_w = 4 -- "OIDC"/"SAML"

  for _, item in ipairs(st.items) do
    local a = item.arn or ""
    if st.filter == "" or a:lower():find(st.filter:lower(), 1, true) then
      local aw = vim.fn.strdisplaywidth(a)
      if aw > arn_w then
        arn_w = aw
      end
    end
  end
  arn_w = arn_w + 2
  kind_w = kind_w + 2

  local title = "IAM  Identity Providers"
    .. "   [region: "
    .. st.region
    .. "]"
    .. (st.profile and ("   [profile: " .. st.profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")
    .. (st.filter ~= "" and ("   [filter: " .. st.filter .. "]") or "")

  local sep = string.rep("-", kind_w + arn_w + 4)
  local lines = { "", title, "", sep, hint_line(), sep, pad_right("Type", kind_w) .. "  ARN", sep }

  st.line_map = {}

  for _, item in ipairs(st.items) do
    local arn = item.arn or ""
    local kind = item.kind or "?"

    if st.filter == "" or arn:lower():find(st.filter:lower(), 1, true) then
      table.insert(lines, pad_right(kind, kind_w) .. "  " .. arn)
      st.line_map[#lines] = arn .. "|" .. kind
    end
  end

  if not next(st.line_map) then
    table.insert(lines, "(no providers match)")
  end
  buf_mod.set_lines(buf, lines)
end

local function fetch(buf, st, call_opts)
  buf_mod.set_loading(buf)
  st.fetching = true
  st.fetch_gen = st.fetch_gen + 1
  local my_gen = st.fetch_gen

  local oidc_list = nil
  local saml_list = nil
  local pending = 2

  local function on_done()
    pending = pending - 1
    if pending > 0 then
      return
    end
    if my_gen ~= st.fetch_gen then
      return
    end
    st.fetching = false
    st.items = merge(oidc_list or {}, saml_list or {})
    st.cache = st.items
    render(buf, st)
  end

  spawn.run({ "iam", "list-open-id-connect-providers", "--output", "json" }, function(ok, lines)
    if my_gen ~= st.fetch_gen then
      return
    end
    if ok then
      local raw = table.concat(lines, "\n")
      local ok2, data = pcall(vim.json.decode, raw)
      if ok2 and type(data) == "table" then
        oidc_list = type(data.OpenIDConnectProviderList) == "table" and data.OpenIDConnectProviderList or {}
      end
    end
    on_done()
  end, call_opts)

  spawn.run({ "iam", "list-saml-providers", "--output", "json" }, function(ok, lines)
    if my_gen ~= st.fetch_gen then
      return
    end
    if ok then
      local raw = table.concat(lines, "\n")
      local ok2, data = pcall(vim.json.decode, raw)
      if ok2 and type(data) == "table" then
        saml_list = type(data.SAMLProviderList) == "table" and data.SAMLProviderList or {}
      end
    end
    on_done()
  end, call_opts)
end

local function key_under_cursor(st)
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
      line_map = {},
      cache = nil,
      fetching = false,
      fetch_gen = 0,
      region = config.resolve_region(call_opts),
      profile = config.resolve_profile(call_opts),
    }
  end
  local st = _state[identity]

  keymaps.apply_iam_list(buf, {
    open_detail = function()
      local key = key_under_cursor(st)
      if not key then
        vim.notify("aws.nvim: no provider under cursor", vim.log.levels.WARN)
        return
      end
      local arn, kind = key:match("^(.+)|(.+)$")
      require("aws.iam.detail.provider").open(arn, kind, call_opts)
    end,
    filter = function()
      vim.ui.input({ prompt = "Filter providers: ", default = st.filter }, function(input)
        if input == nil then
          return
        end
        st.filter = input
        if st.cache then
          st.items = st.cache
        end
        render(buf, st)
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
