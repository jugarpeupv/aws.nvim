--- aws.nvim – CloudFormation stack resources viewer
--- Renders a hierarchical tree mirroring the AWS Console "Resources" tab.
--- Uses aws:cdk:path metadata (from get-template) when available to build
--- the CDK construct tree; falls back to a flat list for non-CDK stacks.
--- Lines with a known console URL are underlined; press gx to open in browser.
local M = {}

local spawn       = require("aws.spawn")
local buf_mod     = require("aws.buffer")
local keymaps     = require("aws.keymaps")
local config      = require("aws.config")
local console_url = require("aws.cloudformation.console_url")

local FILETYPE      = "aws-cloudformation"
local HL_LINK       = "AwsResourceLink"   -- underline on logical_id when URL is available
local HL_TYPE       = "AwsResourceType"   -- highlight for AWS:: resource type tokens
local NS_ID         = vim.api.nvim_create_namespace("aws_resource_links")

-- AwsResourceLink: underline only, inherits fg so it works on any colorscheme.
vim.api.nvim_set_hl(0, HL_LINK, { underline = true, default = true })
-- AwsResourceType: a subtle distinguishing colour for the "AWS::X::Y" token.
-- Uses a bold Comment-like style by default; users can override in their config.
vim.api.nvim_set_hl(0, HL_TYPE, { link = "Type", default = true })

local function buf_name(stack_name)
  return "aws://cloudformation/resources/" .. stack_name
end

-------------------------------------------------------------------------------
-- Status icon helper
-------------------------------------------------------------------------------

local function status_icon(status)
  if not status then return "" end
  local ic = config.values.icons
  if status:find("DELETE")      then return ic.deleted      end
  if status:find("FAILED")      then return ic.failed       end
  if status:find("IN_PROGRESS") then return ic.in_progress  end
  if status:find("COMPLETE")    then return ic.complete     end
  return ic.stack
end

-------------------------------------------------------------------------------
-- Tree builder
--
-- Each resource may carry a cdk_path string like:
--   "PublicspaStorageStack/spadistribution/Distribution/Resource"
-- We strip the first segment (stack scope) and the last segment ("Resource"
-- or "Default") when it adds no information, then use the remaining segments
-- as the folder hierarchy in the tree.
--
-- Resources without cdk_path are placed at the root level.
-------------------------------------------------------------------------------

---@class ResourceEntry
---@field logical_id  string
---@field physical_id string
---@field type        string
---@field status      string
---@field cdk_path    string|nil   raw aws:cdk:path value, may be nil

