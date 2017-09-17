################################################################################
### /usr/local/lib/vmtools/lock.inc.sh BEGIN
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
# This library handles directory locking features.
#
# Public functions:
#   lock_acquire [-cdn] directory...
#         Acquire a lock on a directory.
#   lock_check [-e] [directory...]
#         Check if a directory is already locked by the current process.
#   lock_mvpath source destination
#         Update locks path after a directory has been moved or renamed.
#   lock_release [-cd] directory...
#         Release a lock on a directory.
#
################################################################################

################################################################################
# Global variables
################################################################################

# List of owned lock files.
lock_list=''


################################################################################
# Functions
################################################################################

###
# lock_acquire [-cdn] directory...
#
# Acquire a lock on `directory'.
#
# The options `-c' and `-d' allow to acquire the locks on child or directory
# tree globally at once.
#
# If the directory is already locked, this function will wait during
# `$cfg_limit_waitlock' for the lock to be removed, and then fail.
#
#
# See `lock_release()' or the opposite operation.
#
# Options:
#   -c    Enable child-based recursion.
#   -d    Enable directory-based recursion.
#   -n    Do not actually lock the target, only try to determine wether the
#         directory contains an unlocked and stopped VM or not (currently this
#         test only detects virtual machines running on the same host: it will
#         not detect a VM shared on a network storage and currently in use by
#         another host).
#
lock_acquire() {
	local 'dir' 'lockpath' 'opt' 'OPTARG' 'OPTIND' 'setlock' 'timeout'
	setlock='yes'

	OPTIND=1
	while getopts 'cdn' opt
	do
		case "$opt" in
			'c'|'d') lock_recurse -f 'lock_acquire' "$@"; return $? ;;
			'n') setlock='no' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))

	for dir
	do
		dir=$( realpath -- "$dir" ) || return 1
		if lock_check -- "$dir"
		then
			echo "ERROR: ${dir}: A lock has already been acquired for this" \
				"path." >&2
			return 1
		fi

		if [ ! -d "$dir" -o ! -w "$dir" ]
		then
			echo "ERROR: '${dir}' is not a valid directory or is not" \
				"writable." >&2
			return 1
		fi
		cli_trace 4 "lock_acquire: ${dir}: Acquiring lock."

		if [ "$setlock" = 'yes' ]
		then
			# Acquire the lock
			# Symbolic link create is an atomic operation even on dodgy NFS
			# servers where directory creation may not be.
			# The link target stores the original lock location, useful when
			# the directory gets moved (see `lock_mvpath()' and
			# `lock_release()'.)
			lockpath="${dir}/${cfg_file_lock:?}"
			if ! ln -s "${dir}" "$lockpath" 2>/dev/null
			then
				cli_trace 2 "Waiting to acquire lock on '${dir}'" \
					"(${cfg_limit_waitlock} sec. max.)..." >&2

				timeout=$(( $( date +%s ) + ${cfg_limit_waitlock:?} )) || return 1
				while ! ln -s -- "${dir}" "$lockpath" \
					2>/dev/null
				do
					if [ "$( date +%s )" -gt "$timeout" ]
					then
						echo "ERROR: Failed to acquire lock." >&2
						echo "If it is not used anymore, the file '$lockpath'" \
							"must be deleted manually or using the" \
							"'vmclearlock' utility." >&2
							return 1
					fi
					# `sleep' may or may not support floating point numbers.
					sleep 0.1 2>/dev/null || sleep 1 || return 1
				done
			fi

			cleanup_add rm -- "$lockpath"
			if ! str_list_add 'lock_list' "$lockpath"
			then
				lock_release -- "$dir" || return 1
				return 1
			fi
		fi

		if vmps_init -q -d "$dir"
		then
			echo "ERROR: ${dir}: This virtual machine is currently running," \
				"failed to acquire a lock." >&2
			if [ "$setlock" = 'yes' ]
			then
				lock_release -- "$dir" || return 1
			fi
			return 1
		fi

	done
}

