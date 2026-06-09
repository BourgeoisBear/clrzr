#!/usr/bin/awk

BEGIN {

	FS = "\n"
	rHex = "[[:xdigit:]]"
	rSpc = "[[:space:]]*"
	rFlt = "([0-9]*\\.)?[0-9]+"
	rPct = rFlt "%"
	rFltOrPct = rFlt "%?"
	cma = rSpc "," rSpc

	rExpr = "(" \
		"(0x|#)(" rHex "{8}|" rHex "{6}|" rHex "{4}|" rHex "{3})" \
		"|" \
		"(rgb|rgba)\\(" rSpc rFltOrPct cma rFltOrPct cma rFltOrPct "(" cma rFltOrPct ")?" rSpc "\\)" \
		"|" \
		"(hsl|hsla)\\(" rSpc rFlt cma rPct cma rPct "(" cma rFltOrPct ")?" rSpc "\\)" \
	")"

	rNumPfx = "^" rSpc "[0-9]+\t"
}

{
	szLine = tolower($1)

	# --characters-as-bytes / -b ?
	# --posix

	# PREFIX: buf_no \t line_no \t lines_total \t

	# BUF#
	match(szLine, rNumPfx)
	szBufNo = substr(szLine, RSTART, RLENGTH - 1)
	szLine = substr(szLine, RSTART + RLENGTH)

	# LINE#
	match(szLine, rNumPfx)
	szLineNo = substr(szLine, RSTART, RLENGTH - 1)
	szLine = substr(szLine, RSTART + RLENGTH)

	# LAST LINE#
	match(szLine, rNumPfx)
	szLastLineNo = substr(szLine, RSTART, RLENGTH - 1)
	szLine = substr(szLine, RSTART + RLENGTH)

	if( (szLine == "--begin--") || (szLine == "--end--") ) {
		printf "%s|%s|0|%s|%s\n", szBufNo, szLineNo, szLastLineNo, szLine
	}
	else {

		# GET COLORS WITHIN LINE
		colAbs = 0
		while( 1 ) {

			match(szLine, rExpr)
			colAbs += RSTART

			if( RLENGTH < 0 ) {
				break
			}

			printf "%s|%s|%d|%d|%s\n", szBufNo, szLineNo, colAbs, RLENGTH, substr(szLine, RSTART, RLENGTH)
			colAbs += RLENGTH - 1
			szLine = substr(szLine, RSTART + RLENGTH)
		}
	}

	fflush()
}

# GAWK: --sandbox
# AWK: --safe
#
# awk -f ./clrzr.awk ./colortest.txt | sort | uniq
