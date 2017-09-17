################################################################################
### /usr/local/share/vmtools/modules/clone/storage_hdd_backend.inc.sh BEGIN
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
# This modules handles storage image files for copied virtual machines.
#
# Copied VM may inherit parent VM storage in various ways:
#   - Parent's storage file may be used as backing (see `qemu-img'(1)).
#   - Parent's storage file may be copied.
#   - Parent's storage file may be used as-is by the child.
#
# The method used depends on various factors, like the type of copy, type of
# file and file location.
#
################################################################################

mod_clone() {
	local 'entry' 'i' 'is_iso' 'is_readonly' 'prefix' 'setting'
	local 'dst_parent_home' 'dst_parent_storage'
	local 'src_home' 'src_parent_home' 'src_parent_storage' 'src_storage'
	src_home=${1:?"ERROR (BUG): Missing parameter."}

	for entry in $( set | grep '^vm_storage_[[:alnum:]]*_backend=' )
	do
		setting=${entry%%"="*}
		src_storage=$( str_unescape -- "${entry#*"="}" ) || return 1

		# Check `$src_storage' value.

		if [ -z "$src_storage" ]
		then
			continue
		fi
		src_storage=$( storage_get_path -- "$src_storage" ) || return 1

		case "$src_storage" in "${vm_home:?}/"*)
			# A previous branch module may already have processed this file.
			continue
		esac
		if expr "$src_storage" : '[a-zA-Z]*://\|[nN][bB][dD]:' >/dev/null
		then
			# Remote image, nothing to do.
			continue
		fi
		if ! storage_isreadable -- "$src_storage"
		then
			return 1
		fi

		if file -b "$src_storage" | grep -q 'ISO 9660 CD-ROM filesystem'
		then
			is_iso='yes'
			prefix=''
			is_readonly='yes'
			src_backing_storage=''
		else
			is_iso='no'
			if [ "$vmcp_snapshot" = 'yes' ]
			then
				prefix='snap:'
				is_readonly='yes'
			else
				prefix=$( storage_get_prefix -- "$src_storage" ) || return 1
				case "$prefix" in
					'ro:'|'snap:' ) is_readonly='yes' ;;
					*) is_readonly='no' ;;
				esac
			fi
		fi

		# Set variables related to the source VM.

		src_parent_home=$( parent_get_nearest -- "$src_home" ) || return 1
		if [ -n "$src_parent_home" ]
		then
			src_parent_storage=$(
				settings_reset
				settings_loadvm -- "${src_parent_home:?}"
				eval "printf '%s' \"\$$setting\""
			) || return 1
		else
			src_parent_storage=''
		fi

		# Set variables related to the destination VM.

		dst_parent_home=$( parent_get_nearest ) || return 1
		if [ -n "$dst_parent_home" ]
		then
			dst_parent_storage=$(
				settings_reset
				settings_loadvm -- "${dst_parent_home:?}"
				eval "printf '%s' \"\$$setting\""
			) || return 1
		else
			dst_parent_storage=''
		fi

		# Process the requested action.

		case "${vmcp_action:?}" in
			'copy')
				src_backing_storage=$( storage_get_backingfile -- \
					"$src_storage" ) || return 1

				if [ -n "$src_backing_storage" ]
				then
					# The source storage files uses a backing file:
					# Qemu copy, keep same backing file.
					mod_clone_backing -- "$src_backing_storage" || return 1

				elif [ "${src_storage%/*}" = "$src_home" ]
				then
					# Standalone storage file in the source VM home:
					# Copy it to the destination VM home.
					mod_clone_copy || return 1

				elif [ "$is_readonly" = 'yes' ]
				then
					# External read-only storage:
					# Use it directly.
					mod_clone_use || return 1

				else
					# External writeable storage:
					# Copy it to the destination VM home.
					mod_clone_copy || return 1
				fi
				;;

			'fork')
				if [ "$is_readonly" != 'yes' ]
				then
					# Writable storage file:
					# Create our own snapshot image.
					mod_clone_backing "$src_storage" || return 1

				elif [ "$vmcp_snapshot" = 'yes' -a "$prefix" = 'snap:' ]
				then
					# Snapshot mode:
					# Apply the prefix explicitely.
					mod_clone_use || return 1
				fi
				# Read-only storage file:
				# Passively inherit source settings.
				;;

			'recursive copy')
				src_backing_storage=$( storage_get_backingfile -- \
					"$src_storage" ) || return 1

				if [ -n "$src_backing_storage" ]
				then
					if [ "$src_backing_storage" = "$src_parent_storage" ]
					then
						# Backing file is parent's storage:
						# Qemu copy, use own parent as backing file.
						mod_clone_backing -- "$dst_parent_storage" || return 1

					else
						# Backing file is an external file:
						# Qemu copy, keep same backing file.
						mod_clone_backing -- "$src_backing_storage" || return 1
					fi

				elif [ "${src_storage%/*}" = "$src_home" ]
				then
					# Standalone storage file in the source VM home:
					# Copy it to the destination VM home.
					mod_clone_copy || return 1

				elif [ "$is_readonly" = 'yes' ]
				then
					# External read-only storage:
					# Use it directly.
					mod_clone_use || return 1

				else
					# External writeable storage:
					# Copy it to the destination VM home.
					mod_clone_copy || return 1
				fi
				;;

			'autonomous copy')
				if [ "$is_readonly" = 'yes' ]
				then
					# Read-only storage file:
					# Use it directly.
					mod_clone_use || return 1

				else
					# Writeable storage file:
					# Copy it to the destination VM home.
					# The content of QCOW2 backing files will automativally be
					# merged.
					mod_clone_copy || return 1
				fi
				;;

			*)
				echo "ERROR (BUG): storage_backend.inc.sh: Invalid value for" \
					"\$vmcp_action: '${vmcp_action}'." >&2
				return 1
				;;
		esac
	done
}