###
# lock_check [-e] [directory...]
#
# Check if `directory' is already locked by the current process.
#
# Non-existing paths are considered as not locked.
# If several directories are passed as parameter, the current process must own
# a lock on every one of them for this functionto return 0.
#
# Options:
#   -e    Display an error message if the directory is not locked.
#
lock_check() {
	local 'dir' 'dirs_list' 'display_error' 'lockpath' 'opt' 'OPTARG' 'OPTIND'
	display_error='no'

	OPTIND=1
	while getopts 'e' opt
	do
		case "$opt" in
			'e') display_error='yes' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))

	if [ $# -ne 0 ]
	then
		dirs_list=$( realpath -- "$@" ) || return 1
	else
		dirs_list=${vm_home:?}
	fi

	for dir in $dirs_list
	do
		lockpath="${dir}/${cfg_file_lock:?}"

		if ! printf '%s' "$lock_list" | grep -Fqx -- "$lockpath"
		then
			if [ "$display_error" = 'yes' ]
			then
				# If the caller expects the directory to be locked and it is not,
				# this means there is a bug somewhere in vmtools.
				echo "ERROR (BUG): ${dir}: Directory not locked." >&2
			fi
			return 1
		elif [ ! -L "$lockpath" ]
		then
			# Consistency check failed, something bad is hapening.
			echo "ERROR (BUG?): ${dir}: The path has been locked but the lock" \
				"file is missing." >&2
			# System state unknown and locking unreliable, emergency exit.
			exit 1
		fi
	done

	return 0
}

###
# lock_mvpath source destination
#
# Update this library's locks list to take a directory move/rename into account.
#
# This function must be called after moving or renaming a directory containing
# lock files (either directly or in a subdirectory).
# Without this the lock files will be assumed as belonging to another process.
#
lock_mvpath() {
	local 'dst' 'src'
	[ "${1-}" = '--' ] && shift
	src=${1:?"ERROR (BUG): lock_mvpath: Missing parameter."}
	dst=${2:?"ERROR (BUG): lock_mvpath: Missing parameter."}

	lock_list=$( printf '%s' "$lock_list" | sed \
		"s/^$( str_escape_sed -- "${src}/" )/$( str_escape_sed -- "${dst}/" \
		)/" )
}

