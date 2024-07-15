vim9script

# Clear this and set `g:healthcheck_buffer_cmd` to `tabnew` in order to make this work
# like the original version or the neovim version.

# I have changed this because vim tabs are awful. If both of these are cleared, `topleft
# new` will be executed regardless.
g:healthcheck_buffer_pos = g:->get('healthcheck_buffer_pos', 'topleft')
g:healthcheck_buffer_cmd = g:->get('healthcheck_buffer_command', 'new')

class HealthCheck
  var name: string
  var func: string = null_string
  var type: string = null_string
  var header: string

  def newVim(name: string)
    this.name = name->matchstr('\zs[^\/]*\ze\.vim$')
    this.func = printf('health#%s#check', this.name)
    this.type = 'vim'

    this._SetHeader()
  enddef

  def newLua(name: string)
    this.name = name
      ->substitute('.*lua[\/]\(.\{-}\)[\/]health\([\/]init\)\?\.lua$', '\1', '')
      ->substitute('[\/]', '.', 'g')
    this.func = printf('require("%s.health").check()', this.name)
    this.type = 'lua'

    this._SetHeader()
  enddef

  def newBlank(name: string)
    this.name = name
    this._SetHeader()
  enddef

  def _SetHeader()
    this.header = this.type == null_string ? printf("## %s\n", this.name)
      : printf("## %s: %s\n", this.name, this.func)
  enddef
endclass

class OutputManager
  var _output: dict<list<string>> = {}
  var _checks: dict<HealthCheck>

  def new(checks: dict<HealthCheck>)
    this._checks = checks

    for key in checks->keys()
      this._output[key] = []
    endfor
  enddef

  def StartCheck(name: string)
    this.Clear(name)
  enddef

  def Clear(name: string = null_string)
    this._output[this.Name(name)] = []
  enddef

  def RemoveBlankFirstLine(name: string = null_string)
    var key = this.Name(name)

    if this._output[key]->len() > 0 && this._output[key][0] == ''
      this._output[key]->remove(0)
    endif
  enddef

  def AddTrailingBlankIfRequired(name: string = null_string)
    var key = this.Name(name)

    if this._output[key]->len() > 0 && this._output[key][-1] != ''
      this._output[key]->add('')
    endif
  enddef

  def InsertHeader(name: string, header: string)
    this._output[name]->extend(header->split("\n", 1), 0)
  enddef

  def Add(output: string, name: string = null_string)
    this._output[this.Name(name)]->extend(output->split("\n", 1))
  enddef

  def IsEmpty(name: string = null_string): bool
    return this._output[this.Name(name)]->empty()
  enddef

  def Contents(name: string): list<string>
    return this._output[name]
  enddef

  def Name(name: string = null_string): string
    if name == null_string
      return matchstr(expand('<stack>'), '\vhealth#\i+#check')
        ->substitute('health#', '', '')
        ->substitute('#check', '', '')
    else
      return name
    endif
  enddef
endclass

var om: OutputManager = null_object

def CreateBuffer()
  var cmd = [g:healthcheck_buffer_pos, g:healthcheck_buffer_cmd]
    ->filter('!empty(v:val)')
    ->join(' ')

  if empty(cmd)
    topleft new
  else
    execute cmd
  endif

  setlocal buflisted nomodified nomodeline buftype=nofile bufhidden=hide
  setlocal noswapfile nospell
  setfiletype checkhealth
enddef

def Resolve(plugins: list<string>): dict<HealthCheck>
  var resolved: dict<HealthCheck> = {}

  for candidate in FindCandidates(plugins->empty() ? ['*'] : plugins)
    var name = candidate.name->substitute('-', '_', 'g')
    var item = resolved->get(name, null)

    # Prefer Lua checks over vim
    if item && item.type == 'lua'
      continue
    endif

    if !item || item.type == ''
      resolved[name] = candidate
    endif

  endfor

  var output: dict<HealthCheck> = {}

  for item in resolved->values()
    output[item.name] = item
  endfor

  return output
enddef

def FindCandidates(patterns: list<string>): list<HealthCheck>
  var result: list<HealthCheck> = []

  for pattern in patterns
    var name = pattern
      ->substitute('\.', '/', 'g')
      ->substitute('*$', '**', 'g') # find all submodule e.g vim*

    var paths = GetPluginHealthchecks(name)

    if paths->len() == 0
      result->add(HealthCheck.newBlank(name))
    else
      for path in paths->sort()->uniq()
        if path =~# 'vim$'
          result->add(HealthCheck.newVim(path))
        elseif path =~# 'lua$'
          result->add(HealthCheck.newLua(path))
        else
          result->add(HealthCheck.newBlank(path))
        endif
      endfor
    endif
  endfor

  return result
enddef

