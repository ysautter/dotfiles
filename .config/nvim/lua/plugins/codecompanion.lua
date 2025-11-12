return {
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  opts = {
    strategies = {
      chat = {
        adapter = "ollama",
        model = "gpt-oss",
      },
      inline = {
        adapter = "ollama",
        model = "gpt-oss",
      },
      cmd = {
        adapter = "ollama",
        model = "gpt-oss",
      },
    },
    opts = {
      log_level = "DEBUG",
    },
  },
}