###
# mod_clone_backing backing_file
#
# Generate a new storage file, using the backing file given as parameter.
#
mod_clone_backing() {
	local 'backing' 'dst_storage' 'qemu_opts'
	[ "${1-}" = '--' ] && shift
	backing=${1:?"ERROR (BUG): mod_clone_backing: Missing parameter."}
	qemu_opts=''

	dst_storage=$( storage_createpath -s ".qcow2" -- \
		"${vm_home:?}/${src_storage##*/}" ) || return 1
	cleanup_backup -m -- "$dst_storage" || return 1

	cli_trace 4 "mod_clone_backing: ${vm_home}: ${dst_storage}: Copy from" \
		"'${src_storage}' using a backing file: '${backing}'" \
		"(\$vmcp_action='${vmcp_action}')."

	if [ "$backing" = "$src_storage" ]
	then
		if [ "${cfg_ui_verbosity:?}" -lt 4 ]
		then
			qemu_opts="${qemu_opts}q"
		fi
		qemu-img 'create' ${qemu_opts:+"-${qemu_opts}"} -f 'qcow2' \
			-o "nocow=on,backing_file=$( str_escape_comma -- "$backing" )" -- \
			"${dst_storage:?}" || return 1
	else
		if [ "${cfg_ui_verbosity:?}" -ge 2 ]
		then
			# Display qemu-img progress information.
			echo "${vm_home}: Copying '${src_storage}' to '${dst_storage}':" >&2
			qemu_opts="${qemu_opts}p"
		fi
		if [ "$vm_qemu_compress" = 'yes' ]
		then
			qemu_opts="${qemu_opts}c"
		fi
		qemu-img 'convert' ${qemu_opts:+"-${qemu_opts}"} -O 'qcow2' \
		-o "nocow=on,backing_file=$( str_escape_comma -- "$backing" )" -- \
		"${src_storage:?}" "${dst_storage:?}" || return 1
	fi
	settings_override "${setting:?}" "${prefix}${dst_storage}" || return 1
}

###
# mod_clone_copy
#
mod_clone_copy() {
	local 'ddst_storage' 'qemu_opts'

	dst_storage=$( storage_createpath -s ".qcow2" -- \
		"${vm_home:?}/${src_storage##*/}" ) || return 1
	cleanup_backup -m -- "$dst_storage" || return 1

	if [ "${is_iso:?}" = 'yes' ]
	then
		cli_trace 4 "mod_clone_copy: ${vm_home}: ${dst_storage}: Copy" \
			"('cp') from '${src_storage}' (\$vmcp_action='${vmcp_action}')."
		cp -- "$src_storage" "$dst_storage" || return 1
	else
		cli_trace 4 "mod_clone_copy: ${vm_home}: ${dst_storage}: Copy" \
			"('qemu-img') from '${src_storage}'" \
			"(\$vmcp_action='${vmcp_action}')."

		qemu_opts=''
		if [ "${cfg_ui_verbosity:?}" -ge 2 ]
		then
			# Display qemu-img progress information.
			echo "${vm_home}: Copying '${src_storage}' to '${dst_storage}':" >&2
			qemu_opts="${qemu_opts}p"
		fi
		if [ "$vm_qemu_compress" = 'yes' ]
		then
			qemu_opts="${qemu_opts}c"
		fi

		# Compared to `cp', `qemu-img' better handles files metadata (sparse
		# files, Btrfs COW, etc.). Third-party files will be automatically
		# converted, thus cleanly handling event VMDK images with several
		# extent files.
		qemu-img 'convert' ${qemu_opts:+"-${qemu_opts}"} -O 'qcow2' \
			-o 'nocow=on' -- "$src_storage" "$dst_storage" || return 1
	fi

	settings_override "${setting:?}" "${prefix}${dst_storage}" || return 1
}

###
# mod_clone_use
#
mod_clone_use() {
	cli_trace 4 "mod_clone_copy: ${vm_home}: ${src_storage}: Reusing source" \
		"VM storage (\$vmcp_action='${vmcp_action}')."
	settings_override "${setting:?}" "${prefix}${src_storage:?}" || return 1
}

################################################################################
### /usr/local/share/modules/clone/storage_hdd_backend.inc.sh END
################################################################################
