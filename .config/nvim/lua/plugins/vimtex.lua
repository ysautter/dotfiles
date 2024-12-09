return {
  "lervag/vimtex",
  init = function()
    vim.g.tex_flavor = "latex"
    vim.g.vimtex_view_method = "zathura_simple"
    vim.g.vimtex_compiler_latexmk = {
      aux_dir = "aux",
      out_dir = "target",
      callback = 1,
      continuous = 1,
      executable = "latexmk",
      options = {
        "-lualatex",
        "-verbose",
        "-file-line-error",
        "-synctex=1",
        "-interaction=nonstopmode",
        "-shell-escape",
      },
    }
  end,
}
