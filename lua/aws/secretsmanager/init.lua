--- aws.nvim – Secrets Manager public surface
--- Aggregates the individual submodules into one require-able table.
local M = {}

--- Open the Secrets Manager secrets list in a horizontal split.
---@param call_opts AwsCallOpts|nil
function M.list_secrets(call_opts)
  require("aws.secretsmanager.secrets").open(call_opts)
end

--- Open the detail view for a secret by name in a vertical split.
---@param name      string
---@param call_opts AwsCallOpts|nil
function M.open_detail(name, call_opts)
  require("aws.secretsmanager.detail").open(name, call_opts)
end

--- Prompt and delete a secret by name.
---@param name       string
---@param on_success fun()|nil
---@param call_opts  AwsCallOpts|nil
function M.delete_secret(name, on_success, call_opts)
  require("aws.secretsmanager.delete").confirm(name, on_success, call_opts)
end

return M
