# aws.nvim

Manage AWS resources without leaving your editor. aws.nvim brings
CloudFormation stacks, S3 buckets, CloudWatch log groups, Lambda functions,
ACM certificates, Secrets Manager secrets, CloudFront distributions, API
Gateway REST APIs, ECS/Fargate clusters, IAM identities, and VPCs directly
into Neovim buffers — letting you browse, filter, inspect, and delete using
the same motions and keybindings you already know.

All AWS CLI calls run asynchronously, so the editor never blocks. Output lands
in standard `nofile` buffers, which means `/` search, `gg`/`G`, yank, and
every other built-in motion work out of the box.

## Service Picker

Instead of remembering a separate command per service, use `:AwsPicker` to open
a fuzzy finder showing all supported services. Select one to open its list
buffer immediately.

```
:AwsPicker
:AwsPicker --region eu-west-1
:AwsPicker --profile prod
:AwsPicker --profile prod --region us-east-1
```

The picker automatically uses the best available backend:

| Priority | Backend | Requirement |
|---|---|---|
| 1 | snacks.nvim | `folke/snacks.nvim` loaded |
| 2 | Telescope | `nvim-telescope/telescope.nvim` loaded |
| 3 | `vim.ui.select` | always available (works with `dressing.nvim`, `fzf-lua`, etc.) |

**Recommended keymap** (add to your config):

```lua
vim.keymap.set("n", "<leader>aa", "<cmd>AwsPicker<cr>", { desc = "AWS service picker" })
-- or with a fixed profile/region:
vim.keymap.set("n", "<leader>ap", "<cmd>AwsPicker --profile prod<cr>", { desc = "AWS picker (prod)" })
```

Supported services:
- AWS CloudFormation
- AWS CloudWatch
- AWS S3
- AWS Lambda
- AWS ACM (Certificate Manager)
- AWS Secrets Manager
- AWS CloudFront
- AWS API Gateway
- AWS ECS / Fargate
- AWS IAM (Users, Groups, Roles, Policies, Identity Providers)
- AWS VPC (Subnets, Internet/NAT Gateways, Route Tables, Security Groups)
- AWS DynamoDB (Scan, Query)

## Screenshots

### CloudFormation

![CloudFormation stacks buffer](media/aws_cloudformation.png)

### S3

![S3 buckets buffer](media/aws_s3.png)

### CloudWatch

![CloudWatch log groups buffer](media/aws_cloudwatch.png)

## Requirements

| Dependency | Version |
|---|---|
| Neovim | >= 0.9 |
| AWS CLI | v2 recommended |

Authentication is entirely delegated to the user. The plugin assumes the `aws`
binary is on `$PATH` and that credentials are already configured (environment
variables, `~/.aws/credentials`, SSO, IAM role, etc.). If a CLI call fails the
raw stderr output is shown verbatim in the buffer.

## Installation

### lazy.nvim

```lua
{
  "you/aws.nvim",
  config = function()
    require("aws").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "you/aws.nvim",
  config = function()
    require("aws").setup()
  end,
}
```

## Configuration

All options are optional. Call `setup()` with any overrides:

```lua
require("aws").setup({
  -- Default AWS CLI environment overrides applied to every command.
  -- These are used when no per-command --profile / --region flag is given.
  -- Authentication must already be handled by your environment.
  default_aws_profile = nil,   -- sets AWS_PROFILE for every CLI call
  default_aws_region  = nil,   -- sets AWS_DEFAULT_REGION for every CLI call

  -- Status icons (requires a Nerd Font; replace with ASCII if needed)
  icons = {
      stack       = "󰆼 ",
      complete    = "󰱑 ",
      failed      = "󰱞 ",
      in_progress = "󰔟 ",
      deleted     = "󰩺 ",
  },

  -- Buffer-local keymaps for each service.
  -- Set any key to false to disable it entirely.
  keymaps = {
    cloudformation = {
      open_resources = "<CR>",   -- open resources for stack under cursor
      open_events    = "E",      -- open events for stack under cursor
      delete         = "dd",     -- delete stack under cursor
      filter         = "F",      -- prompt to filter stacks by name
      clear_filter   = "C",      -- clear active filter
      refresh        = "R",      -- re-fetch stacks from AWS
    },
    s3 = {
      open_bucket  = "<CR>",   -- open bucket in oil.nvim (oil-s3://)
      empty        = "de",     -- empty bucket under cursor (recursive rm)
      delete       = "dd",     -- delete bucket under cursor (must be empty first)
      filter       = "F",      -- prompt to filter buckets by name
      clear_filter = "C",      -- clear active filter
      refresh      = "R",      -- re-fetch buckets from AWS
    },
    cloudwatch = {
      open_streams = "<CR>",   -- open log streams for group under cursor
      open_logs    = "<CR>",   -- open log events for stream under cursor
      delete       = "dd",     -- delete log group under cursor
      filter       = "F",      -- prompt to filter log groups by name
      clear_filter = "C",      -- clear active filter
      refresh      = "R",      -- re-fetch from AWS
    },
    lambda = {
      open_detail  = "<CR>",   -- open detail view for function under cursor
      open_logs    = "L",      -- open CloudWatch log streams for function
      delete       = "dd",     -- delete function under cursor
      filter       = "F",      -- prompt to filter functions by name
      clear_filter = "C",      -- clear active filter
      refresh      = "R",      -- re-fetch from AWS
      detail_logs  = "L",      -- open CW log streams from the detail buffer
    },
    acm = {
      open_detail    = "<CR>",   -- open detail view for certificate under cursor
      delete         = "dd",     -- delete certificate under cursor
      filter         = "F",      -- prompt to filter certificates by domain
      clear_filter   = "C",      -- clear active filter
      refresh        = "R",      -- re-fetch from AWS
      detail_refresh = "R",      -- refresh the detail view
    },
    secretsmanager = {
      open_detail    = "<CR>",   -- open detail view for secret under cursor
      delete         = "dd",     -- delete secret under cursor (no recovery window)
      filter         = "F",      -- prompt to filter secrets by name
      clear_filter   = "C",      -- clear active filter
      refresh        = "R",      -- re-fetch from AWS
      detail_refresh = "R",      -- refresh the detail view
      reveal         = "gS",     -- toggle reveal/hide secret value in detail view
    },
    cloudfront = {
      open_detail       = "<CR>", -- open detail view for distribution under cursor
      invalidate        = "I",    -- prompt to create a cache invalidation
      filter            = "F",    -- prompt to filter distributions
      clear_filter      = "C",    -- clear active filter
      refresh           = "R",    -- re-fetch from AWS
      detail_refresh    = "R",    -- refresh the detail view
      detail_invalidate = "I",    -- create a cache invalidation from detail buffer
    },
    apigateway = {
      open_detail    = "<CR>", -- open detail view for REST API under cursor
      filter         = "F",    -- prompt to filter APIs by name
      clear_filter   = "C",    -- clear active filter
      refresh        = "R",    -- re-fetch from AWS
      detail_refresh = "R",    -- refresh the detail view
    },
    ecs = {
      open_detail    = "<CR>", -- open detail view for cluster under cursor
      filter         = "F",    -- prompt to filter clusters by name
      clear_filter   = "C",    -- clear active filter
      refresh        = "R",    -- re-fetch from AWS
      detail_refresh = "R",    -- refresh the detail view
    },
    iam = {
      open_detail    = "<CR>", -- open detail / sub-list for item under cursor
      filter         = "F",    -- prompt to filter list by name
      clear_filter   = "C",    -- clear active filter
      refresh        = "R",    -- re-fetch from AWS
      detail_refresh = "R",    -- refresh the detail view
      toggle_scope   = "T",    -- toggle policy scope Local ↔ All (policies list only)
    },
    vpc = {
      open_detail    = "<CR>", -- open detail view for VPC under cursor
      open_sg        = "<CR>", -- open security group detail from VPC detail buffer
      filter         = "F",    -- prompt to filter VPCs by name or ID
      clear_filter   = "C",    -- clear active filter
      refresh        = "R",    -- re-fetch from AWS
      detail_refresh = "R",    -- refresh the detail view
    },
  },
})
```

## Per-command flags

Every `:Aws*` command accepts optional `--region` and `--profile` flags that
override `default_aws_region` / `default_aws_profile` for that single
invocation. The flags can appear anywhere in the argument list.

```
:AwsCF list --region us-east-1
:AwsCF list --profile prod --region eu-west-1
:AwsS3 --region ap-southeast-1
:AwsCW list --profile staging
:AwsLambda list --region eu-west-1
```

Tab-completion is available for both flags and sub-commands.

`:AwsPicker` accepts `--region` and `--profile` too — the selected service
opens with those overrides applied.

