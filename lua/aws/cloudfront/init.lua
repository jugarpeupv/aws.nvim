--- aws.nvim – CloudFront public surface
--- Aggregates the individual submodules into one require-able table.
local M = {}

--- Open the CloudFront distributions list in a horizontal split.
---@param call_opts AwsCallOpts|nil
function M.list_distributions(call_opts)
  require("aws.cloudfront.distributions").open(call_opts)
end

--- Open the detail view for a distribution by ID in a vertical split.
---@param id        string
---@param call_opts AwsCallOpts|nil
function M.open_detail(id, call_opts)
  require("aws.cloudfront.detail").open(id, call_opts)
end

--- Prompt for an invalidation path and create a cache invalidation.
---@param id         string
---@param on_success fun()|nil
---@param call_opts  AwsCallOpts|nil
function M.invalidate(id, on_success, call_opts)
  require("aws.cloudfront.invalidate").prompt(id, on_success, call_opts)
end

return M
