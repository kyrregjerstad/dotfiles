return {
  "NickvanDyke/opencode.nvim",
  cond = not vim.g.vscode,
  dependencies = {
    -- LazyVim already includes snacks.nvim, so this should be available
    { "folke/snacks.nvim", opts = { input = {}, picker = {} } },
  },
  config = function()
    -- Configuration options
    vim.g.opencode_opts = {
      -- Add any custom configuration here if needed
      -- See lua/opencode/config.lua for all options
    }

    -- Required for auto-reload functionality
    vim.opt.autoread = true

    -- Keymaps (adjust leader key and bindings to your preference)
    local keymap = vim.keymap.set

    keymap({ "n", "x" }, "<leader>oa", function()
      require("opencode").ask("@this: ", { submit = true })
    end, { desc = "Ask about this" })

    keymap({ "n", "x" }, "<leader>os", function()
      require("opencode").select()
    end, { desc = "Select prompt" })

    keymap({ "n", "x" }, "<leader>o+", function()
      require("opencode").prompt("@this")
    end, { desc = "Add this" })

    keymap("n", "<leader>ot", function()
      require("opencode").toggle()
    end, { desc = "Toggle embedded" })

    keymap("n", "<leader>oc", function()
      require("opencode").command()
    end, { desc = "Select command" })

    keymap("n", "<leader>on", function()
      require("opencode").command("session_new")
    end, { desc = "New session" })

    keymap("n", "<leader>oi", function()
      require("opencode").command("session_interrupt")
    end, { desc = "Interrupt session" })

    keymap("n", "<leader>oA", function()
      require("opencode").command("agent_cycle")
    end, { desc = "Cycle selected agent" })

    keymap("n", "<S-C-u>", function()
      require("opencode").command("messages_half_page_up")
    end, { desc = "Messages half page up" })

    keymap("n", "<S-C-d>", function()
      require("opencode").command("messages_half_page_down")
    end, { desc = "Messages half page down" })
  end,
}
