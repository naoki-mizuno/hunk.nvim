local M = {}

function M.check()
  vim.health.start("hunk.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.error("hunk.nvim requires Neovim >= 0.10")
  end

  local has_nui, _ = pcall(require, "nui.popup")
  if has_nui then
    vim.health.ok("nui.nvim is installed")
  else
    vim.health.error("nui.nvim is not installed (required)", {
      "Install nui.nvim: https://github.com/MunifTanjim/nui.nvim",
    })
  end

  local has_devicons, _ = pcall(require, "nvim-web-devicons")
  if has_devicons then
    vim.health.ok("nvim-web-devicons is installed")
  else
    vim.health.info("nvim-web-devicons is not installed (optional, for file icons)")
  end

  local has_mini_icons, _ = pcall(require, "mini.icons")
  if has_mini_icons then
    vim.health.ok("mini.icons is installed")
  else
    vim.health.info("mini.icons is not installed (optional, for file icons)")
  end
end

return M
