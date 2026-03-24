--- aws.nvim – buffer-local keymap applier
--- Reads key bindings from config so users can override them.
local M = {}

--- Set a single buffer-local normal-mode mapping.
--- Pass `key = false` to skip (user disabled the binding).
---@param buf  integer
---@param key  string|false
---@param fn   function
---@param desc string
local function map(buf, key, fn, desc)
  if not key or key == false then return end
  vim.keymap.set("n", key, fn, {
    buffer  = buf,
    noremap = true,
    silent  = true,
    desc    = "aws.nvim: " .. desc,
  })
end

--- Set a single buffer-local visual-mode mapping.
--- The callback receives (r1, r2) — the inclusive 1-based line range of the
--- visual selection — so it does not need to read '< / '> marks itself.
--- Passing the range at mapping time (before mode switches) avoids the classic
--- issue where a two-key sequence like "dd" causes Vim to leave visual mode
--- after the first key, making the second key fire the normal-mode mapping.
---@param buf  integer
---@param key  string|false
---@param fn   fun(r1: integer, r2: integer)
---@param desc string
local function vmap(buf, key, fn, desc)
  if not key or key == false then return end
  vim.keymap.set("v", key, function()
    -- getpos("v") returns the *start* of the visual selection in all visual modes.
    -- The current cursor position is the *end*.
    local vpos   = vim.fn.getpos("v")   -- {bufnum, line, col, off}
    local curpos = vim.fn.getpos(".")
    local r1 = math.min(vpos[2],   curpos[2])
    local r2 = math.max(vpos[2],   curpos[2])
    -- Exit visual mode first so ui.select / vim.notify work cleanly.
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false
    )
    fn(r1, r2)
  end, {
    buffer  = buf,
    noremap = true,
    silent  = true,
    desc    = "aws.nvim: " .. desc,
  })
end

--- Apply CloudFormation stacks-buffer keymaps.
--- `actions` is a table of named callbacks; keys come from config.
---@param buf     integer
---@param actions table<string, function>
function M.apply_cloudformation(buf, actions)
  local km = require("aws.config").values.keymaps.cloudformation

  map(buf, km.open_resources, actions.open_resources, "open stack resources")
  map(buf, km.open_events,    actions.open_events,    "open stack events")
  map(buf, km.delete,         actions.delete,          "delete stack")
  map(buf, km.filter,         actions.filter,          "filter stacks")
  map(buf, km.clear_filter,   actions.clear_filter,    "clear filter")
  map(buf, km.refresh,        actions.refresh,         "refresh stacks")
  -- Visual-mode delete
  vmap(buf, km.delete, actions.delete_visual, "delete selected stacks")
end

--- Apply CloudFormation resources-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_cloudformation_resources(buf, actions)
  local km = require("aws.config").values.keymaps.cloudformation

  map(buf, km.refresh,     actions.refresh,     "refresh resources")
  map(buf, km.open_events, actions.open_events,  "open stack events")
end

--- Apply CloudFormation events-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_cloudformation_events(buf, actions)
  local km = require("aws.config").values.keymaps.cloudformation

  map(buf, km.refresh, actions.refresh, "refresh events")
end

--- Apply S3 buckets-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_s3(buf, actions)
  local km = require("aws.config").values.keymaps.s3

  map(buf, km.open_bucket,  actions.open_bucket,  "open bucket in oil.nvim")
  map(buf, km.empty,        actions.empty,        "empty bucket")
  map(buf, km.delete,       actions.delete,        "delete bucket")
  map(buf, km.filter,       actions.filter,        "filter buckets")
  map(buf, km.clear_filter, actions.clear_filter,  "clear filter")
  map(buf, km.refresh,      actions.refresh,       "refresh buckets")
  -- Visual-mode delete
  vmap(buf, km.delete, actions.delete_visual, "delete selected buckets")
end

--- Apply CloudWatch log groups-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_cloudwatch(buf, actions)
  local km = require("aws.config").values.keymaps.cloudwatch

  map(buf, km.open_streams, actions.open_streams, "open log streams")
  map(buf, km.delete,       actions.delete,        "delete log group")
  map(buf, km.filter,       actions.filter,        "filter log groups")
  map(buf, km.clear_filter, actions.clear_filter,  "clear filter")
  map(buf, km.refresh,      actions.refresh,       "refresh log groups")
  -- Visual-mode delete
  vmap(buf, km.delete, actions.delete_visual, "delete selected log groups")
