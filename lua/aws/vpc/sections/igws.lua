--- aws.nvim – VPC Internet Gateways section buffer
--- Lists IGWs attached to a VPC. No detail drill-down (IGWs have minimal info).
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-vpc"

local _state = {}

local function buf_name(vpc_id)
  return "aws://vpc/sections/igws/" .. vpc_id
end

local function tag_name(tags, fallback)
  if type(tags) == "table" then
    for _, t in ipairs(tags) do
      if t.Key == "Name" then
        return t.Value or fallback
      end
    end
  end
  return fallback
end

local function render(buf, vpc_id)
  local st = _state[vpc_id]
  if not st then
    return
  end

  local km = config.values.keymaps.vpc
  local hint = (km.detail_refresh or "R") .. " refresh"
  local sep = string.rep("-", 72)

  local title = "VPC  Internet Gateways:  " .. vpc_id .. (st.fetching and "   [loading…]" or "")

  local lines = { "", title, "", sep, hint, sep }

  local items = st.items or {}
  if #items == 0 and not st.fetching then
    table.insert(lines, "  (none)")
  else
    local w_id = 6
    local w_name = 4
    for _, igw in ipairs(items) do
      w_id = math.max(w_id, tonumber(vim.fn.strdisplaywidth(igw.id)) or 0)
      w_name = math.max(w_name, tonumber(vim.fn.strdisplaywidth(igw.name)) or 0)
    end
    w_id = math.min(w_id, 40)
    w_name = math.min(w_name, 60)

    local fmt = string.format("  %%-%ds  %%-%ds  %%s", w_id, w_name)
    table.insert(lines, string.format(fmt, "IGW ID", "Name", "State"))
    table.insert(lines, "  " .. string.rep("-", w_id + w_name + 20))

    for _, igw in ipairs(items) do
      table.insert(lines, string.format(fmt, igw.id, igw.name ~= igw.id and igw.name or "—", igw.state))
    end
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

local function fetch(vpc_id, buf, call_opts)
  local st = _state[vpc_id]
  st.fetching = true
  st.fetch_gen = (st.fetch_gen or 0) + 1
  local my_gen = st.fetch_gen
  buf_mod.set_loading(buf)

  spawn.run(
    { "ec2", "describe-internet-gateways", "--filters", "Name=attachment.vpc-id,Values=" .. vpc_id, "--output", "json" },
    function(ok, out)
      if my_gen ~= st.fetch_gen then
        return
      end
      st.fetching = false
      if not ok then
        buf_mod.set_error(buf, out)
        return
      end
      local ok2, data = pcall(vim.json.decode, table.concat(out, "\n"))
      if not ok2 or type(data) ~= "table" or type(data.InternetGateways) ~= "table" then
        buf_mod.set_error(buf, { "Failed to parse describe-internet-gateways output" })
        return
      end
      local result = {}
      for _, igw in ipairs(data.InternetGateways) do
        local state = "detached"
        if type(igw.Attachments) == "table" then
          for _, att in ipairs(igw.Attachments) do
            if att.VpcId == vpc_id then
              state = att.State or "attached"
              break
            end
          end
        end
        table.insert(result, {
          id = igw.InternetGatewayId or "?",
          name = tag_name(igw.Tags, igw.InternetGatewayId or "?"),
          state = state,
          tags = igw.Tags or {},
        })
      end
      st.items = result
      st.cache = result
      render(buf, vpc_id)
    end,
    call_opts
  )
end

---@param vpc_id    string
---@param call_opts AwsCallOpts|nil
function M.open(vpc_id, call_opts)
  local buf = buf_mod.get_or_create(buf_name(vpc_id), FILETYPE)
  buf_mod.open_vsplit(buf)

  if not _state[vpc_id] then
    _state[vpc_id] = { items = {}, cache = nil, fetching = false, fetch_gen = 0 }
  end
  local st = _state[vpc_id]

  keymaps.apply_vpc_section(buf, {
    refresh = function()
      st.cache = nil
      fetch(vpc_id, buf, call_opts)
    end,
  })

  if st.cache then
    st.items = st.cache
    render(buf, vpc_id)
  else
    fetch(vpc_id, buf, call_opts)
  end
end

return M
