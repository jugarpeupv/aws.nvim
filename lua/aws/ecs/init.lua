--- aws.nvim – ECS public surface
--- Aggregates the individual submodules into one require-able table.
local M = {}

--- Open the ECS clusters list in a horizontal split.
---@param call_opts AwsCallOpts|nil
function M.list_clusters(call_opts)
  require("aws.ecs.clusters").open(call_opts)
end

--- Open the detail view for an ECS cluster (services + tasks) in a vertical split.
---@param cluster_arn string
---@param call_opts   AwsCallOpts|nil
function M.open_detail(cluster_arn, call_opts)
  require("aws.ecs.detail").open(cluster_arn, call_opts)
end

return M
