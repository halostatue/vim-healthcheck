vim9script

if g:->get('loaded_healthcheck', false)
  finish
endif

g:loaded_healthcheck = true

command -nargs=* -bar CheckHealth health#check([<f-args>])
