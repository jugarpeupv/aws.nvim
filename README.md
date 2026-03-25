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

## CloudFormation

### Commands

| Command | Description |
|---|---|
| `:AwsCF list` | Open the stacks list |
| `:AwsCF events <name>` | Open events for a specific stack |
| `:AwsCF delete <name>` | Delete a specific stack (with confirmation) |
| `:AwsCF --region <r> list` | Open stacks in a specific region |
| `:AwsCF --profile <p> list` | Open stacks with a specific profile |

### Stacks buffer (`filetype=aws-cloudformation`)

| Default key | Action |
|---|---|
| `<CR>` | Open resources for the stack under cursor |
| `E` | Open events for the stack under cursor |
| `dd` | Delete the stack under cursor (asks for confirmation) |
| `F` | Filter stacks by name |
| `C` | Clear active filter |
| `R` | Refresh the list |

All keys are configurable via `setup()` (see above).

### Resources buffer (`filetype=aws-cloudformation`)

Opened from the stacks buffer with `<CR>`. Fires two parallel AWS calls
(`list-stack-resources` + `get-template`) and renders the full resource tree.

**CDK stacks** are displayed as a hierarchical construct tree — folder nodes
mirror your CDK construct hierarchy, and leaf lines show `logical_id`,
`AWS::X::Y` type, physical id, and status side by side. Non-CDK stacks fall
back to a flat list. The title shows a `(CDK)` badge when CDK metadata is
detected.

**Folds** are pre-computed from the construct hierarchy, so `zc`/`zo`/`za`
collapse and expand entire CDK construct subtrees. The buffer opens fully
expanded (`foldlevel=99`).

**Highlights:** the `AWS::X::Y` type token uses the `AwsResourceType` highlight
group (linked to `Type` by default). Logical IDs that have a known AWS Console
URL are underlined via the `AwsResourceLink` highlight group.

| Default key | Action |
|---|---|
| `<CR>` | Open resource — `AWS::S3::Bucket` opens the bucket in oil.nvim; `AWS::Logs::LogGroup` opens CloudWatch log streams |
| `E` | Open events for this stack |
| `gx` | Open the AWS Console page for the resource under cursor |
| `R` | Refresh resources |

### Events buffer (`filetype=aws-cloudformation`)

| Default key | Action |
|---|---|
| `R` | Refresh events |

Standard Neovim motions (`gg`, `G`, `/{pattern}`, `n`, `N`, yank, …) work
because output lives in a normal `nofile` buffer.

---

## S3

### Commands

| Command | Description |
|---|---|
| `:AwsS3 list` | Open the buckets list (default when no sub-command given) |
| `:AwsS3 empty <name>` | Empty a bucket (delete all objects, with confirmation) |
| `:AwsS3 delete <name>` | Delete a bucket (bucket must be empty, with confirmation) |
| `:AwsS3 --region <r>` | Open buckets in a specific region |
| `:AwsS3 --profile <p>` | Open buckets with a specific profile |

### Buckets buffer (`filetype=aws-s3`)

| Default key | Action |
|---|---|
| `<CR>` | Open the bucket under cursor in oil.nvim (`oil-s3://`) |
| `de` | Empty the bucket under cursor (asks for confirmation) |
| `dd` | Delete the bucket under cursor (asks for confirmation; bucket must be empty) |
| `F` | Filter buckets by name |
| `C` | Clear active filter |
| `R` | Refresh the list |

All keys are configurable via `setup()` (see above).

Bucket regions are not shown in the list view to keep loading instant.
`list-buckets` returns in a single fast call; no per-bucket API calls are made.

---

## CloudWatch

### Commands

| Command | Description |
|---|---|
| `:AwsCW list` | Open the log groups list (default when no sub-command given) |
| `:AwsCW streams <group>` | Open log streams for a specific log group |
| `:AwsCW logs <group> <stream>` | Open log events for a specific stream |
| `:AwsCW delete <group>` | Delete a log group (with confirmation) |
| `:AwsCW --region <r>` | Open log groups in a specific region |
| `:AwsCW --profile <p>` | Open log groups with a specific profile |

