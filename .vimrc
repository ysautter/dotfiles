set runtimepath+=~/.vim_runtime

if empty(glob('~/.vim/autoload/plug.vim'))
   "silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    "\ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
   "autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

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
source ~/.vim_runtime/my_configs.vim

let mapleader = ","
let maplocalleader = ','
" For vim-surround
vmap Si S(i_<esc>f)
au FileType mako vmap Si S"i${ _(<esc>2f"a) }<esc>

let vimDir = '$HOME/.vim'

if stridx(&runtimepath, expand(vimDir)) == -1
  " vimDir is not on runtimepath, add it
  let &runtimepath.=','.vimDir
endif

" Keep undo history across sessions by storing it in a file
if has('persistent_undo')
    let myUndoDir = expand(vimDir . '/undodir')
    " Create dirs
    call system('mkdir ' . vimDir)
    call system('mkdir ' . myUndoDir)
    let &undodir = myUndoDir
    set undofile
endif

set directory^=$HOME/.vim/tmp//
" Change tab to 4 spaces
"setlocal tabstop=8 softtabstop=0 expandtab shiftwidth=4 smarttab
let &t_ut=''
set enc=utf-8
set fileencoding=utf-8
set fileencodings=utf-8,latin1
