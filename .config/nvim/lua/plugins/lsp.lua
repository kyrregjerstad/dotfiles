return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        tsgo = { enabled = false },
        vtsls = {
          settings = {
            vtsls = {
              autoUseWorkspaceTsdk = true,
            },
          },
        },
      },
    },
  },
}