###
# lock_recurse [-nd] -c -f callback directory...
# lock_recurse [-nc] -d -f callback directory...
#
# Helper for 'lock_acquire()` and `lock_release()'.
# This function implements recursion features for its caller.
#
# It is mandatory to use at least the `-c' or `-d' flags. Recursion types may
# be combined.
#
# Options
#   -c    Enable child-based recursion.
#   -d    Enable directory-based recursion.
#   -f    Name of calling function, either `lock_acquire' or `lock_release'.
#   -n    Do not actually lock the target, only try to determine wether the
#         directory contains an unlocked and stopped VM or not (currently this
#         test only detects virtual machines running on the same host: it will
#         not detect a VM shared on a network storage and currently in use by
#         another host).
#
lock_recurse() {
	local 'action' 'callback' 'childs_list' 'dir' 'dirs_done' 'dirs_new'
	local 'dirs_old' 'lock_opts' 'nesting' 'opt' 'OPTARG' 'OPTIND'
	action=''
	dirs_done=''

	# Explicit loop detection is not required as the lock acquire or release
	# operation will naturally fail in case a loop is present.

	OPTIND=1
	while getopts 'cdf:n' opt
	do
		case "$opt" in
			'c') # Child-based recursion.
				action="${action}c"
				;;
			'd') # Directory-based recursion.
				action="${action}d"
				;;
			'f') # Callback function.
				callback=$OPTARG
				;;
			'n') # Do not create lockfile.
				lock_opts="n"
				;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	if [ -z "$action" ]
	then
		echo "ERROR (BUG): lock_recurse: Action parameter missing." >&2
		return 1
	fi
	if [ -z "$callback" ]
	then
		echo "ERROR (BUG): lock_recurse: Callback function name missing." >&2
		return 1
	fi

	case "$action" in
		*'d'*)
			dirs_new=$( realpath -- "$@" ) || return 1
			# SC2086: Word splitting expected on `$dirs_new'.
			# shellcheck disable=SC2086
			dirs_new=$( find $dirs_new -type d -a \! -path "*${newline:?}*" ) \
				|| return 1
			# shellcheck disable=SC2086
			eval "$( str_escape -s ' ' -- "$callback" \
				${lock_opts:+"-${lock_opts}"} -- $dirs_new )" || return 1
			# shellcheck disable=SC2086
			str_list_add 'dirs_done' $dirs_new
			;;
		*)
			eval "$( str_escape -s ' ' -- "$callback" \
				${lock_opts:+"-${lock_opts}"} -- "$@" )" || return 1
			str_list_add 'dirs_done' "$@"
			;;
	esac

	case "$action" in *'c'*)
		nesting=0
		dirs_old="$*"
		while [ -n "$dirs_old" ]
		do
			nesting=$(( nesting + 1 ))
			dirs_new=''

			if [ "$nesting" -ge "${cfg_limit_nesting:?}" ]
			then
				echo "ERROR: Infinite loop found in virtual machines" \
					"parent-child links:" >&2
				# SC2086: Word splitting expected on `$dirs_old'.
				# shellcheck disable=SC2086
				printf '    %s\n' $dirs_old >&2
				return 1
			fi

			for dir in $dirs_old
			do
				# We must gather the childs only from previously locked VMs,
				# otherwise there is a slight chance that another process may
				# modify the childs list while we are traversing the tree.
				childs_list=$( childs_get_list -- "$dir" ) || return 1
				if [ -n "$childs_list" ]
				then
					# SC2086: Word splitting expected on `$childs_list'.
					# shellcheck disable=SC2086
					str_list_add 'dirs_new' $childs_list || return 1
				fi
			done

			for dir in $dirs_new
			do
				if test -z "$dirs_done" \
					|| ! printf '%s' "$dirs_done" | grep -Fqx "$dir"
				then
					eval "$callback" ${lock_opts:+"-${lock_opts}"} -- \
						"$( str_escape -- "$dir" )" || return 1
				fi
			done

			dirs_old=$dirs_new
		done
	esac
}

###
# lock_release [-cd] directory...
#
# Release a lock on `directory'.
#
# The options `-c' and `-d' allow to acquire the locks on child or directory
# tree globally at once.
#
# It is considered a bug to attempt to release an unlocked directory.
#
# See `lock_acquire()' for the opposite operation.
#
# Options:
#   -c    Enable child-based recursion.
#   -d    Enable directory-based recursion.
#
lock_release() {
	local 'dir' 'dirs_list' 'lnpath' 'lockpath' 'opt' 'OPTARG' 'OPTIND' 'rc'

	OPTIND=1
	while getopts 'cd' opt
	do
		case "$opt" in
			'c'|'d') lock_recurse -f 'lock_release' "$@"; return $? ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	: "${1:?"ERROR (BUG): lock_release: Missing parameter."}"
	rc=0

	dirs_list=$( realpath -- "$@" ) || return 1
	# SC2086: Word splitting expected on `$dirs_list'.
	# shellcheck disable=SC2086
	lock_check -e -- $dirs_list || return 1

	for dir in $dirs_list
	do
		lockpath="${dir}/${cfg_file_lock:?}"
		# `$lnpath' may point to a different location if the directories have
		# been moved, see `lock_mvpath()'.
		lnpath="$( readlink -- "$lockpath" )/${cfg_file_lock:?}" || return 1
		if rm -- "$lockpath"
		then
			cleanup_remove rm -- "$lnpath" || return 1
			str_list_remove 'lock_list' "^$( str_escape_grep -- "$lockpath" )\$"
			cli_trace 4 "lock_release: ${dir}: Lock released."
		else
			printf 'ERROR: %s: Failed to remove the lock file.\n' "$lockpath" \
				>&2
			rc=1
		fi
	done

	return "$rc"
}

################################################################################
### /usr/local/lib/vmtools/lock.inc.sh END
################################################################################
