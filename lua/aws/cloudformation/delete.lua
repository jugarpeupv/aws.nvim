--- aws.nvim – CloudFormation stack deletion (async, with confirmation prompt)
local M = {}

local spawn = require("aws.spawn")

--- Dispatch a delete-stack call without a confirmation prompt.
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param stack_name string
---@param on_success  fun()|nil
---@param call_opts   AwsCallOpts|nil
function M.run(stack_name, on_success, call_opts)
  vim.notify("aws.nvim: dispatching delete for " .. stack_name .. "...", vim.log.levels.INFO)
  spawn.run(
    { "cloudformation", "delete-stack", "--stack-name", stack_name },
    function(ok, lines)
      if not ok then
        vim.notify(
          "aws.nvim: delete-stack failed:\n" .. table.concat(lines, "\n"),
          vim.log.levels.ERROR
        )
        return
      end
      vim.notify("aws.nvim: delete dispatched for " .. stack_name, vim.log.levels.INFO)
      if on_success then on_success() end
    end,
    call_opts
  )
end

--- Ask the user to confirm, then dispatch an async delete-stack call.
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param stack_name string
---@param on_success  fun()|nil  optional callback invoked after successful dispatch
---@param call_opts   AwsCallOpts|nil
function M.confirm(stack_name, on_success, call_opts)
  vim.ui.select(
    { "Yes, delete " .. stack_name, "Cancel" },
    { prompt = "Delete CloudFormation stack?" },
    function(_, idx)
      if not idx or idx ~= 1 then return end
      M.run(stack_name, on_success, call_opts)
    end
  )
end

return M
