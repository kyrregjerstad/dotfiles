return {
	"folke/sidekick.nvim",
	cond = not vim.g.vscode,
	event = "VeryLazy",
	opts = {
		nes = {
			enabled = false,
		},
		copilot = {
			status = {
				enabled = false,
			},
		},
		cli = {
			mux = {
				backend = "zellij", -- or "tmux" if you prefer
				enabled = false,
			},
			watch = true,
		},
	},
	config = function(_, opts)
		require("sidekick").setup(opts)

		-- We don't use Copilot. Sidekick includes a default Copilot CLI entry,
		-- so remove it after setup to keep it out of Sidekick's tool picker.
		require("sidekick.config").cli.tools.copilot = nil
	end,
	keys = {
		{
			"<c-.>",
			function()
				require("sidekick.cli").focus()
			end,
			mode = { "n", "x", "i", "t" },
			desc = "Sidekick Switch Focus",
		},
		{
			"<leader>aa",
			function()
				require("sidekick.cli").toggle({ focus = true })
			end,
			desc = "Sidekick Toggle CLI",
			mode = { "n", "v" },
		},
		{
			"<leader>ac",
			function()
				require("sidekick.cli").toggle({ name = "claude", focus = true })
			end,
			desc = "Sidekick Claude Toggle",
			mode = { "n", "v" },
		},
		{
			"<leader>ag",
			function()
				require("sidekick.cli").toggle({ name = "grok", focus = true })
			end,
			desc = "Sidekick Grok Toggle",
			mode = { "n", "v" },
		},
		{
			"<leader>ap",
			function()
				require("sidekick.cli").select_prompt()
			end,
			desc = "Sidekick Ask Prompt",
			mode = { "n", "v" },
		},
	},
}
