################################################################################
### /usr/local/lib/vmtools/childs.inc.sh BEGIN
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
# This library handles childs database, listing the path of every direct fork
# of a VM (parent-to-childs links).
#
# The database itself is stored in the file `$cfg_file_childs' in the parent's
# VM home directory. The file contains one canonical path to a child's VM home
# per line. When there is no child the file is usually deleted.
#
# See also `parent.inc.sh' for the handling of the child-to-parent link.
#
# Public functions:
#   childs_add [-f] parent_dir child_dir...
#         Add a new child to a childs list DB.
#   childs_clear [parent_dir]
#         Delete the content of a childs list DB.
#   childs_get_list [parent_dir]
#         Return the content of a childs list DB.
#   childs_init [parent_dir]
#         Explicitely load a child list DB.
#   childs_remove parent_dir child_dir...
#         Remove a child from a childs list DB.
#   childs_save parent_dir
#         Save the modifications made to a childs list DB.
#
################################################################################

################################################################################
# Global variables
################################################################################

# Path to the parent VM home directory.
childs_vmhome=''

# Content of the childs list database.
# Do not access it directly, use the `childs_*()' functions.
childs_list=''


################################################################################
# Functions
################################################################################

###
# childs_add [-f] parent_dir child_dir...
#
# Loads the childs list from `parent_dir' if it is not already loaded and adds
# `child_dir' as a new child.
#
# Childs already belonging to the list are silently ignored.
# An error will be raised if the child path contains a newline character.
# This operation only alters the childs lit in memory, see `childs_save()' to
# update the childs list file.
#
# See `childs_remove()' for the opposite operation.
#
# Options:
#   -f    Force the addition: do not check the child existence.
#
childs_add() {
	local 'child_dir' 'force' 'opt' 'OPTARG' 'OPTIND' 'parent_dir'
	force='no'

	OPTIND=1
	while getopts 'f' opt
	do
		case "$opt" in
			'f') force='yes' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	if [ $# -lt 2 ]
	then
		echo "ERROR (BUG): childs_add: Missing parameter." >&2
		return 1
	fi

	parent_dir=$1
	childs_init -- "$parent_dir" || return 1
	shift

	for child_dir
	do
		if [ "$child_dir" = "$parent_dir" ]
		then
			echo "ERROR (BUG): childs_add: Attempt to add '${child_dir}' as" \
				"it's own child." >&2
			return 1
		fi

		if [ "$force" != 'yes' ]
		then
			storage_isreadable -h -- "$child_dir" || return 1
		else
			# Always check that the name does not contain invalid characters.
			case "$child_dir" in *"$newline"*)
				echo "ERROR: Carriage returns are not supported in directory" \
					"names." >&2
				return 1
			esac
		fi

		# `str_list_add()' rejects names containing line feeds.
		str_list_add 'childs_list' "$child_dir" || return 1
	done

	childs_list=$( printf '%s' "$childs_list" | LC_ALL=C sort -u ) || return 1
}

###
# childs_clear [parent_dir]
#
# Delete the content of a childs list.
#
# This function does not modify any file, see `childs_save()'.
# Any parameter is directly passed to `childs_init()' to identify the childs
# list to load.
#
childs_clear() {
	childs_init "$@" || return 1
	cli_trace 4 "childs_clear: ${childs_vmhome}: Clearing child list."
	childs_list=''
}

###
# childs_get_list [parent_dir]
#
# Return the content of a childs list on the standard output..
#
# Any parameter is directly passed to `childs_init()' to identify the childs
# list to load.
#
childs_get_list() {
	childs_init "$@" || return 1
	printf '%s' "$childs_list"
}

###
# childs_init [parent_dir]
#
# Load the childs list from `parent_dir'.
#
# A warning is raised if this list contains invalid childs.
#
childs_init() {
	local 'c' 'child' 'childs_nf' 'childsdb' 'dir' 'newlist'
	[ "${1-}" = '--' ] && shift
	dir=${1:-"${vm_home:?}"}

	if [ -n "$childs_vmhome" -a "$childs_vmhome" = "$dir" ]
	then
		return 0
	fi
	childs_vmhome=$dir
	childsdb="${childs_vmhome}/${cfg_file_childs:?}"

	if [ -s "$childsdb" ]
	then
		cli_trace 4 "childs_init: ${childs_vmhome}: Loading childs list."
		childs_list=$( cat "$childsdb" ) || return 1
		childs_nf=''
		for c in $childs_list
		do
			if [ ! -f "${c}/${cfg_file_vmsettings:?}" ]
			then
				str_list_add 'childs_nf' "$c"
			fi
		done
		if [ -n "$childs_nf" ]
		then
			echo "WARNING: ${childsdb}: This file references some childs" \
				"which don't seem to exist anymore:" >&2
			printf '    %s\n' $childs_nf
			echo "Use 'vmfix -p' to unregister them." >&2
		fi
	else
		cli_trace 4 "childs_init: ${childs_vmhome}: No child."
		childs_list=''
	fi
}

###
# childs_remove parent_dir child_dir...
#
# Loads the childs list from `parent_dir' if it is not already loaded and
# remove `child_dir' from the list.
#
# A warning is raised if `child_dir' is not part of the list.
# This operation only alters the childs lit in memory, see `childs_save()' to
# update the childs list file.
#
# See `childs_clear()' to remove all childs at once.
# See `childs_add()' for the opposite operation.
#
childs_remove() {
	local 'child_dir' 'childslist_old' 'parent_dir'
	[ "${1-}" = '--' ] && shift

	if [ $# -lt 2 ]
	then
		echo "ERROR (BUG): childs_remove: Missing parameter." >&2
		return 1
	fi

	parent_dir=$1
	childs_init -- "$parent_dir" || return 1
	shift

	for child_dir
	do
		if [ "$childs_list" = "$child_dir" ]
		then
			childs_list=''
		else
			childslist_old=$childs_list
			str_list_remove 'childs_list' "^$( str_escape_grep "$child_dir" )\$"
			if [ "$childs_list" = "$childslist_old" ]
			then
				echo "WARNING: '${child_dir}' is not a child of" \
					"'${parent_dir}'." >&2
			fi
		fi
	done
}

###
# childs_save parent_dir
#
# Update `parent_dir' childs list file.
#
# `parent_dir' must have been locked by the caller.
# It is considered a bug to call this function without having previously loaded
# `parent_dir' childs list.
# This function creates a backup of the original childs list to allow rollbacks.
#
childs_save() {
	local 'childsdb'
	[ "${1-}" = '--' ] && shift
	parent_dir=${1:?"ERROR (BUG): childs_save: Missing parameter."}

	if [ -z "${childs_vmhome-}" ]
	then
		echo "ERROR (BUG): childs_save: Trying to save uninitialized childs." \
			>&2
		return 1
	fi
	if [ "$parent_dir" != "$childs_vmhome" ]
	then
		echo "ERROR (BUG): childs_save: Save target does not match" \
			"\$childs_vmhome." >&2
		return 1
	fi
	childsdb="${childs_vmhome}/${cfg_file_childs:?}"
	cli_trace 4 "childs_save: ${childs_vmhome}: Save childs list."

	lock_check -e -- "$childs_vmhome" || return 1
	cleanup_backup -m -- "$childsdb" || return 1

	if [ -n "$childs_list" ]
	then
		printf '%s\n' "$childs_list" >"$childsdb" || return 1
	fi
}

################################################################################
### /usr/local/lib/vmtools/childs.inc.sh BEGIN
################################################################################
