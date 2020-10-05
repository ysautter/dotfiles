set runtimepath+=~/.vim_runtime

source ~/.vim_runtime/vimrcs/plugins.vim
source ~/.vim_runtime/vimrcs/basic.vim
source ~/.vim_runtime/vimrcs/filetypes.vim
"source ~/.vim_runtime/vimrcs/plugins_config.vim
source ~/.vim_runtime/vimrcs/extended.vim
"source ~/.vim_runtime/vimrcs/snippets.vim
set number relativenumber
set clipboard=unnamedplus
nnoremap k gk
nnoremap j gj
try
	source ~/.vim_runtime/my_configs.vim
catch
endtry
let mapleader = ","
let maplocalleader = ','
" For vim-surround
vmap Si S(i_<esc>f)
au FileType mako vmap Si S"i${ _(<esc>2f"a) }<esc>


set directory^=$HOME/.vim/tmp//
" Change tab to 4 spaces
"setlocal tabstop=8 softtabstop=0 expandtab shiftwidth=4 smarttab
let &t_ut=''
