################################################################################
### /usr/local/lib/vmtools/str.inc.sh BEGIN
################################################################################
#
# Copyright 2017 WhiteWinterWolf (www.whitewinterwolf.com)
#
# This file is part of vmtools.
#
# vmtools is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# ------------------------------------------------------------------------------
#
# This library provides string and strings list manipulation function.
#
# A strings list a list of string separated by linefeed characters.
# Such list is mainly used:
#   - To build a list of parameters to pass to a command-line.
#   - To build a database of paths, words, or any other single-line strings and
#     either manipulate it in-memory or store it in a file.
#
# The linefeed ('\n') character being used as the field separator, it cannot
# appear in the strings added to the list. This condition is explicitely
# checked and an error is raised if not fulfilled.
#
# Public functions:
#   str_escape string...
#         Escape `string' to be safely eval'd.
#   str_escape_comma string...
#         Escape commas from Qemu's parameters.
#   str_escape_grep [-c set] string...
#         Escape `string' to make it suitable as a `grep' pattern.
#   str_escape_sed string...
#         Escape `string' to make it suitable as a `sed' pattern.
#   str_explode string...
#         Generate a strings list from a spaces/tabs separated words list.
#   str_list_add [-p] varname string...
#         Add a string to a strings list.
#   str_list_remove varname pattern...
#         Remove all strings matching a pattern from a strings list.
#   str_nonewline string...
#         Check that a string does not contain any linefeed character.
#   str_toupper string...
#         Switch a string to uppercase.
#   str_unescape string...
#         Unescape `string' (remove quotes)
#
################################################################################

################################################################################
# Functions
################################################################################

###
# str_escape [-s field_separator] string...
#
# Escape `string' to be safely eval'd.
#
# All shell special characters in `string' loose their special meaning and are
# taken literally.
#
# Options:
#   -s field_separator
#         Replace the field separator used to concatenate several escaped
#         `string'. By default `$IFS' is used, allowing to pass the result
#         to `str_list_add' as several entries. Using space instead will pass
#         all escaped strings as a single list element.
#
str_escape() {
	local 'filter' 'opt' 'OPTARG' 'OPTIND' 'ret' 'sep' 'str'
	filter="s/'/'\\\\''/g"
	ret=''
	sep=$IFS

	OPTIND=1
	while getopts 's:' opt
	do
		case "$opt" in
			's') sep=$OPTARG ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))

	for str
	do
		case "$str" in
			*[![:alnum:]._/-]*)
				case "$str" in *\'*)
					str=$( printf '%s' "$str" | sed "$filter" )
				esac
				str="'${str}'"
				;;
			'')
				str="''"
				;;
		esac
		ret="${ret:+"${ret}${sep}"}${str}"
	done

	printf '%s' "$ret"
}

###
# str_escape_comma string...
#
# Some Qemu options use commas as parameters separator.
# This function allows to properly escape them.
#
# Do not use this function for Qemu options which do not expect such separator.
#
str_escape_comma() {
	local 'str'
	[ "${1-}" = '--' ] && shift

	for str
	do
		case "$str" in
			# Commas must be escaped using a second comma.
			*,*) printf '%s' "$str" | sed 's/,/,,/g' ;;
			*) printf '%s' "$str" ;;
		esac
	done
}

###
# str_escape_grep [-c set] string...
#
# Escape `string' to make it suitable to be used in a `grep'(1) pattern.
#
# This function actually escapes all characters which have a special meaning in
# an Basic Regular Expression (BRE) as defined here:
# <http://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap09.html#tag_09_03>
# This function can therefore also be used in any other situation where such
# escaping would be required.
#
# Options:
#   -c    An additional set of characters to escape.
#
str_escape_grep() {
	local 'chars' 'filter' 'opt' 'OPTARG' 'OPTIND' 'ret' 'str'
	chars=''
	ret=''

	OPTIND=1
	while getopts 'c:' opt
	do
		case "$opt" in
			'c') chars=$OPTARG ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	# '^'and '$' are handled separately, see below.
	chars='\\.*['"$chars"
	filter='s#['"$chars"']#\\&#g'

	for str
	do
		case "$str" in *[${chars}^\$]*)
			# Only escape '^' and '$' when they are respectively the first and
			# last characters.
			str=$( printf '%s' "$str" | sed -e "$filter" \
				-e 's/^^/\\^/' -e 's/$$/\\$/' )
			;;
		esac
		ret="${ret:+"$ret "}${str}"
	done

	printf '%s' "$ret"
}

###
# str_escape_sed string...
#
# Escape `string' to make it suitable to be used in a `sed'(1) expression.
#
# The encompassing `sed' expression must use a forward slash ('/') as delimiter
# for this function to be effective.
#
str_escape_sed() {
	[ "${1-}" = '--' ] && shift
	str_escape_grep -c '/' -- "$@"
}

###
# str_explode string...
#
# Produce a linefeed separated strings list from a space or tab separated list
# of extended strings.
#
# If several `string' parameters are given, they will be concatenated.
#
# Each extended string must be properly escaped, see vmtols.conf(5) for more
# information on extended strings.
#
# The result is suitable to be used with the `str_list_*()' functions.
#
# To do the opposite action, ie. build a one-liner from an exploded string,
# use `str_escape()'as below, passing it the unquoted exploded variable:
#
#      str_escape -s ' ' -- $exploded_string
#
str_explode() {
	local 'extended_str'
	[ "${1-}" = '--' ] && shift
	extended_str="\\([[:alnum:]._/-]*\\|'[^']*'\\|\\\\'\\)*"

	# SC2046: Word splitting expected on `sed' output.
	# shellcheck disable=SC2046
	str_unescape -- $( printf '%s ' "$@" \
		| sed "s/\\(${extended_str}\\)[[:space:]]*/\\1\\n/g" ) || return 1
}

