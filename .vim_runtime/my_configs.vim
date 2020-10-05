" for making TGMC
au BufEnter ~/Dokumente/tuxguard/TGMC_dev/public/* nnoremap <F4> :Make<CR>

" make YCM compatible with UltiSnips (using supertab)
let g:ycm_key_list_select_completion = ['<C-n>', '<Down>']
let g:ycm_key_list_previous_completion = ['<C-p>', '<Up>']
let g:SuperTabDefaultCompletionType = '<C-n>'

" better key bindings for UltiSnipsExpandTrigger
let g:UltiSnipsExpandTrigger = "<tab>"
let g:UltiSnipsJumpForwardTrigger = "<tab>"
let g:UltiSnipsJumpBackwardTrigger = "<s-tab>"

" enable spell checker for thesis
au BufEnter ~/Dokumente/uni/bachelor/thesis/thesis-master/thesis-master/src/* setlocal spell spelllang=en_us

" reselect pasted text
nnoremap <expr> gp '`[' . strpart(getregtype(), 0, 1) . '`]'

" set language tool
let g:languagetool_jar='$HOME/bin/LanguageTool-4.8/languagetool-commandline.jar'

nnoremap <leader>sw :grep -r ./ -e "<C-R><C-W>"<CR>:cw<CR>
nnoremap <leader>s :grep -r ./ -e 

let g:instant_markdown_autostart = 0
