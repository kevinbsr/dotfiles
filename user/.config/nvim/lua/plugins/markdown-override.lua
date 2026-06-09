return {
  "mfussenegger/nvim-lint",
  opts = {
    linters = {
      ["markdownlint-cli2"] = {
        -- Força o linter a usar o arquivo global da sua Home, ignorando regras de repositório
        args = { "--config", vim.fn.expand("~/.markdownlint.yaml") },
      },
    },
  },
}
