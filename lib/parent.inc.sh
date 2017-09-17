################################################################################
### /usr/local/lib/vmtools/parent.inc.sh BEGIN
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
# This library handles child-to-parent links, including the recursive loading
# of parents' VM settings files.
#
# See also `childs.inc.sh' for the handling of the parent-to-childs links.
# See also `settings.inc.sh' for the storage of the parent path into the
# VM setting file.
#
# Public variables:
#   parent_follow='yes'
#         If "yes", enable recursive inheritance from parents' settings.
#
# Public functions:
#   parent parent_path
#         Add a new parent and load its settings.
#   parent_add [-f] directory
#         Add a new parent.
#   parent_clear
#         Reset this library internal state.
#   parent_get_furthest [vmhome_dir]
#         Get VM's furthest parent path.
#   parent_get_nearest [vmhome_dir]
#         Get VM's nearest parent path.
#   parent_isempty
#         Check if the current VM has no parent.
#
################################################################################

################################################################################
# Global variables
################################################################################

# Set to "yes" to enable parent inheritance, otherwise only the VM settings
# file loca to the current VM will be loaded and any parent setting will be
# ignored.
# This setting may be configured directly by calling functions.
parent_follow='yes'

# Closest and furthest parent of the current VM.
# These values may remain empty when the current node has no parent.
parent_nearest=''
parent_furthest=''

# Parent nesting level.
# This variable is increased for each new nested parent and allows to detect
# infinite loops.
parent_nestinglvl=0

# Home directory of the current VM.
parent_vmhome=''


################################################################################
# Functions
################################################################################

###
# parent parent_path
#
# Add the new parent `parent_path' to the current virtual machine ancestry and
# load its settings.
#
# The current VM is determined using the `$vm_home' variable. Use `parent_clear'
# to reset this library internal state and switch to another virtual machine.
#
# This statement is designed to be called directly from a VM settings file.
#
# See also `parent_add()' to only update the virtual machine parentage.
#
parent() {
	[ "${1-}" = '--' ] && shift
	parent_add -- "$1" || return 1

	if [ "$template_nestinglvl" -ne 0 ]
	then
		echo "ERROR: A template must not use the 'parent' keyword." >&2
		echo "Current templates: $( template_get_list )." >&2
		return 1
	fi

	if [ "$parent_follow" = 'yes' ]
	then
		if [ "$parent_nestinglvl" -ge "${cfg_limit_nesting:?}" ]
		then
			echo "ERROR: A loop has been detected in parent nesting." >&2
			echo "Current parent: '${parent_furthest}'." >&2
			return 1
		fi

		parent_nestinglvl=$(( parent_nestinglvl + 1 ))
		include_vmsettings -- "${parent_furthest}/${cfg_file_vmsettings:?}" \
			|| return 1
		parent_nestinglvl=$(( parent_nestinglvl - 1 ))
	fi
}

###
# parent_add [-f] directory
#
# Add a new parent to the current virtual machine ancestry.
#
# The current VM is determined using the `$vm_home' variable. Use `parent_clear'
# to reset this library internal state and switch to another virtual machine.
#
# This function only operates in memory. To actually saved a modified parent
# path, see `settings_save()'. See also `settings_setparent()' which makes the
# whole process of reseting this library and updating parent's path more
# straightforward.
#
# Options:
#   -f    Force the addition, do not check parent existence.
#
parent_add() {
	local 'force' 'opt' 'OPTARG' 'OPTIND'
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

	if [ $# -ne 1 ]
	then
		echo "ERROR: ${parent_furthest:-$vm_home}/${cfg_file_vmsettings}:" \
			"'parent' accepts only one single mandatory argument" \
			"(${#} provided)." >&2
		return 1
	elif [ -z "$1" ]
	then
		echo "ERROR: ${parent_furthest:-$vm_home}/${cfg_file_vmsettings}:" \
			"'parent' path is empty." >&2
		return 1
	elif [ "$force" != 'yes' -a ! -r "${1}/${cfg_file_vmsettings:?}" ]
	then
		echo "WARNING: ${parent_furthest:-$vm_home}/${cfg_file_vmsettings}:" \
			"The parent '${1}' does not exists or does not contain any" \
			"valid virtual machine." >&2
	fi

	parent_checkinit || return 1

	if [ -z "$parent_nearest" ]
	then
		parent_nearest=$1
		parent_vmhome=${vm_home:?}
	fi
	cli_trace 4 "parent_add: ${parent_furthest:-"$parent_vmhome"}: Has a" \
		"parent: '${1}' (parent_follow='${parent_follow}')."
	parent_furthest=$1
}

###
# parent_clear
#
# Reset this library internal state.
#
# This function is useful:
#   - To clear this library internal state before loading a new virtual machine.
#   - To clear current VM ancestry tree before setting it a new parent path.
#
parent_clear() {
	parent_nearest=''
	parent_furthest=''
	# `$vm_home' is empty when called by `settings_reset()'.
	parent_vmhome=${vm_home:-}
}

###
# parent_get_furthest [vmhome_dir]
#
# Outputs the furthest parent of `vmhome_dir', or the current VM if no
# parameter is provided, on stdout..
#
# If a `vmhome_dir' parameter is given, this function does not require any
# reinitialisation of this library state before being called.
#
parent_get_furthest() {
	local 'dir'
	[ "${1-}" = '--' ] && shift
	dir=${1-}
	cli_trace 4 "parent_get_furthest: ${dir}: Read furthest parent."

	# Acceptable to have `$vm_home' empty at this point.
	if [ -n "$dir" -a "$dir" != "$vm_home" ]
	then
		(
			settings_loadvm -- "$dir" || exit 1

			printf '%s' "$parent_furthest"
		) || return 1
	else
		parent_checkinit || return 1
		printf '%s' "$parent_furthest"
	fi
}

###
# parent_get_nearest [vmhome_dir]
#
# Outputs the nearest parent of `vmhome_dir', or the current VM if no
# parameter is provided, on stdout
#
# If a `vmhome_dir' parameter is given, this function does not require any
# reinitialisation of this library state before being called.
#
parent_get_nearest() {
	local 'dir'
	[ "${1-}" = '--' ] && shift
	dir=${1-}

	# Acceptable to have `$vm_home' empty at this point.
	if [ -n "$dir" -a "$dir" != "$parent_vmhome" ]
	then
		(
			settings_loadvm -s -- "$dir" || exit 1
			printf '%s' "$parent_nearest"
		) || return 1
	else
		parent_checkinit || return 1
		printf '%s' "$parent_nearest"
	fi
}

###
# parent_checkinit
#
# Check if this library internal state has been correctly initialized with
# the current VM (as defined by the `$vm_home' variable).
#
# This function is not meant to be called directly outside of this library.
#
parent_checkinit() {
	if [ -z "$parent_vmhome" -o "$parent_vmhome" != "${vm_home:?}" ]
	then
		printf 'ERROR (BUG): parent_checkinit: Parent structure not initialized.\n' \
			>&2
		return 1
	fi
}

###
# parent_isempty
#
# Return true if the currently selected VM has no parent.
#
parent_isempty() {
	parent_checkinit || return 1
	test -z "$parent_nearest"
}

################################################################################
### /usr/local/lib/vmtools/parent.inc.sh END
################################################################################
