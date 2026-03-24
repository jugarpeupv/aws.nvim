--- aws.nvim – ECS cluster detail view (vsplit)
--- Shows cluster metadata + all services (with task counts, launch type, status).
--- Fires two parallel calls: describe-clusters + list/describe-services.
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-ecs"

local function buf_name(cluster_arn)
  -- Use just the short name for a readable buffer name
  local short = cluster_arn:match("/([^/]+)$") or cluster_arn
  return "aws://ecs/detail/" .. short
end

---@class EcsDetailState
---@field cluster  table|nil       describe-clusters result item
---@field services table[]|nil     describe-services result items (all pages)
---@field region   string
---@field profile  string|nil

local _state = {}  -- cluster_arn -> EcsDetailState

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

--- Extract the short name from an ARN.
---@param arn string
---@return string
local function short_name(arn)
  return arn:match("/([^/]+)$") or arn
end

---@param buf        integer
---@param cluster_arn string
local function render(buf, cluster_arn)
  local st = _state[cluster_arn]
  if not st then return end

  local cluster = st.cluster or {}
  local region  = st.region
  local profile = st.profile
  local km      = config.values.keymaps.ecs

  local lines = {}
  local LABEL = 32

  local function row(label, value)
    table.insert(lines, "  " .. pad_right(label, LABEL) .. (value or "—"))
  end

  local cname = short_name(cluster_arn)

  -- ── Title ──────────────────────────────────────────────────────────────────
  table.insert(lines, "")
  local title = "ECS  >>  " .. cname
    .. "   [region: " .. region .. "]"
    .. (profile and ("   [profile: " .. profile .. "]") or "")
  table.insert(lines, title)
  table.insert(lines, "")

  local sep_len = math.max(vim.fn.strdisplaywidth(title), 72)
  local sep     = string.rep("-", sep_len)
  table.insert(lines, sep)

  -- ── Hint line ──────────────────────────────────────────────────────────────
  local hints = {}
  if km.detail_refresh then table.insert(hints, km.detail_refresh .. " refresh") end
  if #hints > 0 then
    table.insert(lines, table.concat(hints, "  |  "))
    table.insert(lines, sep)
  end

  -- ── Cluster General ────────────────────────────────────────────────────────
  table.insert(lines, "Cluster")
  table.insert(lines, sep)
  row("Name",                    cluster.clusterName or cname)
  row("ARN",                     cluster.clusterArn  or cluster_arn)
  row("Status",                  cluster.status)
  row("Registered Instances",    tostring(cluster.registeredContainerInstancesCount or 0))
  row("Running Tasks",           tostring(cluster.runningTasksCount  or 0))
  row("Pending Tasks",           tostring(cluster.pendingTasksCount  or 0))
  row("Active Services",         tostring(cluster.activeServicesCount or 0))

  -- Capacity providers
  local caps = type(cluster.capacityProviders) == "table" and cluster.capacityProviders or {}
  row("Capacity Providers",
    #caps > 0 and table.concat(caps, ", ") or "—")

  -- Default capacity provider strategy
  local strats = type(cluster.defaultCapacityProviderStrategy) == "table"
    and cluster.defaultCapacityProviderStrategy or {}
  if #strats > 0 then
    local parts = {}
    for _, s in ipairs(strats) do
      local p = (s.capacityProvider or "?")
      if s.weight then p = p .. " w=" .. s.weight end
      if s.base   then p = p .. " base=" .. s.base end
      table.insert(parts, p)
    end
    row("Default Cap. Strategy", table.concat(parts, ", "))
  end

  -- Tags
  local tags = type(cluster.tags) == "table" and cluster.tags or {}
  local tag_parts = {}
  for _, t in ipairs(tags) do
    if t.key then table.insert(tag_parts, t.key .. "=" .. (t.value or "")) end
  end
  table.sort(tag_parts)
  row("Tags", #tag_parts > 0 and table.concat(tag_parts, ", ") or "—")

  -- Statistics (from --include STATISTICS)
  local stats = type(cluster.statistics) == "table" and cluster.statistics or {}
  if #stats > 0 then
    table.insert(lines, "")
    table.insert(lines, "Statistics")
    table.insert(lines, sep)
    for _, s in ipairs(stats) do
      row("  " .. (s.name or "?"), s.value or "—")
    end
  end

  -- ── Services ───────────────────────────────────────────────────────────────
  if st.services then
    -- Sort services by name
    local sorted = vim.deepcopy(st.services)
    table.sort(sorted, function(a, b)
      return (a.serviceName or "") < (b.serviceName or "")
    end)

    table.insert(lines, "")
    table.insert(lines, "Services (" .. #sorted .. ")")
    table.insert(lines, sep)

    if #sorted == 0 then
      table.insert(lines, "  (none)")
    else
      -- Column widths for the services table
      local nm_w  = 4   -- "Name"
      local st_w  = 6   -- "Status"
      local lt_w  = 8   -- "Launch"
      for _, svc in ipairs(sorted) do
        local nw = vim.fn.strdisplaywidth(svc.serviceName or "")
        if nw > nm_w then nm_w = nw end
      end
      nm_w = nm_w + 2
      st_w = st_w + 2
      lt_w = lt_w + 2

      -- Header
      table.insert(lines,
        "  " .. pad_right("Name",   nm_w)
             .. pad_right("Status", st_w)
             .. pad_right("Launch", lt_w)
             .. pad_right("Des",    6)
             .. pad_right("Run",    6)
             .. pad_right("Pend",   6)
             .. "Task Definition"
      )
      table.insert(lines, "  " .. string.rep("-", nm_w + st_w + lt_w + 30))

      for _, svc in ipairs(sorted) do
        local sname  = svc.serviceName or "—"
        local sstatus = svc.status      or "—"
        local launch  = svc.launchType  or
          (type(svc.capacityProviderStrategy) == "table"
            and #svc.capacityProviderStrategy > 0
            and "CAP_PROV" or "—")
        local desired = tostring(svc.desiredCount  or 0)
        local running = tostring(svc.runningCount  or 0)
        local pending = tostring(svc.pendingCount  or 0)
        local taskdef = short_name(svc.taskDefinition or "—")

        table.insert(lines,
          "  " .. pad_right(sname,   nm_w)
               .. pad_right(sstatus, st_w)
               .. pad_right(launch,  lt_w)
               .. pad_right(desired, 6)
               .. pad_right(running, 6)
               .. pad_right(pending, 6)
               .. taskdef
        )

        -- Show deployment info if there are active deployments
        local deps = type(svc.deployments) == "table" and svc.deployments or {}
        for _, dep in ipairs(deps) do
          if dep.status ~= "PRIMARY" then
            table.insert(lines,
              "    deployment " .. (dep.status or "?")
              .. "  des=" .. tostring(dep.desiredCount or 0)
              .. "  run=" .. tostring(dep.runningCount or 0)
              .. "  pend=" .. tostring(dep.pendingCount or 0)
            )
          end
        end

        -- Events (last 3, most recent first)
        local events = type(svc.events) == "table" and svc.events or {}
        local show = math.min(3, #events)
        for i = 1, show do
          local ev = events[i]
          if ev and ev.message then
            -- Dates from ECS are ISO strings; just show the time portion
            local time = (ev.createdAt or ""):match("T(%d%d:%d%d:%d%d)") or ""
            table.insert(lines, "    [" .. time .. "] " .. ev.message)
          end
        end
      end
    end
  else
    table.insert(lines, "")
    table.insert(lines, "Services")
    table.insert(lines, sep)
    table.insert(lines, "  [loading…]")
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

-------------------------------------------------------------------------------
-- Fetch
-------------------------------------------------------------------------------

--- Describe all services for a cluster by paginating list-services then
--- calling describe-services in batches of 10 (API maximum).
---@param cluster_arn string
---@param buf         integer
---@param call_opts   AwsCallOpts|nil
---@param on_done     fun(services: table[])
local function fetch_services(cluster_arn, buf, call_opts, on_done)
  local all_arns    = {}
  local all_svcs    = {}
  local batch_total = 0
  local batch_done  = 0

  local function describe_batch(arns)
    local args = { "ecs", "describe-services", "--cluster", cluster_arn, "--services" }
    vim.list_extend(args, arns)
    vim.list_extend(args, { "--output", "json" })
    spawn.run(args, function(ok, lines)
      batch_done = batch_done + 1
      if ok then
        local raw = table.concat(lines, "\n")
        local ok2, data = pcall(vim.json.decode, raw)
        if ok2 and type(data) == "table" and type(data.services) == "table" then
          for _, svc in ipairs(data.services) do
            table.insert(all_svcs, svc)
          end
        end
      end
      if batch_done >= batch_total then
        on_done(all_svcs)
      end
    end, call_opts)
  end

  local function dispatch_batches()
    if #all_arns == 0 then
      on_done({})
      return
    end
    -- Split into batches of 10
    local batches = {}
    local batch   = {}
    for _, arn in ipairs(all_arns) do
      table.insert(batch, arn)
      if #batch == 10 then
        table.insert(batches, batch)
        batch = {}
      end
    end
    if #batch > 0 then table.insert(batches, batch) end
    batch_total = #batches
    for _, b in ipairs(batches) do
      describe_batch(b)
    end
  end

  local function list_page(next_token)
    local args = {
      "ecs", "list-services",
      "--cluster", cluster_arn,
      "--output", "json",
    }
    if next_token then
      vim.list_extend(args, { "--next-token", next_token })
    end
    spawn.run(args, function(ok, lines)
      if not ok then
        on_done({})
        return
      end
      local raw = table.concat(lines, "\n")
      local ok2, data = pcall(vim.json.decode, raw)
      if not ok2 or type(data) ~= "table" then
        on_done({})
        return
      end
      local arns = type(data.serviceArns) == "table" and data.serviceArns or {}
      for _, arn in ipairs(arns) do
        table.insert(all_arns, arn)
      end
      local token = type(data.nextToken) == "string" and data.nextToken or nil
      if token then
        list_page(token)
      else
        dispatch_batches()
      end
    end, call_opts)
  end

  list_page(nil)
end

---@param cluster_arn string
---@param buf         integer
---@param call_opts   AwsCallOpts|nil
local function fetch(cluster_arn, buf, call_opts)
  buf_mod.set_loading(buf)

  local partial  = { cluster = nil, services = nil }
  local pending  = 2   -- cluster + services

  local function on_done()
    pending = pending - 1
    if pending > 0 then return end
    local existing = _state[cluster_arn] or {}
    _state[cluster_arn] = {
      cluster  = partial.cluster  or existing.cluster  or {},
      services = partial.services or existing.services or {},
      region   = config.resolve_region(call_opts),
      profile  = config.resolve_profile(call_opts),
    }
    render(buf, cluster_arn)
  end

  -- ── describe-clusters ──────────────────────────────────────────────────────
  spawn.run({
    "ecs", "describe-clusters",
    "--clusters", cluster_arn,
    "--include", "STATISTICS", "TAGS",
    "--output", "json",
  }, function(ok, lines)
    if not ok then
      partial.cluster = { clusterArn = cluster_arn }
      on_done()
      return
    end
    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if ok2 and type(data) == "table"
       and type(data.clusters) == "table"
       and data.clusters[1] then
      partial.cluster = data.clusters[1]
    else
      partial.cluster = { clusterArn = cluster_arn }
    end
    on_done()
  end, call_opts)

  -- ── list + describe services ───────────────────────────────────────────────
  fetch_services(cluster_arn, buf, call_opts, function(services)
    partial.services = services
    on_done()
  end)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param cluster_arn string
---@param call_opts   AwsCallOpts|nil
function M.open(cluster_arn, call_opts)
  local buf = buf_mod.get_or_create(buf_name(cluster_arn), FILETYPE)
  buf_mod.open_vsplit(buf)

  keymaps.apply_ecs_detail(buf, {
    refresh = function()
      fetch(cluster_arn, buf, call_opts)
    end,
  })

  fetch(cluster_arn, buf, call_opts)
end

return M