### Log groups buffer (`filetype=aws-cloudwatch`)

| Default key | Action |
|---|---|
| `<CR>` | Open log streams for the group under cursor |
| `dd` | Delete the log group under cursor (asks for confirmation) |
| `F` | Filter log groups by name |
| `C` | Clear active filter |
| `R` | Refresh the list |

The list shows each group's retention policy and stored data size. All pages are
fetched automatically via `nextToken` pagination and rendered incrementally.

### Log streams buffer (`filetype=aws-cloudwatch`)

| Default key | Action |
|---|---|
| `<CR>` | Open log events for the stream under cursor |
| `R` | Refresh the list |

Opens in a vertical split alongside the log groups buffer. Streams are sorted by
last event time (most recent first).

### Log events buffer (`filetype=aws-cloudwatch`)

| Default key | Action |
|---|---|
| `R` | Refresh events |

Opens in a vertical split. Each event is prefixed with its UTC timestamp.
Multi-line messages are indented for readability.

All keys are configurable via `setup()` (see above).

---

## Lambda

### Commands

| Command | Description |
|---|---|
| `:AwsLambda list` | Open the functions list (default when no sub-command given) |
| `:AwsLambda detail <name>` | Open the detail view for a specific function |
| `:AwsLambda delete <name>` | Delete a function (with confirmation) |
| `:AwsLambda --region <r>` | Open functions in a specific region |
| `:AwsLambda --profile <p>` | Open functions with a specific profile |

### Functions buffer (`filetype=aws-lambda`)

| Default key | Action |
|---|---|
| `<CR>` | Open detail view for the function under cursor (vertical split) |
| `L` | Open CloudWatch log streams for the function under cursor |
| `dd` | Delete the function under cursor (asks for confirmation) |
| `F` | Filter functions by name (client-side, no extra API calls) |
| `C` | Clear active filter |
| `R` | Refresh the list |

The list shows each function's runtime, memory allocation, and code size. All
pages are fetched automatically via `Marker`/`NextMarker` pagination and
rendered incrementally as they arrive.

Visual-mode `dd` over a range of lines deletes all selected functions in
sequence after a single confirmation prompt.

### Detail buffer (`filetype=aws-lambda`)

Opened in a vertical split from the functions buffer with `<CR>`. Fetches the
full function configuration via `lambda get-function-configuration` and
displays:

- Runtime, handler, memory, timeout, code size, last modified, role
- Description and architecture (when present)
- VPC ID (when the function is VPC-attached)
- Environment variables (key → value table)
- Layers (full ARNs)
- CloudWatch log group link (`/aws/lambda/<function-name>`)

| Default key | Action |
|---|---|
| `L` | Open CloudWatch log streams for this function |
| `R` | Refresh the configuration |

The Lambda log group is always `/aws/lambda/<function-name>`. Pressing `L`
opens the streams buffer directly in a split without needing to navigate to
`:AwsCW` first.

All keys are configurable via `setup()` (see above).

---

## ACM (Certificate Manager)

### Commands

| Command | Description |
|---|---|
| `:AwsACM list` | Open the certificates list (default when no sub-command given) |
| `:AwsACM detail <arn>` | Open the detail view for a specific certificate |
| `:AwsACM delete <arn>` | Delete a certificate (with confirmation) |
| `:AwsACM --region <r>` | Open certificates in a specific region |
| `:AwsACM --profile <p>` | Open certificates with a specific profile |

### Certificates buffer (`filetype=aws-acm`)

| Default key | Action |
|---|---|
| `<CR>` | Open detail view for the certificate under cursor (vertical split) |
| `dd` | Delete the certificate under cursor (asks for confirmation) |
| `F` | Filter certificates by domain name (client-side, no extra API calls) |
| `C` | Clear active filter |
| `R` | Refresh the list |

