################################################################################
### /usr/local/lib/vmtools/vmmv.inc.sh BEGIN
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
# This library provides function helping into moving or otherwise changing the
# path of a VM.
#
# While the main function `vmmv_move()' is obviously used by the `vmmv'(1)
# command, lower-level functions are still designed as public function for the
# use of other commands such as `vmmerge'(1) which use some of them to update
# VM paths after a merge.
#
# Public functions:
#   vmmv_move [-n] source destination
#         Move or rename a virtual machine.
#   vmmv_mvchilds source destination [vmhome_dir...]
#         Update parent-child links to reflect a moved VM.
#   vmmv_mvpath source destination path...
#         Get a path modified to reflect a moved directory.
#   vmmv_mvsettings source destination [vmhome_dir...]
#         Update VM settings and storage to reflect a moved VM.
#
################################################################################

################################################################################
# Global variable
################################################################################

# Used by `vmmv_move()' to return the new VM path.
vmmv_move_dst=''


################################################################################
# Functions
################################################################################

###
# vmmv_move [-n] source destination
#
# Move a virtual machine location from `source' to `destination'.
#
# If `destination' is an already existing directory, then `source' will be
# moved as a subdirectory of `destination', otherwise `source' will be renamed
# as `destination'.
#
# Options:
#   -n    Don't attempt to lock `source', its parent (if any) and its child,
#         use this options when locking has already been done by the caller.
#
# Return codes:
#   0     The virtual home directory has been succefully moved.
#   1     An error occured.
#   2     The move has been cancelled by the user.
#
# Returned value:
#   `$vmmv_move_dst'
#         This function will set this variable in the caling environment to the
#         value of the final destination path (taking into account possible
#         already existing directories, etc.).
#
vmmv_move() {
	local 'childs' 'opt' 'OPTARG' 'OPTIND' 'parent_path' 'reply'
	local 'src' 'src_esc' 'src_needlock'
	src_needlock='yes'

	OPTIND=1
	while getopts 'n' opt
	do
		case "$opt" in
			'n') src_needlock='no' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))

	src=${1:?"ERROR (BUG): vmmv_move: Missing parameter."}
	src=$( realpath -- "$src" ) || return 1
	storage_isreadable -h -- "$src" || return 1

	vmmv_move_dst=${2:?"ERROR (BUG): vmmv_move: Missing parameter."}
	vmmv_move_dst=$( storage_createpath -d -t "$vmmv_move_dst" -- "$src" '' ) \
		|| return 1
	case "$vmmv_move_dst" in "$src"|"${src}/"*)
		echo "ERROR: ${src}: Cannot move a directory to a subdirectory of" \
			"itself: '${vmmv_move_dst}'." >&2
		return 1
	esac

	cli_trace 3 "vmmv_move: ${src}: Moving VM to '${vmmv_move_dst}'."

	# Lock all impacted VMs:
	# - Lock the target itsef and all its descendancy.
	if [ "$src_needlock" = 'yes' ]
	then
		lock_acquire -cd -- "$src" || return 1
	fi

	# - Lock the VM's parent if there is any.
	parent_path=$( parent_get_nearest -- "$src" ) || return 1
	if [ "$src_needlock" = 'yes' -a -n "$parent_path" ]
	then
		lock_acquire -- "$parent_path" || return 1
	fi

	# Update the target and subdirs settings and storage files. This also
	# include the child-to-parent links.

	# `$src' path appears in escaped form in settings files.
	src_esc=$( str_escape -- "$src" )
	# SC2046: Word splitting expected on find output.
	# shellcheck disable=SC2046
	vmmv_mvsettings -- "$src" "$vmmv_move_dst" $( find "$src" \
		\! -path "*${newline}*" -name "${cfg_file_vmsettings:?}" \
		-exec grep -Fl -- "${src_esc%"'"}" {} + ) || return 1

	# Update the target and subdirs parent-to-child links.
	# SC2046: Globing disabled, IFS=\n.
	# shellcheck disable=SC2046
	vmmv_mvchilds -- "$src" "$vmmv_move_dst" $( find "$src" \
		\! -path "*${newline}*" -name "${cfg_file_childs:?}" \
		-exec grep -Fl -- "$src" {} + ) || return 1

	# Update target's childs settings and storage files.
	childs=$( childs_get_list -- "$vmmv_move_dst" ) || return 1
	if [ -n "$childs" ]
	then
		# SC2046,SC2086: Word splitting expected on `$childs'.
		# shellcheck disable=SC2046,SC2086
		vmmv_mvsettings -- "$src" "$vmmv_move_dst" $childs || return 1
	fi

	# Update target parent's parent-to-child link.
	if [ -n "$parent_path" ]
	then
		vmmv_mvchilds -- "$src" "$vmmv_move_dst" "$parent_path" || return 1
	fi

	# Move the VM.
	if [ -d "$vmmv_move_dst" ]
	then
		# Rewrite `$vmmv_move_dst' instead of creating a subdirectory.
		rmdir -- "$vmmv_move_dst" || return 1
	fi
	mv -- "$src" "$vmmv_move_dst" || return 1
	cleanup_add mv -f -- "$vmmv_move_dst" "$src"
	# Also update locks set by the caller.
	lock_mvpath -- "$src" "$vmmv_move_dst"

	# Release all locks and clear cleanup tasks.
	if [ "$src_needlock" = 'yes' ]
	then
		lock_release -cd -- "$vmmv_move_dst" || return 1

		if [ -n "$parent_path" ]
		then
			lock_release -- "$parent_path" || return 1
		fi
	fi
}

