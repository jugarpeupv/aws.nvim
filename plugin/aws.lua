--- aws.nvim – plugin entry point
--- Registers user commands. Loaded automatically by Neovim's plugin system.

if vim.g.loaded_aws_nvim then return end
vim.g.loaded_aws_nvim = true

if vim.fn.has("nvim-0.9") == 0 then
  vim.notify("aws.nvim requires Neovim >= 0.9", vim.log.levels.ERROR)
  return
end

local aws = require("aws")

-------------------------------------------------------------------------------
-- Flag parser
-- Extracts --region <value> and --profile <value> from fargs, returns the
-- remaining positional args plus a call_opts table (or nil when neither flag
-- was present).
-------------------------------------------------------------------------------

---@param fargs string[]
---@return string[], AwsCallOpts|nil, boolean
local function parse_flags(fargs)
  local positional = {}
  local opts = {}
  local fresh = false
  local i = 1
  while i <= #fargs do
    local arg = fargs[i]
    if arg == "--region" and fargs[i + 1] then
      opts.region = fargs[i + 1]
      i = i + 2
    elseif arg == "--profile" and fargs[i + 1] then
      opts.profile = fargs[i + 1]
      i = i + 2
    elseif arg == "--fresh" then
      fresh = true
      i = i + 1
    else
      table.insert(positional, arg)
      i = i + 1
    end
  end
  local call_opts = (opts.region or opts.profile) and opts or nil
  return positional, call_opts, fresh
end

-------------------------------------------------------------------------------
-- :AwsCF [--region <r>] [--profile <p>] [subcommand [name]]
-------------------------------------------------------------------------------

vim.api.nvim_create_user_command("AwsCF", function(opts)
  local args, call_opts = parse_flags(opts.fargs)
  local sub  = args[1] or "list"
  local name = args[2]

  if sub == "list" or sub == "ls" then
    aws.cloudformation.list_stacks(call_opts)

  elseif sub == "events" then
    if not name or name == "" then
      vim.notify("Usage: :AwsCF events <stack-name>", vim.log.levels.WARN)
      return
    end
    aws.cloudformation.stack_events(name, call_opts)

  elseif sub == "delete" or sub == "del" then
    if not name or name == "" then
      vim.notify("Usage: :AwsCF delete <stack-name>", vim.log.levels.WARN)
      return
    end
    aws.cloudformation.delete_stack(name, nil, call_opts)

  else
    vim.notify(
      "aws.nvim: unknown sub-command '" .. sub .. "'\n"
        .. "Available: list, events <name>, delete <name>",
      vim.log.levels.WARN
    )
  end
end, {
  nargs = "*",
  desc  = "aws.nvim: CloudFormation operations",
  complete = function(arglead, cmdline, _)
    local parts = vim.split(cmdline, "%s+", { trimempty = true })
    -- offer flag completions when the lead starts with -
    if arglead:sub(1, 1) == "-" then
      local flags = { "--region", "--profile" }
      local out = {}
      for _, f in ipairs(flags) do
        if f:find(arglead, 1, true) == 1 then table.insert(out, f) end
      end
      return out
    end
    -- offer sub-command completions for the first positional word
    local positional_count = 0
    for _, p in ipairs(parts) do
      if p:sub(1, 1) ~= "-" then positional_count = positional_count + 1 end
    end
    if positional_count <= 1 or (positional_count == 2 and not cmdline:match("%s$")) then
      local out = {}
      for _, s in ipairs({ "list", "events", "delete" }) do
        if s:find(arglead, 1, true) == 1 then table.insert(out, s) end
      end
      return out
    end
    return {}
  end,
})

-------------------------------------------------------------------------------
-- :AwsS3 [--region <r>] [--profile <p>] [subcommand [name]]
-------------------------------------------------------------------------------

