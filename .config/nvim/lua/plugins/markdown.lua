return {
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = function(_, opts)
			opts.formatters_by_ft = opts.formatters_by_ft or {}
			opts.formatters_by_ft.markdown = { "prettier", "markdown-toc" }
			opts.formatters_by_ft["markdown.mdx"] = { "prettier", "markdown-toc" }
		end,
	},
	{
		"mason-org/mason.nvim",
		opts = function(_, opts)
			opts.ensure_installed = vim.tbl_filter(function(tool)
				return tool ~= "markdownlint-cli2"
			end, opts.ensure_installed or {})
		end,
	},
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = function(_, opts)
			opts.linters_by_ft = opts.linters_by_ft or {}
			opts.linters_by_ft.markdown = nil
		end,
	},
}
