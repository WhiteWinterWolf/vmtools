################################################################################
### /usr/local/lib/vmtools/cleanup.inc.sh BEGIN
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
# This library provides rollback capabilities, storing rollback commands and
# files backup.
#
# It relies on the shell's `trap' feature to initiate the rollback process
# either when one of the SIGINT, SIGQUIT or SIGTERM signals is received, or
# if the script exits before `cleanup_end()' has been called.
#
# Public functions:
#   cleanup_add command [arg...]
#         Add a command-line to the rollback process.
#   cleanup_backup [-m] file...
#         Create a backup copy of a file.
#   cleanup_end
#         Deactivate and clear the rollback process.
#   cleanup_remove command [arg...]
#         Remove a command-line from the rollback process.
#   cleanup_reset
#         Reset and create a new rollback process.
#   cleanup_set_tmpdir [directory]
#         Create a temporary directory to store files backup.
#
################################################################################

################################################################################
# Global variables
################################################################################

# Rollback commands to execute automatically upon exit.
# Do not access it directly, use the `cleanup_*()' functions.
cleanup_cmd=''

# Path to a temporary directory storing backup files.
cleanup_tmpdir=''


################################################################################
# Functions
################################################################################

###
# cleanup_add command [arg...]
#
# Add a command-line to the rollback process.
#
# The command-line is composed of `command' associated to its arguments `arg'.
#
# The commands added should be reliable and fast, typically commands such as
# `rm', `rmdir' and `mv' are preferred, and should not depend on the value of
# any variable nor do any assumption on the current state of the environment.
#
# It is considered a bug to add a command-line already present (same command +
# same arguments) in the the rollback process (allowing this would raise an
# issue with `cleanup_remove()').
#
# See `cleanup_remove()' for the opposite operation.
#
cleanup_add() {
	local 'cmd'
	cmd=$( str_escape -s ' ' -- "$@" )
	if [ -z "$cmd" ]
	then
		echo "ERROR (BUG): cleanup_add: Missing parameter." >&2
		return 1
	fi

	if printf '%s' "$cleanup_cmd" | grep  -Fqx "$cmd"
	then
		echo "ERROR (BUG): cleanup_add: Command already registered: '${cmd}'." \
			>&2
		return 1
	fi

	str_list_add -p 'cleanup_cmd' "$cmd"
	trap "cleanup_trap" EXIT INT QUIT TERM
}

###
# cleanup_backup [-m] file...
#
# Create a backup copy of `file' which will be restored as part of the rollback
# process.
#
# If `file' doesn't exists yet then a removal its schedulled as part of the
# rollback process.
#
# Options:
#   -m  Use `mv' instead of `cp' to create the backup file. This is recommended
#       to create a backup of large files which are going to be overwritten.
#       See also `cleanup_set_tmpdir()' to define a temporary directory located
#       on the same partition as `file'.
#
cleanup_backup() {
	local  'dst' 'move' 'opt' 'OPTARG' 'OPTIND' 'src'
	move='no'

	OPTIND=1
	while getopts 'm' opt
	do
		case "$opt" in
			'm') move='yes' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))


	if [ -z "$cleanup_tmpdir" ]
	then
		cleanup_set_tmpdir || return 1
	fi

	for src
	do
		if [ -e "$src" ]
		then
			# The file already exists, create a backup.
			if lsof -- "$src" >&2
			then
				echo "ERROR: ${src}: This file is currently in use by another" \
					"process." >&2
				return 1
			fi

			dst=$( mktemp -u -- \
				"${cleanup_tmpdir}/$( basename -- "$src" ).XXXXX" ) \
				|| return 1
			if [ "$move" = 'yes' ]
			then
				if mv -f -- "$src" "$dst"
				then
					# SC2015: `printf 'Directory'' should return true.
					# shellcheck disable=SC2015
					cli_trace 4 "cleanup_backup: ${src}: $( [ -d "$src" ] \
						&& printf 'Directory' || printf 'File' ) moved to '${dst}'."
				else
					echo "ERROR: ${src}: Failed to move to the backup" \
						"directory ('${dst}')." >&2
					return 1
				fi
			else
				if cp -ar -- "$src" "$dst"
				then
					# SC2015: `printf 'Directory'' should return true.
					# shellcheck disable=SC2015
					cli_trace 4 "cleanup_backup: ${src}: $( [ -d "$src" ] && \
						printf 'Directory' || printf 'File' ) copied to '${dst}'."
				else
					echo "ERROR: ${src}: Failed to create a backup copy" \
						"(${dst}')." >&2
					return 1
				fi
			fi

			cleanup_add mv -f -- "$dst" "$src"
		else
			cli_trace 4 "cleanup_backup: ${src}: No file with such name yet."
			# The file doesn't exists yet, remove any new files created by the
			# caller upon unexpected exit.
			# TODO: `rm -rf' maybe too violent, handle directories in a cleaner way?
			cleanup_add rm -rf -- "$src"
		fi
	done
}