vim.api.nvim_create_user_command("AwsS3", function(opts)
  local args, call_opts = parse_flags(opts.fargs)
  local sub  = args[1] or "list"
  local name = args[2]

  if sub == "list" or sub == "ls" then
    aws.s3.list_buckets(call_opts)

  elseif sub == "empty" then
    if not name or name == "" then
      vim.notify("Usage: :AwsS3 empty <bucket-name>", vim.log.levels.WARN)
      return
    end
    aws.s3.empty_bucket(name, nil, call_opts)

  elseif sub == "delete" or sub == "del" then
    if not name or name == "" then
      vim.notify("Usage: :AwsS3 delete <bucket-name>", vim.log.levels.WARN)
      return
    end
    aws.s3.delete_bucket(name, nil, call_opts)

  else
    vim.notify(
      "aws.nvim: unknown sub-command '" .. sub .. "'\n"
        .. "Available: list, empty <name>, delete <name>",
      vim.log.levels.WARN
    )
  end
end, {
  nargs = "*",
  desc  = "aws.nvim: S3 operations",
  complete = function(arglead, cmdline, _)
    if arglead:sub(1, 1) == "-" then
      local flags = { "--region", "--profile" }
      local out = {}
      for _, f in ipairs(flags) do
        if f:find(arglead, 1, true) == 1 then table.insert(out, f) end
      end
      return out
    end
    local parts = vim.split(cmdline, "%s+", { trimempty = true })
    local positional_count = 0
    for _, p in ipairs(parts) do
      if p:sub(1, 1) ~= "-" then positional_count = positional_count + 1 end
    end
    if positional_count <= 1 or (positional_count == 2 and not cmdline:match("%s$")) then
      local out = {}
      for _, s in ipairs({ "list", "empty", "delete" }) do
        if s:find(arglead, 1, true) == 1 then table.insert(out, s) end
      end
      return out
    end
    return {}
  end,
})

-------------------------------------------------------------------------------
-- :AwsCW [--region <r>] [--profile <p>] [subcommand [name [stream]]]
-------------------------------------------------------------------------------

vim.api.nvim_create_user_command("AwsCW", function(opts)
  local args, call_opts, fresh = parse_flags(opts.fargs)
  local sub    = args[1] or "list"
  local name   = args[2]
  local stream = args[3]

  if sub == "list" or sub == "ls" then
    aws.cloudwatch.list_groups(call_opts, fresh)

  elseif sub == "streams" then
    if not name or name == "" then
      vim.notify("Usage: :AwsCW streams <log-group-name>", vim.log.levels.WARN)
      return
    end
    aws.cloudwatch.list_streams(name, call_opts)

  elseif sub == "logs" then
    if not name or name == "" or not stream or stream == "" then
      vim.notify("Usage: :AwsCW logs <log-group-name> <stream-name>", vim.log.levels.WARN)
      return
    end
    aws.cloudwatch.list_logs(name, stream, call_opts)

  elseif sub == "delete" or sub == "del" then
    if not name or name == "" then
      vim.notify("Usage: :AwsCW delete <log-group-name>", vim.log.levels.WARN)
      return
    end
    aws.cloudwatch.delete_group(name, nil, call_opts)

  else
    vim.notify(
      "aws.nvim: unknown sub-command '" .. sub .. "'\n"
        .. "Available: list, streams <group>, logs <group> <stream>, delete <group>",
      vim.log.levels.WARN
    )
  end
end, {
  nargs = "*",
  desc  = "aws.nvim: CloudWatch operations",
  complete = function(arglead, cmdline, _)
    if arglead:sub(1, 1) == "-" then
      local flags = { "--region", "--profile", "--fresh" }
      local out = {}
      for _, f in ipairs(flags) do
        if f:find(arglead, 1, true) == 1 then table.insert(out, f) end
      end
      return out
    end
    local parts = vim.split(cmdline, "%s+", { trimempty = true })
    local positional_count = 0
    for _, p in ipairs(parts) do
      if p:sub(1, 1) ~= "-" then positional_count = positional_count + 1 end
    end
    if positional_count <= 1 or (positional_count == 2 and not cmdline:match("%s$")) then
      local out = {}
      for _, s in ipairs({ "list", "streams", "logs", "delete" }) do
        if s:find(arglead, 1, true) == 1 then table.insert(out, s) end
      end
      return out
    end
    return {}
  end,
})

-------------------------------------------------------------------------------
-- :AwsLambda [--region <r>] [--profile <p>] [subcommand [name]]
-------------------------------------------------------------------------------