The list shows each certificate's domain name, status (with icon), type
(`AMAZON_ISSUED` / `IMPORTED`), and expiry date. All certificate statuses are
shown by default (including `PENDING_VALIDATION`, `EXPIRED`, `REVOKED`, etc.).
All pages are fetched automatically via `NextToken` pagination and rendered
incrementally as they arrive.

Visual-mode `dd` over a range of lines deletes all selected certificates in
sequence after a single confirmation prompt.

### Detail buffer (`filetype=aws-acm`)

Opened in a vertical split from the certificates buffer with `<CR>`. Fetches
full certificate data via `acm describe-certificate` and displays:

- **Identifiers:** full ARN and certificate ID
- **General:** domain, type, status (with icon), key algorithm, creation /
  issuance / expiry dates, renewal eligibility
- **Certificate Details:** subject, issuer, serial number
- **Subject Alternative Names (SANs):** one per line
- **Domain Validation:** per-domain method, validation status, and DNS CNAME
  record (name + value) — useful for copying into your DNS provider
- **In Use By:** ARNs of load balancers, CloudFront distributions, or other
  resources that reference this certificate

| Default key | Action |
|---|---|
| `R` | Refresh the certificate detail |

All keys are configurable via `setup()` (see above).

---

## Secrets Manager

### Commands

| Command | Description |
|---|---|
| `:AwsSM list` | Open the secrets list (default when no sub-command given) |
| `:AwsSM detail <name>` | Open the detail view for a specific secret |
| `:AwsSM delete <name>` | Delete a secret immediately (no 30-day recovery window) |
| `:AwsSM --region <r>` | Open secrets in a specific region |
| `:AwsSM --profile <p>` | Open secrets with a specific profile |

### Secrets buffer (`filetype=aws-secretsmanager`)

| Default key | Action |
|---|---|
| `<CR>` | Open detail view for the secret under cursor (vertical split) |
| `dd` | Delete the secret under cursor (asks for confirmation; **permanent**, no recovery window) |
| `F` | Filter secrets by name (client-side, no extra API calls) |
| `C` | Clear active filter |
| `R` | Refresh the list |

The list shows each secret's name, description (truncated), last changed date,
and last rotated date. All pages are fetched automatically via `NextToken`
pagination and rendered incrementally as they arrive.

Visual-mode `dd` over a range of lines deletes all selected secrets in sequence
after a single confirmation prompt.

> **Warning:** deletion uses `--force-delete-without-recovery`. The secret is
> destroyed immediately with no 30-day recovery window. The confirmation prompt
> makes this explicit.

### Detail buffer (`filetype=aws-secretsmanager`)

Opened in a vertical split from the secrets buffer with `<CR>`. Fetches full
secret metadata via `secretsmanager describe-secret` and displays:

- **Identifiers:** full ARN and name
- **General:** description, created date, last changed, last accessed, last rotated
- **Rotation:** rotation enabled (yes/no), Lambda ARN (if configured), auto-rotate
  interval in days
- **Tags:** key → value table (when any tags are present)
- **Versions:** version IDs with their staging labels (`AWSCURRENT`, `AWSPREVIOUS`, etc.)

| Default key | Action |
|---|---|
| `R` | Refresh the secret detail |
| `gS` | Toggle reveal / hide the secret value |

All keys are configurable via `setup()` (see above).

The **Secret Value** section is always present at the bottom of the detail
buffer. While hidden it shows a hint line. Pressing `gS` calls
`secretsmanager get-secret-value` and injects the result inline:

- **JSON object secrets** are pretty-printed as `key = value` lines, one per
  key, sorted alphabetically — easy to read and yank individual values with
  standard Neovim motions.
- **Plain string secrets** are displayed as-is (multi-line secrets are
  indented).
- **Binary secrets** show a note that they cannot be displayed as text.
- **Access denied** or any other CLI error is shown inline so you can see the
  exact AWS error message without leaving the buffer.

