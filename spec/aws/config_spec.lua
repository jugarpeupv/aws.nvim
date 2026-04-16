-- spec/aws/config_spec.lua – unit tests for lua/aws/config.lua
--
-- These tests run inside a headless Neovim via plenary.busted.
-- They exercise pure-Lua logic only; no AWS CLI calls are made.

local config = require("aws.config")

describe("config", function()
  -- Reset config state before every test so tests are independent.
  before_each(function()
    config.setup({})
  end)

  -- ── M.setup ──────────────────────────────────────────────────────────────

  describe("setup()", function()
    it("applies default values when called with no arguments", function()
      config.setup()
      assert.is_nil(config.values.default_aws_profile)
      assert.is_nil(config.values.default_aws_region)
      assert.is_string(config.values.icons.complete)
      assert.is_string(config.values.keymaps.cloudformation.open_resources)
    end)

    it("merges user options over defaults", function()
      config.setup({ default_aws_region = "eu-west-1" })
      assert.equals("eu-west-1", config.values.default_aws_region)
      -- Unrelated defaults must survive the merge
      assert.is_nil(config.values.default_aws_profile)
      assert.equals("<CR>", config.values.keymaps.cloudformation.open_resources)
    end)

    it("allows disabling a keymap by setting it to false", function()
      config.setup({
        keymaps = {
          cloudformation = { delete = false },
        },
      })
      assert.equals(false, config.values.keymaps.cloudformation.delete)
      -- Sibling keys must remain at their defaults
      assert.equals("<CR>", config.values.keymaps.cloudformation.open_resources)
    end)

    it("deep-merges nested icon overrides", function()
      config.setup({ icons = { complete = "OK" } })
      assert.equals("OK", config.values.icons.complete)
      -- Other icons survive
      assert.is_string(config.values.icons.failed)
    end)

    it("is idempotent: calling setup() twice resets to the supplied opts", function()
      config.setup({ default_aws_region = "us-east-1" })
      config.setup({ default_aws_region = "ap-southeast-1" })
      assert.equals("ap-southeast-1", config.values.default_aws_region)
    end)
  end)

  -- ── M.env_overrides ───────────────────────────────────────────────────────

  describe("env_overrides()", function()
    it("returns an empty table when no profile or region is configured", function()
      config.setup({})
      local env = config.env_overrides(nil)
      assert.same({}, env)
    end)

    it("includes AWS_PROFILE when default_aws_profile is set", function()
      config.setup({ default_aws_profile = "my-profile" })
      local env = config.env_overrides(nil)
      assert.equals("my-profile", env["AWS_PROFILE"])
      assert.is_nil(env["AWS_DEFAULT_REGION"])
    end)

    it("includes AWS_DEFAULT_REGION when default_aws_region is set", function()
      config.setup({ default_aws_region = "us-west-2" })
      local env = config.env_overrides(nil)
      assert.equals("us-west-2", env["AWS_DEFAULT_REGION"])
    end)

    it("per-call opts override config defaults", function()
      config.setup({
        default_aws_profile = "default-profile",
        default_aws_region = "eu-west-1",
      })
      local env = config.env_overrides({ profile = "override-profile", region = "ap-east-1" })
      assert.equals("override-profile", env["AWS_PROFILE"])
      assert.equals("ap-east-1", env["AWS_DEFAULT_REGION"])
    end)

    it("per-call region-only override does not force a profile key", function()
      config.setup({})
      local env = config.env_overrides({ region = "sa-east-1" })
      assert.equals("sa-east-1", env["AWS_DEFAULT_REGION"])
      assert.is_nil(env["AWS_PROFILE"])
    end)
  end)

  -- ── M.resolve_profile ─────────────────────────────────────────────────────

  describe("resolve_profile()", function()
    it("returns nil when nothing is configured and env is unset", function()
      config.setup({})
      -- Temporarily clear AWS_PROFILE from the environment if set
      local saved = vim.fn.environ()["AWS_PROFILE"]
      vim.env.AWS_PROFILE = nil
      local result = config.resolve_profile(nil)
      -- Restore
      if saved then
        vim.env.AWS_PROFILE = saved
      end
      assert.is_nil(result)
    end)

    it("returns default_aws_profile from config", function()
      config.setup({ default_aws_profile = "staging" })
      vim.env.AWS_PROFILE = nil
      assert.equals("staging", config.resolve_profile(nil))
    end)

    it("per-call profile takes precedence over config default", function()
      config.setup({ default_aws_profile = "staging" })
      assert.equals("prod", config.resolve_profile({ profile = "prod" }))
    end)
  end)

  -- ── M.identity ────────────────────────────────────────────────────────────

  describe("identity()", function()
    it("returns '<profile>@<region>' when both are set via call_opts", function()
      config.setup({})
      -- Stub resolve_region + resolve_profile so the test is deterministic
      -- (avoids calling `aws configure get region` which requires AWS CLI).
      local orig_resolve_region = config.resolve_region
      local orig_resolve_profile = config.resolve_profile
      config.resolve_region = function()
        return "eu-central-1"
      end
      config.resolve_profile = function()
        return "my-profile"
      end

      local id = config.identity({})

      config.resolve_region = orig_resolve_region
      config.resolve_profile = orig_resolve_profile

      assert.equals("my-profile@eu-central-1", id)
    end)

    it("returns just '<region>' when profile is nil", function()
      config.setup({})
      local orig_resolve_region = config.resolve_region
      local orig_resolve_profile = config.resolve_profile
      config.resolve_region = function()
        return "us-east-1"
      end
      config.resolve_profile = function()
        return nil
      end

      local id = config.identity({})

      config.resolve_region = orig_resolve_region
      config.resolve_profile = orig_resolve_profile

      assert.equals("us-east-1", id)
    end)
  end)
end)
