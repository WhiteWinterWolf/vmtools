################################################################################
### /usr/local/lib/vmtools/homedir.inc.sh BEGIN
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
# This library provides virtual machine home directories handling functions.
# See also `storage.inc.sh' for path and storage related functions.
#
# Public functions:
#   homedir_delete [-afr] vmhome_dir...
#         Delete virtual machine home directories.
#   homedir_get_size [path]
#         Returns the disk space occupied by a VM home directory.
#   homedir_init [-d] path
#         Initialize a new VM home directory.
#
################################################################################

################################################################################
# Functions
################################################################################

###
# homedir_clear [-a] [directory]
#
# Delete the content of `directory'.
#
# The directory to delete must already exist and be locked by the caller.
# If it is a VM home directory, it must have no child and its parent (if any)
# must also be locked by the caller (this function will update its childs list).
# If no `directory' is given `$vm_home' is used by default.
#
# This is a rather low-level function, under most circumstances you will most
# likely wish to call `homedir_delete()' instead.
#
# Unlike `homedir_delete()', this function accepts only a single directory as
# parameter.
#
# Options:
#   -a    Delete everything, including unknown files and subdirectories.
#   -f    Do not ask confirmation before deleting a virtual machine.
#
homedir_clear() {
	local 'childs' 'deleteall' 'dir' 'file' 'force' 'filesettings' 'opt'
	local 'OPTARG' 'OPTIND' 'parent_path' 'setting' 'todelete' 'vm_home'
	deleteall='no'
	force='no'

	OPTIND=1
	while getopts 'af' opt
	do
		case "$opt" in
			'a') deleteall='yes' ;;
			'f') force='yes' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))

	dir="${1:-"${vm_home:?}"}"
	lock_check -e -- "$dir" || return 1

	# Prevent any confusion with `homedir_delete()' which accepts several
	# arguments.
	if [ $# -gt 1 ]
	then
		echo "ERROR (BUG): homedir_clear: Too many arguments ($#:" \
			"$( str_escape -- "$@" ))." >&2
		return 1
	fi

	# Handle existing VM home directory specifically
	if [ -e "${dir}/${cfg_file_vmsettings:?}" ]
	then
		# The VM to delete must have no child
		childs=$( childs_get_list -- "$dir" ) || return 1
		if [ -n "$childs" ]
		then
			echo "ERROR: ${dir}: This directory cannot be modifed as it" \
				"contains a virtual machine with childs:" >&2
			printf '    %s\n' $childs >&2
			echo "Use 'vmrm -r' to delete a virtual machine recursively." >&2
			return 1
		fi

		if test "$force" != 'yes' \
			&& ! cli_confirm "Delete the virtual machine '${dir}' [yN]? "
		then
			return 1
		fi

		# If it has any parent, parent's childs list must be updated
		parent_path=$( parent_get_nearest -- "$dir" ) || return 1
		if [ -n "$parent_path" ]
		then
			childs_remove -- "$parent_path" "$dir" || return 1
			childs_save -- "$parent_path" || return 1
		fi

		# Delete all vmtools' own files (except the lock file).
		filesettings=$( set | awk -F '=' '/^cfg_file_/ { print $1 }' )
		if [ -z "$filesettings" ]
		then
			echo "ERROR (BUG): No 'cfg_files_*' setting found." >&2
			return 1
		fi
		todelete=''
		for setting in $filesettings
		do
			case "$setting" in
				'cfg_file_lock'|'cfg_file_tmpdir')
					# Don't delete the lock file. The tmpdir is a template (and
					# should not be silently deleted anyway).
					;;
				*)
					eval "file=\${$setting:?}"
					file="${dir%/}/${file}"
					# The file may or may not exist, this is properly handled by
					# `cleanup_backup()'.
					str_list_add 'todelete' "$file"
					;;
			esac
		done
		# `cleanup_backup()' is used as a reversible `rm'.
		# `$todelete' has been set using `str_list_add()' so is safe unquoted..
		cleanup_backup -m -- ${todelete:?} || return 1
	fi

	#  Delete other files if required
	if [ "$deleteall" = 'yes' ]
	then
		# SC2044: Globing disabled, IFS=\n.
		# shellcheck disable=SC2044
		for file in $( find "$dir" -mindepth 1 -maxdepth 1 \
			-a \! -path "*${newline}*" -a \! -name "${cfg_file_lock:?}" )
		do
			# SC2015: `printf 'directory'' should return true.
			# shellcheck disable=SC2015
			if cli_confirm "Delete the $( [ -d "$file" ] && printf 'directory' \
				|| printf 'file' ) '${file}' (Ctrl-C to abort) [yN]? "
			then
				cleanup_backup -m -- "$file"
			fi
		done
	fi
}

