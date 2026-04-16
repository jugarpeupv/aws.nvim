-- spec/aws/buffer_spec.lua – unit tests for lua/aws/buffer.lua
--
-- Exercises buffer creation, content helpers, and window management.
-- All tests run inside headless Neovim via plenary.busted.

local buf_mod = require("aws.buffer")

-- Helper: read all lines from a buffer as a plain Lua table.
local function get_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

-- Helper: delete a buffer created during a test so they don't accumulate.
local function wipe(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

describe("buffer", function()
  -- ── get_or_create ─────────────────────────────────────────────────────────

  describe("get_or_create()", function()
    it("creates a new valid buffer", function()
      local buf = buf_mod.get_or_create("aws://test/new", "aws-test")
      assert.is_number(buf)
      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      wipe(buf)
    end)

    it("returns the same buffer when called twice with the same name", function()
      local buf1 = buf_mod.get_or_create("aws://test/same", "aws-test")
      local buf2 = buf_mod.get_or_create("aws://test/same", "aws-test")
      assert.equals(buf1, buf2)
      wipe(buf1)
    end)

    it("creates a new buffer after the previous one is wiped", function()
      local buf1 = buf_mod.get_or_create("aws://test/wiped", "aws-test")
      vim.api.nvim_buf_delete(buf1, { force = true })
      local buf2 = buf_mod.get_or_create("aws://test/wiped", "aws-test")
      assert.is_true(vim.api.nvim_buf_is_valid(buf2))
      assert.not_equals(buf1, buf2)
      wipe(buf2)
    end)

    it("sets the correct filetype", function()
      local buf = buf_mod.get_or_create("aws://test/ft", "aws-cloudformation")
      assert.equals("aws-cloudformation", vim.bo[buf].filetype)
      wipe(buf)
    end)

    it("sets buftype to 'nofile'", function()
      local buf = buf_mod.get_or_create("aws://test/nofile", "aws-test")
      assert.equals("nofile", vim.bo[buf].buftype)
      wipe(buf)
    end)

    it("sets bufhidden to 'hide'", function()
      local buf = buf_mod.get_or_create("aws://test/hidden", "aws-test")
      assert.equals("hide", vim.bo[buf].bufhidden)
      wipe(buf)
    end)
  end)

  -- ── set_lines ─────────────────────────────────────────────────────────────

  describe("set_lines()", function()
    it("replaces buffer content with the given lines", function()
      local buf = buf_mod.get_or_create("aws://test/setlines", "aws-test")
      buf_mod.set_lines(buf, { "line one", "line two", "line three" })
      assert.same({ "line one", "line two", "line three" }, get_lines(buf))
      wipe(buf)
    end)

    it("replaces existing content on a second call", function()
      local buf = buf_mod.get_or_create("aws://test/replace", "aws-test")
      buf_mod.set_lines(buf, { "old" })
      buf_mod.set_lines(buf, { "new" })
      assert.same({ "new" }, get_lines(buf))
      wipe(buf)
    end)

    it("leaves the buffer non-modifiable after the call", function()
      local buf = buf_mod.get_or_create("aws://test/modifiable", "aws-test")
      buf_mod.set_lines(buf, { "x" })
      assert.is_false(vim.bo[buf].modifiable)
      wipe(buf)
    end)

    it("accepts an empty table (clears the buffer to a single empty line)", function()
      local buf = buf_mod.get_or_create("aws://test/empty", "aws-test")
      buf_mod.set_lines(buf, { "was here" })
      buf_mod.set_lines(buf, {})
      -- nvim_buf_set_lines with {} leaves exactly one empty string line
      local lines = get_lines(buf)
      assert.equals(1, #lines)
      assert.equals("", lines[1])
      wipe(buf)
    end)
  end)

  -- ── set_loading ───────────────────────────────────────────────────────────

  describe("set_loading()", function()
    it("writes a loading placeholder into the buffer", function()
      local buf = buf_mod.get_or_create("aws://test/loading", "aws-test")
      buf_mod.set_loading(buf)
      local lines = get_lines(buf)
      -- Must contain the loading message somewhere
      local found = false
      for _, l in ipairs(lines) do
        if l:find("Loading", 1, true) then
          found = true
          break
        end
      end
      assert.is_true(found)
      wipe(buf)
    end)
  end)

  -- ── set_error ─────────────────────────────────────────────────────────────

  describe("set_error()", function()
    it("writes the [aws error] header followed by indented error lines", function()
      local buf = buf_mod.get_or_create("aws://test/error", "aws-test")
      buf_mod.set_error(buf, { "AccessDenied", "No credentials" })
      local lines = get_lines(buf)

      local has_header = false
      local has_line1 = false
      local has_line2 = false
      for _, l in ipairs(lines) do
        if l:find("[aws error]", 1, true) then
          has_header = true
        end
        if l:find("AccessDenied", 1, true) then
          has_line1 = true
        end
        if l:find("No credentials", 1, true) then
          has_line2 = true
        end
      end
      assert.is_true(has_header)
      assert.is_true(has_line1)
      assert.is_true(has_line2)
      wipe(buf)
    end)

    it("works with an empty error list", function()
      local buf = buf_mod.get_or_create("aws://test/error-empty", "aws-test")
      buf_mod.set_error(buf, {})
      local lines = get_lines(buf)
      local has_header = false
      for _, l in ipairs(lines) do
        if l:find("[aws error]", 1, true) then
          has_header = true
        end
      end
      assert.is_true(has_header)
      wipe(buf)
    end)
  end)

  -- ── find_win ──────────────────────────────────────────────────────────────

  describe("find_win()", function()
    it("returns nil when the buffer is not shown in any window", function()
      local buf = buf_mod.get_or_create("aws://test/no-win", "aws-test")
      assert.is_nil(buf_mod.find_win(buf))
      wipe(buf)
    end)

    it("returns the window id when the buffer is visible", function()
      local buf = buf_mod.get_or_create("aws://test/has-win", "aws-test")
      local win = buf_mod.open_split(buf)
      assert.equals(win, buf_mod.find_win(buf))
      buf_mod.close_split(buf)
      wipe(buf)
    end)
  end)
end)