###
# str_list_add [-p] varname string...
#
# Add `string' to the strings list `varname'.
#
# Variables created using this function are safe to be used unquoted as
# command-line parameters, each string of the list acting as an individual
# parameter, provided that pathname expansion is disabled (shell's `-f' option)
# and `$IFS' is limited exclusively to the linefeed character (these are the
# default for vmtools scripts).
#
# Options:
#   -p    Push the new elements to the top of the list. By default new elements
#         are added to the end of the list.
#
str_list_add() {
	local 'opt' 'OPTARG' 'OPTIND' 'push' 'value' 'varname'
	push='no'

	OPTIND=1
	while getopts 'p' opt
	do
		case "$opt" in
			'p') push='yes' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))

	varname=${1:?"ERROR (BUG): str_list_add: Missing parameter."}
	case "$varname" in *[![:alnum:]_]*)
		printf "ERROR (BUG): str_list_add: Invalid variable name: '%s'.\\n" \
			"$varname" >&2
		return 1
	esac
	shift

	: "${1:?"ERROR (BUG): str_list_add: Missing parameter."}"
	str_nonewline "$@" || return 1

	eval "value=\$$varname" || return 1
	if [ "$push" = 'yes' ]
	then
		value="${*}${value:+"${IFS}${value}"}"
	else
		value="${value:+"${value}${IFS}"}${*}"
	fi

	eval "$varname=\$value"
}

###
# str_list_remove varname pattern...
#
# Remove `pattern' from the strings list `varname'.
#
# Attempting to remove non-existing element is not considered an error.
# To detect such case, compare the content of the strings list before and after
# calling this function:
#
#     mylist_old=mylist
#     str_list_remove 'mylist' '^foo$'
#     if [ "$mylist" = "$mylist_old" ]
#     then
#     ...
#
# Warning: the values are matched against a pattern:
#   - To search for a litteral value, `pattern' must include the start and
#     ending anchors ("^foo$", note that the "$" is special shell character
#     which mya need to be escaped).
#   - If `pattern' is susceptible to contain any special `grep' characters
#     it should be properly escaped (see `str_escape_grep()').
#   - If several strings matches `pattern' they will all be removed at once.
#
str_list_remove() {
	local 'grep_rc' 'pattern' 'value' 'varname'
	grep_rc=0

	varname=${1:?"ERROR (BUG): str_list_remove: Missing parameter."}
	case "$varname" in *[![:alnum:]_]*)
		printf "ERROR (BUG): str_list_remove: Invalid variable name: '%s'.\\n" \
			"$varname" >&2
		return 1
	esac
	shift

	: "${1:?"ERROR (BUG): str_list_remove: Missing parameter."}"
	str_nonewline "$@" || return 1

	eval "value=\$$varname" || return 1
	for pattern
	do
		value=$( printf '%s' "$value" | grep -v "$pattern" ) || grep_rc=$?
		if [ "$grep_rc" -ge 2 ]
		then
			return 1
		fi
	done
	eval "$varname=\$value"
}

###
# str_nonewline string...
#
# Return 0 if none of the provided `string' contains a linefeed characters.
#
# Linefeed is used in vmtools script as global Internal Field Separator (IFS)
# and as field separator in various places (see `childs.inc.sh' for instance).
# This function allows to assess `string' to ensure it will not cause an issue.
#
str_nonewline() {
	local 'arg' 'IFS'
	IFS=' '

	case "$*" in *"${newline:?}"*)
		# Display only the culprit args to make diagnostic easier.
		for arg
		do
			case "$arg" in *"$newline"*)
				printf "ERROR: New line characters are not allowed: '%s'.\\n" \
					"$arg" >&2
			esac
		done
		return 1
	esac
}

###
# str_toupper string...
#
# Output `string' switched into uppercase on stdout.
#
str_toupper() {
	[ "${1-}" = '--' ] && shift

	case "$*" in
		*[[:lower:]]*)
			printf '%s' "$*" | tr '[:lower:]' '[:upper:]'
			;;
		*)
			printf '%s' "$*"
			;;
	esac
}

###
# str_unescape string...
#
# Output an unescaped version of `string' on stdout.
#
# `string' must be properly escaped string, otherwise an error is raised.
# `
str_unescape() {
	local 'err' 'extended_str' 'str'
	[ "${1-}" = '--' ] && shift
	# Shells may escape singles quotes as '\'' or '"'"'.
	extended_str="\\([[:alnum:]._/-]*\\|'[^']*'\\|\\\\'\\|\"'\"\\)*"

	case "$*" in
		*[![:alnum:]._/-${IFS}]*)
			# Each parameter must be a valid extended string.
			# Ignore grep exit code.
			err=$( printf '%s' "$*" | grep -v "^${extended_str}\$" ) || true
			if [ -n "$err" ]
			then
				echo "ERROR: The string is not properly escaped:" >&2
				# SC2086: Word splitting expected on `$err'.
				# shellcheck disable=SC2086
				printf '    %s\n' $err >&2
				return 1
			fi

			for str
			do
				printf '%s\n' "$str" | sed \
					"s/\\(\\([[:alnum:]._/-]*\\)\\|'\\([^']*\\)'\\|\\\\\\('\\)\\|\"\\('\\)\"\\)/\\2\\3\\4\\5/g"
			done
			;;

		*)
			printf '%s\n' "$@"
			;;
	esac
}


################################################################################
### /usr/local/lib/vmtools/str.inc.sh END
################################################################################
