--- aws.nvim – async AWS CLI subprocess runner
--- Authentication is fully delegated to the user's environment.
--- Any stderr from the CLI is forwarded verbatim to the callback.
local M = {}

--- Build a full environment list for vim.loop.spawn, merging the current
--- process environment with any AWS_* overrides from config + per-call opts.
---@param call_opts AwsCallOpts|nil
---@return string[]|nil  nil when there are no overrides (inherit env as-is)
local function build_env(call_opts)
  local overrides = require("aws.config").env_overrides(call_opts)
  if not next(overrides) then return nil end

  local current = vim.fn.environ()
  for k, v in pairs(overrides) do
    current[k] = v
  end

  local env = {}
  for k, v in pairs(current) do
    table.insert(env, k .. "=" .. v)
  end
  return env
end

--- Run `aws <args>` asynchronously.
--- Calls `cb(ok, lines)` on the vim main loop once the process exits.
---   ok    – true when exit code is 0
---   lines – stdout lines on success; stderr lines on failure
---@param args      string[]
---@param cb        fun(ok: boolean, lines: string[])
---@param call_opts AwsCallOpts|nil  optional per-call profile/region overrides
function M.run(args, cb, call_opts)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  local out_chunks = {}
  local err_chunks = {}

  local handle
  handle = vim.loop.spawn("aws", {
    args  = args,
    stdio = { nil, stdout, stderr },
    env   = build_env(call_opts),
  }, function(code)
    stdout:close()
    stderr:close()
    handle:close()

    local ok  = (code == 0)
    local raw = ok and table.concat(out_chunks) or table.concat(err_chunks)
    local lines = vim.split(raw, "\n", { plain = true, trimempty = true })

    vim.schedule(function() cb(ok, lines) end)
  end)

  stdout:read_start(function(err, data)
    assert(not err, err)
    if data then table.insert(out_chunks, data) end
  end)

  stderr:read_start(function(err, data)
    assert(not err, err)
    if data then table.insert(err_chunks, data) end
  end)
end

return M