###
# vmmv_mvchilds source destination [vmhome_dir...]
#
# Update parent-child links on every child of `vmhome_dir' to reflect a move
# from `source' to `destination'.
#
# This function mainly does two things:
#   - Update the childs list from `vmhome_dir' so that all path below `source'
#     are now below `destination'.
#   - Update the VM settings file of each direct child of `vmhome_dir' to
#     turn a parent path below `source' into one below `destination' and update
#     their path to storage image files (see `vmmv_mvsettings()').
#
# This function only operates on the path passed as parameter and does not
# include any recursion.
#
# It is allowed to pass no `vmhome_dir', this function will have effect in this
# case.
#
vmmv_mvchilds() {
	local 'c' 'childs' 'dir' 'dst' 'newpath_list' 'src'
	[ "${1-}" = '--' ] && shift
	src=${1:?"ERROR (BUG): vmmv_mvchilds: Missing parameter."}
	dst=${2:?"ERROR (BUG): vmmv_mvchilds: Missing parameter."}
	shift 2

	for dir
	do
		dir=${dir%"/${cfg_file_childs:?}"}
		cli_trace 3 "vmmv_mvchilds: ${dir}: Updating childs list."
		childs=$( childs_get_list -- "$dir" ) || return 1

		if [ -n "$childs" ]
		then
			# SC2086: Word splitting expected on `$childs'.
			# shellcheck disable=SC2086
			newpath_list=$( vmmv_mvpath -- "$src" "$dst" $childs ) || return 1
			if [ "$newpath_list" != "$childs" ]
			then
				childs_clear -- "$dir" || return 1
				# SC2086: Word splitting expected on `$newpath_list'.
				# shellcheck disable=SC2086
				childs_add -f -- "$dir" $newpath_list || return 1
				childs_save -- "$dir" || return 1
			fi

			for c in $childs
			do
				# Update settings (parent link and backing file location) of childs
				# located outside of the source directory tree (those inside should
				# be already updated).
				case "$c" in
					"$src"|"${src}/"*) ;;
					*) vmmv_mvsettings -- "$src" "$dst" "$c" || return 1 ;;
				esac
			done
		fi
	done
}

