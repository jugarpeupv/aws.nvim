# aws.nvim

A Neovim plugin for interacting with AWS from the editor.
AWS CLI output is placed into regular Neovim buffers inside horizontal splits,
so all built-in motions, search, and keymaps work out of the box.

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
    stack       = " ",
    complete    = " ",
    failed      = " ",
    in_progress = " ",
    deleted     = " ",
  },

  -- Buffer-local keymaps for each service.
  -- Set any key to false to disable it entirely.
  keymaps = {
    cloudformation = {
      open_events  = "<CR>",   -- open events for stack under cursor
      delete       = "dd",     -- delete stack under cursor
      filter       = "F",      -- prompt to filter stacks by name
      clear_filter = "<C-l>",  -- clear active filter
      refresh      = "r",      -- re-fetch stacks from AWS
      close        = "q",      -- close the split window
    },
    s3 = {
      empty        = "de",     -- empty bucket under cursor (recursive rm)
      delete       = "dd",     -- delete bucket under cursor (must be empty first)
      filter       = "F",      -- prompt to filter buckets by name
      clear_filter = "<C-l>",  -- clear active filter
      refresh      = "r",      -- re-fetch buckets from AWS
      close        = "q",      -- close the split window
    },
    cloudwatch = {
      open_streams = "<CR>",   -- open log streams for group under cursor
      open_logs    = "<CR>",   -- open log events for stream under cursor
      delete       = "dd",     -- delete log group under cursor
      filter       = "F",      -- prompt to filter log groups by name
      clear_filter = "<C-l>",  -- clear active filter
      refresh      = "r",      -- re-fetch from AWS
      close        = "q",      -- close the window
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
| `<CR>` | Open events for the stack under cursor |
| `dd` | Delete the stack under cursor (asks for confirmation) |
| `F` | Filter stacks by name |
| `<C-l>` | Clear active filter |
| `r` | Refresh the list |
| `q` / `<Esc>` | Close the split |

All keys are configurable via `setup()` (see above).

### Events buffer (`filetype=aws-cloudformation`)

| Default key | Action |
|---|---|
| `r` | Refresh events |
| `q` / `<Esc>` | Close the split |

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
| `de` | Empty the bucket under cursor (asks for confirmation) |
| `dd` | Delete the bucket under cursor (asks for confirmation; bucket must be empty) |
| `F` | Filter buckets by name |
| `<C-l>` | Clear active filter |
| `r` | Refresh the list |
| `q` / `<Esc>` | Close the split |

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
| `<C-l>` | Clear active filter |
| `r` | Refresh the list |
| `q` / `<Esc>` | Close the split |

The list shows each group's retention policy and stored data size. All pages are
fetched automatically via `nextToken` pagination and rendered incrementally.

### Log streams buffer (`filetype=aws-cloudwatch`)

| Default key | Action |
|---|---|
| `<CR>` | Open log events for the stream under cursor |
| `r` | Refresh the list |
| `q` / `<Esc>` | Close the split |

Opens in a vertical split alongside the log groups buffer. Streams are sorted by
last event time (most recent first).

### Log events buffer (`filetype=aws-cloudwatch`)

| Default key | Action |
|---|---|
| `r` | Refresh events |
| `q` / `<Esc>` | Close the split |

Opens in a vertical split. Each event is prefixed with its UTC timestamp.
Multi-line messages are indented for readability.

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
    │   ├── events.lua              # Stack events viewer
    │   └── delete.lua              # Async stack deletion with confirmation
    ├── s3/
    │   ├── init.lua                # S3 public surface
    │   ├── buckets.lua             # List, filter, and render buckets
    │   ├── empty.lua               # Async bucket empty with confirmation
    │   └── delete.lua              # Async bucket deletion with confirmation
    └── cloudwatch/
        ├── init.lua                # CloudWatch public surface
        ├── groups.lua              # List, filter, and render log groups (paginated)
        ├── streams.lua             # Log streams viewer (vertical split)
        ├── logs.lua                # Log events viewer (vertical split)
        └── delete.lua              # Async log group deletion with confirmation
```

All CLI calls are asynchronous (`vim.loop.spawn`); the editor never blocks
while waiting for AWS responses.