vim.api.nvim_create_user_command("AwsLambda", function(opts)
  local args, call_opts = parse_flags(opts.fargs)
  local sub  = args[1] or "list"
  local name = args[2]

  if sub == "list" or sub == "ls" then
    aws.lambda.list_functions(call_opts)

  elseif sub == "detail" then
    if not name or name == "" then
      vim.notify("Usage: :AwsLambda detail <function-name>", vim.log.levels.WARN)
      return
    end
    aws.lambda.open_detail(name, call_opts)

  elseif sub == "delete" or sub == "del" then
    if not name or name == "" then
      vim.notify("Usage: :AwsLambda delete <function-name>", vim.log.levels.WARN)
      return
    end
    aws.lambda.delete_function(name, nil, call_opts)

  else
    vim.notify(
      "aws.nvim: unknown sub-command '" .. sub .. "'\n"
        .. "Available: list, detail <name>, delete <name>",
      vim.log.levels.WARN
    )
  end
end, {
  nargs = "*",
  desc  = "aws.nvim: Lambda operations",
  complete = function(arglead, cmdline, _)
    if arglead:sub(1, 1) == "-" then
      local flags = { "--region", "--profile" }
      local out = {}
      for _, f in ipairs(flags) do
        if f:find(arglead, 1, true) == 1 then table.insert(out, f) end
      end
      return out
    end
    local parts = vim.split(cmdline, "%s+", { trimempty = true })
    local positional_count = 0
    for _, p in ipairs(parts) do
      if p:sub(1, 1) ~= "-" then positional_count = positional_count + 1 end
    end
    if positional_count <= 1 or (positional_count == 2 and not cmdline:match("%s$")) then
      local out = {}
      for _, s in ipairs({ "list", "detail", "delete" }) do
        if s:find(arglead, 1, true) == 1 then table.insert(out, s) end
      end
      return out
    end
    return {}
  end,
})

-------------------------------------------------------------------------------
-- :AwsACM [--region <r>] [--profile <p>] [subcommand [arn]]
-------------------------------------------------------------------------------

vim.api.nvim_create_user_command("AwsACM", function(opts)
  local args, call_opts = parse_flags(opts.fargs)
  local sub = args[1] or "list"
  local arn = args[2]

  if sub == "list" or sub == "ls" then
    aws.acm.list_certificates(call_opts)

  elseif sub == "detail" then
    if not arn or arn == "" then
      vim.notify("Usage: :AwsACM detail <certificate-arn>", vim.log.levels.WARN)
      return
    end
    aws.acm.open_detail(arn, call_opts)

  elseif sub == "delete" or sub == "del" then
    if not arn or arn == "" then
      vim.notify("Usage: :AwsACM delete <certificate-arn>", vim.log.levels.WARN)
      return
    end
    -- Extract domain from arn for display (last segment is the cert ID, not the domain)
    aws.acm.delete_certificate(arn, arn, nil, call_opts)

  else
    vim.notify(
      "aws.nvim: unknown sub-command '" .. sub .. "'\n"
        .. "Available: list, detail <arn>, delete <arn>",
      vim.log.levels.WARN
    )
  end
end, {
  nargs = "*",
  desc  = "aws.nvim: ACM (Certificate Manager) operations",
  complete = function(arglead, cmdline, _)
    if arglead:sub(1, 1) == "-" then
      local flags = { "--region", "--profile" }
      local out = {}
      for _, f in ipairs(flags) do
        if f:find(arglead, 1, true) == 1 then table.insert(out, f) end
      end
      return out
    end
    local parts = vim.split(cmdline, "%s+", { trimempty = true })
    local positional_count = 0
    for _, p in ipairs(parts) do
      if p:sub(1, 1) ~= "-" then positional_count = positional_count + 1 end
    end
    if positional_count <= 1 or (positional_count == 2 and not cmdline:match("%s$")) then
      local out = {}
      for _, s in ipairs({ "list", "detail", "delete" }) do
        if s:find(arglead, 1, true) == 1 then table.insert(out, s) end
      end
      return out
    end
    return {}
  end,
})

