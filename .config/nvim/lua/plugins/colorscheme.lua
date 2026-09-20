return {
	{
		"folke/tokyonight.nvim",
		opts = {
			on_highlights = function(highlights, colors)
				highlights.WinSeparator = { fg = colors.blue }
			end,
		},
	},
	{
		"LazyVim/LazyVim",
		opts = { colorscheme = "tokyonight-night" },
	},
}
