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

--- ACM (Certificate Manager) operations.
M.acm = require("aws.acm")

--- Secrets Manager operations.
M.secretsmanager = require("aws.secretsmanager")

--- CloudFront operations.
M.cloudfront = require("aws.cloudfront")

--- API Gateway operations.
M.apigateway = require("aws.apigateway")

--- ECS (Elastic Container Service) / Fargate operations.
M.ecs = require("aws.ecs")

--- IAM (Identity and Access Management) operations.
M.iam = require("aws.iam")

--- VPC (Virtual Private Cloud) operations.
M.vpc = require("aws.vpc")

--- DynamoDB operations.
M.dynamodb = require("aws.dynamodb")

--- EC2 (Elastic Compute Cloud) operations.
M.ec2 = require("aws.ec2")

--- Open the service picker (snacks.nvim > telescope.nvim > vim.ui.select).
---@param call_opts AwsCallOpts|nil
function M.pick(call_opts)
  require("aws.picker").open(call_opts)
end

return M
