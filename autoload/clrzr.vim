" clrzr.vim     Highlights common color representations
" Licence:	Vim license. See ':help license'
" Maintainer:   Jason Stewart <support@eggplantsd.com>
" Derived From:	https://github.com/lilydjwg/colorizer
"               lilydjwg <lilydjwg@gmail.com>
" Derived From: css_color.vim
" 		http://www.vim.org/scripts/script.php?script_id=2150
" Thanks To:	Niklas Hofer (Author of css_color.vim), Ingo Karkat, rykka,
"		KrzysztofUrban, blueyed, shanesmith, UncleBill

let s:keepcpo = &cpo
set cpo&vim


" TODO: TESTS
" - CTRL-W n for new split
" - open multiple, turn off, turn on
" - N-repeated paste
" - multi-line insert (check textprop count)
" - awk vs unicode.  (line2byte, byte2line?)
" - change colors, or enable/disable, with two views into same buffer to reproduce E966
" TODO: allowed filetypes list?
" TODO: sign_column (bigger pls, :h sign-commands)?
" TODO: color change operation


" ---------------------------  CONSTANTS  ---------------------------


" USAGE: HUE
const s:RXFLT = '%(\d*\.)?\d+'

" USAGE: SAT / LGHTNESS
const s:RXPCT = '%(\d*\.)?\d+\%'

" USAGE: RGB / ALPHA
const s:RXPCTORFLT = '%(\d*\.)?\d+\%?'

" USAGE: PARAM SEPARATOR
const s:CMMA = '\s*,\s*'


" ---------------------------  DEBUG HELPERS  ---------------------------


function! s:WriteDebugBuf(object)

  let nt = type(a:object)
  let sz_msg = ""
  if (nt == v:t_string) || (nt == v:t_float) || (nt == v:t_number)
    let sz_msg = string(a:object)
  else
    let sz_msg = js_encode(a:object)
  endif

  call writefile([sz_msg], "./clrzr.log", "as")

endfunction


" WRITE AUTOCMD EVENTS TO DEBUG BUFFER
function! s:SnoopEvent(evt)
  let n_buf = bufnr()
  if n_buf == 1
    call s:WriteDebugBuf([a:evt, 'BUF', n_buf, 'LN', line('.'), 'CT', b:changedtick])
  endif
endfunction


function! s:Debug(var)
  if 0 | call s:WriteDebugBuf(var) | endif
endfunction


" ---------------------------  COLOR HELPERS  ---------------------------


" GET RGB BACKGROUND COLOR (R,G,B int list)
function! s:RgbBgColor()
  let bg = synIDattr(synIDtrans(hlID("Normal")), "bg")
  if match(bg, '#\x\{6\}') > -1
    return [
      \ str2nr(bg[1:2], 16),
      \ str2nr(bg[3:4], 16),
      \ str2nr(bg[5:6], 16),
    \ ]
  endif
  return []
endfunction


" ALPHA MIX RGBA COLOR INTO RGB BACKGROUND COLOR
" (int lists)
function! s:IntAlphaMix(rgba_fg, rgb_bg)
  if len(a:rgba_fg) < 4
    return a:rgba_fg
  endif

  let fa = a:rgba_fg[3] / 255.0
  let fb = (1.0 - fa)
  let l_blended = map(range(3), {ix, _ -> (a:rgba_fg[ix] * fa) + (a:rgb_bg[ix] * fb)})
  return map(l_blended, {_, v -> float2nr(round(v))})
endfunction


" ---------------------------  COLOR/PATTERN EXTRACTORS  ---------------------------

function! s:IsAlphaFirst()
  let is_alpha_first = get(b:, 'clrzr_hex_alpha_first', get(g:, 'clrzr_hex_alpha_first', 0))
  return (is_alpha_first == 1)
endfunction