The fetched value is cached for the lifetime of the buffer — toggling hide/show
after the first reveal does not make a second network call. Press `R` (refresh)
to clear the cache and re-fetch both the metadata and the secret value.

---

## CloudFront

### Commands

| Command | Description |
|---|---|
| `:AwsCFront list` | Open the distributions list (default when no sub-command given) |
| `:AwsCFront detail <id>` | Open the detail view for a specific distribution |
| `:AwsCFront invalidate <id>` | Prompt for an invalidation path and create a cache invalidation |
| `:AwsCFront --region <r>` | Open distributions in a specific region |
| `:AwsCFront --profile <p>` | Open distributions with a specific profile |

### Distributions buffer (`filetype=aws-cloudfront`)

| Default key | Action |
|---|---|
| `<CR>` | Open detail view for the distribution under cursor (vertical split) |
| `I` | Prompt for a path and create a cache invalidation |
| `F` | Filter distributions by ID or domain name (client-side, no extra API calls) |
| `C` | Clear active filter |
| `R` | Refresh the list |

The list shows each distribution's ID, domain name, enabled status, first alias
(plus count of additional aliases), and comment. All pages are fetched
automatically via `Marker`/`NextMarker` pagination and rendered incrementally.

> **Note:** CloudFront is a global service. The `--region` flag still applies
> for authentication context (e.g. when using profiles tied to a specific
> region) but the API itself returns all distributions regardless of region.

### Detail buffer (`filetype=aws-cloudfront`)

Opened in a vertical split from the distributions buffer with `<CR>`. Fetches
the full distribution configuration via `cloudfront get-distribution` and
displays:

- **General:** distribution ID, domain name, deploy status, enabled, comment,
  HTTP version, price class, last modified date
- **Aliases (CNAMEs):** all configured alternate domain names
- **Origins:** one sub-block per origin — ID, domain, type (S3 / Custom),
  path prefix; for Custom origins: HTTP/HTTPS port, protocol policy, SSL protocols
- **Default Cache Behaviour:** target origin, viewer protocol policy, allowed
  and cached methods, default/min/max TTLs, compress flag
- **Cache Behaviours:** additional path patterns with their target origin,
  viewer protocol policy, and default TTL
- **SSL / Viewer Certificate:** certificate source (CloudFront default, ACM,
  or IAM), ACM ARN (when applicable), minimum protocol version, SSL support
  method

| Default key | Action |
|---|---|
| `R` | Refresh the distribution detail |
| `I` | Prompt for a path and create a cache invalidation |

Invalidation results are shown as Neovim notifications (not injected into the
buffer). The default path is `/*` — edit to invalidate specific files or
prefixes.

All keys are configurable via `setup()` (see above).

---

## API Gateway

### Commands

| Command | Description |
|---|---|
| `:AwsAGW list` | Open the REST APIs list (default when no sub-command given) |
| `:AwsAGW detail <id>` | Open the detail view for a specific REST API |
| `:AwsAGW --region <r>` | Open APIs in a specific region |
| `:AwsAGW --profile <p>` | Open APIs with a specific profile |

### REST APIs buffer (`filetype=aws-apigateway`)

| Default key | Action |
|---|---|
| `<CR>` | Open detail view for the REST API under cursor (vertical split) |
| `F` | Filter APIs by ID or name (client-side, no extra API calls) |
| `C` | Clear active filter |
| `R` | Refresh the list |

The list shows each API's ID, name, endpoint type (REGIONAL/EDGE/PRIVATE),
creation date, and description (truncated). All pages are fetched automatically
via `position` pagination and rendered incrementally as they arrive.

### Detail buffer (`filetype=aws-apigateway`)

Opened in a vertical split from the REST APIs buffer with `<CR>`. Fires four
parallel AWS CLI calls (`get-rest-api`, `get-stages`, `get-resources`,
`get-authorizers`) and renders:

