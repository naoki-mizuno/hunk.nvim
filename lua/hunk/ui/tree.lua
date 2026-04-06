local file_tree_api = require("hunk.api.file_tree")
local config = require("hunk.config")
local utils = require("hunk.utils")

local NuiTree = require("nui.tree")
local NuiPopup = require("nui.popup")
local Text = require("nui.text")
local Line = require("nui.line")

local function get_file_extension(path)
  local extension = path:match("^.+(%..+)$")
  if not extension then
    return ""
  end
  return string.sub(extension, 2) or ""
end

local function get_icon(path)
  if not config.icons.enable_file_icons then
    return nil
  end

  local has_mini_icons, mini_icons = pcall(require, "mini.icons")

  if has_mini_icons then
    return mini_icons.get("file", path)
  end

  local has_web_devicons, web_devicons = pcall(require, "nvim-web-devicons")
  if has_web_devicons then
    return web_devicons.get_icon(path, get_file_extension(path), {})
  end
end

local function get_change_color(prefix, change)
  if change.type == "added" then
    return prefix .. "Added"
  end
  if change.type == "deleted" then
    return prefix .. "Deleted"
  end
  return prefix .. "Modified"
end

local function file_tree_to_nodes(file_tree)
  return vim.tbl_map(function(node)
    local line = {}

    if node.type == "file" then
      local icon, color = get_icon(node.change.filepath)
      if icon then
        table.insert(line, Text(icon .. " ", color))
      end
    end

    local highlight
    if node.type == "dir" then
      highlight = "Green"
    elseif node.type == "file" then
      highlight = get_change_color("HunkTreeFile", node.change)
    else
      error("Unknown node type '" .. node.type .. "'")
    end
    table.insert(line, Text(node.name, highlight))

    local children = file_tree_to_nodes(node.children)

    local ui_node = NuiTree.Node({
      line = line,
      change = node.change,
      children = node.children,
      type = node.type,
    }, children)
    ui_node:expand()
    return ui_node
  end, file_tree)
end

local function find_node_by_filepath(tree, path, nodes)
  nodes = nodes or tree:get_nodes()
  for _, node in pairs(nodes) do
    local children = vim.tbl_map(function(id)
      return tree:get_node(id)
    end, node:get_child_ids())

    local match, match_linenr = find_node_by_filepath(tree, path, children)
    if match then
      return match, match_linenr
    end

    if node.type == "file" then
      local _, linenr = tree:get_node(node:get_id())
      if linenr and node.change.filepath == path then
        return node, linenr
      end
    end
  end
end

local function get_changeset_recursive(node, changeset)
  changeset = changeset or {}

  for _, child in ipairs(node.children) do
    if child.type == "file" then
      table.insert(changeset, child.change)
    else
      get_changeset_recursive(child, changeset)
    end
  end

  return changeset
end

local function get_dir_selection_state(node)
  local all_selected = true
  local at_least_one_selected = false

  local changeset = get_changeset_recursive(node)

  for _, change in ipairs(changeset) do
    if not change.selected then
      all_selected = false
    end
    if change.selected then
      at_least_one_selected = true
    elseif utils.any_lines_selected(change) then
      at_least_one_selected = true
    end
  end

  if all_selected then
    return "all"
  end

  if at_least_one_selected then
    return "partial"
  end

  return "none"
end

local function get_dir_icon(node)
  local state = get_dir_selection_state(node)
  if state == "all" then
    return config.icons.selected
  end

  if state == "partial" then
    return config.icons.partially_selected
  end

  return config.icons.deselected
end

local function get_file_icon(change)
  if change.selected then
    return config.icons.selected
  end

  if utils.any_lines_selected(change) then
    return config.icons.partially_selected
  end

  return config.icons.deselected
end

local function count_tree_nodes(nodes)
  local count = 0
  for _, node in ipairs(nodes) do
    count = count + 1
    if node.children and #node.children > 0 then
      count = count + count_tree_nodes(node.children)
    end
  end
  return count
end