###
# vmmv_mvpath source destination path...
#
# Outputs `path' on stdout after having applied a move from `source' to
# `destination' to it.
#
# This function only process the path value, it does not affect the filesystem.
#
# This function can be used to determine if and how a path (or a set of paths)
# would be affected by a move operation.
#
# An empty string as `destination' is allowed, this provides a reliable way
# to determine whether `path' is located below `source' (including corner
# cases such as "/a/b/cde" is not located below "/a/b/c" even if both strings
# start the same).
#
# See also `storage_createpath()' to take into account already existing paths.
#
vmmv_mvpath() {
	local 'destination' 'newpath' 'output' 'path' 'source'
	[ "${1-}" = '--' ] && shift
	source=${1:?"ERROR (BUG): vmmv_mvpath: Missing parameter."}
	destination=${2:-}
	shift 2

	if [ $# -eq 0 ]
	then
		echo "ERROR (BUG): vmmv_mvpath: Missing parameter." >&2
		return 1
	fi

	output=''
	for path
	do
		newpath="${path%/}/"
		newpath="${newpath#"${source%/}/"}"

		# Check that `$path' is indeed a subdirectory of `$source'.
		if [ "$newpath" != "${path%/}/" ]
		then
			newpath="${destination%/}/${newpath}"
			newpath=${newpath%/}
			str_list_add 'output' "$newpath" || return 1
		else
			str_list_add 'output' "$path" || return 1
		fi
	done

	printf '%s' "$output"
}

###
# vmmv_mvsettings source destination [vmhome_dir...]
#
# Update the VM settings file of `vmhome_dir' and its related storage to
# reflect a move from `source' to `destination'.
#
# This function mainly does three things:
#   - Update the path to the parent if applicable.
#   - Update the path to the storage image files.
#   - Update the storage image files themselves if use a backing file and this
#     file location would be affected by the move.
#
# It is allowed to provide no `vmhome_dir', in such case this function has no
# effect.
#
vmmv_mvsettings() {
	local 'backing' 'dir' 'dst' 'file' 'modified' 'newpath' 'parent_path'
	local 'prefix' 'setting' 'src' 'value'
	[ "${1-}" = '--' ] && shift
	src=${1:?"ERROR (BUG): vmmv_mvsettings: Missing parameter."}
	dst=${2:?"ERROR (BUG): vmmv_mvsettings: Missing parameter."}
	shift 2

	for dir
	do
		# Load current VM settings.

		modified='no'
		if [ -f "$dir" ]
		then
			dir=$( dirname -- "$dir" )
		fi
		cli_trace 3 "vmmv_mvsettings: ${dir}: Updating VM settings."
		settings_import -s -- "$dir" || return 1

		# Update parent VM location.

		parent_path=$( parent_get_nearest ) || return 1
		if [ -n "$parent_path" ]
		then
			newpath=$( vmmv_mvpath -- "$src" "$dst" "$parent_path" ) || return 1
			if [ "$newpath" != "$parent_path" ]
			then
				parent_clear
				parent_add -f -- "$newpath"
				modified='yes'
			fi
		fi

		# Update storage file and backing file location.

		for setting in $( settings_get | awk -F '=' \
			'/^vm_storage_[a-z0-9_]*_backend/ { print $1 }' )
		do
			eval "value=\$$setting"
			if [ -z "$value" ]
			then
				continue
			fi

			# Update storage file path
			file=$( storage_get_path -- "$value" ) || return 1
			newpath=$( vmmv_mvpath -- "$src" "$dst" "$file" ) || return 1
			if [ "$newpath" != "$file" ]
			then
				prefix=$( storage_get_prefix -- "$value" )
				settings_override "$setting" "${prefix}${newpath}" || return 1
				modified='yes'
			fi

			# Update storage backing file location
			backing=$( storage_get_backingfile -- "$file" ) || return 1
			if [ -n "$backing" ]
			then
				newpath=$( vmmv_mvpath -- "$src" "$dst" "$backing" ) || return 1
				if [ "$newpath" != "$backing" ]
				then
					cli_trace 4 "vmmv_mvsettings: ${file}: Rebase disk image" \
						"to '${newpath}'."

					# Double-check that no other process is using this file.
					storage_iswritable -- "$file" || return 1

					cleanup_add qemu-img 'rebase' -u -b "$backing" -- "$file"
					qemu-img 'rebase' -u -b "$newpath" -- "$file" || return 1
				fi
			fi
		done

		# Save updated VM settings.

		if [ "$modified" = 'yes' ]
		then
			settings_save \
				"VM moved${newline}from: ${src}${newline}to:   ${dst}" \
				|| return 1
		fi
	done
}

################################################################################
### /usr/local/lib/vmtools/vmmv.inc.sh END
################################################################################
