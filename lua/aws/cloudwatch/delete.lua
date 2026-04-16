--- aws.nvim – CloudWatch log group deletion (async, with confirmation prompt)
local M = {}

local spawn = require("aws.spawn")

--- Delete a log group without a confirmation prompt.
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param group_name string
---@param on_success  fun()|nil
---@param call_opts   AwsCallOpts|nil
function M.run(group_name, on_success, call_opts)
  vim.notify("aws.nvim: deleting log group " .. group_name .. "...", vim.log.levels.INFO)
  spawn.run({ "logs", "delete-log-group", "--log-group-name", group_name }, function(ok, lines)
    if not ok then
      vim.notify("aws.nvim: delete-log-group failed:\n" .. table.concat(lines, "\n"), vim.log.levels.ERROR)
      return
    end
    vim.notify("aws.nvim: deleted log group " .. group_name, vim.log.levels.INFO)
    if on_success then
      on_success()
    end
  end, call_opts)
end

--- Ask the user to confirm, then dispatch an async delete-log-group call.
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param group_name string
---@param on_success  fun()|nil  optional callback invoked after successful deletion
---@param call_opts   AwsCallOpts|nil
function M.confirm(group_name, on_success, call_opts)
  vim.ui.select(
    { "Yes, delete " .. group_name, "Cancel" },
    { prompt = "Delete CloudWatch log group?" },
    function(_, idx)
      if not idx or idx ~= 1 then
        return
      end
      M.run(group_name, on_success, call_opts)
    end
  )
end

return M
