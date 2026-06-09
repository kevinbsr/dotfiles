-- Live Server: servidor local + auto-reload no save
-- (equivalente à extensão "Live Server" do VSCode)
return {
  "barrett-ruth/live-server.nvim",
  -- Instala o CLI live-server automaticamente ao instalar o plugin
  build = "npm install -g live-server",
  cmd = { "LiveServerStart", "LiveServerStop" },
  keys = {
    { "<leader>xl", "<cmd>LiveServerStart<cr>", desc = "Live Server: Start" },
    { "<leader>xL", "<cmd>LiveServerStop<cr>", desc = "Live Server: Stop" },
  },
  opts = {},
}
