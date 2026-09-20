local function current_repo_name()
	local cwd = vim.uv.cwd()
	if not cwd then
		return nil
	end

	local root = vim.fs.root(cwd, { ".git" }) or cwd
	return root:match("([^/\\]+)$")
end

return {
	{
		"folke/snacks.nvim",
		opts = function(_, opts)
			if current_repo_name() ~= "bitfocus-buttons.kyrre-more-instance-level-auth" then
				return
			end

			opts.dashboard = opts.dashboard or {}
			opts.dashboard.preset = opts.dashboard.preset or {}

			opts.dashboard.preset.header = [[
██████╗ ██╗████████╗███████╗ ██████╗  ██████╗██╗   ██╗███████╗
██╔══██╗██║╚══██╔══╝██╔════╝██╔═══██╗██╔════╝██║   ██║██╔════╝
██████╔╝██║   ██║   █████╗  ██║   ██║██║     ██║   ██║███████╗
██╔══██╗██║   ██║   ██╔══╝  ██║   ██║██║     ██║   ██║╚════██║
██████╔╝██║   ██║   ██║     ╚██████╔╝╚██████╗╚██████╔╝███████║
╚═════╝ ╚═╝   ╚═╝   ╚═╝      ╚═════╝  ╚═════╝ ╚═════╝ ╚══════╝

██████╗ ██╗   ██╗████████╗████████╗ ██████╗ ███╗   ██╗███████╗
██╔══██╗██║   ██║╚══██╔══╝╚══██╔══╝██╔═══██╗████╗  ██║██╔════╝
██████╔╝██║   ██║   ██║      ██║   ██║   ██║██╔██╗ ██║███████╗
██╔══██╗██║   ██║   ██║      ██║   ██║   ██║██║╚██╗██║╚════██║
██████╔╝╚██████╔╝   ██║      ██║   ╚██████╔╝██║ ╚████║███████║
╚═════╝  ╚═════╝    ╚═╝      ╚═╝    ╚═════╝ ╚═╝  ╚═══╝╚══════╝
]]
		end,
	},
}