local function compute_tree_width(nodes, depth, icon_widths)
  depth = depth or 1
  if not icon_widths then
    icon_widths = {
      -- max width of expand icon slot (dir: icon + space, file: two spaces)
      expand = math.max(
        vim.fn.strdisplaywidth((config.icons.expanded or "") .. " "),
        vim.fn.strdisplaywidth((config.icons.collapsed or "") .. " "),
        2
      ),
      -- max width of selection icon + trailing space
      selection = math.max(
        vim.fn.strdisplaywidth(config.icons.selected .. " "),
        vim.fn.strdisplaywidth(config.icons.deselected .. " "),
        vim.fn.strdisplaywidth(config.icons.partially_selected .. " ")
      ),
      -- max width of folder icon + trailing space (dirs only)
      folder = math.max(
        vim.fn.strdisplaywidth((config.icons.folder_open or "") .. " "),
        vim.fn.strdisplaywidth((config.icons.folder_closed or "") .. " ")
      ),
      -- file type icon + trailing space (e.g. devicons); 0 when disabled
      file_icon = config.icons.enable_file_icons and 2 or 0,
    }
  end
  local max_width = 0
  for _, node in ipairs(nodes) do
    local is_dir = node.children ~= nil
    local overhead = (depth - 1) * 2
      + icon_widths.expand
      + icon_widths.selection
      + (is_dir and icon_widths.folder or icon_widths.file_icon)
    local w = overhead + vim.fn.strdisplaywidth(node.name)
    if w > max_width then
      max_width = w
    end
    if is_dir and #node.children > 0 then
      local child_max = compute_tree_width(node.children, depth + 1, icon_widths)
      if child_max > max_width then
        max_width = child_max
      end
    end
  end
  return max_width
end

local function resolve_dimension(value, auto_value, max)
  if value == "auto" or value == 0 then
    return auto_value
  elseif value > 0 and value <= 1 then
    return math.max(1, math.floor(max * value))
  else
    return math.floor(value)
  end
end

local function resolve_float_position(pos_cfg, width, border_w, pad)
  -- nui treats position as the content origin; border/padding extend outward.
  local left_extra = border_w + (pad.left or 0)
  local right_extra = border_w + (pad.right or 0)
  local positions = {
    center = { row = "50%", col = "50%" },
    left   = { row = 0, col = left_extra },
    right  = { row = 0, col = math.max(0, vim.o.columns - width - right_extra) },
  }

  local pos = positions[pos_cfg]
  if not pos then
    error("Unknown value '" .. tostring(pos_cfg) .. "' for config entry `ui.tree.float.position`")
  end
  return pos
end

local M = {}