" DECONSTRUCTS
" RGB: #00f #0000ff
" RGBA: #00f8 #0000ff88
" or ARGB: #800f #880000ff
" returns [r,g,b,a]
function! s:HexCode(color_text_in) "{{{2

  let rx_color_prefix = '%(#|0x)'
  let is_alpha_first = s:IsAlphaFirst()

  " STRIP HEX PREFIX
  let foundcolor = tolower(substitute(a:color_text_in, '\v' . rx_color_prefix, '', ''))
  let colorlen = len(foundcolor)

  " SPLIT INTO COMPONENT VALUES
  let lColor = [0xff,0xff,0xff,0xff]
  if colorlen == 8

    for ix in [0,1,2,3]
      let ic = ix * 2
      let lColor[ix] = str2nr(foundcolor[ic:(ic+1)], 16)
    endfor

  elseif colorlen == 6

    for ix in [0,1,2]
      let ic = ix * 2
      let lColor[ix] = str2nr(foundcolor[ic:(ic+1)], 16)
    endfor

  elseif colorlen == 4

    for ix in [0,1,2,3]
      let lColor[ix] = str2nr(foundcolor[ix], 16)
      let lColor[ix] = or(lColor[ix], lColor[ix] * 16)
    endfor

  elseif colorlen == 3

    for ix in [0,1,2]
      let lColor[ix] = str2nr(foundcolor[ix], 16)
      let lColor[ix] = or(lColor[ix], lColor[ix] * 16)
    endfor

  endif

  " RGBA/ARGB NORMALIZE
  if is_alpha_first
    let lColor = lColor[1:3] + [lColor[0]]
  endif

  return lColor

endfunction


" DECONSTRUCTS rgb(255,128,64)
" returns [r,g,b,a] with alpha-value = 0xFF
function! s:RgbColor(color_text_in) "{{{2

  " REGEX: COLOR EXTRACT
  let rx_colors = join(map(range(3), {i, _ -> '(' . s:RXFLT . ')(\%?)'}), s:CMMA)

  " EXTRACT COLOR COMPONENTS
  let rgb_matches = matchlist(a:color_text_in, '\v\(\s*' . rx_colors)
  if empty(rgb_matches) | return [] | endif

  " NORMALIZE TO NUMBER
  let lColor = []
  for ix in [1,3,5]

    let c_cmpnt = str2float(rgb_matches[ix])

    if rgb_matches[ix+1] == '%'
      let c_cmpnt = (c_cmpnt * 255.0) / 100.0
    endif

    " SKIP INVALID COLORS
    if (c_cmpnt < 0.0) || (c_cmpnt > 255.0) | return [] | endif

    call add(lColor, float2nr(round(c_cmpnt)))

  endfor

  " ADD ALPHA PLACE HOLDER & RETURN
  call add(lColor, 0xFF)
  return lColor

endfunction


" DECONSTRUCTS: hsl(195, 100%, 50%)
" returns [r,g,b,a] with alpha-value = 0xFF
function! s:HslColor(color_text_in) "{{{2

  " REGEX: COLOR EXTRACT
  let parts = [
        \ '(' . s:RXFLT . ')',
        \ '(' . s:RXFLT . ')\%',
        \ '(' . s:RXFLT . ')\%',
      \ ]

  let rx_colors = '\v\(\s*' . join(parts, s:CMMA)

  " EXTRACT COLOR COMPONENTS
  let hsl_matches = matchlist(a:color_text_in, rx_colors)
  if empty(hsl_matches) | return [] | endif

  " HUE TO NUMBER
  let hue = fmod(str2float(hsl_matches[1]), 360.0)
  if hue < 0.0 | let hue += 360.0 | endif
  let lColor = [hue]

  " SATURATION & LIGHTNESS TO NUMBER
  for ix in [2,3]
    let c_cmpnt = str2float(hsl_matches[ix]) / 100.0
    if (c_cmpnt < 0.0) || (c_cmpnt > 1.0) | return [] | endif
    call add(lColor, c_cmpnt)
  endfor

  " HSL -> RGB
  let chroma = (1.0 - abs((2.0*lColor[2]) - 1.0)) * lColor[1]
  let hprime = hue / 60.0
  let xval = chroma * (1.0 - abs(fmod(hprime,2.0) - 1))
  let mval = lColor[2] - (chroma / 2.0)

  if hprime < 1.0
    let lColor = [chroma, xval, 0.0]
  elseif hprime < 2.0
    let lColor = [xval, chroma, 0.0]
  elseif hprime < 3.0
    let lColor = [0.0, chroma, xval]
  elseif hprime < 4.0
    let lColor = [0.0, xval, chroma]
  elseif hprime < 5.0
    let lColor = [xval, 0.0, chroma]
  elseif hprime < 6.0
    let lColor = [chroma, 0.0, xval]
  endif

  let lColor = map(lColor, {_, v -> float2nr(round((v+mval) * 255.0))})

  " ADD ALPHA PLACE HOLDER & RETURN
  call add(lColor, 0xFF)
  return lColor