- **General:** API ID, name, description, creation date, API key source,
  endpoint type(s), tags
- **Stages:** one sub-block per stage — name, deployment ID, created/updated
  dates, caching enabled/size, X-Ray tracing, and stage variables (when any)
- **Resources:** flat list sorted by path — each resource shows its full path,
  then each HTTP method indented with authorization type, integration type, and
  integration URI (truncated)
- **Authorizers:** one sub-block per authorizer — name, type
  (TOKEN/REQUEST/COGNITO_USER_POOLS), identity source, TTL, and Lambda URI

| Default key | Action |
|---|---|
| `R` | Refresh the detail (re-fires all four calls in parallel) |

All keys are configurable via `setup()` (see above).

---

## ECS / Fargate

### Commands

| Command | Description |
|---|---|
| `:AwsECS list` | Open the clusters list (default when no sub-command given) |
| `:AwsECS detail <arn>` | Open the detail view for a specific cluster |
| `:AwsECS --region <r>` | Open clusters in a specific region |
| `:AwsECS --profile <p>` | Open clusters with a specific profile |

### Clusters buffer (`filetype=aws-ecs`)

| Default key | Action |
|---|---|
| `<CR>` | Open detail view for the cluster under cursor (vertical split) |
| `F` | Filter clusters by name (client-side, no extra API calls) |
| `C` | Clear active filter |
| `R` | Refresh the list |

The list shows each cluster's name, status, registered instance count, running
and pending task counts, active service count. All clusters are fetched via
`ecs list-clusters` pagination and then described in a single
`ecs describe-clusters` call with `STATISTICS` included.

### Detail buffer (`filetype=aws-ecs`)

Opened in a vertical split from the clusters buffer with `<CR>`. Fires two
parallel operations (`describe-clusters` for metadata and
`list-services` + `describe-services` for all services) and renders:

- **Cluster:** name, ARN, status, registered instances, running/pending tasks,
  active services, capacity providers, default capacity provider strategy, tags,
  and cluster statistics
- **Services:** tabular list sorted by name — service name, status, launch type
  (EC2 / FARGATE / CAP_PROV), desired / running / pending task counts, and task
  definition name. Active rollout deployments are shown as sub-lines.
  The three most recent service events are included per service.

| Default key | Action |
|---|---|
| `R` | Refresh the cluster detail (re-fires all calls in parallel) |

All keys are configurable via `setup()` (see above).

---

## IAM

### Commands

| Command | Description |
|---|---|
| `:AwsIAM` | Open the IAM service menu (default when no sub-command given) |
| `:AwsIAM list` | Open the IAM service menu |
| `:AwsIAM users` | Open the users list directly |
| `:AwsIAM groups` | Open the groups list directly |
| `:AwsIAM roles` | Open the roles list directly |
| `:AwsIAM policies` | Open the policies list directly |
| `:AwsIAM providers` | Open the identity providers list directly |
| `:AwsIAM detail user <name>` | Open the detail view for a specific user |
| `:AwsIAM detail group <name>` | Open the detail view for a specific group |
| `:AwsIAM detail role <name>` | Open the detail view for a specific role |
| `:AwsIAM detail policy <arn>` | Open the detail view for a specific policy |
| `:AwsIAM detail provider <arn> [oidc\|saml]` | Open the detail view for a specific identity provider |
| `:AwsIAM --region <r>` | Use a specific region |
| `:AwsIAM --profile <p>` | Use a specific profile |

### Menu buffer (`filetype=aws-iam`)

Opened by `:AwsIAM`. Presents a 5-item menu:

```
  1.  Users
  2.  Groups
  3.  Roles
  4.  Policies
  5.  Identity Providers
```

| Default key | Action |
|---|---|
| `<CR>` | Open the list for the resource type under cursor |

### Users buffer (`filetype=aws-iam`)

