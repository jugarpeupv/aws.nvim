--- aws.nvim – EC2 public surface
local M = {}

--- Open the EC2 instances list in a horizontal split.
---@param call_opts AwsCallOpts|nil
function M.list_instances(call_opts)
  require("aws.ec2.instances").open(call_opts)
end

--- Open the detail view for an EC2 instance in a vertical split.
---@param instance_id string
---@param call_opts   AwsCallOpts|nil
function M.open_detail(instance_id, call_opts)
  require("aws.ec2.detail").open(instance_id, call_opts)
end

return M
