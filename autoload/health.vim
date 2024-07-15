scriptencoding utf-8

import 'health.vim'

function! health#check(plugin_names) abort
  call s:health.Check(a:plugin_names)
endfunction

" Starts a new report.
function! health#report_start(name) abort
  call s:health.Start(a:name)
endfunction


" Use {msg} to report information in the current section
function! health#report_info(msg) abort
  call s:health.Info(a:msg)
endfunction

" Reports a successful healthcheck.
function! health#report_ok(msg) abort
  call s:health.Ok(a:msg)
endfunction

" Reports a health warning.
" extra: Optional advice (string or list)
function! health#report_warn(msg, extra = v:null) abort
  call s:health.Warn(a:msg, a:extra || v:null)
endfunction

" Reports a failed healthcheck.
" extra: Optional advice (string or list)
function! health#report_error(msg, extra = v:null) abort
  call s:health.Error(a:msg, a:extra || v:null)
endfunction

defcompile