--- Normalise a raw cdk_path into folder segments (everything except the leaf).
---@param raw        string|nil
---@return string[]
local function cdk_path_segments(raw)
  if not raw then return {} end

  local parts = vim.split(raw, "/", { plain = true })
  if #parts == 0 then return {} end

  -- Strip leading stack-scope segment (CDK always prefixes with the stack id).
  table.remove(parts, 1)

  -- Drop a trailing "Resource" or "Default" leaf.
  local last = parts[#parts]
  if last == "Resource" or last == "Default" then
    table.remove(parts)
  end

  -- The last remaining element becomes the leaf display name — drop it too,
  -- since we use logical_id for the leaf label.
  if #parts > 0 then
    table.remove(parts)
  end

  return parts
end

--- Build a nested tree from a flat list of ResourceEntry.
---@param resources ResourceEntry[]
---@return table[]  list of root nodes
local function build_tree(resources)
  local root = { children = {}, _idx = {} }

  local function get_or_create(parent, name)
    if not parent._idx[name] then
      local node = { name = name, children = {}, _idx = {}, resource = nil }
      table.insert(parent.children, node)
      parent._idx[name] = node
    end
    return parent._idx[name]
  end

  for _, r in ipairs(resources) do
    local folders = cdk_path_segments(r.cdk_path)
    local node = root
    for _, seg in ipairs(folders) do
      node = get_or_create(node, seg)
    end
    local leaf = get_or_create(node, r.logical_id)
    leaf.resource = r
  end

  return root.children
end

--- Render the tree into `lines`, populate `line_marks`, and fill `fold_levels`.
---
--- fold_levels maps 1-based buffer line number → foldexpr string:
---   ">N"  – folder node (has children): starts a new fold of level N
---   "N"   – leaf resource line or childless folder: belongs to fold of level N
---   "0"   – header / blank / separator (set externally; render_tree never emits 0)
---
--- Each entry in line_marks is keyed by 1-based line number and contains:
---   { url, id_s, id_e, type_s, type_e }
--- where id_s/id_e are 0-based byte col start/end for the logical_id,
--- and type_s/type_e are 0-based byte col start/end for the AWS:: type token.
--- `line_offset` is the number of lines already in the output before this call.
---@param nodes       table[]
---@param lines       string[]
---@param prefix      string
---@param line_marks  table<integer, table>
---@param fold_levels table<integer, string>
---@param line_offset integer
---@param depth       integer   0-based nesting depth of this level
---@param region      string
local function render_tree(nodes, lines, prefix, line_marks, fold_levels, line_offset, depth, region)
  for i, node in ipairs(nodes) do
    local is_last      = (i == #nodes)
    local connector    = is_last and "└─ " or "├─ "
    local child_prefix = prefix .. (is_last and "   " or "│  ")
    local fold_n       = depth + 1  -- 1-based fold level for this depth

    if node.resource then
      local r    = node.resource
      local icon = status_icon(r.status)
      local phys = r.physical_id or ""
      if #phys > 50 then phys = phys:sub(1, 47) .. "..." end

      -- Build the line piece-by-piece so we can track col offsets.
      local head   = prefix .. connector .. icon .. " "
      local id_s   = #head                        -- 0-based start of logical_id
      local id_e   = id_s + #r.logical_id          -- 0-based exclusive end

      local sep1   = "   "
      local type_s = id_e + #sep1                  -- 0-based start of type token
      local type_e = type_s + #r.type              -- 0-based exclusive end

      local line = head .. r.logical_id
        .. sep1 .. r.type
        .. "   " .. phys
        .. "   " .. (r.status or "")

      table.insert(lines, line)

      local lineno = line_offset + #lines  -- 1-based
      local url    = console_url.build(r.type, r.physical_id, region)
      line_marks[lineno] = {
        url    = url,    -- may be nil if no console link
        id_s   = id_s,
        id_e   = id_e,
        type_s = type_s,
        type_e = type_e,
        rtype  = r.type,
        phys   = r.physical_id,
      }
      -- Leaf resource: belongs to the current fold level.
      fold_levels[lineno] = tostring(fold_n)
    else
      -- Folder / construct node
      table.insert(lines, prefix .. connector .. " " .. node.name)
      local lineno = line_offset + #lines  -- 1-based
      if #node.children > 0 then
        -- Folder with children: opens a new fold so children are inside it.
        fold_levels[lineno] = ">" .. tostring(fold_n)
      else
        -- Childless folder (edge case): treated as a leaf at this level.
        fold_levels[lineno] = tostring(fold_n)
      end
    end

    if #node.children > 0 then
      render_tree(node.children, lines, child_prefix, line_marks, fold_levels, line_offset, depth + 1, region)
    end
  end
end

-------------------------------------------------------------------------------
-- Highlight helpers
-------------------------------------------------------------------------------

--- Apply extmarks for linkable lines (underline on logical_id) and
--- AWS:: type tokens (AwsResourceType highlight).
---@param buf        integer
---@param line_marks table<integer, table>
local function apply_highlights(buf, line_marks)
  vim.api.nvim_buf_clear_namespace(buf, NS_ID, 0, -1)
  for lineno, m in pairs(line_marks) do
    local row = lineno - 1  -- 0-based

    -- Highlight the AWS:: type token on every resource line.
    vim.api.nvim_buf_set_extmark(buf, NS_ID, row, m.type_s, {
      end_col  = m.type_e,
      hl_group = HL_TYPE,
      priority = 50,
    })

    -- Underline the logical_id only when a console URL exists.
    if m.url then
      vim.api.nvim_buf_set_extmark(buf, NS_ID, row, m.id_s, {
        end_col  = m.id_e,
        hl_group = HL_LINK,
        priority = 60,
      })
    end
  end
end

-------------------------------------------------------------------------------
-- Parallel fetch: list-stack-resources + get-template
-------------------------------------------------------------------------------

---@param stack_name string
---@param buf        integer
---@param call_opts  AwsCallOpts|nil
local function fetch(stack_name, buf, call_opts)
  buf_mod.set_loading(buf)

  local results = { resources = nil, cdk_paths = nil }
  local pending = 2

  local function try_render()
    pending = pending - 1
    if pending > 0 then return end
    if not results.resources then return end

    local cdk_paths = results.cdk_paths or {}
    local resources = results.resources

    for _, r in ipairs(resources) do
      r.cdk_path = cdk_paths[r.logical_id]
    end

    -- Sort by cdk_path then logical_id so siblings are adjacent.
    table.sort(resources, function(a, b)
      local pa = (a.cdk_path or "") .. "|" .. a.logical_id
      local pb = (b.cdk_path or "") .. "|" .. b.logical_id
      return pa < pb
    end)

    local has_cdk = next(cdk_paths) ~= nil
    local tree    = build_tree(resources)
    local region  = config.resolve_region(call_opts)
    local count   = #resources
    local title   = "  Resources (" .. count .. ")  >>  " .. stack_name
    if region then title = title .. "   [region: " .. region .. "]" end
    if has_cdk then title = title .. "   (CDK)" end

    local sep  = "  " .. string.rep("-", 110)
    local km   = config.values.keymaps.cloudformation
    local hint = "  " .. (km.refresh or "R") .. " refresh"
      .. (km.open_events and ("   |   " .. km.open_events .. " events") or "")
      .. "   |   <CR> open (S3 / CloudWatch)"
      .. "   |   gx open in browser"

    -- Header lines (before the tree).
    local header = { title, sep, "", hint, sep, "" }
    -- line_marks maps 1-based buffer line → { url, id_s, id_e, type_s, type_e }
    local line_marks  = {}
    -- fold_levels maps 1-based buffer line → foldexpr string
    local fold_levels = {}

    -- Header lines get fold level 0.
    for lnum = 1, #header do
      fold_levels[lnum] = "0"
    end

    local tree_lines = {}
    render_tree(tree, tree_lines, "  ", line_marks, fold_levels, #header, 0, region)

    local out = vim.list_extend(vim.list_extend({}, header), tree_lines)
    table.insert(out, "")
    table.insert(out, sep)

    -- Trailing blank + separator also get fold level 0.
    local total = #out
    fold_levels[total - 1] = "0"
    fold_levels[total]     = "0"

    buf_mod.set_lines(buf, out)
    apply_highlights(buf, line_marks)

    -- Store line_marks on the buffer for the gx handler.
    vim.b[buf].aws_resource_line_urls = (function()
      local t = {}
      for lineno, m in pairs(line_marks) do
        if m.url then t[lineno] = m.url end
      end
      return t
    end)()

    -- Store resource type + physical_id per line for the <CR> handler.
    vim.b[buf].aws_resource_line_info = (function()
      local t = {}
      for lineno, m in pairs(line_marks) do
        if m.rtype then
          t[lineno] = { rtype = m.rtype, phys = m.phys }
        end
      end
      return t
    end)()

    -- Store pre-computed fold levels for the foldexpr.
    vim.b[buf].aws_fold_levels = fold_levels

    -- Force Vim to re-evaluate the foldexpr for every line now that the table
    -- is populated.  Without this the folds are stale (or absent) on the first
    -- open because set_lines fires before the table exists.
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("normal! zx")
    end)
  end

  -- ── Request 1: list-stack-resources ────────────────────────────────────────
  spawn.run({
    "cloudformation", "list-stack-resources",
    "--stack-name", stack_name,
    "--query", table.concat({
      "StackResourceSummaries[*].{",
        "LogicalId:LogicalResourceId,",
        "PhysicalId:PhysicalResourceId,",
        "Type:ResourceType,",
        "Status:ResourceStatus}",
    }, ""),
    "--output", "json",
  }, function(ok, lines)
    if not ok then
      buf_mod.set_error(buf, lines)
      results.resources = nil
      pending = 1
      try_render()
      return
    end
    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if not ok2 or type(data) ~= "table" then
      buf_mod.set_error(buf, { "Failed to parse JSON", raw })
      results.resources = nil
      pending = 1
      try_render()
      return
    end
    local parsed = {}
    for _, item in ipairs(data) do
      table.insert(parsed, {
        logical_id  = item.LogicalId  or "",
        physical_id = item.PhysicalId or "",
        type        = item.Type       or "",
        status      = item.Status     or "",
        cdk_path    = nil,
      })
    end
    results.resources = parsed
    try_render()
  end, call_opts)

  -- ── Request 2: get-template (for aws:cdk:path metadata) ────────────────────
  spawn.run({
    "cloudformation", "get-template",
    "--stack-name", stack_name,
    "--query", "TemplateBody",
    "--output", "json",
  }, function(ok, lines)
    if not ok then
      results.cdk_paths = {}
      try_render()
      return
    end
    local raw = table.concat(lines, "\n")
    local ok2, tmpl = pcall(vim.json.decode, raw)
    if not ok2 or type(tmpl) ~= "table" then
      -- TemplateBody may arrive as a JSON-encoded string; try one more decode.
      if type(tmpl) == "string" then
        local ok3, inner = pcall(vim.json.decode, tmpl)
        if ok3 and type(inner) == "table" then
          tmpl = inner
        else
          results.cdk_paths = {}
          try_render()
          return
        end
      else
        results.cdk_paths = {}
        try_render()
        return
      end
    end

    -- tmpl might still be a string if the first decode produced a string.
    if type(tmpl) == "string" then
      local ok3, inner = pcall(vim.json.decode, tmpl)
      tmpl = (ok3 and type(inner) == "table") and inner or nil
    end

    local cdk_paths = {}
    if type(tmpl) == "table" then
      local tpl_resources = tmpl.Resources or {}
      for logical_id, res_def in pairs(tpl_resources) do
        if type(res_def) == "table" then
          local meta = res_def.Metadata
          if type(meta) == "table" then
            local path = meta["aws:cdk:path"]
            if type(path) == "string" then
              cdk_paths[logical_id] = path
            end
          end
        end
      end
    end
    results.cdk_paths = cdk_paths
    try_render()
  end, call_opts)
end

-------------------------------------------------------------------------------
-- Fold expression
-- Fold levels are pre-computed during render_tree and stored in
-- vim.b[buf].aws_fold_levels (1-based lnum → foldexpr string).
-- This function just does a lookup; it must be called with the correct buf
-- in scope (which Vim guarantees via v:lnum being evaluated in the buf's context).
-------------------------------------------------------------------------------

--- Return the fold level for the given 1-based line number in a resources buf.
---@param lnum integer
---@return string   foldexpr string ("0", "1", ">1", "2", ">2", …)
local function resources_foldexpr(lnum)
  local levels = vim.b.aws_fold_levels
  if not levels then return "0" end
  return levels[lnum] or "0"
end

-- Register the foldexpr globally once; the function is re-used across bufs.
_G._aws_nvim_resources_foldexpr = resources_foldexpr

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param stack_name string
---@param call_opts  AwsCallOpts|nil
function M.open(stack_name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(stack_name), FILETYPE)
  buf_mod.open_split(buf)

  keymaps.apply_cloudformation_resources(buf, {
    refresh = function() fetch(stack_name, buf, call_opts) end,
    open_events = function()
      require("aws.cloudformation.events").open(stack_name, call_opts)
    end,
  })

  -- gx: open the console URL for the resource on the current line.
  vim.keymap.set("n", "gx", function()
    local line_urls = vim.b[buf].aws_resource_line_urls
    if not line_urls then return end
    local lineno = vim.api.nvim_win_get_cursor(0)[1]  -- 1-based
    local url = line_urls[lineno]
    if not url then
      vim.notify("No console link for this line", vim.log.levels.INFO)
      return
    end
    -- vim.ui.open is available in Neovim ≥ 0.10; fall back to xdg-open / open.
    if vim.ui.open then
      vim.ui.open(url)
    else
      local cmd = vim.fn.has("mac") == 1 and "open" or "xdg-open"
      vim.fn.jobstart({ cmd, url }, { detach = true })
    end
  end, {
    buffer  = buf,
    noremap = true,
    silent  = true,
    desc    = "aws.nvim: open resource in AWS Console",
  })

  -- <CR>: context-sensitive open for certain resource types.
  --   AWS::S3::Bucket      → open the bucket in oil.nvim (oil-s3://)
  --   AWS::Logs::LogGroup  → open CloudWatch log streams for the group
  vim.keymap.set("n", "<CR>", function()
    local line_info = vim.b[buf].aws_resource_line_info
    if not line_info then return end
    local lineno = vim.api.nvim_win_get_cursor(0)[1]
    local info   = line_info[lineno]
    if not info then return end

    if info.rtype == "AWS::S3::Bucket" then
      local ok, oil = pcall(require, "oil")
      if not ok then
        vim.notify("aws.nvim: oil.nvim is required to browse S3 buckets", vim.log.levels.ERROR)
        return
      end
      local profile  = (call_opts and call_opts.profile) or config.values.default_aws_profile
      local region_v = (call_opts and call_opts.region)  or config.values.default_aws_region
      -- Register creds in the buckets module so BufEnter autocmd stays in sync.
      local buckets_mod = require("aws.s3.buckets")
      if buckets_mod._register_bucket_creds then
        buckets_mod._register_bucket_creds(info.phys, profile, region_v)
      end
      -- Apply immediately for the initial oil open.
      local oil_cfg = require("oil.config")
      local new_args = {}
      if profile  then table.insert(new_args, "--profile=" .. profile)  end
      if region_v then table.insert(new_args, "--region="  .. region_v) end
      oil_cfg.extra_s3_args = new_args
      local scheme = (vim.version().minor >= 11) and "oil-s3://" or "oil-sss://"
      oil.open(scheme .. info.phys .. "/")

    elseif info.rtype == "AWS::Logs::LogGroup" then
      require("aws.cloudwatch.streams").open(info.phys, call_opts)

    end
  end, {
    buffer  = buf,
    noremap = true,
    silent  = true,
    desc    = "aws.nvim: open resource (S3 bucket / CloudWatch log group)",
  })

  -- Set up indent-based folding for this buffer.
  -- Use a Lua foldexpr so we don't pollute the global foldexpr setting.
  vim.api.nvim_buf_call(buf, function()
    vim.opt_local.foldmethod  = "expr"
    vim.opt_local.foldexpr    = "v:lua._aws_nvim_resources_foldexpr(v:lnum)"
    vim.opt_local.foldlevel   = 99   -- start fully open
    vim.opt_local.foldminlines = 0
  end)

  fetch(stack_name, buf, call_opts)
end

return M
