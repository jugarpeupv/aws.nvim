--- aws.nvim – IAM Role detail view
--- Parallel fetches: get-role, list-attached-role-policies, list-role-policies (inline),
---                   generate-service-last-accessed-details (polled)
local M = {}

local spawn = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config = require("aws.config")

local FILETYPE = "aws-iam"

local _state = {}

local function buf_name(name)
  return "aws://iam/detail/role/" .. name
end

local function kv(key, value)
  return string.format("  %-28s  %s", key, tostring(value or "—"))
end

local function section(title)
  return { "", title, string.rep("-", #title) }
end

--- Encode a Lua table as indented JSON lines (no external deps).
--- Returns a list of strings, each being one rendered line.
local function json_lines(val, indent)
  indent = indent or 0
  local pad = string.rep("  ", indent)
  local t = type(val)

  if t == "nil" then
    return { pad .. "null" }
  elseif t == "boolean" then
    return { pad .. tostring(val) }
  elseif t == "number" then
    return { pad .. tostring(val) }
  elseif t == "string" then
    -- escape quotes inside the string value
    return { pad .. '"' .. val:gsub('"', '\\"') .. '"' }
  elseif t == "table" then
    -- detect array vs object
    local is_array = #val > 0 or next(val) == nil
    -- check if all numeric keys 1..#val
    if is_array then
      for k, _ in pairs(val) do
        if type(k) ~= "number" then
          is_array = false
          break
        end
      end
    end

    if is_array then
      if #val == 0 then
        return { pad .. "[]" }
      end
      local out = { pad .. "[" }
      for i, v in ipairs(val) do
        local child = json_lines(v, indent + 1)
        if i < #val then
          child[#child] = child[#child] .. ","
        end
        for _, l in ipairs(child) do
          table.insert(out, l)
        end
      end
      table.insert(out, pad .. "]")
      return out
    else
      local keys = {}
      for k in pairs(val) do
        table.insert(keys, k)
      end
      table.sort(keys)
      if #keys == 0 then
        return { pad .. "{}" }
      end
      local out = { pad .. "{" }
      for i, k in ipairs(keys) do
        local inner = json_lines(val[k], indent + 1)
        -- prepend key onto first line
        inner[1] = string.rep("  ", indent + 1) .. '"' .. tostring(k) .. '": ' .. inner[1]:gsub("^%s+", "")
        if i < #keys then
          inner[#inner] = inner[#inner] .. ","
        end
        for _, l in ipairs(inner) do
          table.insert(out, l)
        end
      end
      table.insert(out, pad .. "}")
      return out
    end
  end
  return { pad .. tostring(val) }
end

local function render(buf, name)
  local st = _state[name]
  if not st then
    return
  end

  local km = config.values.keymaps.iam
  local hint = (km.detail_refresh or "R") .. " refresh"
  local sep = string.rep("-", 72)
  local lines = { "", "IAM  Role: " .. name, "", sep, hint, sep }

  -- General
  for _, l in ipairs(section("General")) do
    table.insert(lines, l)
  end
  if st.role then
    local r = st.role
    table.insert(lines, kv("RoleName", r.RoleName))
    table.insert(lines, kv("RoleId", r.RoleId))
    table.insert(lines, kv("ARN", r.Arn))
    table.insert(lines, kv("Path", r.Path))
    table.insert(lines, kv("Created", r.CreateDate))
    table.insert(lines, kv("Description", r.Description))
    table.insert(lines, kv("MaxSessionDuration", tostring(r.MaxSessionDuration or "—") .. "s"))
  else
    table.insert(lines, st.role == false and "  (error)" or "  [loading…]")
  end

  -- Trust Policy — full JSON
  for _, l in ipairs(section("Trust Policy (AssumeRole)")) do
    table.insert(lines, l)
  end
  if st.role then
    local doc = st.role.AssumeRolePolicyDocument
    if type(doc) == "table" then
      for _, l in ipairs(json_lines(doc, 1)) do
        table.insert(lines, l)
      end
    elseif type(doc) == "string" then
      for _, l in vim.split(doc, "\n", { plain = true }) do
        table.insert(lines, "  " .. l)
      end
    else
      table.insert(lines, "  (empty)")
    end
  elseif st.role == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  -- Tags
  for _, l in ipairs(section("Tags")) do
    table.insert(lines, l)
  end
  if st.role then
    local tags = st.role.Tags
    if type(tags) == "table" and #tags > 0 then
      for _, tag in ipairs(tags) do
        table.insert(lines, kv(tag.Key or "", tag.Value or ""))
      end
    else
      table.insert(lines, "  (none)")
    end
  elseif st.role == false then
    table.insert(lines, "  (error)")
  else
    table.insert(lines, "  [loading…]")
  end

  -- Attached Policies
  for _, l in ipairs(section("Attached Policies")) do
    table.insert(lines, l)
  end
  if st.attached then
    if #st.attached == 0 then
      table.insert(lines, "  (none)")
    else
      for _, p in ipairs(st.attached) do
        table.insert(lines, "  " .. (p.PolicyName or "") .. "   " .. (p.PolicyArn or ""))
      end
    end
  else
    table.insert(lines, st.attached == false and "  (error)" or "  [loading…]")
  end

  -- Inline Policies
  for _, l in ipairs(section("Inline Policies")) do
    table.insert(lines, l)
  end
  if st.inline then
    if #st.inline == 0 then
      table.insert(lines, "  (none)")
    else
      for _, n in ipairs(st.inline) do
        table.insert(lines, "  " .. n)
      end
    end
  else
    table.insert(lines, st.inline == false and "  (error)" or "  [loading…]")
  end

  -- Last Accessed
  for _, l in ipairs(section("Last Accessed")) do
    table.insert(lines, l)
  end
  if st.last_accessed == nil then
    table.insert(lines, "  [loading…]")
  elseif st.last_accessed == false then
    table.insert(lines, "  (error or not available)")
  elseif #st.last_accessed == 0 then
    table.insert(lines, "  (no data)")
  else
    -- header
    table.insert(lines, string.format("  %-50s  %-26s  %s", "Service", "Last Authenticated", "Region"))
    table.insert(lines, string.rep("-", 90))
    for _, svc in ipairs(st.last_accessed) do
      local sname = svc.ServiceName or svc.ServiceNamespace or "?"
      local last = svc.LastAuthenticated or "never"
      local region = svc.LastAuthenticatedRegion or "—"
      table.insert(lines, string.format("  %-50s  %-26s  %s", sname, last, region))
    end
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

--- Poll get-service-last-accessed-details until COMPLETED (max_tries × 1.5 s each).
local function poll_last_accessed(job_id, name, buf, call_opts, tries)
  tries = tries or 0
  if tries > 20 then
    _state[name].last_accessed = false
    render(buf, name)
    return
  end

  spawn.run(
    { "iam", "get-service-last-accessed-details", "--job-id", job_id, "--output", "json" },
    function(ok, lines_out)
      if not ok then
        _state[name].last_accessed = false
        render(buf, name)
        return
      end
      local ok2, data = pcall(vim.json.decode, table.concat(lines_out, "\n"))
      if not ok2 or type(data) ~= "table" then
        _state[name].last_accessed = false
        render(buf, name)
        return
      end

      if data.JobStatus == "COMPLETED" then
        _state[name].last_accessed = data.ServicesLastAccessed or {}
        render(buf, name)
      elseif data.JobStatus == "FAILED" then
        _state[name].last_accessed = false
        render(buf, name)
      else
        -- IN_PROGRESS – try again in 1.5 s
        vim.defer_fn(function()
          poll_last_accessed(job_id, name, buf, call_opts, tries + 1)
        end, 1500)
      end
    end,
    call_opts
  )
end

local function fetch(name, buf, call_opts)
  buf_mod.set_loading(buf)
  local st = { role = nil, attached = nil, inline = nil, last_accessed = nil }
  _state[name] = st
  local pending = 3

  local function on_done()
    pending = pending - 1
    if pending > 0 then
      return
    end
    render(buf, name)
  end

  spawn.run({ "iam", "get-role", "--role-name", name, "--output", "json" }, function(ok, lines_out)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(lines_out, "\n"))
      if ok2 and type(data) == "table" and type(data.Role) == "table" then
        local r = data.Role
        -- AssumeRolePolicyDocument may come back as a URL-encoded JSON string
        local doc = r.AssumeRolePolicyDocument
        if type(doc) == "string" then
          local decoded_str = vim.uri_decode and vim.uri_decode(doc) or doc
          local ok3, decoded = pcall(vim.json.decode, decoded_str)
          if ok3 then
            r.AssumeRolePolicyDocument = decoded
          end
        end
        st.role = r

        -- Kick off last-accessed job now that we have the ARN
        local arn = r.Arn
        if arn then
          spawn.run(
            { "iam", "generate-service-last-accessed-details", "--arn", arn, "--output", "json" },
            function(ok3, la_lines)
              if ok3 then
                local ok4, la_data = pcall(vim.json.decode, table.concat(la_lines, "\n"))
                if ok4 and type(la_data) == "table" and la_data.JobId then
                  poll_last_accessed(la_data.JobId, name, buf, call_opts)
                  return
                end
              end
              _state[name].last_accessed = false
              render(buf, name)
            end,
            call_opts
          )
        else
          st.last_accessed = false
        end
      else
        st.role = false
        st.last_accessed = false
      end
    else
      st.role = false
      st.last_accessed = false
    end
    on_done()
  end, call_opts)

  spawn.run({ "iam", "list-attached-role-policies", "--role-name", name, "--output", "json" }, function(ok, lines_out)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(lines_out, "\n"))
      st.attached = (ok2 and type(data) == "table" and type(data.AttachedPolicies) == "table" and data.AttachedPolicies)
        or {}
    else
      st.attached = false
    end
    on_done()
  end, call_opts)

  spawn.run({ "iam", "list-role-policies", "--role-name", name, "--output", "json" }, function(ok, lines_out)
    if ok then
      local ok2, data = pcall(vim.json.decode, table.concat(lines_out, "\n"))
      st.inline = (ok2 and type(data) == "table" and type(data.PolicyNames) == "table" and data.PolicyNames) or {}
    else
      st.inline = false
    end
    on_done()
  end, call_opts)
end

---@param name       string
---@param call_opts  AwsCallOpts|nil
function M.open(name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(name), FILETYPE)
  buf_mod.open_vsplit(buf)
  keymaps.apply_iam_detail(buf, {
    refresh = function()
      fetch(name, buf, call_opts)
    end,
  })
  fetch(name, buf, call_opts)
end

return M
