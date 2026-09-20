if not vim.g.vscode then
	return {}
end

-- Disable plugins that are useless or broken inside VS Code / Cursor
return {
	{ "nvim-treesitter/nvim-treesitter", enabled = false },
	{ "nvim-treesitter/nvim-treesitter-textobjects", enabled = false },
}
