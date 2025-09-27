-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

if vim.g.vscode then
  -- Override LazyVim's LSP mappings to use VSCode commands
  vim.keymap.set("n", "grr", function()
    require("vscode").action("editor.action.referenceSearch.trigger")
  end, { desc = "Find references" })

  vim.keymap.set("n", "grt", function()
    require("vscode").action("editor.action.goToTypeDefinition")
  end, { desc = "Go to type definition" })

  vim.keymap.set("n", "gri", function()
    require("vscode").action("editor.action.goToImplementation")
  end, { desc = "Go to implementation" })

  vim.keymap.set("n", "gra", function()
    require("vscode").action("editor.action.quickFix")
  end, { desc = "Code actions" })

  vim.keymap.set("n", "grn", function()
    require("vscode").action("editor.action.rename")
  end, { desc = "Rename symbol" })

  -- Keep the standard ones too
  vim.keymap.set("n", "gd", function()
    require("vscode").action("editor.action.revealDefinition")
  end, { desc = "Go to definition" })

  -- Override LazyVim's window management for VSCode
  vim.keymap.set("n", "<leader>wv", function()
    require("vscode").action("workbench.action.splitEditor")
  end, { desc = "Split window vertically" })

  vim.keymap.set("n", "<leader>ws", function()
    require("vscode").action("workbench.action.splitEditorDown")
  end, { desc = "Split window horizontally" })

  vim.keymap.set("n", "<leader>wd", function()
    require("vscode").action("workbench.action.closeActiveEditor")
  end, { desc = "Delete window" })

  vim.keymap.set("n", "<leader>wo", function()
    require("vscode").action("workbench.action.closeOtherEditors")
  end, { desc = "Delete other windows" })

  -- Navigate between splits
  vim.keymap.set("n", "<C-h>", function()
    require("vscode").action("workbench.action.focusLeftGroup")
  end, { desc = "Go to left window" })

  vim.keymap.set("n", "<C-l>", function()
    require("vscode").action("workbench.action.focusRightGroup")
  end, { desc = "Go to right window" })

  vim.keymap.set("n", "<C-j>", function()
    require("vscode").action("workbench.action.focusBelowGroup")
  end, { desc = "Go to lower window" })

  vim.keymap.set("n", "<C-k>", function()
    require("vscode").action("workbench.action.focusAboveGroup")
  end, { desc = "Go to upper window" })

  vim.keymap.set("n", "]a", function()
    require("vscode").action("editor.action.goToNextSymbol")
  end, { desc = "Goto next start @parameter.inner" })

  vim.keymap.set("n", "[a", function()
    require("vscode").action("editor.action.goToPrevSymbol")
  end, { desc = "Goto prev start @parameter.inner" })

  vim.keymap.set("n", "]A", function()
    require("vscode").action("editor.action.goToNextSymbol")
  end, { desc = "Goto next end @parameter.inner" })

  vim.keymap.set("n", "[A", function()
    require("vscode").action("editor.action.goToPrevSymbol")
  end, { desc = "Goto prev end @parameter.inner" })

  vim.keymap.set("n", "]c", function()
    require("vscode").action("workbench.action.editor.nextChange")
  end, { desc = "Goto next start @class.outer" })

  vim.keymap.set("n", "[c", function()
    require("vscode").action("workbench.action.editor.previousChange")
  end, { desc = "Goto prev start @class.outer" })

  vim.keymap.set("n", "]f", function()
    require("vscode").action("workbench.action.compareEditor.nextChange")
  end, { desc = "Goto next start @function.outer" })

  vim.keymap.set("n", "[f", function()
    require("vscode").action("workbench.action.compareEditor.previousChange")
  end, { desc = "Goto prev start @function.outer" })

  vim.keymap.set("n", "]h", function()
    require("vscode").action("workbench.action.editor.nextChange")
  end, { desc = "Next Hunk" })

  vim.keymap.set("n", "[h", function()
    require("vscode").action("workbench.action.editor.previousChange")
  end, { desc = "Prev Hunk" })

  vim.keymap.set("n", "]]", function()
    require("vscode").action("editor.action.wordHighlight.next")
  end, { desc = "Next Reference" })

  vim.keymap.set("n", "[[", function()
    require("vscode").action("editor.action.wordHighlight.prev")
  end, { desc = "Previous Reference" })

  vim.keymap.set("n", "]b", function()
    require("vscode").action("workbench.action.nextEditor")
  end, { desc = "Next Buffer" })

  vim.keymap.set("n", "[b", function()
    require("vscode").action("workbench.action.previousEditor")
  end, { desc = "Prev Buffer" })

  vim.keymap.set("n", "]d", function()
    require("vscode").action("editor.action.marker.nextInFiles")
  end, { desc = "Next Diagnostic" })

  vim.keymap.set("n", "[d", function()
    require("vscode").action("editor.action.marker.prevInFiles")
  end, { desc = "Prev Diagnostic" })

  vim.keymap.set("n", "]e", function()
    require("vscode").action("editor.action.marker.next")
  end, { desc = "Next Error" })

  vim.keymap.set("n", "[e", function()
    require("vscode").action("editor.action.marker.prev")
  end, { desc = "Prev Error" })

  vim.keymap.set("n", "]w", function()
    require("vscode").action("editor.action.marker.next")
  end, { desc = "Next Warning" })

  vim.keymap.set("n", "[w", function()
    require("vscode").action("editor.action.marker.prev")
  end, { desc = "Prev Warning" })

  vim.keymap.set("n", "]q", function()
    require("vscode").action("workbench.action.quickOpenNavigateNext")
  end, { desc = "Next Trouble/Quickfix Item" })

  vim.keymap.set("n", "[q", function()
    require("vscode").action("workbench.action.quickOpenNavigatePrevious")
  end, { desc = "Prev Trouble/Quickfix Item" })

  vim.keymap.set("n", "]s", function()
    require("vscode").action("editor.action.marker.next")
  end, { desc = "Next misspelled word" })

  vim.keymap.set("n", "[s", function()
    require("vscode").action("editor.action.marker.prev")
  end, { desc = "Prev misspelled word" })

  vim.keymap.set("n", "]t", function()
    require("vscode").action("workbench.action.quickOpenNavigateNext")
  end, { desc = "Next Todo Comment" })

  vim.keymap.set("n", "[t", function()
    require("vscode").action("workbench.action.quickOpenNavigatePrevious")
  end, { desc = "Prev Todo Comment" })
end
