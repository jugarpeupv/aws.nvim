# aws.nvim

Manage AWS resources without leaving your editor. aws.nvim brings
CloudFormation stacks, S3 buckets, CloudWatch log groups, and Lambda functions
directly into Neovim buffers — letting you browse, filter, delete, and tail
logs using the same motions and keybindings you already know.

All AWS CLI calls run asynchronously, so the editor never blocks. Output lands
in standard `nofile` buffers, which means `/` search, `gg`/`G`, yank, and
every other built-in motion work out of the box.

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
    └── lambda/
        ├── init.lua                # Lambda public surface
        ├── functions.lua           # List, filter, and render functions (paginated)
        ├── detail.lua              # Function detail viewer (vertical split)
        └── delete.lua              # Async function deletion with confirmation
```

All CLI calls are asynchronous (`vim.loop.spawn`); the editor never blocks
while waiting for AWS responses.
