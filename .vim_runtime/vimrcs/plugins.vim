call plug#begin()
Plug 'nathanaelkane/vim-indent-guides'
Plug 'preservim/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'lervag/vimtex'
let g:tex_flavor='latex'
let g:vimtex_view_method='zathura'
let g:vimtex_quickfix_mode=0
    let g:vimtex_compiler_latexmk = {
        \ 'build_dir' : '',
        \ 'callback' : 1,
        \ 'continuous' : 1,
        \ 'executable' : 'latexmk',
        \ 'hooks' : [],
        \ 'options' : [
        \   '-verbose',
        \   '-file-line-error',
        \   '-synctex=1',
        \   '-interaction=nonstopmode',
        \   '-shell-escape',
        \ ],
        \}
set conceallevel=1
let g:tex_conceal='abdmg'
Plug 'morhetz/gruvbox'
Plug 'sirver/ultisnips'
Plug 'honza/vim-snippets'
let g:UltiSnipsExpandTrigger = '<tab>'
let g:UltiSnipsJumpForwardTrigger = '<tab>'
let g:UltiSnipsJumpBackwardTrigger = '<s-tab>'
Plug 'yuttie/comfortable-motion.vim'
Plug 'tpope/vim-surround'
Plug 'vim-syntastic/syntastic'
Plug 'preservim/nerdcommenter'
Plug 'jiangmiao/auto-pairs'
"Plug 'tpope/vim-fugitive'
Plug 'vim-airline/vim-airline'
  let g:airline_left_sep = ''
  let g:airline_right_sep = ''
Plug 'vim-airline/vim-airline-themes'
Plug 'tpope/vim-dispatch'
Plug 'idanarye/vim-merginal'
Plug 'ervandew/supertab'
" make YCM compatible with UltiSnips (using supertab)
  let g:ycm_key_list_select_completion = ['<C-n>', '<Down>']
  let g:ycm_key_list_previous_completion = ['<C-p>', '<Up>']
  let g:SuperTabDefaultCompletionType = '<C-n>'
Plug 'dpelle/vim-LanguageTool'
Plug 'ycm-core/YouCompleteMe'
Plug 'godlygeek/tabular'
Plug 'preservim/vim-markdown'
  let g:tex_conceal = ""
  let g:vim_markdown_math = 1
  let g:vim_markdown_folding_disabled = 1
"Plug 'plasticboy/vim-markdown'
"Plug 'suan/vim-instant-markdown', {'for': 'markdown', 'do': 'yarn install'}
  "let g:instant_markdown_autostart = 0
  "let g:instant_markdown_mathjax = 1
Plug 'mattn/emmet-vim'
Plug 'christoomey/vim-tmux-navigator'
Plug 'yuezk/vim-js'
Plug 'maxmellon/vim-jsx-pretty'
Plug 'dense-analysis/ale'
"Plug 'vimwiki/vimwiki'
Plug   'KeitaNakamura/tex-conceal.vim', {'for': 'tex'}
Plug 'chrisbra/colorizer'
Plug 'iamcco/markdown-preview.nvim', { 'do': 'cd app && yarn install'  }
Plug 'jyyan/vim-volt-syntax'
Plug 'glench/vim-jinja2-syntax'
Plug 'kshenoy/vim-signature'
call plug#end()

"map <leader>nn :NERDTreeToggle<cr>
"map <leader>nb :NERDTreeFromBookmark<Space>
"map <leader>nf :NERDTreeFind<cr>
