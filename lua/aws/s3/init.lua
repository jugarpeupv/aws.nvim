--- aws.nvim – S3 public surface
local M = {}

--- Open the S3 buckets list buffer.
---@param call_opts AwsCallOpts|nil
function M.list_buckets(call_opts)
  require("aws.s3.buckets").open(call_opts)
end

--- Confirm and empty a bucket (all objects deleted recursively).
---@param bucket_name string
---@param on_success   fun()|nil
---@param call_opts    AwsCallOpts|nil
function M.empty_bucket(bucket_name, on_success, call_opts)
  require("aws.s3.empty").confirm(bucket_name, on_success, call_opts)
end

--- Confirm and delete a bucket (must already be empty).
---@param bucket_name string
---@param on_success   fun()|nil
---@param call_opts    AwsCallOpts|nil
function M.delete_bucket(bucket_name, on_success, call_opts)
  require("aws.s3.delete").confirm(bucket_name, on_success, call_opts)
end

return M