end

--- Apply CloudWatch log streams-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_cloudwatch_streams(buf, actions)
  local km = require("aws.config").values.keymaps.cloudwatch

  map(buf, km.open_logs, actions.open_logs, "open log events")
  map(buf, km.refresh,   actions.refresh,   "refresh streams")
end

--- Apply CloudWatch log events-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_cloudwatch_logs(buf, actions)
  local km = require("aws.config").values.keymaps.cloudwatch

  map(buf, km.refresh, actions.refresh, "refresh log events")
end

--- Apply Lambda functions-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_lambda(buf, actions)
  local km = require("aws.config").values.keymaps.lambda

  map(buf, km.open_detail,  actions.open_detail,  "open lambda function detail")
  map(buf, km.open_logs,    actions.open_logs,     "open CloudWatch logs for function")
  map(buf, km.delete,       actions.delete,        "delete lambda function")
  map(buf, km.filter,       actions.filter,        "filter functions")
  map(buf, km.clear_filter, actions.clear_filter,  "clear filter")
  map(buf, km.refresh,      actions.refresh,       "refresh functions")
  -- Visual-mode delete
  vmap(buf, km.delete, actions.delete_visual, "delete selected lambda functions")
end

--- Apply Lambda detail-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_lambda_detail(buf, actions)
  local km = require("aws.config").values.keymaps.lambda

  map(buf, km.detail_logs, actions.open_logs, "open CloudWatch logs for function")
  map(buf, km.refresh,     actions.refresh,   "refresh detail")
end

--- Apply ACM certificates-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_acm(buf, actions)
  local km = require("aws.config").values.keymaps.acm

  map(buf, km.open_detail,  actions.open_detail,  "open certificate detail")
  map(buf, km.delete,       actions.delete,        "delete certificate")
  map(buf, km.filter,       actions.filter,        "filter certificates")
  map(buf, km.clear_filter, actions.clear_filter,  "clear filter")
  map(buf, km.refresh,      actions.refresh,       "refresh certificates")
  -- Visual-mode delete
  vmap(buf, km.delete, actions.delete_visual, "delete selected certificates")
end

--- Apply ACM certificate detail-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_acm_detail(buf, actions)
  local km = require("aws.config").values.keymaps.acm

  map(buf, km.detail_refresh, actions.refresh, "refresh certificate detail")
end

--- Apply Secrets Manager secrets-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_secretsmanager(buf, actions)
  local km = require("aws.config").values.keymaps.secretsmanager

  map(buf, km.open_detail,  actions.open_detail,  "open secret detail")
  map(buf, km.delete,       actions.delete,        "delete secret")
  map(buf, km.filter,       actions.filter,        "filter secrets")
  map(buf, km.clear_filter, actions.clear_filter,  "clear filter")
  map(buf, km.refresh,      actions.refresh,       "refresh secrets")
  -- Visual-mode delete
  vmap(buf, km.delete, actions.delete_visual, "delete selected secrets")
end

--- Apply Secrets Manager secret detail-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_secretsmanager_detail(buf, actions)
  local km = require("aws.config").values.keymaps.secretsmanager

  map(buf, km.detail_refresh, actions.refresh, "refresh secret detail")
  map(buf, km.reveal,         actions.reveal,  "toggle reveal secret value")
end

--- Apply CloudFront distributions-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_cloudfront(buf, actions)
  local km = require("aws.config").values.keymaps.cloudfront

  map(buf, km.open_detail,  actions.open_detail,  "open distribution detail")
  map(buf, km.invalidate,   actions.invalidate,    "create cache invalidation")
  map(buf, km.filter,       actions.filter,        "filter distributions")
  map(buf, km.clear_filter, actions.clear_filter,  "clear filter")
  map(buf, km.refresh,      actions.refresh,       "refresh distributions")
end

--- Apply CloudFront distribution detail-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_cloudfront_detail(buf, actions)
  local km = require("aws.config").values.keymaps.cloudfront

  map(buf, km.detail_refresh,    actions.refresh,    "refresh distribution detail")
  map(buf, km.detail_invalidate, actions.invalidate, "create cache invalidation")
end

return M
