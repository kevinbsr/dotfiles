return {
  -- 1. Treesitter: usa a API do branch `main` SEM sobrescrever o config do LazyVim
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "php", "phpdoc", "blade" })

      -- Mapeia *.blade.php -> filetype "blade"
      vim.filetype.add({
        pattern = {
          [".*%.blade%.php"] = "blade",
        },
      })

      -- Registra o parser externo do Blade (API nova do branch main)
      require("nvim-treesitter.parsers").blade = {
        install_info = {
          url = "https://github.com/EmranMR/tree-sitter-blade",
          files = { "src/parser.c" },
          branch = "main",
        },
      }
      vim.treesitter.language.register("blade", "blade")
    end,
  },

  -- 2. Conform.nvim: garante SOMENTE pint no PHP (sobrescreve php_cs_fixer da extra)
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.php = { "pint" }
      opts.formatters_by_ft.blade = { "blade-formatter" }
    end,
  },

  -- 3. Mason: provisiona os binários locais
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "pint",
        "blade-formatter",
        "intelephense",
      })
    end,
  },

  -- 4. LSP: Intelephense acoplado ao PHP + Blade
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        intelephense = {
          filetypes = { "php", "blade" },
          settings = {
            intelephense = {
              environment = {
                phpVersion = "8.5",
              },
              files = {
                maxSize = 5000000,
              },
            },
          },
        },
      },
    },
  },

  -- 5. laravel.nvim: experiência tipo IDE (artisan, rotas, make, view finder, etc.)
  {
    "adalessa/laravel.nvim",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "nvim-neotest/nvim-nio",
    },
    ft = { "php", "blade" },
    event = { "BufEnter composer.json" },
    keys = {
      { "<leader>p", "", desc = "+laravel" },
      { "<leader>pp", function() Laravel.pickers.laravel() end, desc = "Laravel: Picker" },
      { "<leader>pa", function() Laravel.pickers.artisan() end, desc = "Laravel: Artisan" },
      { "<leader>pr", function() Laravel.pickers.routes() end, desc = "Laravel: Routes" },
      { "<leader>pm", function() Laravel.pickers.make() end, desc = "Laravel: Make" },
      { "<leader>pc", function() Laravel.pickers.commands() end, desc = "Laravel: Custom Commands" },
      { "<leader>po", function() Laravel.pickers.resources() end, desc = "Laravel: Resources" },
      { "<leader>ph", function() Laravel.run("artisan docs") end, desc = "Laravel: Documentation" },
      { "<leader>pt", function() Laravel.commands.run("actions") end, desc = "Laravel: Code Actions" },
      { "<leader>px", function() Laravel.commands.run("command_center") end, desc = "Laravel: Command Center" },
      { "<c-g>", function() Laravel.commands.run("view:finder") end, desc = "Laravel: View Finder" },
      {
        "gf",
        function()
          if Laravel.app("gf").cursorOnResource() then
            return "<cmd>lua Laravel.commands.run('gf')<cr>"
          end
          return "gf"
        end,
        expr = true,
        noremap = true,
        desc = "Laravel: Go to resource",
      },
    },
    opts = {
      features = {
        pickers = {
          provider = "snacks",
        },
      },
    },
  },
}
