################################################################################
### /usr/local/lib/vmtools/hdd.inc.sh BEGIN
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
# This library provides path-related functions:
#   - To check various path (files, directories and virtual machines home dir.
#   - To manipulate backend path and image files.
#
# Backend path is composed of an optional prefix and a path to a storage device
# image file.
# The prefix may be "ro:", "rw:" or "snap:" depending on the type of access to
# to the image file.
# The image file may be any kind of image file supported by Qemu.
#
# Public functions:
#   storage_createpath [-d|-h|-f|-n] [-t target] [-s suffix] path...
#         Generate a path suitable to store new content.
#   storage_get_backingfile image_file
#         Get the backing file path.
#   storage_get_canonical backend_path
#         Turn a backend path into its canonical form.
#   storage_get_path backend_path
#         Get the path section of a backend path.
#   storage_get_prefix backend_path
#         Get the prefix section of a backend path.
#   storage_isreadable [-d|-h|-f] path
#         Check if a given path can be safely read.
#   storage_iswritable [-d|-h|-f|-n] path
#         Check if a given path can be safely written.
#
################################################################################

################################################################################
# Functions
################################################################################

###
# storage_createpath [-d|-h|-f] [-t target] [-s suffix] path...
#
# Generate a path suitable to store new content from an already existing `path'
# (which can be a directory or a filename) and an optional suffix.
#
# Ensures that the path is writeable and suitable to be used for new content,
# depending on the given type.
# If several `path' parameters are given, they are sucessively tried until a
# suitable path is found. If a path already exists, this function attempts to
# add an incremental number to it.
# In case of doubt, it  interactively consults the user (unless
# `$cfg_ui_assumeyes' is "yes", usually trigerred by using the `-y'
# command-line flag).
#
# This function does not create the path or modify anything, it only generates
# a path name suitable for the caller to use for new content.
#
# Path types:
#   -d    Regular directory.
#   -h    Virtual machine home directory.
#   -f    Regular file.
#   -n    New object.
#
# By default `-f' is used.
#
# Options:
#   -t target
#         Location where to create the new path, by default `$vm_home'.
#   -s suffix
#         Extension to use for the new path.
#
# See also:
# - `storage_iswritable()' for more details on the various path types.
# - `vmmv_mvpath()' to generate a path reflecting a moved directory.
#
storage_createpath() {
	local 'i' 'new_path' 'ok' 'old_path' 'opt' 'OPTARG' 'OPTIND' 'prompt'
	local 'reply' 'suffix' 'target' 'type'
	target=''
	suffix=''
	type='f'

	OPTIND=1
	while getopts 'dfhns:t:' opt
	do
		case "$opt" in
			'd') type='d' ;;   # Directory.
			'f') type='f' ;;   # File.
			'h') type='h' ;;   # VM home.
			'n') type='n' ;;   # New object.
			's') suffix="$OPTARG" ;;
			't') target="$OPTARG" ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	if [ $# -eq 0 ]
	then
		echo "ERROR (BUG): storage_createpath: Missing parameter." >&2
		return 1
	fi
	target=${target:-"${vm_home:?}"}
	target=$( realpath -- "$target" ) || return 1

	# Attempt to automatically find a good new path using the various paths
	# provided as parameter.
	ok='no'
	while [ "$ok" != 'yes' ]
	do
		old_path=${1-}
		new_path=$( basename -s "$suffix" -- "$old_path" )
		new_path="${target}${new_path:+"/${new_path}"}${suffix}"
		shift

		if test $# -eq 0 \
			|| storage_iswritable "-${type}" -- "$new_path" 2>/dev/null
		then
			ok='yes'
		fi
	done

	if storage_iswritable "-${type}" -- "$new_path"
	then
		if [ "$type" = 'f' -a -e "$new_path" ]
		then
			if cli_confirm \
				"The file '${new_path}' already exists, OVERWRITE it [yN]? "
			then
				ok='yes'
			else
				ok='no'
			fi
		else
			ok='yes'
		fi
	else
		ok='no'
	fi

	if [ "$ok" != 'yes' ]
	then
		# Create a new name suggestion.
		new_path=$( basename -s "$suffix" -- "$old_path" )
		new_path="${target}${new_path:+"/${new_path}"}"
		i=1
		while [ -e "${new_path}_${i}${suffix}" ]
		do
			i=$(( i + 1 ))
		done
		new_path="${new_path}_${i}${suffix}"

		if storage_iswritable "-${type}" -- "${new_path}_${i}${suffix}" \
			2>/dev/null && cli_confirm "Use '${new_path}' instead [yN]? "
		then
			echo "The path '${new_path}' will be used instead." >&2
			ok='yes'
		elif [ "$cfg_ui_assumeyes" != 'yes' ]
		then
			# Ask the user for a new name.
			reply=$noreply
			while [ "$ok" != 'yes' -a -n "$reply" ]
			do
				printf '%s ' "Type a new path, press enter to continue or" \
					"Ctrl-C to abort: " >&2
				read reply || return 1

				if [ -n "$reply" ]
				then
					case "$reply" in
						"/"*) ;;
						# User most probably entered a relative file name
						# instead of a absolute path.
						*) reply="${target}/${reply}" ;;
					esac
					new_path=$reply

					if storage_iswritable  "-${type}" -- "$new_path"
					then
						echo "The path '${new_path}' will be used." >&2
						ok='yes'
					fi
				fi
			done
		fi
	fi

	if [ "$ok" = 'yes' ]
	then
		printf '%s' "$new_path"
	else
		return 1
	fi
}

