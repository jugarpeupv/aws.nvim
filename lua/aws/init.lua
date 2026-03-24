--- aws.nvim – public API entry point
local M = {}

--- Configure the plugin. Call once in your Neovim config.
---@param opts AwsConfig|nil
function M.setup(opts)
  require("aws.config").setup(opts)
end

--- CloudFormation operations.
M.cloudformation = require("aws.cloudformation")

--- S3 operations.
M.s3 = require("aws.s3")

--- CloudWatch operations.
M.cloudwatch = require("aws.cloudwatch")

--- Lambda operations.
M.lambda = require("aws.lambda")

return M
