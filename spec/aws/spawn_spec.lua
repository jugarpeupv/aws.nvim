-- spec/aws/spawn_spec.lua – unit tests for lua/aws/spawn.lua
--
-- spawn.lua wraps vim.loop.spawn to run `aws` CLI commands asynchronously.
-- These tests verify the success and failure paths by spawning real system
-- commands (echo / sh) that are available on any POSIX system, so no actual
-- AWS CLI or credentials are needed.
--
-- The async callback is driven by vim.wait() polling, which pumps the libuv
-- event loop without requiring plenary's async scheduler.

local config = require("aws.config")
local spawn = require("aws.spawn")

-- Helper: block until `predicate()` returns truthy, or time out after 5 s.
local function wait_for(predicate)
  local ok = vim.wait(5000, predicate, 10)
  assert.is_true(ok, "timed out waiting for async callback")
end

describe("spawn", function()
  before_each(function()
    config.setup({})
  end)

  -- ── success path ──────────────────────────────────────────────────────────

  describe("run() – success path", function()
    it("calls the callback with ok=true when the command exits 0", function()
      local called_ok
      local called_lines
      local done = false

      local orig_spawn = vim.loop.spawn
      vim.loop.spawn = function(_, opts, on_exit)
        return orig_spawn("echo", {
          args = { "hello from test" },
          stdio = opts.stdio,
          env = opts.env,
        }, on_exit)
      end

      spawn.run({ "ignored" }, function(ok, lines)
        called_ok = ok
        called_lines = lines
        done = true
      end, nil)

      wait_for(function()
        return done
      end)
      vim.loop.spawn = orig_spawn

      assert.is_true(called_ok)
      assert.is_table(called_lines)
      assert.equals(1, #called_lines)
      assert.equals("hello from test", called_lines[1])
    end)
  end)

  -- ── failure path ──────────────────────────────────────────────────────────

  describe("run() – failure path", function()
    it("calls the callback with ok=false when the command exits non-zero", function()
      local called_ok
      local called_lines
      local done = false

      local orig_spawn = vim.loop.spawn
      vim.loop.spawn = function(_, opts, on_exit)
        return orig_spawn("sh", {
          args = { "-c", "echo 'something went wrong' >&2; exit 1" },
          stdio = opts.stdio,
          env = opts.env,
        }, on_exit)
      end

      spawn.run({ "ignored" }, function(ok, lines)
        called_ok = ok
        called_lines = lines
        done = true
      end, nil)

      wait_for(function()
        return done
      end)
      vim.loop.spawn = orig_spawn

      assert.is_false(called_ok)
      assert.is_table(called_lines)
      assert.equals(1, #called_lines)
      assert.equals("something went wrong", called_lines[1])
    end)
  end)

  -- ── env overrides ─────────────────────────────────────────────────────────

  describe("run() – environment", function()
    it("passes AWS_PROFILE into the subprocess environment when configured", function()
      config.setup({ default_aws_profile = "test-profile" })

      local received_line
      local done = false

      local orig_spawn = vim.loop.spawn
      vim.loop.spawn = function(_, opts, on_exit)
        return orig_spawn("sh", {
          args = { "-c", "echo $AWS_PROFILE" },
          stdio = opts.stdio,
          env = opts.env,
        }, on_exit)
      end

      spawn.run({ "ignored" }, function(_, lines)
        received_line = lines[1]
        done = true
      end, nil)

      wait_for(function()
        return done
      end)
      vim.loop.spawn = orig_spawn

      assert.equals("test-profile", received_line)
    end)
  end)
end)