###
# storage_get_backingfile image_file
#
# Outputs the path of the backing file behind `file' on stdout.
#
# If `file' has no backing file, an empty string is produced.
#
storage_get_backingfile() {
	local 'image_file' 'qemu_out'
	[ "${1-}" = '--' ] && shift
	image_file=${1:?"ERROR (BUG): storage_get_backing_file: Missing parameter."}

	qemu_out=$( qemu-img 'info' -- "$image_file" ) || return 1
	printf '%s' "$qemu_out" | grep '^backing file: ' | cut -d ' ' -f 3-
}

###
# storage_get_canonical backend_path
#
# Outputs on stddout the `backend_path' with its path section updated to
# contain a canonical path.
#
# Any prefix is kept.
#
storage_get_canonical() {
	local 'backend_path' 'path' 'prefix'
	[ "${1-}" = '--' ] && shift
	backend_path=${1:?"ERROR (BUG): storage_get_canonical: Missing parameter."}

	prefix=$( storage_get_prefix -- "$backend_path" ) || return 1
	path=$( storage_get_path -- "$backend_path" ) || return 1

	printf '%s%s' "$prefix" "$path"
}

###
# storage_get_path backend_path
#
# Outputs on stdout the path section of `backend_path'.
#
# Any prefix is stripped out.
#
storage_get_path() {
	local 'backend_path'
	[ "${1-}" = '--' ] && shift
	backend_path=${1:?"ERROR (BUG): storage_get_path: Missing parameter."}

	# Remove any access-mode prefix from the storage path
	case "$backend_path" in "rw:"*|"snap:"*|"ro:"*)
		backend_path=${backend_path#*":"}
	esac

	if [ -z "$backend_path" ]
	then
		echo "ERROR: Invalid backend path: '${1}'." >&2
		return 1
	fi

	# SC2088: The tilde must be manually expanded notably when a prefix has
	# been used.
	# shellcheck disable=SC2088
	case "$backend_path" in '~/'*)
		backend_path="${HOME}/${backend_path#"~/"}"
	esac

	if [ -e "$( dirname -- "$backend_path" )" ]
	then
		backend_path=$( realpath -- "$backend_path" ) || return 1
	fi

	printf '%s' "$backend_path"
}

###
# storage_get_prefix backend_path
#
# Outputs on stdout the prefix section of `backend_path'.
#
# This function may return one of the following strings:
#   - "" (empty string if `backend_path' has no prefix).
#   - "ro:"
#   - "rw:"
#   - "snap:"
#
storage_get_prefix() {
	local 'backend_path'
	[ "${1-}" = '--' ] && shift
	backend_path=${1:?"ERROR (BUG): storage_get_prefix: Missing parameter."}

	case "$backend_path" in "rw:"*|"snap:"*|"ro:"*)
		printf '%s:' "${backend_path%%":"*}"
	esac
}

###
# storage_isreadable [-d|-f|-h] path
#
# Checks is `file_path' is a readable, existing file not currently in use by
# any other process in read-write mode.
#
# The file may be currently in use by other processes in read-only mode.
#
# If the condition above are not met, a NOTICE message is raised.
# No higher message level is used as this may be an expected behavior, the
# caller has to raise a more context-dependant error or warning message if
# needed.
#
# Path types:
#   -d    Regular directory.
#   -h    Virtual machine home directory.
#   -f    Regular file.
#
storage_isreadable() {
	local 'dest' 'opt' 'OPTARG' 'OPTIND' 'type'
	type='f'

	OPTIND=1
	while getopts 'dfh' opt
	do
		case "$opt" in
			'd') type='d' ;;
			'f') type='f' ;;
			'h') type='h' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	dest=${1:?"ERROR (BUG): storage_isreadable: Missing parameter."}

	case "$dest" in *"$newline"*)
		echo "ERROR: New line characters are not allowed in path: '$dest'." >&2
		return 1
	esac

	case "$type" in
		'd')
			if [ ! -d "$dest" ]
			then
				echo "NOTICE: '${dest}': Path not found or not a directory." >&2
				return 1

			elif [ ! -r "$dest" ]
			then
				echo "NOTICE: ${dest}: The directory is not readable." >&2
				return 1
			fi
			;;

		'f')
			if [ ! -f "$dest" ]
			then
				echo "NOTICE: '${dest}' is not a regular file." >&2
				return 1

			elif [ ! -r "$dest" ]
			then
				echo "NOTICE: ${dest}: File not found or not readable." >&2
				return 1

			# TODO: Some work seems to be ongoing on Qemu-side to add a native locking
			# feature, this would allow to make this check more reliable:
			# https://lists.gnu.org/archive/html/qemu-devel/2016-10/msg05276.html
			# Access to image files open in read-only mode is allowed to allow actions
			# such as creating a new fork of a VM while one of its child is running.
			elif lsof -F 'f' -- "$dest" | grep -q '[uUwW]$'
			then
				echo "NOTICE: ${dest}: Another process is attempting to modify this" \
					"file." >&2
				return 1
			fi
			;;

		'h')
			if [ ! -e "${dest}/${cfg_file_vmsettings:?}" ]
			then
				echo "NOTICE: '${dest}' is not a virtual machine home" \
					"directory." >&2
				return 1
			fi
			;;
	esac
}

