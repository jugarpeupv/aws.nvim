--- aws.nvim – VPC module facade
local M = {}

--- Open the VPC list buffer.
---@param call_opts AwsCallOpts|nil
function M.list_vpcs(call_opts)
  require("aws.vpc.vpcs").open(call_opts)
end

--- Open the VPC section menu for a specific VPC.
---@param vpc_id    string
---@param vpc_name  string|nil
---@param call_opts AwsCallOpts|nil
function M.open_menu(vpc_id, vpc_name, call_opts)
  require("aws.vpc.menu").open(vpc_id, vpc_name, call_opts)
end

--- Open the VPC General/Tags detail buffer for a specific VPC.
---@param vpc_id    string
---@param call_opts AwsCallOpts|nil
function M.open_detail(vpc_id, call_opts)
  require("aws.vpc.detail").open(vpc_id, call_opts)
end

return M
