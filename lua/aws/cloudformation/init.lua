--- aws.nvim – CloudFormation public surface
--- Aggregates the individual submodules into one require-able table.
local M = {}

local stacks = require("aws.cloudformation.stacks")
local events = require("aws.cloudformation.events")
local delete = require("aws.cloudformation.delete")

--- Open the stacks list in a horizontal split.
---@param call_opts AwsCallOpts|nil
function M.list_stacks(call_opts)
  stacks.open(call_opts)
end

--- Open the events split for a named stack.
---@param stack_name string
---@param call_opts  AwsCallOpts|nil
function M.stack_events(stack_name, call_opts)
  events.open(stack_name, call_opts)
end

--- Prompt and delete a stack by name.
---@param stack_name string
---@param on_success  fun()|nil
---@param call_opts   AwsCallOpts|nil
function M.delete_stack(stack_name, on_success, call_opts)
  delete.confirm(stack_name, on_success, call_opts)
end

return M
