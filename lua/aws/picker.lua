--- aws.nvim – service picker
--- Opens a fuzzy finder (snacks.nvim > telescope.nvim > vim.ui.select) showing
--- all supported AWS services. Selecting one opens its list buffer with the
--- forwarded call_opts (region / profile).
local M = {}

-------------------------------------------------------------------------------
-- Service registry
-- Each entry: { label, desc, action(call_opts) }
-------------------------------------------------------------------------------

local services = {
  {
    label  = "CloudFormation",
    desc   = "Stacks — browse, inspect resources and events",
    action = function(co) require("aws.cloudformation").list_stacks(co) end,
  },
  {
    label  = "S3",
    desc   = "Buckets — browse, empty, delete",
    action = function(co) require("aws.s3").list_buckets(co) end,
  },
  {
    label  = "CloudWatch",
    desc   = "Log groups → streams → events",
    action = function(co) require("aws.cloudwatch").list_groups(co) end,
  },
  {
    label  = "Lambda",
    desc   = "Functions — detail view, logs, delete",
    action = function(co) require("aws.lambda").list_functions(co) end,
  },
  {
    label  = "ACM",
    desc   = "Certificates — detail view, delete",
    action = function(co) require("aws.acm").list_certificates(co) end,
  },
  {
    label  = "Secrets Manager",
    desc   = "Secrets — detail view, reveal value, delete",
    action = function(co) require("aws.secretsmanager").list_secrets(co) end,
  },
  {
    label  = "CloudFront",
    desc   = "Distributions — detail view, cache invalidation",
    action = function(co) require("aws.cloudfront").list_distributions(co) end,
  },
  {
    label  = "API Gateway",
    desc   = "REST APIs — detail view (stages, resources, authorizers)",
    action = function(co) require("aws.apigateway").list_apis(co) end,
  },
  {
    label  = "ECS / Fargate",
    desc   = "Clusters — detail view (services, deployments, events)",
    action = function(co) require("aws.ecs").list_clusters(co) end,
  },
  {
    label  = "IAM",
    desc   = "Users, groups, roles, policies, identity providers",
    action = function(co) require("aws.iam").open_menu(co) end,
  },
  {
    label  = "VPC",
    desc   = "VPCs — subnets, gateways, route tables, security groups",
    action = function(co) require("aws.vpc").list_vpcs(co) end,
  },
  {
    label  = "DynamoDB",
    desc   = "Tables — scan, query, detail view, delete",
    action = function(co) require("aws.dynamodb").list_tables(co) end,
  },
  {
    label  = "EC2",
    desc   = "Instances — detail view, filter by name/id",
    action = function(co) require("aws.ec2").list_instances(co) end,
  },
}

-------------------------------------------------------------------------------
-- Backend: snacks.nvim
-------------------------------------------------------------------------------

local function open_snacks(call_opts)
  local items = {}
  for _, svc in ipairs(services) do
    table.insert(items, {
      text  = svc.label .. "  " .. svc.desc,  -- searched by snacks
      label = svc.label,
      desc  = svc.desc,
      action = svc.action,
    })
  end

  require("snacks").picker.pick({
    title  = "AWS Services",
    items  = items,
    format = function(item)
      -- two-column display: service label (highlighted) + description
      return {
        { item.label, "Title" },
        { "  " .. item.desc, "Comment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        item.action(call_opts)
      end
    end,
  })
end

-------------------------------------------------------------------------------
-- Backend: telescope.nvim
-------------------------------------------------------------------------------

local function open_telescope(call_opts)
  local pickers    = require("telescope.pickers")
  local finders    = require("telescope.finders")
  local conf       = require("telescope.config").values
  local actions    = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = "AWS Services",
    finder = finders.new_table({
      results = services,
      entry_maker = function(svc)
        return {
          value   = svc,
          display = svc.label .. "  " .. svc.desc,
          ordinal = svc.label .. " " .. svc.desc,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          selection.value.action(call_opts)
        end
      end)
      return true
    end,
  }):find()
end

-------------------------------------------------------------------------------
-- Backend: vim.ui.select (always available)
-------------------------------------------------------------------------------

local function open_select(call_opts)
  local labels = {}
  for _, svc in ipairs(services) do
    table.insert(labels, svc.label .. "  —  " .. svc.desc)
  end

  vim.ui.select(labels, {
    prompt = "AWS service",
    kind   = "aws.nvim",
  }, function(choice, idx)
    if not choice or not idx then return end
    services[idx].action(call_opts)
  end)
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

--- Open the service picker using the best available backend.
--- Priority: snacks.nvim > telescope.nvim > vim.ui.select
---@param call_opts AwsCallOpts|nil
function M.open(call_opts)
  if package.loaded["snacks"] then
    local ok, _ = pcall(open_snacks, call_opts)
    if ok then return end
    -- fall through on error (e.g. snacks version without picker)
  end

  if package.loaded["telescope"] then
    local ok, _ = pcall(open_telescope, call_opts)
    if ok then return end
  end

  open_select(call_opts)
end

return M