endfunction


" HANDLES ALPHA VERSIONS OF RGB/HSL
" returns [r,g,b,a] with alpha-value from Color_Func() call populated
function! s:AlphaColor(Color_Func, color_text_in)

  " GET BASE COLOR
  let lColor = a:Color_Func(a:color_text_in)
  if empty(lColor) | return lColor | endif

  " EXTRACT ALPHA COMPONENT
  let alpha_match = matchlist(a:color_text_in, '\v(' . s:RXPCTORFLT . ')\s*\)')
  if empty(alpha_match) | return lColor | endif
  let alpha_suff = alpha_match[1]

  " PARSE ALPHA TO [0.0, 1.0]
  let ix_pct = match(alpha_suff, '%')
  let alpha = 2.0
  if ix_pct > -1
    let alpha = str2float(alpha_suff[:ix_pct-1]) / 100.0
  else
    let alpha = str2float(alpha_suff)
  endif

  " SKIP COLORS WITH INVALID ALPHA
  if alpha > 1.0 | return [] | endif

  " SCALE TO [0, 255]
  let lColor[3] = float2nr(round(alpha * 255.0))
  return lColor

endfunction


" PLUGIN IS EFFECTIVELY OFF FOR THE CURRENT WINDOW
function! s:IsEnabled()
  return exists('s:clrzr_on') && (s:clrzr_on == 1)
endfunction


function! s:RemoveProps(n_buf, l_first, l_last)

  " ENSURE THAT BUFFER STILL EXISTS
  let l_info = getbufinfo(a:n_buf)
  if empty(l_info) | return 0 | endif

  " REMOVE TEXTPROPS FROM LINES l_first TO l_last
  let firstlast = sort([a:l_first, a:l_last], 'f')
  return prop_remove({
        \ 'bufnr': a:n_buf,
        \ 'id': 777,
        \ 'all': 1,
      \ }, firstlast[0], firstlast[1])

endfunction

" BUILDS TEXTPROPS (COLORS+PATTERNS) FOR THE CURRENT BUFFER
function! s:RebuildTextProps(bufinfo, l_first, l_last)

  if (!s:IsEnabled() || empty(a:bufinfo)) | return | endif

  " SKIP UNLOADED AND/OR UNLISTED BUFFERS
  if !(a:bufinfo.loaded) || !(a:bufinfo.listed)
    return
  endif

  let n_buf = a:bufinfo.bufnr

  " SKIP PROCESSING HELPFILES (usually large)
  if getbufvar(n_buf, '&syntax') ==? 'help' | return | endif

  " GET LINE PROCESSING RANGE
  let l_range = sort([a:l_first, a:l_last], 'f')

  " ONLY PARSE UP TO g:clrzr_maxlines
  let n_maxlines = get(g:, 'clrzr_maxlines', -1)
  if type(n_maxlines) != v:t_number | let n_maxlines = -1 | endif
  if n_maxlines > 0
    if l_range[0] > n_maxlines | return | endif
    if l_range[1] > n_maxlines | let l_range[1] = n_maxlines | endif
  endif

  " GET LINES FROM CURRENT BUFFER
  let lines = getbufline(n_buf, l_range[0], l_range[1])
  if empty(lines) | return | endif

  " CACHE CURRENT BACKGROUND COLOR FOR ALPHA BLENDING
  let s:rgb_bg = s:RgbBgColor()

  " WRITE LINES TO AWK CHANNEL
  if !exists('s:awk_chan')
    echoerr "AWK CHANNEL NOT SET!"
    return
  endif

  let sts = ch_status(s:awk_chan)
  if sts != 'open'
    echoerr "AWK CHANNEL STATUS = " . sts
    return
  endif

  let meta = [n_buf, l_range[0], l_range[1]]

  call ch_sendraw(s:awk_chan, join(meta, "\t") . "\t--begin--\n")

  for line in lines
    call ch_sendraw(s:awk_chan, join(meta, "\t") . "\t" . line . "\n")
    let meta[1] += 1
  endfor

  let meta[1] = meta[2]
  call ch_sendraw(s:awk_chan, join(meta, "\t") . "\t--end--\n")

