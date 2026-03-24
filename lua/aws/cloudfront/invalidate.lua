--- aws.nvim – CloudFront cache invalidation (async, with prompt)
local M = {}

local spawn = require("aws.spawn")

--- Create a CloudFront cache invalidation without a confirmation prompt.
--- Calls `on_success()` (if provided) when the CLI returns exit 0.
---@param id         string          CloudFront distribution ID
---@param paths      string[]        list of paths to invalidate, e.g. {"/*"}
---@param on_success fun()|nil
---@param call_opts  AwsCallOpts|nil
function M.run(id, paths, on_success, call_opts)
  vim.notify("aws.nvim: creating invalidation for " .. id .. "...", vim.log.levels.INFO)

  -- Build the --paths argument: "Quantity=N,Items=[/a,/b]"
  local quantity = tostring(#paths)
  local items    = table.concat(paths, ",")
  local paths_arg = "Quantity=" .. quantity .. ",Items=[" .. items .. "]"

  spawn.run(
    {
      "cloudfront", "create-invalidation",
      "--distribution-id", id,
      "--paths", paths_arg,
      "--output", "json",
    },
    function(ok, lines)
      if not ok then
        vim.notify(
          "aws.nvim: create-invalidation failed:\n" .. table.concat(lines, "\n"),
          vim.log.levels.ERROR
        )
        return
      end
      vim.notify(
        "aws.nvim: invalidation created for distribution " .. id,
        vim.log.levels.INFO
      )
      if on_success then on_success() end
    end,
    call_opts
  )
end

--- Prompt the user for an invalidation path (default `/*`), then run.
---@param id         string          CloudFront distribution ID
---@param on_success fun()|nil
---@param call_opts  AwsCallOpts|nil
function M.prompt(id, on_success, call_opts)
  vim.ui.input(
    { prompt = "Invalidation path (default /*): ", default = "/*" },
    function(input)
      if input == nil then return end            -- user cancelled
      local path = (input == "" and "/*") or input
      M.run(id, { path }, on_success, call_opts)
    end
  )
end

return M
