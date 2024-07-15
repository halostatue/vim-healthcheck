vim9script

const PATH_SEP = has('win32') || has('win64') ? '\' : '/'
const SUGGEST_FAQ = 'https://github.com/neovim/neovim/wiki/FAQ'

# Version transformation: 800 -> 80, 801 -> 81, 1201 -> 121
const SHORTVER = $'{v:version}'[ : -3] .. $'{v:version}'[-1 : ]

class Result
  var _type: string
  var _value: string = null_string

  def newOk(value: string)
    this._type = 'ok'
    this._value = value
  enddef

  def newErr()
    this._type = 'err'
  enddef

  def IsOk(): bool
    return this._type == 'ok'
  enddef

  def IsErr(): bool
    return this._type == 'err'
  enddef

  def Value(): string
    if this._type == 'err'
      throw 'Unable to unwrap Ok from Err value'
    endif

    return this._value
  enddef
endclass

def CheckVimEnv(): bool
  var candidates = [
    [$VIM, 'runtime', 'doc', 'usr_01.txt'],
    [$VIM, 'vim' .. SHORTVER, 'doc', 'usr_01.txt'],
  ]

  for entries in candidates
    if entries->join(PATH_SEP)->filereadable()
      return true
    endif
  endfor

  health#report_error(printf('$VIM is invalid: %s', $VIM), [
    'Read `:help $VIM` and set $VIM properly.',
    'Remove config to set $VIM manually.',
  ])

  return false
enddef

def CheckPaste(): bool
  if &paste
    health#report_error([
      "'paste' is enabled. This option is only for pasting text.",
      'It should not be set in your config.',
    ]->join("\n"), [
      'Remove `set paste` from your vimrc, if applicable.',
      'Check `:verbose set paste?` to see if a plugin or script set the option.',
    ])

    return false
  endif

  return true
enddef

def CheckConfig()
  health#report_start('Configuration')
  if CheckVimEnv() && CheckPaste()
    health#report_ok('no issues found')
  endif
enddef

def System(cmd: string): Result
  var out = system(cmd)

  if v:shell_error
    health#report_error(printf("command failed: %s\n%s", cmd, out))
    return Result.newErr()
  endif

  return Result.newOk(out)
enddef

def GetTmuxOption(option: string): Result
  var result = System(printf('tmux show-option -qvg %s', option))

  if result.IsErr()
    return result
  endif

  if result.Value() =~ '\v^(\s|\t|\r)*$'
    result = System(printf('tmux show-option -qvgs %s', option))

    if result.IsErr()
      return result
    endif
  endif

  return result
enddef

def CheckEscapeTime(): bool
  const suggestions = [
    ['set escape-time in ~/.tmux.conf:', 'set-option -sg escape-time 10']->join("\n"),
    SUGGEST_FAQ
  ]

  health#report_info('Checking escape-time')

  var result = GetTmuxOption('escape-time')

  if result.IsOk()
    var tmux_esc_time = result.Value()

    if tmux_esc_time->empty()
      health#report_error('`escape-time` is not set', suggestions)
    elseif tmux_esc_time->str2nr() > 300
      health#report_error(
        '`escape-time` (' .. tmux_esc_time .. ') is higher than 300ms', suggestions
      )
    else
      health#report_ok('escape-time: ' .. tmux_esc_time)
      return true
    endif
  endif

  return false
enddef

def CheckFocusEvents(): bool
  const suggestions = [
   [
    '(tmux 1.9+ only) Set `focus-events` in ~/.tmux.conf:',
    'set-option -g focus-events on'
   ]->join("\n")
  ]

  health#report_info('Checking focus-events')

  var result = GetTmuxOption('focus-events')

  if result.IsOk()
    var tmux_focus_events = result.Value()

    if tmux_focus_events->empty() || tmux_focus_events !=# 'on'
      health#report_warn("`focus-events` is not enabled. |'autoread'| may not work.",
        suggestions)
    else
      health#report_ok('focus-events: ' .. tmux_focus_events)
      return true
    endif
  endif

  return false
enddef

def CheckDefaultTerminal(): bool
  health#report_info('$TERM: ' .. $TERM)

  var result = GetTmuxOption('default-terminal')

  if result.IsOk()
    var tmux_default_term = result.Value()

    if tmux_default_term !=# $TERM
      health#report_info('default-terminal: ' .. tmux_default_term)
      health#report_error(
        '$TERM differs from the tmux `default-terminal` setting. Colors might look wrong.',
        ['$TERM may have been set by some rc (.bashrc, .zshrc, ...).']
      )
    elseif $TERM !~# '\v(tmux-256color|screen-256color)'
      health#report_error(
        '$TERM should be "screen-256color" or "tmux-256color" in tmux. Colors might look wrong.',
        [
          [
            'Set default-terminal in ~/.tmux.conf:',
            'set-option -g default-terminal "screen-256color"',
          ]->join("\n"),
          SUGGEST_FAQ
        ]
      )
    else
      return true
    endif
  endif

  return false
enddef

def CheckRgb(): bool
  var result = System('tmux server-info')

  if result.IsOk()
    var info = result.Value()
    var has_tc = info->stridx(" Tc: (flag) true") != -1
    var has_rgb = info->stridx(" RGB: (flag) true") != -1

    if has_tc || has_rgb
      return true
    endif

    health#report_warn(
      "Neither Tc nor RGB capability set. True colors are disabled. |'termguicolors'| won't work properly.",
      [
        "Put this in your ~/.tmux.conf and replace XXX by your $TERM outside of tmux:\nset-option -sa terminal-overrides ',XXX:RGB'",
        "For older tmux versions use this instead:\nset-option -ga terminal-overrides ',XXX:Tc'",
      ]
    )
  endif

  return false
enddef

def CheckTmux()
  if empty($TMUX) || !executable('tmux')
    return
  endif

  health#report_start('tmux')

  if CheckEscapeTime() && CheckFocusEvents() && CheckDefaultTerminal() && CheckRgb()
    health#report_ok('no issues found')
  endif
enddef

def CheckPerformance()
  health#report_start('Performance')

  var slow = 1.5
  var start = reltime()

  system('echo')

  var elapsed = start->reltime()->reltimefloat()

  if elapsed > slow
    health#report_warn(printf('Slow shell invocation (took %.2f seconds).', elapsed))
  else
    health#report_ok(printf('`echo` comand took %.2f seconds.', elapsed))
  endif
enddef

export def Check()
  CheckConfig()
  CheckTmux()
  CheckPerformance()
enddef

defcompile