###
# homedir_delete [-afr] vmhome_dir...
#
# Delete virtual machine home directories.
#
# All the directories to delete must have been previously locked, the parent
# of the highest directory to delete must also be locked.
#
# See `homedir_init()' for the opposite operation.
#
# Options:
# -a    Delete all, including unknown files and subdirectories.
# -f    Do not ask confirmation before deleting a virtual machine.
# -r    Enable recursive mode: delete all childs too.
#
homedir_delete() {
	local 'deleteall_opts' 'childs' 'dir' 'OPTARG' 'OPTIND' 'recursive'
	local 'recursive_opt'
	deleteall_opt=''
	recursive='no'

	OPTIND=1
	while getopts "afr" opt
	do
		case "$opt" in
			'a'|'f') deleteall_opt="${deleteall_opt}${opt}" ;;
			'r') recursive='yes' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	if [ $# -eq 0 ]
	then
		"ERROR (BUG): homedir_delete: Missing parameter."
		return 1
	fi

	for dir
	do
		dir=$( realpath -- "$dir" ) || return 1

		# Set temporary directory to the parent directory.
		# It must be writeable otherwise it will never be possible to delete
		# `$dir' itself.
		if [ ! -w "${dir%/*}" ]
		then
			echo "ERROR: ${dir%/*}: The directory is not writable." >&2
			return 1
		fi
		# We cannot simply span a sub-shell and reset the `cleanup' data
		# structure as this would break global rollback for larger commands
		# like `vmmerge'.
		if [ -z "$cleanup_tmpdir" ]
		then
			cleanup_set_tmpdir -- "${dir%/*}" || return 1
		fi

		# Delete files and directories
		if [ "$recursive" = 'yes' ]
		then
			childs=$( childs_get_list -- "$dir" ) || return 1
			if [ -n "$childs" ]
			then
				# SC2086: Word splitting expected on `$childs'.
				# shellcheck disable=SC2086
				homedir_delete -r ${deleteall_opt:+"-${deleteall_opt}"} -- \
					$childs || return 1
			fi
		fi
		homedir_clear ${deleteall_opt:+"-${deleteall_opt}"} -- "$dir" \
			|| return 1

		lock_release -- "$dir" || return 1
		if [ -z "$( ls -AU -- "$dir" )" ]
		then
			cleanup_add mkdir -- "$dir"
			rmdir -- "$dir" || return 1
		else
			echo "WARNING: ${dir}: The directory is not empty and has not" \
				"been deleted." >&2
		fi
	done
}

###
# homedir_get_size [path]
#
# Returns the disk space occupied by `path' or by `$vm_home' if no `path' has
# been provided on stdout.
#
# This function counts only the size of the files located directly below `path',
# it does not count files located in subdirectories (like childs VM) or in
# external directory (like external disk images).
# This function counts the space really used by a file, which may be smaller
# than the logical size of the file in case of sparse files.
#
homedir_get_size() {
	local 'dir' 'find_out'
	[ "${1-}" = '--' ] && shift
	dir=${1:-"${vm_home:?}"}

	find_out=$( find "$dir" -mindepth 1 -maxdepth 1 -type 'f' \
		-exec du -k '{}' + ) || return 1

	printf '%s' "$find_out" | awk '{ SUM += $1 } END { print SUM }'
}

###
# homedir_init [-d] path
#
# Initialize the given path as a VM home directory, acquire a lock on it and
# sets `$vm_home'and `$vm_name' accordingly.
#
# See `homedir_delete()' for the opposite operation.
# See also `storage_createpath()' to generate a new valid path for this VM.
#
homedir_init() {
	local 'clear_opts' 'oldparent' 'opt' 'OPTARG' 'OPTIND'
	oldparent=''
	clear_opts=''

	OPTIND=1
	while getopts 'd' opt
	do
		case "$opt" in
			'd') clear_opts='-a' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))

	vm_home=${1:?"ERROR (BUG): homedir_init: Missing parameter."}
	vm_home=$( realpath -- "${vm_home%"/${cfg_file_vmsettings:?}"}" ) \
		|| return 1
	# `vm_name' set for the calling environment.
	# shellcheck disable=SC2034
	vm_name=${vm_home##*/}

	case "$vm_home" in *"$newline"*)
		echo "ERROR: New line characters are not allowed in path:" \
			"'${vm_home}'." >&2
		return 1
	esac

	# The calling environment must not inherit an incoherent VM home and parent
	# information.
	parent_clear

	if [ -e "$vm_home" ]
	then
		lock_acquire -- "$vm_home" || return 1
		if [ -e "${vm_home}/${cfg_file_vmsettings:?}" ]
		then
			oldparent=$( parent_get_nearest -- "$vm_home" ) || return 1
			if [ -n "$oldparent" ]
			then
				# Parent must be locked for `homedir_clear()'.
				lock_acquire -- "$oldparent" || return 1
			fi
		fi
	else
		# VM home parent dir already exists, otherwise the call to `realpath'
		# above should have failed.
		mkdir -- "$vm_home" || return 1
		# Changed from `rmdir' to `rm -rf' as interrupted recursive copy would
		# not been correctly cleaned otherwise (when a branch has been
		# correctly copied but must be deleted because another branch failed).
		cleanup_add rm -rf -- "$vm_home"
		lock_acquire -- "$vm_home" || return 1
	fi

	homedir_clear ${clear_opts:+"$clear_opts"} || return 1

	if [ -n "$oldparent" ]
	then
		lock_release -- "$oldparent" || return 1
	fi
}

################################################################################
### /usr/local/lib/vmtools/homedir.inc.sh END
################################################################################