###
# cleanup_end
#
# Remove all temporary files and clears cleanup commands list.
#
# This function should be used at the end of the global or a atomic operation
# in order to deactivate the rollback process which would otherwise take place
# upon exit.
#
# See also `cleanup_reset()' to declare a new atomic operation from within
# a subshell.
#
cleanup_end() {
	if [ -n "$cleanup_tmpdir" ]
	then
		rm -r -- "$cleanup_tmpdir" || echo "WARNING: ${cleanup_tmpdir}:" \
			"Failed to remove the temporary backup directory." >&2
	fi
	cleanup_reset
}

###
# cleanup_remove command [arg...]
#
# Remove a command-line from the rollback process.
#
# It is considered a bug to attempt to remove a command-line which has not
# been previously registered in the rollback process.
#
# See`cleanup_end()' to remove at once all registered commands fom the rollback
# process before exiting normally.
# See `cleanup_add()' for the opposite action.
#
cleanup_remove() {
	local 'cleanupcmd_old' 'cmd'
	cmd=$( str_escape -s ' ' -- "$@" )
	if [ -z "$cmd" ]
	then
		echo "ERROR (BUG): cleanup_remove: Missing parameter." >&2
		return 1
	fi

	cleanupcmd_old=$cleanup_cmd
	str_list_remove 'cleanup_cmd' "^$( str_escape_grep -- "$cmd" )\$"
	if [ "$cleanup_cmd" = "$cleanupcmd_old" ]
	then
		echo "ERROR (BUG): cleanup_remove: Cleanup command not registered:" \
			"'${cmd}'." >&2
		return 1
	fi

	if [ -z "$cleanup_cmd" ]
	then
		trap - EXIT INT QUIT TERM
	fi
}

###
# cleanup_reset
#
# This function allows to isolate a new subshell from its parent, this notably
# prevents `cleanup_end()' from deleting temporary files created by the
# parent shell.
#
# Do not call this function outside of a new subshell, since this will loose
# every previously set cleanup commands files and leave temporary files.
#
cleanup_reset() {
	cleanup_cmd=''
	cleanup_tmpdir=''
	trap - EXIT INT QUIT TERM
}

###
# cleanup_set_tmpdir [directory]
#
# This function creates a new subdirectory with a unique name below `directory'.
#
# In case some backuped files may be large (like disk images), try to use
# the VM home dir if available instead of the system's default temporary dir.
# The directory is not hidden (not a dotted name) to avoid any silent
# accumulation of old backup directory over time in case of issue (theorically
# those should be deleted automatically, even in case of an internal error).
#
# Once set, you cannot change the temporary directory in the same shell. In a
# subshell, `cleanup_reset()' allows to reset the data structure, thus allowing
# to define a new directory if required.
#
cleanup_set_tmpdir() {
	local 'dir'
	[ "${1-}" = '--' ] && shift
	dir=${1:-"${TMPDIR:-"/tmp"}"}

	if [ -n "$cleanup_tmpdir" ]
	then
		echo "WARNING (BUG): cleanup_set_tmpdir: Attempt to overwrite" \
			"'\$cleanup_tmpdir'." >&2
		return 1
	fi

	cleanup_tmpdir=$( mktemp -d -- "${dir%"/"}/${cfg_file_tmpdir:?}" ) \
		|| return 1
	cleanup_add rmdir -- "${cleanup_tmpdir:?}"
}

###
# cleanup_trap
#
# Trap handler.
#
# This function is not designed to be called directly.
# It is called invoked directly by the shell before exiting.
#
cleanup_trap() {
	trap '' EXIT INT QUIT TERM
	cli_trace 3 "cleanup_trap: EMERGENCY EXIT INITIATED!"
	set +e
	eval "$cleanup_cmd"
	trap - EXIT INT QUIT TERM
}

################################################################################
### /usr/local/lib/vmtools/cleanup.inc.sh END
################################################################################
