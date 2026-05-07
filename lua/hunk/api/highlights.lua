local M = {}

function M.set_win_hl(winid, highlights)
  vim.api.nvim_set_option_value("winhl", table.concat(highlights, ","), {
    win = winid,
  })
end

local function color_as_hex(color)
  if not color then
    return
  end
  return string.format("#%06x", color)
end

function M.define_highlights()
  local diff_delete_highlight = vim.api.nvim_get_hl(0, {
    name = "DiffDelete",
    link = true,
  })

  vim.api.nvim_set_hl(
    0,
    "HunkDiffAddAsDelete",
    vim.tbl_deep_extend("force", diff_delete_highlight, {
      bg = color_as_hex(diff_delete_highlight.bg),
      fg = color_as_hex(diff_delete_highlight.fg),
      sp = color_as_hex(diff_delete_highlight.sp),
    })
  )

  vim.api.nvim_set_hl(0, "HunkDiffDelete", {
    link = "HunkDiffDeleteDim",
  })

  vim.api.nvim_set_hl(0, "HunkDiffDeleteDim", {
    default = true,
    link = "Comment",
  })

  vim.api.nvim_set_hl(0, "HunkTreeFileAdded", {
    default = true,
    link = "DiagnosticOk",
  })
  vim.api.nvim_set_hl(0, "HunkTreeFileDeleted", {
    default = true,
    link = "DiagnosticError",
  })
  vim.api.nvim_set_hl(0, "HunkTreeFileModified", {
    default = true,
    link = "DiagnosticInfo",
  })

  vim.api.nvim_set_hl(0, "HunkTreeDir", {
    default = true,
    link = "Directory",
  })

  vim.api.nvim_set_hl(0, "HunkTreeDirIcon", {
    default = true,
    link = "Directory",
  })

  vim.api.nvim_set_hl(0, "HunkTreeSelectionIcon", {
    default = true,
    link = "Comment",
  })

  vim.api.nvim_set_hl(0, "HunkSignAdd", {
    default = true,
    link = "DiagnosticOk",
  })

  vim.api.nvim_set_hl(0, "HunkSignDelete", {
    default = true,
    link = "DiagnosticError",
  })
end

return M
