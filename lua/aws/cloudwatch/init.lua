--- aws.nvim – CloudWatch public surface
--- Aggregates the individual submodules into one require-able table.
local M = {}

--- Open the CloudWatch log groups list in a horizontal split.
---@param call_opts AwsCallOpts|nil
---@param fresh     boolean|nil   pass true to bypass the session cache
function M.list_groups(call_opts, fresh)
  require("aws.cloudwatch.groups").open(call_opts, fresh)
end

--- Open the log streams split for a named log group.
---@param group_name string
---@param call_opts  AwsCallOpts|nil
function M.list_streams(group_name, call_opts)
  require("aws.cloudwatch.streams").open(group_name, call_opts)
end

--- Open the log events split for a named stream in a log group.
---@param group_name  string
---@param stream_name string
---@param call_opts   AwsCallOpts|nil
function M.list_logs(group_name, stream_name, call_opts)
  require("aws.cloudwatch.logs").open(group_name, stream_name, call_opts)
end

--- Prompt and delete a log group by name.
---@param group_name string
---@param on_success  fun()|nil
---@param call_opts   AwsCallOpts|nil
function M.delete_group(group_name, on_success, call_opts)
  require("aws.cloudwatch.delete").confirm(group_name, on_success, call_opts)
end

return M
