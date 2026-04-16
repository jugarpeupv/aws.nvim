-- Minimal Neovim init for running tests in CI.
-- Adds the plugin root to runtimepath so `require("aws.*")` resolves,
-- then loads plenary (expected to be cloned into .deps/plenary.nvim).

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

-- Add plugin root to rtp
vim.opt.rtp:prepend(root)

-- Add plenary (cloned by the CI workflow into .deps/)
local plenary_path = root .. "/.deps/plenary.nvim"
vim.opt.rtp:prepend(plenary_path)

-- Disable all default plugins we do not need
vim.opt.loadplugins = false

-- Silence deprecation warnings that clutter test output
vim.deprecate = function() end
