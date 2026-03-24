--- aws.nvim – Secrets Manager secret deletion (async, with confirmation prompt)
local M = {}

local spawn = require("aws.spawn")

--- Delete a secret without a confirmation prompt.
--- Uses --force-delete-without-recovery to skip the 30-day recovery window.
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param name       string          the secret name or ARN
---@param on_success fun()|nil
---@param call_opts  AwsCallOpts|nil
function M.run(name, on_success, call_opts)
  vim.notify("aws.nvim: deleting secret " .. name .. "...", vim.log.levels.INFO)
  spawn.run(
    {
      "secretsmanager", "delete-secret",
      "--secret-id", name,
      "--force-delete-without-recovery",
      "--output", "json",
    },
    function(ok, lines)
      if not ok then
        vim.notify(
          "aws.nvim: delete-secret failed:\n" .. table.concat(lines, "\n"),
          vim.log.levels.ERROR
        )
        return
      end
      vim.notify("aws.nvim: deleted secret " .. name, vim.log.levels.INFO)
      if on_success then on_success() end
    end,
    call_opts
  )
end

--- Ask the user to confirm, then dispatch an async delete call.
--- The prompt makes clear that deletion is immediate (no recovery window).
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param name       string          the secret name (used as --secret-id and display)
---@param on_success fun()|nil       optional callback invoked after successful deletion
---@param call_opts  AwsCallOpts|nil
function M.confirm(name, on_success, call_opts)
  vim.ui.select(
    { "Yes, delete immediately (no recovery window)", "Cancel" },
    { prompt = "Delete secret '" .. name .. "'?" },
    function(_, idx)
      if not idx or idx ~= 1 then return end
      M.run(name, on_success, call_opts)
    end
  )
end

return M
