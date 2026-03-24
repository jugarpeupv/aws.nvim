--- aws.nvim – configuration and defaults
local M = {}

---@class AwsKeymapsCF
--- Keymaps active inside the CloudFormation stacks buffer.
--- Set any key to false to disable it.
---@field open_resources string|false  open resources for stack under cursor
---@field open_events    string|false  open events for stack under cursor
---@field delete         string|false  delete stack under cursor
---@field filter         string|false  prompt to filter stacks by name
---@field clear_filter   string|false  clear active filter
---@field refresh        string|false  re-fetch stacks from AWS
---@field close          string|false  close the split window

---@class AwsKeymapsS3
--- Keymaps active inside the S3 buckets buffer.
--- Set any key to false to disable it.
---@field open_bucket  string|false  open bucket under cursor in oil.nvim (oil-s3://)
---@field empty        string|false  empty bucket under cursor
---@field delete       string|false  empty + delete bucket under cursor
---@field filter       string|false  prompt to filter buckets by name
---@field clear_filter string|false  clear active filter
---@field refresh      string|false  re-fetch buckets from AWS
---@field close        string|false  close the split window

---@class AwsKeymapsCW
--- Keymaps active inside CloudWatch buffers.
--- Set any key to false to disable it.
---@field open_streams string|false  open log streams for group under cursor
---@field open_logs    string|false  open log events for stream under cursor
---@field delete       string|false  delete log group under cursor
---@field filter       string|false  prompt to filter by name
---@field clear_filter string|false  clear active filter
---@field refresh      string|false  re-fetch from AWS
---@field close        string|false  close the window

---@class AwsKeymapsLambda
--- Keymaps active inside Lambda buffers.
--- Set any key to false to disable it.
---@field open_detail  string|false  open detail view for function under cursor
---@field open_logs    string|false  open CloudWatch log streams for function under cursor
---@field delete       string|false  delete function under cursor
---@field filter       string|false  prompt to filter functions by name
---@field clear_filter string|false  clear active filter
---@field refresh      string|false  re-fetch from AWS
---@field close        string|false  close the window
---@field detail_logs  string|false  open CW log streams from the detail buffer

---@class AwsKeymapsACM
--- Keymaps active inside ACM (Certificate Manager) buffers.
--- Set any key to false to disable it.
---@field open_detail    string|false  open detail view for certificate under cursor
---@field delete         string|false  delete certificate under cursor
---@field filter         string|false  prompt to filter certificates by domain
---@field clear_filter   string|false  clear active filter
---@field refresh        string|false  re-fetch from AWS
---@field detail_refresh string|false  refresh the detail view

---@class AwsKeymapsSecretsManager
--- Keymaps active inside Secrets Manager buffers.
--- Set any key to false to disable it.
---@field open_detail    string|false  open detail view for secret under cursor
---@field delete         string|false  delete secret under cursor
---@field filter         string|false  prompt to filter secrets by name
---@field clear_filter   string|false  clear active filter
---@field refresh        string|false  re-fetch from AWS
---@field detail_refresh string|false  refresh the detail view
---@field reveal         string|false  toggle reveal/hide secret value in detail view

---@class AwsKeymaps
---@field cloudformation AwsKeymapsCF
---@field s3             AwsKeymapsS3
---@field cloudwatch     AwsKeymapsCW
---@field lambda         AwsKeymapsLambda
---@field acm            AwsKeymapsACM
---@field secretsmanager AwsKeymapsSecretsManager

---@class AwsIcons
---@field stack       string
---@field complete    string
---@field failed      string
---@field in_progress string
---@field deleted     string

---@class AwsConfig
---@field default_aws_profile  string|nil  AWS_PROFILE default (nil = inherit environment)
---@field default_aws_region   string|nil  AWS_DEFAULT_REGION default (nil = inherit environment)
---@field icons    AwsIcons
---@field keymaps  AwsKeymaps
---@class AwsCallOpts
--- Per-call overrides passed to individual commands (e.g. from :AwsCF --region eu-west-1).
--- When set these take precedence over default_aws_profile / default_aws_region.
---@field profile string|nil
---@field region  string|nil

local defaults = {
  -- Auth is delegated to the user; these are optional convenience defaults.
  default_aws_profile = nil,
  default_aws_region  = nil,

  icons = {
    stack       = " ",
    complete    = " ",
    failed      = " ",
    in_progress = " ",
    deleted     = " ",
  },

  keymaps = {
    cloudformation = {
      open_resources = "<CR>",
      open_events    = "E",
      delete         = "dd",
      filter         = "F",
      clear_filter   = "C",
      refresh        = "R",
      close          = "q",
    },
    s3 = {
      open_bucket  = "<CR>",
      empty        = "de",
      delete       = "dd",
      filter       = "F",
      clear_filter = "C",
      refresh      = "R",
      close        = "q",
    },
    cloudwatch = {
      open_streams = "<CR>",
      open_logs    = "<CR>",
      delete       = "dd",
      filter       = "F",
      clear_filter = "C",
      refresh      = "R",
      close        = "q",
    },
    lambda = {
      open_detail  = "<CR>",
      open_logs    = "L",
      delete       = "dd",
      filter       = "F",
      clear_filter = "C",
      refresh      = "R",
      close        = "q",
      detail_logs  = "L",
    },
    acm = {
      open_detail    = "<CR>",
      delete         = "dd",
      filter         = "F",
      clear_filter   = "C",
      refresh        = "R",
      detail_refresh = "R",
    },
    secretsmanager = {
      open_detail    = "<CR>",
      delete         = "dd",
      filter         = "F",
      clear_filter   = "C",
      refresh        = "R",
      detail_refresh = "R",
      reveal         = "gS",
    },
  },
}

M.values = vim.deepcopy(defaults)

--- Merge user options into the active config. Call once from setup().
---@param opts AwsConfig|nil
function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", defaults, opts or {})
end

--- Build a minimal env override table for spawn.lua.
--- Per-call overrides take precedence over the config defaults.
---@param call_opts AwsCallOpts|nil
---@return table<string,string>
function M.env_overrides(call_opts)
  local env = {}
  local profile = (call_opts and call_opts.profile) or M.values.default_aws_profile
  local region  = (call_opts and call_opts.region)  or M.values.default_aws_region
  if profile then env["AWS_PROFILE"]        = profile end
  if region  then env["AWS_DEFAULT_REGION"] = region  end
  return env
end

--- Resolve the effective AWS profile for display purposes.
--- Priority: per-call opts > config default > AWS_PROFILE env var > nil (no display)
---@param call_opts AwsCallOpts|nil
---@return string|nil
function M.resolve_profile(call_opts)
  return (call_opts and call_opts.profile)
    or M.values.default_aws_profile
    or vim.fn.environ()["AWS_PROFILE"]
end

--- Resolve the effective AWS region for display purposes.
--- Priority: per-call opts > config default > AWS_DEFAULT_REGION env var >
---           `aws configure get region` (reads ~/.aws/config) > "unknown"
---@param call_opts AwsCallOpts|nil
---@return string
function M.resolve_region(call_opts)
  local explicit = (call_opts and call_opts.region)
    or M.values.default_aws_region
    or vim.fn.environ()["AWS_DEFAULT_REGION"]
  if explicit then return explicit end

  -- Fall back to reading ~/.aws/config via the CLI (fast, no network call).
  local profile = M.resolve_profile(call_opts)
  local cmd = profile
    and ("aws configure get region --profile " .. vim.fn.shellescape(profile))
    or  "aws configure get region"
  local result = vim.fn.trim(vim.fn.system(cmd))
  if result ~= "" then return result end

  return "unknown"
end

--- Build a short identity string for use in buffer names: "region" or "profile@region".
---@param call_opts AwsCallOpts|nil
---@return string
function M.identity(call_opts)
  local region  = M.resolve_region(call_opts)
  local profile = M.resolve_profile(call_opts)
  if profile then
    return profile .. "@" .. region
  end
  return region
end

return M
