--- aws.nvim – ACM certificate deletion (async, with confirmation prompt)
local M = {}

local spawn = require("aws.spawn")

--- Delete an ACM certificate without a confirmation prompt.
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param cert_arn   string
---@param on_success fun()|nil
---@param call_opts  AwsCallOpts|nil
function M.run(cert_arn, on_success, call_opts)
  vim.notify("aws.nvim: deleting certificate " .. cert_arn .. "...", vim.log.levels.INFO)
  spawn.run({ "acm", "delete-certificate", "--certificate-arn", cert_arn }, function(ok, lines)
    if not ok then
      vim.notify("aws.nvim: delete-certificate failed:\n" .. table.concat(lines, "\n"), vim.log.levels.ERROR)
      return
    end
    vim.notify("aws.nvim: deleted certificate " .. cert_arn, vim.log.levels.INFO)
    if on_success then
      on_success()
    end
  end, call_opts)
end

--- Ask the user to confirm, then dispatch an async delete-certificate call.
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param cert_arn   string          the full certificate ARN
---@param domain     string          display name shown in the prompt
---@param on_success fun()|nil       optional callback invoked after successful deletion
---@param call_opts  AwsCallOpts|nil
function M.confirm(cert_arn, domain, on_success, call_opts)
  vim.ui.select({ "Yes, delete " .. domain, "Cancel" }, { prompt = "Delete ACM certificate?" }, function(_, idx)
    if not idx or idx ~= 1 then
      return
    end
    M.run(cert_arn, on_success, call_opts)
  end)
end

return M