endfunction


function! s:UnHlAlpha(text, n_col, n_length)

  let l_col = a:n_col
  let l_len = a:n_length

  if a:text[0] == '#' || a:text[0] == '0'

    let ix_hex = match(a:text, '\v\x+')
    if ix_hex > -1

      let af = s:IsAlphaFirst()
      let sz_hex = a:text[ix_hex:]

      if len(sz_hex) == 8
        let l_len -= af ? ix_hex + 2 : 2
        let l_col += af ? ix_hex + 2 : 0
      elseif len(sz_hex) == 4
        let l_len -= af ? ix_hex + 1 : 1
        let l_col += af ? ix_hex + 1 : 0
      endif
    endif

  elseif (a:text[0:3] ==# 'rgba') || (a:text[0:3] ==# 'hsla')

    let ix_tail = match(a:text, '\v,[^,]*\)')
    if ix_tail > -1 | let l_len = ix_tail | endif

  endif

  return [l_col, l_len]

endfunction


" EXTRACTS COLOR DATA FROM MATCHES & CREATES HIGHLIGHT GROUPS
" NOTE: this is a callback, & doesn't seem to play well with
" typical local state variables like w: & b:.  that is why buffer
" props are set/read explicitly (with a bufnr reference) &
" metadata like bufnr & line are passed through awk
function! s:ProcessMatch(match)

  if !s:IsEnabled() | return | endif

  " EXTRACT SOURCE INFORMATION FROM AWK OUTPUT
  let lParts = split(a:match, '|')
  if len(lParts) < 5 | return | endif
  let [n_buf, n_line, n_col, n_length] = map(lParts[0:3], {_,v -> str2nr(trim(v))})

  if n_buf < 0
    echoerr 'INVALID BUF'
    return
  endif

  " NOTE: for --begin--, n_line is firstline#, n_length is lastline#
  if lParts[4] == '--begin--'

    " CLEAR PROPS FOR UPDATE RANGE
    call s:RemoveProps(n_buf, n_line, n_length)
    return

  " NOTE: for --end--, n_line is lastline#, n_length is lastline#
  elseif lParts[4] == '--end--'

    " NOTE: can do end-of-batch work here if needed
    return

  endif

  " EXTRACT COLOR INFORMATION FROM SYNTAX
  " returns [r,g,b,a] lists
  " RETURNS [syntax_pattern, rgb_color_list]
  let color_text = lParts[4]
  let rgba_color = []
  if color_text[0] == '#' || color_text[0] == '0'
    let rgba_color = s:HexCode(color_text)
  elseif color_text[0:3] ==# 'rgba'
    let rgba_color = s:AlphaColor(function('s:RgbColor'), color_text)
  elseif color_text[0:3] ==# 'hsla'
    let rgba_color = s:AlphaColor(function('s:HslColor'), color_text)
  elseif color_text[0:2] ==# 'rgb'
    let rgba_color = s:RgbColor(color_text)
  elseif color_text[0:2] ==# 'hsl'
    let rgba_color = s:HslColor(color_text)
  else
    return
  endif

  " SKIP INVALID COLORS
  if empty(rgba_color) | return | endif

  let rgb_color = rgba_color[0:2]
  if rgba_color[3] < 0xFF
    if empty(s:rgb_bg)
      " TRIM ALPHA COMPONENT IF BG COLOR IS UNKNOWN
      let [n_col, n_length] = s:UnHlAlpha(color_text, n_col, n_length)
    else
      " ALPHA-BLEND TRANSPARENCIES
      let rgb_color = s:IntAlphaMix(rgba_color, s:rgb_bg)
    endif
  endif

  " NOTE: text properties are per-buffer `text-prop-intro`

  " CHECK IF TEXTPROP GROUP EXISTS
  " NOTE: key by full RGBA, so as not to create new groups
  "       on :colorscheme change
  let group = 'Czr' . call('printf', ['%02x%02x%02x%02x'] + rgba_color)
  let pt = prop_type_get(group, {'bufnr': n_buf})
  let b_create = empty(pt)

  let cmd_highlight = [
        \ 'highlight',
        \ group,
        \ 'guibg=#' . call('printf', ['%02x%02x%02x'] + rgb_color),
        \ 'guifg=fg',
      \]
  execute join(cmd_highlight, ' ')

  if b_create
    let pt = prop_type_add(group, {
          \ 'bufnr': n_buf,
          \ 'highlight': group,
          \ 'combine': 0,
          \ 'start_incl': 0,
          \ 'end_incl': 0,
        \})
  endif

  " INSERT MATCH PATTERN FOR HIGHLIGHT
  call prop_add(n_line, n_col, {
        \ 'bufnr': n_buf,
        \ 'length': n_length,
        \ 'type': group,
        \ 'id': 777,
      \ })

endfunction


" ---------------------------  EXPOSED COMMANDS  ---------------------------


function! clrzr#RefreshAllBuffers()
  let bufs = getbufinfo()
  for d_buf in bufs
    call s:RebuildTextProps(d_buf, 1, d_buf.linecount)
  endfor
endfunction


function! clrzr#Refresh()
  let [d_buf] = getbufinfo(bufnr())
  call s:RebuildTextProps(d_buf, 1, d_buf.linecount)
endfunction


" TOGGLES ALPHA COMPONENT POSITION FOR HEX COLORS IN CURRENT WINDOW
function! clrzr#AlphaPosToggle()
  if s:IsAlphaFirst()
    let b:clrzr_hex_alpha_first = 0
  else
    let b:clrzr_hex_alpha_first = 1
  endif
  call clrzr#Refresh()
endfunction


function! s:AwkOut(chan, msg)
  call s:ProcessMatch(a:msg)
endfunction


function! s:AwkErr(chan, msg)
  " TODO: disable window w/ error
  echoerr ['ERR', a:msg]
endfunction


function! s:AwkExit(job_id, exit)
  " TODO: disable window w/ error
  call s:Debug(['EXIT', a:job_id, a:exit])
endfunction


const s:CLRZR_AWK_SCRIPT_PATH = expand('<sfile>:p:h') . '/clrzr.awk'

function! clrzr#Enable()

  if s:IsEnabled() | return | endif

  call s:Debug(['ENABLE'])

  let job_opts = {
        \ 'in_mode': 'nl',
        \ 'out_mode': 'nl',
        \ 'err_mode': 'nl',
        \ 'err_cb': function('s:AwkErr'),
        \ 'exit_cb': function('s:AwkExit'),
        \ 'out_cb': function('s:AwkOut'),
        \ 'drop': 'auto',
        \ 'stoponexit': 'kill',
        \ 'pty': 0,
      \ }

  if has("patch-8.1.350")
    let job_opts['noblock'] = 1
  endif

	let l:awk_cmd = ['awk']
	if executable('gawk')
		let l:awk_cmd = ['gawk', '--posix']
	elseif executable('mawk')
		let l:awk_cmd = ['mawk', '--posix', '-W', 'interactive']
	elseif executable('goawk')
		let l:awk_cmd = ['goawk']
	endif
	call extend(l:awk_cmd, ['-f', s:CLRZR_AWK_SCRIPT_PATH])

  let s:awk_job = job_start(l:awk_cmd, job_opts)

  " NOTE: string(chan) == 'channel fail' is error
  let s:awk_chan = job_getchannel(s:awk_job)
  if string(s:awk_chan) == 'channel fail'
    echoerr 'JOB CHANNEL FAILURE'
    unlet s:awk_chan
    unlet s:awk_job
    return
  else
    let s:clrzr_on = 1

    " REFRESH ALL EXISTING BUFFERS ON RE-ENABLE
    " LEAVE THIS TO AUTOCMDS FOR FIRST RUN
    if exists('s:first_ran')
      call clrzr#RefreshAllBuffers()
    else
      let s:first_ran = 1
    endif

  endif

  augroup Clrzr

    autocmd!

    " NOTE: for event investigations
    if 0

      const probe = [
            \ 'TextChanged',
            \ 'TextChangedI',
            \ 'InsertLeave',
            \ 'SafeState',
          \ ]

      for evt in probe
        let cmd = ['autocmd', evt, '* call s:SnoopEvent("' . evt . '")']
        execute join(cmd, ' ')
      endfor

    else

      " REBUILD HIGHLIGHTS AFTER READS
      autocmd BufReadPost,FileReadPost,StdinReadPost,FileChangedShellPost * call clrzr#Refresh()

      " NOTE: FilterReadPost isn't triggered when `shelltemp` is off,
      "       but ShellFilterPost is regardless
      autocmd ShellFilterPost * call clrzr#Refresh()

      " FORCE-REBUILD HIGHLIGHTS AFTER COLORSCHEME CHANGE
      " (to re-blend alpha colors with new background color)
      " NOTE: refreshes all windows in case bg color changed
      autocmd ColorScheme * call clrzr#RefreshAllBuffers()

      " NORMAL MODE CHANGES
      autocmd TextChanged * call s:RefreshDirtyRange()

      " INSERT MODE CHANGES
      autocmd InsertLeave * call s:RefreshDirtyRange()

      " UPDATE LINE UNDER CURSOR WHILE TYPING IN INSERT MODE
      autocmd SafeState * call s:SafeStateUpdate()

      " NOTE: visual block insert:
      " InsertLeave is after first line finished
      " TextChanged is after others are filled-down

    augroup END

  endif

endfunction


function! s:SafeStateUpdate()
  if mode(1) ==# 'i'
    let n_buf = bufnr()
    let line_cursor = line('.')
    let [d_buf] = getbufinfo(n_buf)
    call s:RebuildTextProps(d_buf, line_cursor, line_cursor)
  endif
endfunction


function! s:RefreshDirtyRange()

  " NOTE: we get the same region on rapid N-copy pastes,
  "       so we can't debounce (i.e. have to refresh immediately)

  " GET CHANGE REGION, EXIT IF EMPTY
  let pos = [ getpos("'["), getpos("']") ]

  if (pos[0][1] == pos[1][1]) && (pos[0][2] == pos[1][2])
    return
  endif

  let n_buf = bufnr()
  let [d_buf] = getbufinfo(n_buf)
  call s:RebuildTextProps(d_buf, pos[0][1], pos[1][1])

endfunction


" REMOVE TEXTPROPS & clrzr_ VARS FROM BUFFER
function! s:ClearBufferProps(bufinfo)
  let n_buf = a:bufinfo.bufnr
  call s:RemoveProps(n_buf, 1, a:bufinfo.linecount)
  call setbufvar(n_buf, 'clrzr_hex_alpha_first', 0)
endfunction


" REMOVE AUTOGROUP & CLEAR HIGHLIGHTS ACROSS ALL WINDOWS
function! clrzr#Disable()

  augroup Clrzr
    au!
  augroup END
  augroup! Clrzr

  unlet! s:clrzr_on

  " END JOB, REMOVE chan2winid MAPPING
  if exists('s:awk_job')
    call job_stop(s:awk_job)
    unlet s:awk_chan
    unlet s:awk_job
  endif

  " REMOVE clrzr_ STATE
  let bufs = getbufinfo()
  for d_buf in bufs
    call s:ClearBufferProps(d_buf)
  endfor

endfunction


" ---------------------------  SETUP  ---------------------------


" Restoration and modelines
let &cpo = s:keepcpo
unlet s:keepcpo

" vim:ft=vim:fdm=marker:fmr={{{,}}}:ts=8:sw=2:sts=2:et
