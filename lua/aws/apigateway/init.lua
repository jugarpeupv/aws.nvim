--- aws.nvim – API Gateway public surface
--- Aggregates the individual submodules into one require-able table.
local M = {}

--- Open the API Gateway REST APIs list in a horizontal split.
---@param call_opts AwsCallOpts|nil
function M.list_apis(call_opts)
  require("aws.apigateway.apis").open(call_opts)
end

--- Open the detail view for a REST API by ID in a vertical split.
---@param id        string
---@param call_opts AwsCallOpts|nil
function M.open_detail(id, call_opts)
  require("aws.apigateway.detail").open(id, call_opts)
end

return M