-------------------------------------------------------------------------------
-- :AwsSM [--region <r>] [--profile <p>] [subcommand [name]]
-------------------------------------------------------------------------------

vim.api.nvim_create_user_command("AwsSM", function(opts)
  local args, call_opts = parse_flags(opts.fargs)
  local sub  = args[1] or "list"
  local name = args[2]

  if sub == "list" or sub == "ls" then
    aws.secretsmanager.list_secrets(call_opts)

  elseif sub == "detail" then
    if not name or name == "" then
      vim.notify("Usage: :AwsSM detail <secret-name>", vim.log.levels.WARN)
      return
    end
    aws.secretsmanager.open_detail(name, call_opts)

  elseif sub == "delete" or sub == "del" then
    if not name or name == "" then
      vim.notify("Usage: :AwsSM delete <secret-name>", vim.log.levels.WARN)
      return
    end
    aws.secretsmanager.delete_secret(name, nil, call_opts)

  else
    vim.notify(
      "aws.nvim: unknown sub-command '" .. sub .. "'\n"
        .. "Available: list, detail <name>, delete <name>",
      vim.log.levels.WARN
    )
  end
end, {
  nargs = "*",
  desc  = "aws.nvim: Secrets Manager operations",
  complete = function(arglead, cmdline, _)
    if arglead:sub(1, 1) == "-" then
      local flags = { "--region", "--profile" }
      local out = {}
      for _, f in ipairs(flags) do
        if f:find(arglead, 1, true) == 1 then table.insert(out, f) end
      end
      return out
    end
    local parts = vim.split(cmdline, "%s+", { trimempty = true })
    local positional_count = 0
    for _, p in ipairs(parts) do
      if p:sub(1, 1) ~= "-" then positional_count = positional_count + 1 end
    end
    if positional_count <= 1 or (positional_count == 2 and not cmdline:match("%s$")) then
      local out = {}
      for _, s in ipairs({ "list", "detail", "delete" }) do
        if s:find(arglead, 1, true) == 1 then table.insert(out, s) end
      end
      return out
    end
    return {}
  end,
})

-------------------------------------------------------------------------------
-- :AwsCFront [--region <r>] [--profile <p>] [subcommand [id]]
-------------------------------------------------------------------------------

vim.api.nvim_create_user_command("AwsCFront", function(opts)
  local args, call_opts = parse_flags(opts.fargs)
  local sub = args[1] or "list"
  local id  = args[2]

  if sub == "list" or sub == "ls" then
    aws.cloudfront.list_distributions(call_opts)

  elseif sub == "detail" then
    if not id or id == "" then
      vim.notify("Usage: :AwsCFront detail <distribution-id>", vim.log.levels.WARN)
      return
    end
    aws.cloudfront.open_detail(id, call_opts)

  elseif sub == "invalidate" or sub == "inv" then
    if not id or id == "" then
      vim.notify("Usage: :AwsCFront invalidate <distribution-id>", vim.log.levels.WARN)
      return
    end
    aws.cloudfront.invalidate(id, nil, call_opts)

  else
    vim.notify(
      "aws.nvim: unknown sub-command '" .. sub .. "'\n"
        .. "Available: list, detail <id>, invalidate <id>",
      vim.log.levels.WARN
    )
  end
end, {
  nargs = "*",
  desc  = "aws.nvim: CloudFront operations",
  complete = function(arglead, cmdline, _)
    if arglead:sub(1, 1) == "-" then
      local flags = { "--region", "--profile" }
      local out = {}
      for _, f in ipairs(flags) do
        if f:find(arglead, 1, true) == 1 then table.insert(out, f) end
      end
      return out
    end
    local parts = vim.split(cmdline, "%s+", { trimempty = true })
    local positional_count = 0
    for _, p in ipairs(parts) do
      if p:sub(1, 1) ~= "-" then positional_count = positional_count + 1 end
    end
    if positional_count <= 1 or (positional_count == 2 and not cmdline:match("%s$")) then
      local out = {}
      for _, s in ipairs({ "list", "detail", "invalidate" }) do
        if s:find(arglead, 1, true) == 1 then table.insert(out, s) end
      end
      return out
    end
    return {}
  end,
})
