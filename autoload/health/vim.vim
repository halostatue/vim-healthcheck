scriptencoding utf-8

import 'health/vim.vim' as vimHealth

function! health#vim#check() abort
  call s:vimHealth.Check()
endfunction