| Default key | Action |
|---|---|
| `<CR>` | Open detail view for the user under cursor (vertical split) |
| `F` | Filter users by name (client-side) |
| `C` | Clear active filter |
| `R` | Refresh the list |

The list shows each user's name, user ID, path, and creation date. All pages
are fetched automatically via `IsTruncated`/`Marker` pagination and rendered
incrementally.

### Groups buffer (`filetype=aws-iam`)

| Default key | Action |
|---|---|
| `<CR>` | Open detail view for the group under cursor (vertical split) |
| `F` | Filter groups by name (client-side) |
| `C` | Clear active filter |
| `R` | Refresh the list |

### Roles buffer (`filetype=aws-iam`)

| Default key | Action |
|---|---|
| `<CR>` | Open detail view for the role under cursor (vertical split) |
| `F` | Filter roles by name (client-side) |
| `C` | Clear active filter |
| `R` | Refresh the list |

### Policies buffer (`filetype=aws-iam`)

| Default key | Action |
|---|---|
| `<CR>` | Open detail view for the policy under cursor (vertical split) |
| `T` | Toggle scope: `Local` (customer-managed) ↔ `All` (includes AWS-managed) |
| `F` | Filter policies by name (client-side) |
| `C` | Clear active filter |
| `R` | Refresh the list |

Defaults to `Local` scope (customer-managed policies only) to avoid loading
the ~1 000+ AWS-managed policies on every open. Press `T` to include them.
The active scope is shown as a badge in the buffer header.

### Identity Providers buffer (`filetype=aws-iam`)

| Default key | Action |
|---|---|
| `<CR>` | Open detail view for the provider under cursor (vertical split) |
| `R` | Refresh the list |

Lists both OIDC and SAML providers in a single buffer via two parallel API
calls (`list-open-id-connect-providers` + `list-saml-providers`). Each row
shows the provider type (OIDC / SAML) and its full ARN.

### User detail buffer (`filetype=aws-iam`)

Opened in a vertical split. Fires six parallel AWS CLI calls and displays:

- **General:** username, user ID, ARN, path, creation date, password last used
- **Groups:** all groups the user belongs to (name + ARN)
- **Attached Policies:** managed policies attached directly to the user
- **Inline Policies:** names of inline policies embedded on the user
- **Access Keys:** key ID, status (`Active` / `Inactive`), and creation date
- **MFA Devices:** serial number and enable date for each registered MFA device

| Default key | Action |
|---|---|
| `R` | Refresh all sections |

### Group detail buffer (`filetype=aws-iam`)

Fires three parallel calls (`get-group`, `list-attached-group-policies`,
`list-group-policies`) and displays:

- **General:** group name, group ID, ARN, path, creation date
- **Members:** usernames of all IAM users in the group
- **Attached Policies:** managed policies attached to the group
- **Inline Policies:** names of inline policies on the group

| Default key | Action |
|---|---|
| `R` | Refresh all sections |

### Role detail buffer (`filetype=aws-iam`)

Fires three parallel calls (`get-role`, `list-attached-role-policies`,
`list-role-policies`) and displays:

- **General:** role name, role ID, ARN, path, creation date, description,
  max session duration
- **Trust Policy (AssumeRole):** the full `AssumeRolePolicyDocument` rendered
  as pretty-printed, syntax-highlighted JSON
- **Tags:** all tags attached to the role (key → value)
- **Attached Policies:** managed policies attached to the role
- **Inline Policies:** names of inline policies on the role
- **Last Accessed:** per-service last-authentication timestamps and region,
  fetched asynchronously via `generate-service-last-accessed-details` +
  `get-service-last-accessed-details` (polls until the job completes, then
  re-renders the section in place)

| Default key | Action |
|---|---|
| `R` | Refresh all sections |

### Policy detail buffer (`filetype=aws-iam`)

Fires three parallel calls (`get-policy`, `list-policy-versions`,
`list-entities-for-policy`) and displays:

- **General:** policy name, policy ID, ARN, path, description, default version,
  attachment count, creation and update dates
