--- aws.nvim – DynamoDB module facade
local M = {}

--- Open the DynamoDB tables list in a horizontal split.
---@param call_opts AwsCallOpts|nil
function M.list_tables(call_opts)
  require("aws.dynamodb.tables").open(call_opts)
end

--- Open the per-table section menu in a vertical split.
---@param table_name string
---@param call_opts  AwsCallOpts|nil
function M.open_menu(table_name, call_opts)
  require("aws.dynamodb.menu").open(table_name, call_opts)
end

--- Open the detail view for a DynamoDB table in a vertical split.
---@param table_name string
---@param call_opts  AwsCallOpts|nil
function M.open_detail(table_name, call_opts)
  require("aws.dynamodb.detail").open(table_name, call_opts)
end

--- Open the item scan/query buffer for a DynamoDB table in a vertical split.
---@param table_name string
---@param call_opts  AwsCallOpts|nil
function M.open_scan(table_name, call_opts)
  require("aws.dynamodb.scan").open(table_name, call_opts)
end

--- Delete a DynamoDB table (with confirmation).
---@param table_name string
---@param on_done    function|nil   called after successful deletion
---@param call_opts  AwsCallOpts|nil
function M.delete_table(table_name, on_done, call_opts)
  require("aws.dynamodb.delete").confirm(table_name, on_done, call_opts)
end

return M
