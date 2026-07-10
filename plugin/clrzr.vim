" clrzr.vim       Colorize all text in the form #rrggbb or #rgb; entrance
" Licence:        Vim license. See ':help license'
" Maintainer:     Jason Stewart <support@eggplantsd.com>
" Derived From:   https://github.com/lilydjwg/colorizer (lilydjwg <lilydjwg@gmail.com>)
" Derived From:   http://www.vim.org/scripts/script.php?script_id=2150 (css_color.vim)
" Thanks To:      Niklas Hofer (Author of css_color.vim), Ingo Karkat, rykka,
"                 KrzysztofUrban, blueyed, shanesmith, UncleBill
"

" Reload guard and 'compatible' handling
if exists("loaded_clrzr") | finish | endif

if !has('textprop')
  autocmd VimEnter * echomsg 'clrzr disabled: +textprop Vim feature not found'
  finish
endif

if !has('gui_running')
  if !(has('termguicolors') && &termguicolors)
    autocmd VimEnter * echomsg 'clrzr disabled: termguicolors not enabled and/or available'
    finish
  endif
endif

if !exists('##TextChanged')
  autocmd VimEnter * echomsg 'clrzr disabled: TextChanged autocmd not found'
  finish
endif

let loaded_clrzr = 1

let s:save_cpo = &cpo
set cpo&vim

command! ClrzrOn      call clrzr#Enable()
command! ClrzrOff     call clrzr#Disable()
command! ClrzrAposTog call clrzr#AlphaPosToggle()
command! ClrzrRefresh call clrzr#Refresh()

"nnoremap <leader>C :ClrzrOn<CR>
"nnoremap <leader>V :ClrzrOff<CR>
"nnoremap <leader>R :ClrzrRefresh<CR>

if !exists('g:clrzr_startup') || g:clrzr_startup
  call clrzr#Enable()
endif

" Cleanup and modelines {{{1
let &cpo = s:save_cpo
" vim:ft=vim:fdm=marker:fmr={{{,}}}:ts=8:sw=2:sts=2:
