################################################################################
### /usr/local/lib/vmtools/include.inc.sh BEGIN
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
# This library handles the loading of vmtools modules and configuration files.
#
# Public functions:
#   include_globalconf
#         Load vmtools global configuration file.
#   include_module [-n] file...
#         Load vmtools modules files.
#   include_vmsettings file
#         Load a virtual machine settings file.
#
################################################################################


################################################################################
# Functions
################################################################################

###
# include_globalconf
#
# Load vmtools global configuration file.
#
# All default settings are loaded from `/usr/local/share/vmtools/vmtools.conf'.
# This file must be available and readable.
#
# Local-system overrides are then loaded from `/etc/vmtools/vmtools.conf'.
# This file is optional and may define only the settings to override.
#
# If `$cfg_include_userhome' is "yes", user's overrides are then loaded from
# `~/.config/vmtools/vmtools.conf' (`$XDG_CONFIG_HOME' may be used to define
# another location for user's configuration files than the default `~/.config').
# This file is optional too.
#
# See "XDG Base Directory Specification":
# https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
#
# TODO: Also check `/usr/local/etc' to load system-wide settings (BSD systems).
# The easiest way would be to always check both `/etc' and `/usr/local/etc' no
# matter the current system.
#
include_globalconf() {
	local 'filepath'

	# Default settings
	if [ -r "/usr/local/share/vmtools/vmtools.conf" ]
	then
		. "/usr/local/share/vmtools/vmtools.conf"
	else
		echo "ERROR: /usr/local/share/vmtools/vmtools.conf: File not found" \
			"or not readable." >&2
		return 1
	fi

	# System-wide settings override
	if [ -r "/etc/vmtools/vmtools.conf" ]
	then
		. "/etc/vmtools/vmtools.conf"
	fi

	# Local user settings override
	if [ "$cfg_include_userhome" = 'yes' ]
	then
		filepath="${XDG_CONFIG_HOME:-"${HOME}/.config"}/vmtools/vmtools.conf"
		if [ -r "$filepath" ]
		then
			. "$filepath"
		fi
	fi
}

###
# include_module [-n] file...
#
# Include the module file `file'.
#
# `file' shall name a module file present under at least one of the vmtools
# modules location, including the subdirectory where it is located.
#
# Modules files are successively searched in the following locations:
#   1. If `$cfg_include_userhome' is "yes", user's modules are searched in
#     `~/.config"}/vmtools/modules'(`$XDG_CONFIG_HOME' may be used to define
#      another location for user's configuration files than the default
#      `~/.config'). If this directory does not exist it is ignored.
#   2. Local system moduls are searched in `/etc/vmtools/modules'. If this
#      directory does not exist it is ignored.
#   3. Default vmtools modules are searched in `/usr/local/share/vmtools/modules'.
#      This directory must exist.
#
# Once a module with a matching name is found in one directory, other
# directories are not searched, thus allowing to overwrite a particular module
# at the system or user level.
#
# `file' must end with the extension ".inc.sh" be composed of any of those
# characters:
#   - Alphanumerical characters.
#   - Underscore ('_').
#   - Dash ('-').
#   - Path separator ('/').
#
# For more information on the "XDG Base Directory Specification", see:
# https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
#
# Options:
#   -n    Do not include the module files, only check their existence.
#
include_module() {
	local 'doinclude' 'f' 'files' 'opt' 'OPTARG' 'OPTIND' 'str'
	doinclude='yes'

	OPTIND=1
	while getopts 'n' opt
	do
		case "$opt" in
			'n') doinclude='no' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	: "${1:?"ERROR (BUG): include_module: Missing parameter."}"

	files=''
	for f
	do
		if ! expr "$f" : '[[:alnum:]/_-]\{1,\}\.inc\.sh$' >/dev/null
		then
			echo "ERROR: ${f}: Invalid module name." >&2
			return 1
		fi

		if [ "$cfg_include_userhome" = 'yes' \
			-a -r "${XDG_CONFIG_HOME:-"${HOME}/.config"}/vmtools/modules/${f}" ]
		then
			# Local user modules
			str_list_add 'files' \
				"${XDG_CONFIG_HOME:-"${HOME}/.config"}/vmtools/modules/${f}" \
				|| return 1

		elif [ -r "/etc/vmtools/modules/${f}" ]
		then
			# System-wide settings override
			str_list_add 'files' "/etc/vmtools/modules/${f}" || return 1

		elif [ -r "/usr/local/share/vmtools/modules/${f}" ]
		then
			# Default settings
			str_list_add 'files' "/usr/local/share/vmtools/modules/${f}" \
				|| return 1

		else
			echo "ERROR: ${f}: module not found." >&2
			return 1
		fi
	done

	# Actually include the files only when we are sure there wasn't any error.
	# This is required notably in the template input module to allow the user
	# to correct en errouneous templates list input.
	if [ "$doinclude" = 'yes' ]
	then
		for f in $files
		do
			cli_trace 4 "include_module: ${f}: Loading file."
			. "$f"
		done
	fi
}

###
# include_vmsettings file
#
# Load a virtual machine settings file.
#
# This function is basically sourcing the content of the VM settings file with
# a few added sanity checks against the file content.
#
# TODO: Check that `parent' is invoked only once, unless there is a way to
# check this from the parent() function?
#
include_vmsettings() {
	local 'c' 'content' 'extended_str' 'filepath' 'grep_rc' 'safe_str'
	local 'unexpected'
	[ "${1-}" = '--' ] && shift
	filepath=${1:?"ERROR (BUG) include_vmsettings: Missing parameter."}

	if [ ! -r "$filepath" ]
	then
		echo "ERROR: ${filepath}: File not found or not readable." >&2
		return 1
	fi

	cli_trace 4 "include_vmsettings: ${filepath}: Loading VM settings file."

	# Remove leading spaces, comments and trailing spaces.
	content=$( sed 's/^[[:space:]]*\(#.*$\)\?//; s/[[:space:]]\{1,\}$//' \
		"$filepath" ) || return 1

	# This file is user-editable, perform some sanity checks.
	grep_rc=0
	extended_str="\\([[:alnum:]._/-]*\\|'[^']*'\\|\\\\'\\)*"
	safe_str='[[:alnum:]_]\{1,\}'
	# `template' is parsed as an extended string here to allow optional quoting.
	unexpected=$( echo "$content" | grep -v -e '^$' \
		-e '^template\([[:space:]]\{1,\}'"$extended_str"'\)\{1,\}$' \
		-e '^parent\([[:space:]]\{1,\}'"$extended_str"'\)\{1\}$' \
		-e "^vm_${safe_str}=${extended_str}\$" ) || grep_rc=$?
	if [ "$grep_rc" -ne 1 ]
	then
		echo "ERROR: ${filepath}: This file contains unexpected content:" >&2
		# SC2086: Word splitting is expected on `$unexpected'.
		# shellcheck disable=SC2086
		printf '    %s' $unexpected >&2
		return 1
	fi

	# We need to execute each line individually to ensure we catch non-null
	# exit codes
	for c in $content
	do
		eval "$c" || return 1
	done
}

################################################################################
### /usr/local/lib/vmtools/include.inc.sh END
################################################################################
