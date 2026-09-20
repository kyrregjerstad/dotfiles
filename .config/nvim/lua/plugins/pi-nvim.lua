return {
  "carderne/pi-nvim",
  cond = not vim.g.vscode,
  opts = {
    set_default_keymaps = false,
  },
  keys = {
    {
      "<leader>ap",
      "<cmd>Pi<cr>",
      mode = "n",
      desc = "Pi Prompt",
    },
    {
      "<leader>ap",
      ":Pi<cr>",
      mode = "x",
      desc = "Pi Selection",
    },
    {
      "<leader>as",
      "<cmd>PiSessions<cr>",
      desc = "Pi Sessions",
    },
  },
}
