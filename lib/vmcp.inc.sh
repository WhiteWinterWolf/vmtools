################################################################################
### /usr/local/lib/vmtools/vmcp.inc.sh BEGIN
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
# This library handles the copy of a virtual machine from one location to
# another.
#
# Several copy modes are supported, in each mode the resulting VM will have a
# similar content than its source:
#   - Default copy: the resulting VM shares the same parent as its source.
#   - Fork: the resulting VM is a child of the source VM.
#   - Autonomous copy: the resulting VM does not depend on any parent VM.
#
# The only differences between the the source and destination VM are handled
# by the customizables "clone" modules (by default it affects storage image
# path and network MAC address).
#
# The copy may be recursive, two kinds of recursion are supported:
#   - Child-based recursion: all source's childs will be copied as
#     destination's childs.
#   - Directory-based recursion: all VM located below the source path (which
#     may in this case not necessarily be a VM home directory) will be copied
#     below the destination path.
#
# These two recursion types can be combined to execute a child-based recursive
# copy of all VM located below a path.
#
# See `vmcp_copy_single()' for implementation details on the various copy types.
#
# Public functions:
#   vmcp_copy source target
#         Copy the virtual machine `source' to `target'.
#   vmcp_parseargs_args arg...
#         Parse command-line arguments, sets `$vmcp_*' global variables.
#
################################################################################

################################################################################
# Global variables
################################################################################

# The settings below should be set using the `vmcp_parseargs_args()' function.

# Name of action to perform: 'copy', 'autonomous copy' or 'fork'.
# This variable is also used by the clone modules to determine what to do.
vmcp_action=''

# If set to 'yes', parent's unique properties like the MAC address will be
# inherited by the child VM.
vmcp_clone_inherit='no'

# If "yes", enable recursion over virtual machine childs.
vmcp_recurse_childs='no'

# If "yes", enable recursion over given path subdirectories.
vmcp_recurse_directories='no'

# If "yes", use snapshot for all writable storage backends.
vmcp_snapshot='no'

# If "yes", the source VM is considered read-only.
vmcp_readonly='no'


################################################################################
# Functions
################################################################################

###
# vmcp_copy source target
#
# Copy the virtual machine `source' to `target'.
#
# If `target' is an already existing directory, `source' will be created as a
# subdirectory of `target', otherwise `target' will directly contain the copied
# virtual machine.
#
# SC2030: This function executes itself in a subshell.
# shellcheck disable=SC2030
#
vmcp_copy() (
	local 'action_old' 'dst' 'lock_opt' 'recurse_done'
	local 'recurse_dst_root' 'recurse_src_root' 'src' 'src_parent_path'
	[ "${1-}" = '--' ] && shift
	cleanup_reset

	# Set the source directory.
	src=${1:?"ERROR (BUG): vmcp_copy: Missing parameter."}
	src=$( realpath -- "$src" ) || return 1

	# Set the destination directory.
	dst=${2:?"ERROR (BUG): vmcp_copy: Missing parameter."}
	if [ -d "$dst" ]
	then
		dst=$( storage_createpath -d -t "$dst" -- "$src" ) || return 1
	else
		dst=$( storage_createpath -d -t "$dst" -- '' ) || return 1
	fi
	homedir_init -- "$dst" || return 1
	dst=$vm_home

	# Lock the source directory.
	lock_opt=''
	[ "$vmcp_recurse_childs" = 'yes' ] && lock_opt="${lock_opt}c"
	[ "$vmcp_recurse_directories" = 'yes' ] && lock_opt="${lock_opt}d"
	if [ "$vmcp_readonly" = 'yes' ]
	then
		lock_acquire ${lock_opt:+"-${lock_opt}"} -n -- "$src" || return 1
	else
		lock_acquire ${lock_opt:+"-${lock_opt}"} -- "$src" || return 1
		src_parent_path=$( parent_get_nearest -- "$src" ) || return 1
		if [ -n "$src_parent_path" ]
		then
			lock_acquire -- "$src_parent_path" || return 1
		fi
	fi

	# Copy the VM.
	action_old=$vmcp_action
	recurse_done=''
	recurse_dst_root=$dst
	recurse_src_root=$src
	vmcp_copy_recurse -- 1 "$src" "$dst" || return 1

	# Unlock both the source and destination directories.
	if [ "$vmcp_readonly" != 'yes' ]
	then
		if [ -n "$src_parent_path" ]
		then
			lock_release -- "$src_parent_path" || return 1 1
		fi
		lock_release ${lock_opt:+"-${lock_opt}"} -- "$src" || return 1
	fi
	lock_release -d -- "$dst" || return 1
	cleanup_end
)

