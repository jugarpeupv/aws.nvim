--- aws.nvim – Lambda function deletion (async, with confirmation prompt)
local M = {}

local spawn = require("aws.spawn")

--- Delete a Lambda function without a confirmation prompt.
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param fn_name    string
---@param on_success fun()|nil
---@param call_opts  AwsCallOpts|nil
function M.run(fn_name, on_success, call_opts)
  vim.notify("aws.nvim: deleting function " .. fn_name .. "...", vim.log.levels.INFO)
  spawn.run(
    { "lambda", "delete-function", "--function-name", fn_name },
    function(ok, lines)
      if not ok then
        vim.notify(
          "aws.nvim: delete-function failed:\n" .. table.concat(lines, "\n"),
          vim.log.levels.ERROR
        )
        return
      end
      vim.notify("aws.nvim: deleted function " .. fn_name, vim.log.levels.INFO)
      if on_success then on_success() end
    end,
    call_opts
  )
end

--- Ask the user to confirm, then dispatch an async delete-function call.
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param fn_name    string
---@param on_success fun()|nil  optional callback invoked after successful deletion
---@param call_opts  AwsCallOpts|nil
function M.confirm(fn_name, on_success, call_opts)
  vim.ui.select(
    { "Yes, delete " .. fn_name, "Cancel" },
    { prompt = "Delete Lambda function?" },
    function(_, idx)
      if not idx or idx ~= 1 then return end
      M.run(fn_name, on_success, call_opts)
    end
  )
end

return M
