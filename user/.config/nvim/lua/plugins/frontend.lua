-- React / frontend tooling
return {
  -- Auto-close e auto-rename tags JSX/HTML
  {
    "windwp/nvim-ts-autotag",
    event = "InsertEnter",
    opts = {
      opts = {
        enable_close = true,
        enable_rename = true,
        enable_close_on_slash = true,
      },
    },
  },

  -- Emmet para expansão rápida de JSX/HTML
  {
    "olrtg/nvim-emmet",
    keys = {
      { "<leader>xe", "<cmd>lua require('nvim-emmet').wrap_with_abbreviation()<cr>", desc = "Emmet wrap" },
    },
  },

  -- Indentação de 2 espaços para arquivos front-end
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed or {}, {
        "javascript",
        "typescript",
        "tsx",
        "html",
        "css",
        "json",
      })
    end,
  },

  -- Configura prettier como formatter padrão para arquivos front-end
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        javascript = { "prettier" },
        javascriptreact = { "prettier" },
        typescript = { "prettier" },
        typescriptreact = { "prettier" },
        css = { "prettier" },
        html = { "prettier" },
        json = { "prettier" },
      },
    },
  },

  -- LSPs de HTML / CSS / Emmet para web dev vanilla
  -- (Mason instala html-lsp, css-lsp e emmet-language-server automaticamente)
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        html = {},
        cssls = {},
        emmet_language_server = {
          filetypes = { "html", "css", "scss", "javascriptreact", "typescriptreact" },
        },
      },
    },
  },
}