def GetPluginHealthchecks(name: string): list<string>
  var result = []
  var patterns = [
    'autoload/health/%s.vim', 'lua/**/%s/health/init.lua', 'lua/**/%s/health.lua'
  ]

  for pattern in patterns
    var globs = globpath(&runtimepath, printf(pattern, name), true, true)

    result->extend(globs)
  endfor

  return result
enddef

def Finish()
  setlocal readonly nospell
  # needed for plasticboy/vim-markdown, because it uses fdm=expr
  normal! zR
  redraw | echo ''
enddef

# Runs the specified healthchecks or all discovered healthchecks if `pluginNames` is
# empty.
export def Check(names: any)
  var pluginNames: list<string> = []

  if names->empty()
    pluginNames = []
  elseif names->type() == v:t_list
    for [idx, name] in names->items()
      if name->type() == v:t_string
        pluginNames->add(name)
      endif

      throw printf('Check names[%d] is not a string: got %s', idx, name->typename())
    endfor
  elseif names->type() == v:t_string
    pluginNames = names->split(' ')
  else
    throw printf('Check names is not a list of string: got %s', names->typename())
  endif

  var checks = Resolve(pluginNames)

  # create report buffer
  CreateBuffer()

  defer Finish()

  if checks->empty()
    setline(1, 'ERROR: No healthchecks found.')
    return
  endif

  redraw | echo 'Running healthchecks...'

  om = OutputManager.new(checks)

  for name in checks->keys()->sort()
    om.StartCheck(name)

    var check = checks[name]

    try
      if check.func == ''
        throw 'healthcheck_not_found'
      endif

      if check.type == 'vim'
        call(check.func, [])
      elseif check.type == 'lua'
        luaeval(check.func)
      else
        throw 'healthcheck_not_found'
      endif

      # In the event the healthcheck doesn't return anything (the plugin
      # author should avoid this possibility)
      if om.IsEmpty(name)
        throw 'healthcheck_no_return_value'
      endif
    catch
      om.Clear(name)

      if v:exception =~# 'healthcheck_not_found'
        Error(printf('No healthcheck found for "%s" plugin.', check.name))
      elseif v:exception =~# 'healthcheck_no_return_value'
        Error(printf('The healthcheck report for "%s" plugin is empty.', check.name))
      else
        Error(printf(
          "Failed to run healthcheck for \"%s\" plugin. Exception:\n%s\n%s",
          check.name, v:throwpoint, v:exception
        ))
      endif
    endtry

    om.RemoveBlankFirstLine(name)
    om.InsertHeader(name, check.header)
    om.Add('', name)

    append('$', om.Contents(name))

    redraw
  endfor

  deletebufline(bufnr(), 1)
enddef

# Indents lines *except* line 1 of a string if it contains newlines.
def IndentAfterLine1(str: string, columns: number): string
  var lines = str->split("\n", 0)

  if lines->len() < 2
    return str
  endif

  for i in range(1, lines->len() - 1) # Indent lines after the first
    lines[i] = lines[i]->substitute('^\s*', repeat(' ', columns), 'g')
  endfor

  return lines->join("\n")
enddef

# Changes ':h clipboard' to ':help |clipboard|'.
def HelpToLink(str: string): string
  return str->substitute('\v:h%[elp] ([^|][^"\r\n ]+)', ':help |\1|', 'g')
enddef

# Format a message for a specific report item.
# extra: Optional advice (string or list)
def FormatReportMessage(status: string, message: string, extra: any = null): string
  var output = printf('  - %s: %s', status, IndentAfterLine1(message, 4))

  if extra->type() == v:t_string || extra->type() == v:t_list
    var advice = extra->type() == v:t_string ? [extra] : extra

    if !advice->empty()
      output ..= "\n    - ADVICE:"
      for suggestion in advice
        output ..= "\n      - " .. IndentAfterLine1(suggestion, 10)
      endfor
    endif
  endif

  return HelpToLink(output)
enddef

# From a path return a list [{name}, {func}, {type}] representing a healthcheck
def FilepathToHealthcheck(path: string): list<string>
  if path =~# 'vim$'
    var name = path->matchstr('\zs[^\/]*\ze\.vim$')

    return [name, 'health#' .. name .. '#check', 'v']
  endif

  var base_path = path->substitute(
    '.*lua[\/]\(.\{-}\)[\/]health\([\/]init\)\?\.lua$', '\1', ''
  )

  var name = base_path->substitute('[\/]', '.', 'g')

  return [name, 'require("' .. name .. '.health").check()', 'l']
enddef

export def Start(name: string)
  om.AddTrailingBlankIfRequired()
  om.Add(printf("### %s\n", name))
enddef

export def Info(message: string)
  om.Add(FormatReportMessage('INFO', message))
enddef

export def Ok(message: string)
  om.Add(FormatReportMessage('OK', message))
enddef

export def Warn(message: string, extra: any = null)
  om.Add(FormatReportMessage('WARN', message, extra))
enddef

export def Error(message: string, extra: any = null)
  om.Add(FormatReportMessage('ERROR', message, extra))
enddef

defcompile