###
# vmcp_copy_recurse level source destination
#
# This is a helper and is not designed to be called outside of this library.
#
# This function implements recursion, the copy itself is delegated to
# `vmcp_copy_single()'.
#
# SC2031: This function is invoked by `vmcp_cp()', it has access to its
# variables.
# shellcheck disable=SC2031
#
vmcp_copy_recurse() {
	local 'dst' 'level' 'src' 'src_child' 'src_childs_list' 'src_parent_path'
	local 'src_subdir' 'src_subdirs_list' 'vm_home'
	[ "${1-}" = '--' ] && shift
	level=${1:?"ERROR (BUG): vmcp_copy_recurse: Missing parameter."}
	src=${2:?"ERROR (BUG): vmcp_copy_recurse: Missing parameter."}
	dst=${3:?"ERROR (BUG): vmcp_copy_recurse: Missing parameter."}

	level=$(( level + 1 ))
	if [ "$level" -ge "${cfg_limit_nesting:?}" ]
	then
		echo "ERROR: A loop has been detected during the copy process." >&2
		echo "Current source: '${src}'." >&2
		return 1
	fi

	if [ ! -d "$src" ]
	then
		echo "ERROR: ${src}: The source path is not a valid directory." >&2
		return 1
	elif test "$vmcp_readonly" != 'yes' && ! lock_check -- "$src"
	then
		 echo "ERROR: ${src}: The source path is not locked." >&2
		 return 1
	fi

	if ! printf '%s' "$recurse_done" | grep -Fqx "$src"
	then
		str_list_add 'recurse_done' "$src" || return 1

		# Copy directories and VMs.

		if [ "$vmcp_recurse_directories" = 'yes' \
		-a ! -e "${src}/${cfg_file_vmsettings:?}" ]
		then
			# Recursing over a directory which does not contain a VM:
			# Simply create an empty directory.
			dst="${dst}/${src##*/}"
			if [ ! -e "$dst" ]
			then
				mkdir -- "$dst" || return 1
			fi
			lock_acquire -- "$dst" || return 1
		else
			# If we are recursively copying a tree, ensure we copy the parent
			# first if it is located at a lower level to avoid dependency
			# issues.
			if [ "$vmcp_recurse_directories" = 'yes' ]
			then
				src_parent_path="$( parent_get_nearest -- "$src" )" || return 1
				if [ -n "$src_parent_path" ]
				then
					dst_parent_path=$( vmmv_mvpath -- "${recurse_src_root:?}" \
						"${recurse_dst_root:?}" "$src_parent_path" ) || return 1

					if test "$dst_parent_path" != "$src_parent_path" && \
						! printf '%s' "$recurse_done" \
						| grep -Fqx "$src_parent_path"
					then
						vmcp_action='recursive copy'
						vmcp_copy_recurse -- "$level" "$src_parent_path" \
							"$dst_parent_path" || return 1
					fi
				fi
			fi

			# Check `$dst' value.
			if [ "$src" = "${recurse_src_root:?}" ]
			then
				# Initial round, the destination should have been locked by
				# `vmcp_copy()'.
				lock_check -e -- "$dst" || return 1
				vm_home=$dst
			else
				# Following rounds: destination is locked by `homedir_init()'.
				dst=$( storage_createpath -h -t "$dst" -- '' "$src" ) \
					|| return 1
				homedir_init -- "$dst" || return 1
				# `$vm_home' contains the canonical path to `$dst'.
				dst=$vm_home
			fi

			vmcp_copy_single -- "$src" "$dst" || return 1
		fi

		# Handle recursion.

		# Process drectory-based recursion first as it must respect source
		# directories structure.
		if [ "$vmcp_recurse_directories" = 'yes' ]
		then
			src_subdirs_list=$( find "$src" -mindepth 1 -maxdepth 1 \
				\! -path "*${newline:?}*" -type d ) || return 1
			for src_subdir in $src_subdirs_list
			do
				vmcp_action='recursive copy'
				vmcp_copy_recurse -- "$level" "$src_subdir" "$dst" || return 1
			done
		fi

		# Process child-based recursion to complete directory-based
		# generated directory tree with external VMs.
		if [ "$vmcp_recurse_childs" = 'yes' \
			-a -e "${src}/${cfg_file_vmsettings:?}" ]
		then
			src_childs_list=$( childs_get_list -- "$src" ) || return 1
			for src_child in $src_childs_list
			do
				vmcp_action='recursive copy'
				vmcp_copy_recurse -- "$level" "$src_child" "$dst" || return 1
			done
		fi
	fi
}

