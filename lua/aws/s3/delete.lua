--- aws.nvim – S3 bucket deletion (async, with confirmation prompt)
--- NOTE: the bucket must already be empty before calling this.
---       Use aws.s3.empty first, or call empty.confirm() → delete.confirm() in sequence.
local M = {}

local spawn = require("aws.spawn")

--- Delete a bucket without a confirmation prompt (bucket must already be empty).
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param bucket_name string
---@param on_success  fun()|nil
---@param call_opts   AwsCallOpts|nil
function M.run(bucket_name, on_success, call_opts)
  vim.notify("aws.nvim: deleting bucket " .. bucket_name .. "...", vim.log.levels.INFO)
  spawn.run({ "s3api", "delete-bucket", "--bucket", bucket_name }, function(ok, lines)
    if not ok then
      vim.notify("aws.nvim: delete-bucket failed:\n" .. table.concat(lines, "\n"), vim.log.levels.ERROR)
      return
    end
    vim.notify("aws.nvim: bucket " .. bucket_name .. " deleted", vim.log.levels.INFO)
    if on_success then
      on_success()
    end
  end, call_opts)
end

--- Ask the user to confirm, then run `s3api delete-bucket --bucket <name>`.
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param bucket_name string
---@param on_success  fun()|nil  optional callback invoked after successful deletion
---@param call_opts   AwsCallOpts|nil
function M.confirm(bucket_name, on_success, call_opts)
  vim.ui.select(
    { "Yes, delete " .. bucket_name, "Cancel" },
    { prompt = "Delete S3 bucket? (bucket must be empty)" },
    function(_, idx)
      if not idx or idx ~= 1 then
        return
      end
      M.run(bucket_name, on_success, call_opts)
    end
  )
end

return M