function M.create(opts)
  local is_float = config.ui.tree.use_float

  -- Build the file tree early so auto-width can use it
  local file_tree
  if config.ui.tree.mode == "flat" then
    file_tree = file_tree_api.build_flat_file_tree(opts.changeset)
  elseif config.ui.tree.mode == "nested" then
    file_tree = file_tree_api.build_file_tree(opts.changeset)
  else
    error("Unknown value '" .. config.ui.tree.mode .. "' for config entry `ui.tree.mode`")
  end

  local popup = nil
  local winid = opts.winid

  if is_float then
    local float_cfg = config.ui.tree.float
    local pad = float_cfg.padding or {}
    local border_w = float_cfg.border ~= "none" and 1 or 0
    local padding_w = (pad.left or 0) + (pad.right or 0)
    local border_h = border_w * 2 + (pad.top or 0) + (pad.bottom or 0)
    local tabline_rows = (vim.o.showtabline == 2
      or (vim.o.showtabline == 1 and vim.fn.tabpagenr("$") > 1)) and 1 or 0
    local statusline_rows = vim.o.laststatus > 0 and 1 or 0
    local available_rows = vim.o.lines - vim.o.cmdheight - statusline_rows - tabline_rows
    local float_width = resolve_dimension(
      config.ui.tree.width,
      compute_tree_width(file_tree) + padding_w,
      vim.o.columns - border_w * 2 - padding_w
    )
    local float_height = resolve_dimension(
      float_cfg.height,
      count_tree_nodes(file_tree),
      available_rows - border_h
    )

    popup = NuiPopup({
      enter = true,
      focusable = true,
      border = { style = float_cfg.border, padding = float_cfg.padding },
      relative = "editor",
      position = resolve_float_position(float_cfg.position, float_width, border_w, pad),
      size = { width = float_width, height = float_height },
    })
    popup:mount()
    winid = popup.winid
    -- nui's QuitPre handler calls self:unmount(), which destroys the buffer
    -- backing the NuiTree. Override unmount on this instance so :q behaves
    -- like hide() instead. This keeps nui's BufWinEnter handler intact,
    -- which re-registers WinClosed → hide() after each show().
    function popup:unmount()
      self:hide()
    end
  elseif not winid then
    error("opts.winid is required when use_float is false")
  end

  local tree = NuiTree({
    winid = winid,
    bufnr = vim.api.nvim_win_get_buf(winid),
    nodes = {},

    prepare_node = function(node)
      local line = Line()

      line:append(string.rep("  ", node:get_depth() - 1))

      if node:has_children() then
        if node:is_expanded() then
          local icon = config.icons.expanded or ""
          line:append(icon .. " ", "Comment")
        else
          local icon = config.icons.collapsed or ""
          line:append(icon .. " ", "Comment")
        end
      else
        line:append("  ")
      end

      local selection_icon
      if node.type == "dir" then
        selection_icon = get_dir_icon(node)
      else
        selection_icon = get_file_icon(node.change)
      end

      line:append(selection_icon .. " ", "HunkTreeSelectionIcon")

      if node.type == "dir" then
        local icon = config.icons.folder_closed
        if node:is_expanded() then
          icon = config.icons.folder_open
        end
        line:append(icon .. " ", "HunkTreeDirIcon")
      end

      for _, text in ipairs(node.line) do
        line:append(text)
      end

      return line
    end,
  })

  local buf = vim.api.nvim_win_get_buf(winid)

  local textoff = vim.fn.getwininfo(winid)[1].textoff or 0
  local resolved_width = resolve_dimension(
    config.ui.tree.width,
    compute_tree_width(file_tree) + textoff,
    vim.o.columns
  )

  local Component = {
    buf = buf,
    width = resolved_width,
  }

  function Component.render()
    tree:render()
  end

  if is_float then
    function Component.focus()
      if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
        vim.api.nvim_set_current_win(popup.winid)
      end
    end

    function Component.close()
      if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
        popup:hide()
      end
    end

    function Component.toggle()
      if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
        popup:hide()
      else
        -- Clear stale winid so _open_window() doesn't short-circuit
        popup.winid = nil
        popup:show()
        vim.api.nvim_set_current_win(popup.winid)
      end
    end
  else
    function Component.focus()
      vim.api.nvim_set_current_win(winid)
    end

    function Component.close()
      -- no-op for embedded modes
    end

    function Component.toggle()
      vim.api.nvim_set_current_win(winid)
    end
  end

  local callback_opts = { tree = Component }

  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, {
      buffer = buf,
      desc = desc,
      nowait = true,
    })
  end

  for _, chord in ipairs(utils.into_table(config.keys.tree.open_file)) do
    map("n", chord, function()
      local node = tree:get_node()
      if node and node.type == "file" then
        opts.on_open(node.change, callback_opts)
      end
    end, "Open file under cursor")
  end

  for _, chord in ipairs(utils.into_table(config.keys.tree.expand_node)) do
    map("n", chord, function()
      local node = tree:get_node()
      if not node then
        return
      end
      if node.type == "file" then
        opts.on_preview(node.change, callback_opts)
      end
      if node.type == "dir" and not node:is_expanded() then
        node:expand()
        Component.render()
      end
    end, "Expand or preview node under cursor")
  end

  for _, chord in ipairs(utils.into_table(config.keys.tree.collapse_node)) do
    map("n", chord, function()
      local node = tree:get_node()
      if node and node.type == "dir" and node:is_expanded() then
        node:collapse()
        Component.render()
      end
    end, "Collapse node under cursor")
  end

  for _, chord in ipairs(utils.into_table(config.keys.tree.toggle_file)) do
    map("n", chord, function()
      local node = tree:get_node()
      if node and node.type == "file" then
        opts.on_toggle(node.change, nil, callback_opts)
        return
      end

      local changeset = get_changeset_recursive(node)
      local state = get_dir_selection_state(node)
      for _, change in ipairs(changeset) do
        opts.on_toggle(change, state ~= "all", callback_opts)
      end
    end, "Toggle all hunks in file under cursor")
  end

  config.hooks.on_tree_mount({ buf = buf, tree = tree, opts = opts })

  tree:set_nodes(file_tree_to_nodes(file_tree))
  Component.render()

  local selected_file = file_tree_api.find_first_file_in_tree(file_tree)
  if selected_file then
    local _, selected_linenr = find_node_by_filepath(tree, selected_file.change.filepath)
    if selected_linenr then
      vim.api.nvim_win_set_cursor(winid, { selected_linenr, 0 })
    end

    opts.on_preview(selected_file.change, callback_opts)
  end

  return Component
end

return M