###
# storage_iswritable [-d|-h|-f|-n] path
#
# Check that `path' can be safely written.
#
# The path may be of various types:
#   - If it does not already exists, its parent directory must exist and be
#     writable.
#   - If it is an existing regular directory, it must be an empty and writable.
#   - If the path will be a virtual machine home directory, the directory
#     itself may already exist but must not already contain a virtual machine
#     (it is allowed for instance to already contain disk images files).
#   - If it is an already existing file, it must be writable and not currently
#     in use by any other process.
#
# If the condition above are not met, a NOTICE message is raised.
# No higher message level is used as this may be an expected behavior, the
# caller has to raise a more context-dependant error or warning message if
# needed.
#
# Path types:
#   -d    Regular directory.
#   -h    Virtual machine home directory.
#   -f    Regular file.
#   -n    New object.
#
storage_iswritable() {
	local 'dest' 'opt' 'OPTARG' 'OPTIND' 'type'
	type='f'

	OPTIND=1
	while getopts 'dfhn' opt
	do
		case "$opt" in
			'd') type='d' ;;   # Directory.
			'f') type='f' ;;   # File.
			'h') type='h' ;;   # VM home.
			'n') type='n' ;;   # New object.
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	dest=${1:?"ERROR (BUG): storage_iswritable: Missing parameter."}

	case "$dest" in *"$newline"*)
		echo "ERROR: New line characters are not allowed in path: '$dest'." >&2
		return 1
	esac

	if [ ! -e "$dest" ]
	then
		if [ ! -d "${dest%/*}" ]
		then
			echo "NOTICE: '${dest%/*}' does not exists or is not a" \
				"directory." >&2
			return 1
		elif [ ! -w "${dest%/*}" ]
		then
			echo "NOTICE: '${dest%/*}' is not writable." >&2
			return 1
		fi
	else
		case "$type" in
			'd'|'h')
				if [ ! -d "$dest" ]
				then
					echo "NOTICE: '${dest}' is not a directory." >&2
					# SC2012: Informational output, special chars are no issue.
					# shellcheck disable=SC2012
					ls -Al -- "$dest" | sed 's/^/    /' >&2
					return 1
				elif [ -e "${dest}/${cfg_file_vmsettings:?}" ]
				then
					echo "NOTICE: ${dest}: This path is an already existing" \
						"virtual machine home." >&2
					return 1
				elif [ "$type" = 'd' -a -n "$( ls -AU -- "$dest" )" ]
				then
					echo "NOTICE: ${dest}: The directory is not empty:" >&2
					# SC2012: Informational output, special chars are no issue.
					# shellcheck disable=SC2012
					ls -Al -- "$dest" | sed 's/^/    /' >&2
					return 1
				elif [ ! -w "$dest" ]
				then
					echo "NOTICE: ${dest}: The directory is not writable." >&2
					# SC2012: Informational output, special chars are no issue.
					# shellcheck disable=SC2012
					ls -dl -- "$dest" | sed 's/^/    /' >&2
					return 1
				fi
				;;

			'f')
				if [ ! -f "$dest" ]
				then
					echo "NOTICE: '${dest}' is not a regular file." >&2
					return 1
				elif [ ! -w "$dest" ]
				then
					echo "NOTICE: ${dest}: This file exists but is not" \
						"writable." >&2
					return 1
				elif lsof -- "$dest" >/dev/null
				then
					echo "NOTICE: ${dest}: This file is currently in use by" \
						"another process." >&2
					return 1
				fi
				;;

			'n')
				echo "NOTICE: '${dest}' already exists." >&2
				# SC2012: Informational output, special chars are no issue.
				# shellcheck disable=SC2012
				ls -ld -- "$dest" | sed 's/^/    /' >&2
				return 1
				;;

			*)
				echo "ERROR (BUG): storage_iswritable: Invalid value for \$type:" \
					"'${type}'." >&2
				return 1
		esac
	fi
}

################################################################################
### /usr/local/lib/vmtols/hdd.inc.sh END
################################################################################
