--- aws.nvim – S3 bucket empty (async, with confirmation prompt)
--- Handles versioned buckets by deleting all versions and delete markers
--- in a loop until list-object-versions reports nothing left.
local M = {}

local spawn = require("aws.spawn")

--- Delete one page of versions+markers, then recurse until the bucket is empty.
---@param bucket_name string
---@param call_opts   AwsCallOpts|nil
---@param on_done     fun(ok: boolean, err: string|nil)
local function delete_all_versions(bucket_name, call_opts, on_done)
  -- List up to 1000 versions+delete-markers in one call
  spawn.run({
    "s3api",
    "list-object-versions",
    "--bucket",
    bucket_name,
    "--output",
    "json",
    "--query",
    "{Versions:Versions,DeleteMarkers:DeleteMarkers}",
  }, function(ok, lines)
    if not ok then
      on_done(false, table.concat(lines, "\n"))
      return
    end

    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if not ok2 or type(data) ~= "table" then
      on_done(false, "Failed to parse list-object-versions response")
      return
    end

    -- Build a flat list of {Key, VersionId} for both versions and markers
    local objects = {}
    for _, entry in ipairs(type(data.Versions) == "table" and data.Versions or {}) do
      table.insert(objects, { Key = entry.Key, VersionId = entry.VersionId })
    end
    for _, entry in ipairs(type(data.DeleteMarkers) == "table" and data.DeleteMarkers or {}) do
      table.insert(objects, { Key = entry.Key, VersionId = entry.VersionId })
    end

    -- Nothing left → done
    if #objects == 0 then
      on_done(true, nil)
      return
    end

    -- Encode the delete payload as JSON and pass via stdin-replacement:
    -- aws s3api delete-objects accepts --delete as a JSON string argument.
    local payload_ok, payload = pcall(vim.json.encode, { Objects = objects, Quiet = true })
    if not payload_ok then
      on_done(false, "Failed to encode delete payload")
      return
    end

    spawn.run({
      "s3api",
      "delete-objects",
      "--bucket",
      bucket_name,
      "--delete",
      payload,
    }, function(ok3, err_lines)
      if not ok3 then
        on_done(false, table.concat(err_lines, "\n"))
        return
      end
      -- Recurse: there may be more pages (list-object-versions returns max 1000)
      delete_all_versions(bucket_name, call_opts, on_done)
    end, call_opts)
  end, call_opts)
end

--- Empty a bucket without a confirmation prompt.
--- Calls `on_success()` (if provided) when the bucket is confirmed empty.
---@param bucket_name string
---@param on_success  fun()|nil
---@param call_opts   AwsCallOpts|nil
function M.run(bucket_name, on_success, call_opts)
  vim.notify("aws.nvim: emptying bucket " .. bucket_name .. "...", vim.log.levels.INFO)
  delete_all_versions(bucket_name, call_opts, function(ok, err)
    if not ok then
      vim.notify("aws.nvim: failed to empty bucket:\n" .. (err or "unknown error"), vim.log.levels.ERROR)
      return
    end
    vim.notify("aws.nvim: bucket " .. bucket_name .. " emptied", vim.log.levels.INFO)
    if on_success then
      on_success()
    end
  end)
end

--- Ask the user to confirm, then fully empty the bucket including all versions
--- and delete markers (handles versioned buckets).
--- Calls `on_success()` (if provided) when the bucket is confirmed empty.
---@param bucket_name string
---@param on_success  fun()|nil
---@param call_opts   AwsCallOpts|nil
function M.confirm(bucket_name, on_success, call_opts)
  vim.ui.select(
    { "Yes, empty " .. bucket_name, "Cancel" },
    { prompt = "Empty S3 bucket? (all objects and versions will be deleted)" },
    function(_, idx)
      if not idx or idx ~= 1 then
        return
      end
      M.run(bucket_name, on_success, call_opts)
    end
  )
end

return M