###
# vmcp_copy_single source destination
#
# This is a helper for `vmcp_copy()' and is not designed to be called from
# outside of this library.
#
# This function implements the actual copy of the VM and the invocation of the
# "clone" modules through `vmcp_invoke_modules()'.
#
# SC2031: This function is invoked by `vmcp_cp()', it has access to its
# variables.
# shellcheck disable=SC2031
#
vmcp_copy_single() {
	local 'comment' 'dst' 'dst_parent_path' 'src' 'src_parent_path' 'vm_home'
	[ "${1-}" = '--' ] && shift
	src=${1:?"ERROR (BUG): vmcp_copy_single: Missing parameter."}
	dst=${2:?"ERROR (BUG): vmcp_copy_single: Missing parameter."}

	dst_parent_path=''
	src_parent_path=$( parent_get_nearest -- "$src" ) || return 1
	if [ "${vmcp_action:?}" = 'recursive copy' ]
	then
		if [ -n "$src_parent_path" ]
		then
			dst_parent_path=$( vmmv_mvpath -- "${recurse_src_root:?}" \
				"${recurse_dst_root:?}" "$src_parent_path" ) || return 1
		fi
		if [ "$dst_parent_path" = "$src_parent_path" ]
		then
			# The source's parent is located outside of the recursion tree:
			# We need to apply the initial action.
			vmcp_action=${action_old:?}
		fi
	fi

	case "${vmcp_action:?}" in
		'copy')
			cli_trace 3 "${src}: Copy to '${dst}'."
			settings_import -s -- "$src" || return 1
			comment="Copied from '${vm_name}':${newline}${src}"
			vm_home=$dst
			vm_name=${dst##*/}

			parent_clear
			if [ -n "$src_parent_path" ]
			then
				parent_add -- "$src_parent_path" || return 1
			fi

			vmcp_invoke_modules -- "$src" || return 1
			settings_save "$comment" "$dst" || return 1

			if [ "$vmcp_readonly" != 'yes' ]
			then
				if [ -n "$src_parent_path" ]
				then
					childs_add -- "$src_parent_path" "$dst" || return 1
					childs_save -- "$src_parent_path" || return 1
				fi
			fi
			;;

		'fork')
			cli_trace 3 "${src}: Fork to '${dst}'."
			# Do not use `settings_import()' as forked VM must contain only
			# modified settings and inherit the rest from their ancestors.
			settings_loadvm -- "$src" || return 1
			comment="Forked from '${vm_name}':${newline}${src}"
			vm_home=$dst
			vm_name=${dst##*/}

			parent_clear
			parent_add -- "$src" || return 1

			vmcp_invoke_modules -- "$src" || return 1
			settings_save "$comment" "$dst" || return 1

			childs_add -- "$src" "$dst" || return 1
			childs_save -- "$src" || return 1
			;;

		'recursive copy')
			settings_import -s -- "$src" || return 1
			comment="Recursive copy of '${vm_name}':${newline}${src}"
			vm_home=$dst
			vm_name=${dst##*/}

			# Update parent link
			parent_clear
			if [ -n "$src_parent_path" ]
			then
				if [ "$vmcp_recurse_directories" = 'yes' ]
				then
					cli_trace 3 "${src}: Directory-recursive copy to" \
						"'${dst}'."
					# Directory-based recursion directly transposes the
					# source directory structure below the recursion root.
					parent_add -- "${dst_parent_path:?}" || return 1
				elif [ "$vmcp_recurse_childs" = 'yes' ]
				then
					cli_trace 3 "${src}: Child-recursive copy to '${dst}'."
					# Child-based recursion creates a new directory
					# structure where VM childs are direct subfolders.
					dst_parent_path=${dst%/*}
					parent_add -- "${dst_parent_path:?}" || return 1
				else
					echo "ERROR (BUG): vmcp_copy: Selected action is" \
						"'recursive copy' but neither directory nor child" \
						"recursion is enabled." >&2
					return 1
				fi
			fi

			vmcp_invoke_modules -- "$src" || return 1
			settings_save "$comment" "$dst" || return 1

			if [ -n "$dst_parent_path" ]
			then
				childs_add -- "$dst_parent_path" "$dst" || return 1
				childs_save -- "$dst_parent_path" || return 1
			fi
			;;

		'autonomous copy')
			cli_trace 3 "${src}: Autonomous copy to '${dst}'."
			settings_import -- "$src" || return 1
			comment="Autonomous copy of '${vm_name}':${newline}${src}"
			vm_home=$dst
			vm_name=${dst##*/}

			parent_clear

			vmcp_invoke_modules -- "$src" || return 1
			settings_save "$comment" "$dst" || return 1
			;;

		*)
			echo "ERROR (BUG): vmcp_copy: Invalid value for \$vmcp_action:"\
				"'${vmcp_action}'." >&2
			return 1
			;;
	esac
}

