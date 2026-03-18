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
---@param buf  integer
---@param key  string|false
---@param fn   function
---@param desc string
local function vmap(buf, key, fn, desc)
  if not key or key == false then return end
  vim.keymap.set("v", key, fn, {
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

  map(buf, km.open_events,  actions.open_events,  "open stack events")
  map(buf, km.delete,       actions.delete,        "delete stack")
  map(buf, km.filter,       actions.filter,        "filter stacks")
  map(buf, km.clear_filter, actions.clear_filter,  "clear filter")
  map(buf, km.refresh,      actions.refresh,       "refresh stacks")
  map(buf, km.close,        actions.close,         "close window")
  -- <Esc> always closes regardless of user config
  map(buf, "<Esc>",         actions.close,         "close window")
  -- Visual-mode delete
  vmap(buf, km.delete, actions.delete_visual, "delete selected stacks")
end

--- Apply CloudFormation events-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_cloudformation_events(buf, actions)
  local km = require("aws.config").values.keymaps.cloudformation

  map(buf, km.refresh, actions.refresh, "refresh events")
  map(buf, km.close,   actions.close,   "close window")
  map(buf, "<Esc>",    actions.close,   "close window")
end

--- Apply S3 buckets-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_s3(buf, actions)
  local km = require("aws.config").values.keymaps.s3

  map(buf, km.empty,        actions.empty,        "empty bucket")
  map(buf, km.delete,       actions.delete,        "delete bucket")
  map(buf, km.filter,       actions.filter,        "filter buckets")
  map(buf, km.clear_filter, actions.clear_filter,  "clear filter")
  map(buf, km.refresh,      actions.refresh,       "refresh buckets")
  map(buf, km.close,        actions.close,         "close window")
  map(buf, "<Esc>",         actions.close,         "close window")
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
  map(buf, km.close,        actions.close,         "close window")
  map(buf, "<Esc>",         actions.close,         "close window")
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
  map(buf, km.close,     actions.close,     "close window")
  map(buf, "<Esc>",      actions.close,     "close window")
end

--- Apply CloudWatch log events-buffer keymaps.
---@param buf     integer
---@param actions table<string, function>
function M.apply_cloudwatch_logs(buf, actions)
  local km = require("aws.config").values.keymaps.cloudwatch

  map(buf, km.refresh, actions.refresh, "refresh log events")
  map(buf, km.close,   actions.close,   "close window")
  map(buf, "<Esc>",    actions.close,   "close window")
end

return M