---


## Architecture

```
aws.nvim/
├── plugin/aws.lua                  # Entry point – registers :Aws* commands
└── lua/aws/
    ├── init.lua                    # Public API + setup()
    ├── config.lua                  # Defaults and user-config merge
    ├── spawn.lua                   # Async aws CLI runner (vim.loop / libuv)
    ├── buffer.lua                  # Buffer creation and split helpers
    ├── keymaps.lua                 # Configurable buffer-local keymap applier
    ├── picker.lua                  # Service picker (snacks > telescope > vim.ui.select)
    ├── cloudformation/
    │   ├── init.lua                # CloudFormation public surface
    │   ├── stacks.lua              # List, filter, and render stacks
    │   ├── resources.lua           # CDK construct tree + resource list viewer
    │   ├── console_url.lua         # AWS Console URL builder (28 resource types)
    │   ├── events.lua              # Stack events viewer
    │   └── delete.lua              # Async stack deletion with confirmation
    ├── s3/
    │   ├── init.lua                # S3 public surface
    │   ├── buckets.lua             # List, filter, and render buckets
    │   ├── empty.lua               # Async bucket empty with confirmation
    │   └── delete.lua              # Async bucket deletion with confirmation
    ├── cloudwatch/
    │   ├── init.lua                # CloudWatch public surface
    │   ├── groups.lua              # List, filter, and render log groups (paginated)
    │   ├── streams.lua             # Log streams viewer (vertical split)
    │   ├── logs.lua                # Log events viewer (vertical split)
    │   └── delete.lua              # Async log group deletion with confirmation
    ├── lambda/
    │   ├── init.lua                # Lambda public surface
    │   ├── functions.lua           # List, filter, and render functions (paginated)
    │   ├── detail.lua              # Function detail viewer (vertical split)
    │   └── delete.lua              # Async function deletion with confirmation
    ├── acm/
    │   ├── init.lua                # ACM public surface
    │   ├── certificates.lua        # List, filter, and render certificates (paginated)
    │   ├── detail.lua              # Certificate detail viewer (vertical split)
    │   └── delete.lua              # Async certificate deletion with confirmation
    ├── secretsmanager/
    │   ├── init.lua                # Secrets Manager public surface
    │   ├── secrets.lua             # List, filter, and render secrets (paginated)
    │   ├── detail.lua              # Secret detail viewer (vertical split)
    │   └── delete.lua              # Async secret deletion with confirmation (no recovery window)
    ├── cloudfront/
    │   ├── init.lua                # CloudFront public surface
    │   ├── distributions.lua       # List, filter, and render distributions (paginated)
    │   ├── detail.lua              # Distribution detail viewer (vertical split)
    │   └── invalidate.lua          # Async cache invalidation with path prompt
    ├── apigateway/
    │   ├── init.lua                # API Gateway public surface
    │   ├── apis.lua                # List, filter, and render REST APIs (paginated)
    │   └── detail.lua              # REST API detail viewer (parallel fetch, vertical split)
    ├── ecs/
    │   ├── init.lua                # ECS public surface
    │   ├── clusters.lua            # List, filter, and render clusters (paginated)
    │   └── detail.lua              # Cluster detail viewer (services + tasks, parallel fetch)
    └── iam/
        ├── init.lua                # IAM public surface
        ├── menu.lua                # 5-item service menu (Users/Groups/Roles/Policies/Providers)
        ├── users.lua               # List, filter, and render users (paginated)
        ├── groups.lua              # List, filter, and render groups (paginated)
        ├── roles.lua               # List, filter, and render roles (paginated)
        ├── policies.lua            # List, filter, render policies; Local/All scope toggle
        ├── providers.lua           # List OIDC + SAML providers (parallel fetch)
        └── detail/
            ├── user.lua            # User detail (6 parallel calls)
            ├── group.lua           # Group detail (3 parallel calls)
            ├── role.lua            # Role detail (3 parallel calls + async last-accessed job)
            ├── policy.lua          # Policy detail (3 parallel calls)
            └── provider.lua        # OIDC / SAML provider detail
    └── vpc/
        ├── init.lua                # VPC public surface
        ├── vpcs.lua                # List, filter, and render VPCs (paginated)
        └── detail.lua              # VPC detail viewer (6 parallel calls, vertical split)
```

All CLI calls are asynchronous (`vim.loop.spawn`); the editor never blocks
while waiting for AWS responses.
