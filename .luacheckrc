-- .luacheckrc – luacheck configuration for aws.nvim

-- Neovim global APIs available at runtime
globals = {
  "vim",
  "_G",
}

-- busted test globals
std = "min"
files["spec/**/*.lua"] = {
  std = "+busted",
}

-- Ignore long-line warnings for now (stylua enforces column width)
max_line_length = false

-- Common false-positives from module patterns
ignore = {
  "212", -- unused argument (common in callbacks)
  "213", -- unused loop variable
}