###
# vmcp_invoke_modules src_vm
#
# This function is a helper for `vmcp_copy()' and is not designed to be called
# directly.
#
# Invoke the clone modules listed in `$cfg_modules_clone'.
#
vmcp_invoke_modules() {
	local 'mods_list' 'module' 'src'
	[ "${1-}" = '--' ] && shift
	src=${1:?"ERROR (BUG): vmcp_invoke_module: Missing parameter."}

	mods_list=$( str_explode -- "$cfg_modules_clone" ) || return 1
	for module in $mods_list
	do
		cli_trace 3 "${vm_home}: cloning VM settings: ${module}."
		include_module -- "clone/${module}.inc.sh" || return 1
		mod_clone "$src" || return 1
	done
}

###
# vmcp_parseargs_args arg...
#
# Parse command-line arguments and sets `$vmcp_*' global variables accordingly.
#
# Sets the global variable OPTIND to allow shifting the parameters in the
# calling context (see http://pubs.opengroup.org/onlinepubs/9699919799/utilities/getopts.html).
#
# The default value for `$vmcp_action' must be explicitely set by the caller
# *after* calling this function if it was not set by user parameters:
#     vmcp_action=${vmcp_action:-'copy'}
#
vmcp_parseargs() {
	# `$OPTIND' must not be available to the caller, do not set it local!
	local 'OPTARG'

	OPTIND=1
	while getopts "acfhkM:m:no:qRrsvyz" param
	do
		case "$param" in

			'a') # Produce an autonomous VM.
				if [ -n "$vmcp_action" ]
				then
					echo "ERROR: You cannot mix '-a', '-c' and '-f' flags." \
						>&2
					return 2
				fi
				vmcp_action='autonomous copy'
				;;

			'c') # Copy the source VM.
				if [ -n "$vmcp_action" ]
				then
					echo "ERROR: You cannot mix '-a', '-c' and '-f' flags." \
						>&2
					return 2
				fi
				vmcp_action='copy'
				;;

			'f') # Fork the source VM.
				if [ -n "$vmcp_action" ]
				then
					echo "ERROR: You cannot mix '-c', '-f' and '-s' flags." \
						>&2
					return 2
				fi
				vmcp_action='fork'
				;;

			'h') # Show usage information.
				printf '%s\n' "$usage"
				exit 0
				;;

			'k') # Keep parent's unique properties
				vmcp_clone_inherit='yes'
				;;

			'M') # Disable a clone module.
				case " ${cfg_modules_clone} " in
					*" ${OPTARG} "*)
						cfg_modules_clone=$( printf '%s' "$cfg_modules_clone" \
							| sed "s/$( str_escape_sed -- "$OPTARG" )//g" )
						;;
					*)
						cli_trace 4 "Duplicate module '${OPTARG}' already" \
							"disabled."
						;;
				esac
				;;

			'm') # Enable a supplementary clone module.
				case " ${cfg_modules_clone} " in
					*" ${OPTARG} "*)
						cli_trace 4 "Clone module '${OPTARG}' already enabled."
						;;
					*)
						cfg_modules_clone="$cfg_modules_clone $( \
							str_escape -- "$OPTARG" )"
						;;
				esac
				;;

			'n') # Do not modify the source VM during an autonomous copy.
				vmcp_readonly='yes'
				;;

			'o') # Override a setting.
				case "$OPTARG" in
					*?=?*)
						settings_override "${OPTARG%%=*}" "${OPTARG#*=}"  \
							|| return 2
						;;
					*)
						echo "$OPTARG: Malformed option value, it must be" \
							"'vm_setting_name=value'" >&2
						return 2
						;;
				esac
				;;

			'q') # Decrease verbosity.
				if [ "${cfg_ui_verbosity:?}" -gt 0 ]
				then
					cfg_ui_verbosity=$(( cfg_ui_verbosity - 1 )) || return 1
				fi
				;;

			'R') # Recurse over VM childs.
				vmcp_recurse_childs='yes'
				;;

			'r') # Recurse over subdirectories.
				vmcp_recurse_directories='yes'
				;;

			's') # Snapshot mode.
				vmcp_snapshot='yes'
				;;

			'v') # Increase verbosity.
				cfg_ui_verbosity=$(( ${cfg_ui_verbosity:?} + 1 )) || return 1
				;;

			'y') # Never ask any confirmation, always assume `y' as answer.
				settings_override 'cfg_ui_assumeyes' 'yes'
				;;

			'z') # Compress copied or converted images.
				settings_set 'vm_qemu_compress' 'yes'
				;;

			*)
				printf 'Unexpected argument: %s\n' "$1" >&2
				return 2
				;;
		esac
	done
	shift $(( OPTIND - 1 ))

	settings_set 'cfg_ui_verbosity' "${cfg_ui_verbosity:?}"
	if [ "${cfg_ui_verbosity:?}" -ge 5 ]
	then
		set -x
	fi

	if [ "$vmcp_readonly" = 'yes' -a "$vmcp_action" != 'autonomous copy' ]
	then
		echo "ERROR: '-n' can only used with '-a' (autonomous copy mode)." >&2
		return 2
	fi

	if [ $# -lt 2 ]
	then
		echo "ERROR: You must provide at least one source and one target" \
			"path." >&2
		return 2
	fi
}

################################################################################
### /usr/local/lib/vmtools/vmcp.inc.sh END
################################################################################
