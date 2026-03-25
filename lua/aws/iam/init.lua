--- aws.nvim – IAM module facade
local M = {}

--- Open the IAM service menu (users / groups / roles / policies / providers).
---@param call_opts AwsCallOpts|nil
function M.open_menu(call_opts)
  require("aws.iam.menu").open(call_opts)
end

function M.list_users(call_opts)     require("aws.iam.users").open(call_opts)     end
function M.list_groups(call_opts)    require("aws.iam.groups").open(call_opts)    end
function M.list_roles(call_opts)     require("aws.iam.roles").open(call_opts)     end
function M.list_policies(call_opts)  require("aws.iam.policies").open(call_opts)  end
function M.list_providers(call_opts) require("aws.iam.providers").open(call_opts) end

function M.open_user(name, call_opts)     require("aws.iam.detail.user").open(name, call_opts)          end
function M.open_group(name, call_opts)    require("aws.iam.detail.group").open(name, call_opts)         end
function M.open_role(name, call_opts)     require("aws.iam.detail.role").open(name, call_opts)          end
function M.open_policy(arn, call_opts)    require("aws.iam.detail.policy").open(arn, call_opts)         end
function M.open_provider(arn, kind, call_opts) require("aws.iam.detail.provider").open(arn, kind, call_opts) end

return M
