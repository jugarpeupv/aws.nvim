--- aws.nvim – DynamoDB delete helper (table deletion with confirmation)
local M = {}

local spawn = require("aws.spawn")

--- Show a confirmation prompt then delete a DynamoDB table.
---@param table_name string
---@param on_done    function|nil  called after successful deletion
---@param call_opts  AwsCallOpts|nil
function M.confirm(table_name, on_done, call_opts)
  vim.ui.select(
    { "Yes, delete " .. table_name, "Cancel" },
    { prompt = "Delete DynamoDB table '" .. table_name .. "'? This is irreversible." },
    function(_, idx)
      if not idx or idx ~= 1 then return end
      M.run(table_name, on_done, call_opts)
    end
  )
end

--- Delete a DynamoDB table without prompting.
---@param table_name string
---@param on_done    function|nil  called after successful deletion
---@param call_opts  AwsCallOpts|nil
function M.run(table_name, on_done, call_opts)
  spawn.run(
    { "dynamodb", "delete-table", "--table-name", table_name, "--output", "json" },
    function(ok, lines)
      if not ok then
        vim.notify(
          "aws.nvim: failed to delete table '" .. table_name .. "'\n"
            .. table.concat(lines, "\n"),
          vim.log.levels.ERROR
        )
        return
      end
      vim.notify("aws.nvim: table '" .. table_name .. "' deletion initiated", vim.log.levels.INFO)
      if on_done then on_done() end
    end,
    call_opts
  )
end

return M