- **Versions:** all policy versions with their version ID, creation date, and a
  `[default]` badge on the active version
- **Attached To:** users, groups, and roles the policy is currently attached to

| Default key | Action |
|---|---|
| `R` | Refresh all sections |

### Provider detail buffer (`filetype=aws-iam`)

#### OIDC

Fetches via `get-open-id-connect-provider` and displays:

- **OIDC Provider:** ARN, creation date
- **Client IDs:** all registered audience values
- **Thumbprints:** all server certificate thumbprints

#### SAML

Fetches via `get-saml-provider` and displays:

- **SAML Provider:** ARN, creation date, valid until date
- **SAML Metadata Document:** first 10 lines of the XML metadata (truncated to
  avoid filling the buffer with a large XML document)

| Default key | Action |
|---|---|
| `R` | Refresh the provider detail |

All keys are configurable via `setup()` (see above).

---

## VPC

### Commands

| Command | Description |
|---|---|
| `:AwsVPC list` | Open the VPCs list (default when no sub-command given) |
| `:AwsVPC detail <vpc-id>` | Open the detail view for a specific VPC |
| `:AwsVPC --region <r>` | Open VPCs in a specific region |
| `:AwsVPC --profile <p>` | Open VPCs with a specific profile |

### VPCs buffer (`filetype=aws-vpc`)

| Default key | Action |
|---|---|
| `<CR>` | Open detail view for the VPC under cursor (vertical split) |
| `F` | Filter VPCs by name or VPC ID (client-side, no extra API calls) |
| `C` | Clear active filter |
| `R` | Refresh the list |

The list shows each VPC's name, VPC ID, state, CIDR block, and whether it is the
default VPC. All pages are fetched automatically via `NextToken` pagination and
rendered incrementally as they arrive.

### Detail buffer (`filetype=aws-vpc`)

Opened in a vertical split from the VPCs buffer with `<CR>`. Fires six parallel
AWS CLI calls and renders:

- **General:** VPC ID, name tag, state, all associated CIDR blocks (primary +
  secondary), default VPC flag, instance tenancy, owner ID, DHCP options ID
- **Tags:** all tags attached to the VPC (sorted alphabetically; `Name` is shown
  in General and omitted here)
- **Subnets:** tabular list sorted by AZ then CIDR — subnet name, subnet ID,
  CIDR, availability zone, available IP count, and whether public IPs are
  automatically assigned on launch
- **Internet Gateways:** IGW ID and name tag for each gateway attached to the VPC
- **NAT Gateways:** NAT gateway ID, state, subnet ID, public IP, and private IP.
  Gateways in `deleted` state are omitted.
- **Route Tables:** each route table with its name/ID, associated subnet IDs
  (or `(main)` for the main route table), and the full routes table — destination
  (CIDR / prefix), target (IGW / NAT GW / transit GW / VPC peering /
  network interface / instance), and route state
- **Security Groups:** tabular list sorted by name — group ID, group name, and
  description

| Default key | Action |
|---|---|
| `<CR>` | Open security group detail for the group under cursor (vertical split) |
| `R` | Refresh all sections (re-fires all six calls in parallel) |

All keys are configurable via `setup()` (see above).

### Security Group detail buffer (`filetype=aws-vpc`)

Opened in a vertical split from the VPC detail buffer with `<CR>` on any row in
the Security Groups section. Fetches full inbound and outbound rules via a single
`ec2 describe-security-groups --group-ids` call and renders:

- **General:** group ID, name, description, VPC ID, owner ID
- **Tags:** all tags attached to the group (sorted alphabetically)
- **Inbound Rules:** protocol, port range, and source for each permission (IPv4
  CIDR, IPv6 CIDR, prefix list ID, or referenced security group)
- **Outbound Rules:** same layout as inbound rules

| Default key | Action |
|---|---|
| `R` | Refresh the security group detail |

All keys are configurable via `setup()` (see above).

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
