################################################################################
### /usr/local/share/vmtools/modules/buildcmd/storage.inc.sh BEGIN
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
# This modules sets CD-ROM and DVD-ROM readers devices available to the guest.
#
# If one of the device backend path points to a directory, this module
# automatically generates the matching ISO file.
#
################################################################################

mod_buildcmd() {
	local 'backend' 'create' 'drive' 'enable' 'i' 'ret' 'varname'
	varname=${1:?"ERROR (BUG): mod_buildcmd: Missing parameter."}
	eval "ret=\$$varname"

	for i in 1 2
	do
		eval "enable=\$vm_storage_cdrom${i}_enable"
		if [ "$enable" = 'yes' ]
		then
			eval "backend=\$vm_storage_cdrom${i}_backend"
			drive="if=ide,index=$(( i + 1 )),media=cdrom,read-only"

			if [ -n "$backend" ]
			then
				# Parse the path
				# Remove the prefix from the path.
				case "$backend" in
					"rw:"*|"snap:"*)
						echo "ERROR: CD-ROM images cannot be writable." >&2
						# TODO: When given a device path, can we transparently
						# enable SCSI passthrough to allow to burn CDs from the
						# guest?
						# See http://wiki.qemu-project.org/Features/VirtioSCSI
						return 1
						;;
					"ro:"*)
						backend=${backend#"ro:"}
						;;
					*)
						# No prefix.
						;;
				esac
				# SC2088: anually expanding the tilde, required if a prefix has
				# been used.
				# shellcheck disable=SC2088
				case "$backend" in "~/"*)
					backend="${HOME}/${backend#"~/"}"
				esac

				# Determine backend type
				if [ -d "$backend" ]
				then

					### Directory: on-the-fly ISO file creation ###

					if ! type "genisoimage" >/dev/null 2>&1
					then
						echo "ERROR: The command 'genisoimage' doesn't seem" \
							"available on this system, cannot generate a" \
							"temporary ISO image for the directory" \
							"'${backend}'." >&2
						return 1
					fi

					if [ -z "$cleanup_tmpdir" ]
					then
						if [ -n "$vm_home" ]
						then
							cleanup_set_tmpdir -- "$vm_home" || return 1
						elif [ -w "${backend%/*}" ]
						then
							cleanup_set_tmpdir -- "${backend%/*}" || return 1
						else
							cleanup_set_tmpdir || return 1
						fi
					fi
					create=$( mktemp -- \
						"${cleanup_tmpdir}/${backend##*/}.iso.XXXXX" ) \
						|| return 1

					if ! genisoimage -JR --quiet -o "$create" -- "$backend"
					then
						echo "ERROR: Failed to create '${create}'." >&2
						return 1
					fi
					cli_trace 3 "storage_cdrom: ${backend}: Backend content" \
						"copied into an ISO file: '${create}'."
					backend=$create

				# AFAIK NBD storage does not allow to store ISO images.
				elif expr "$backend" : '[a-zA-Z]*://' >/dev/null
				then

					### Remote file URL ###

					:   # Nothing to do

				elif [ -r "$backend" ]
				then

					### Local file path ###

					:   # Nothing to do

				else
					echo "ERROR: ${backend}: file not found or not readable." \
						>&2
					return 1
				fi

				drive="${drive},file=$( str_escape_comma -- "$backend" )"
			fi

			str_list_add 'ret' '-drive' "$drive" || return 1
		fi
	done

	eval "$varname=\$ret"
}

################################################################################
### /usr/local/share/vmtools/modules/buildcmd/storage.inc.sh END
################################################################################
