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
# This modules set hard_disk drives available to the guest.
#
################################################################################

mod_buildcmd() {
	local 'backend' 'childs' 'createsize' 'drive' 'enable' 'i' 'params' 'ret'
	local 'rwmode' 'varname'
	varname=${1:?"ERROR (BUG): mod_buildcmd: Missing parameter."}
	eval "ret=\$$varname"

	for i in 1 2
	do
		eval "enable=\$vm_storage_hdd${i}_enable"
		if [ "$enable" = 'yes' ]
		then
			eval "backend=\$vm_storage_hdd${i}_backend"
			if [ -z "$backend" ]
			then
				echo "ERROR: HDD${i}: Storage enabled but no backing file" \
					"configured." >&2
				return 1
			fi

			eval "createsize=\$vm_storage_hdd${i}_createsize"
			if test -n "$createsize" && \
				! expr "$createsize" : '[0-9]\+[MGT]$' >/dev/null
			then
				echo "ERROR: Invalid HDD image file creation size, a unit must"
					"be explicitely given (either 'M', 'G' or 'T'):" \
					"'${createsize}'." >&2
				return 1
			fi

			# Parse the path
			case "$backend" in
				"rw:"*)
					rwmode=${vm_storage_rwmode:?}
					;;
				"snap:"*)
					if [ "${vm_storage_rwmode:?}" != 'ro' ]
					then
						rwmode="snap"
					else
						rwmode='ro'
					fi
					;;
				"ro:"*)
					rwmode='ro'
					;;
				*)
					rwmode=''
					;;
			esac
			backend=$( storage_get_path -- "$backend" ) || return 1

			# Determine backend type
			if [ -d "$backend" ]
			then

				### Directory: Virtual VFAT (VVFAT) sharing ###

				if [ -n "$createsize" ]
				then
					echo "ERROR: HDD${i}: You cannot use 'createsize' when" \
						"the backend storage targets a directory (VVFAT" \
						"share)." >&2
					return 1
				fi

				case "$rwmode" in
					'rw')
						# Some pages warn that VVFAT in rw mode is unreliable,
						# did not found any clear info in the source which warns
						# only against FAT32 support (and VVFAT is not even
						# mentionned in Qemu man page).
						# TODO: Should we display a warning message here?
						drive="fat:rw:${backend}"
						;;
					"snap")
						echo "ERROR: HDD${i}: You cannot use the snapshot" \
							"mode when then backend storage targets a" \
							"directory (VVFAT share)." >&2
						return 1
						;;
					'ro'|'')
						drive="fat:${backend}"
						;;
					*)
						echo "ERROR (BUG): HDD${i}: Invalid value for \$rwmode" \
							": '${rwmode}'." >&2
						return 1
						;;
				esac
				# VVFAT seems only available using the legacy -hda/-hdb syntax.
				case "$i" in
					'1')
						str_list_add 'ret' '-hda' "$drive" || return 1
						;;
					"2")
						str_list_add 'ret' '-hdb' "$drive" || return 1
						;;
					*)
						echo "ERROR (BUG): Invalid HDD identifier: ${i}." >&2
						return 1
					;;
				esac

			else
				if expr "$backend" : '[a-zA-Z]*://\|[nN][bB][dD]:' >/dev/null
				then

					### Remote file URL ###

					if [ -n "$createsize" ]
					then
						echo "ERROR: HDD${i}: You cannot use 'createsize' when" \
							"the backend storage is a remote URL." >&2
						return 1
					fi

					if [ -z "$rwmode" ]
					then
						if expr "$backend" : \
							'[iI][sS][cC][sS][iI]://\|[nN][bB][dD]:' >/dev/null
						then
							# iSCSI & NBD share are writable by default.
							rwmode=${vm_storage_rwmode:?}
						else
							# Other remote files use snapshot mode by default.
							if [ "${vm_storage_rwmode:?}" != 'ro' ]
							then
								rwmode="snap"
							else
								rwmode='ro'
							fi
						fi
					fi

				else

					### Local file path ###

					if [ "${vm_storage_rwmode:?}" = 'rw' \
						-a \( "$rwmode" = 'rw' -o -z "$rwmode" \) ]
					then
						if [ -n "$vm_home" ]
						then
							childs=$( childs_get_list ) || return 1
							if [ -n "$childs" ]
							then
								echo "ERROR: This virtual machine has childs," \
									"its hard disk images cannot be modified." \
									"Use the '-s' or '-r' command line flags" \
									"to start it in snapshot or read-only" \
									"mode." >&2
								echo "Childs list:" >&2
								printf '%s\n' "$childs" | sed 's/^/    /' >&2
								return 1
							fi
						fi
						if ! storage_iswritable -- "$backend"
						then
							# `storage_iwritable()` already displays an error
							# message, we just complete it here.
							echo "Depending on the cause of the error, you" \
								"may want to use the command line parameters" \
								"'-s' or '-r' to start this VM in snapshot" \
								"or read-only mode, or prefix this file's URL" \
								"with 'snap:' or 'ro:'." >&2
							return 1
						fi
					else
						if ! storage_isreadable -- "$backend"
						then
							return 1
						fi
					fi

					if [ -n "$createsize" ]
					then
						# Create a new HDD backend file or overwrite an
						# existing one
						if [ "${vm_storage_rwmode:?}" != 'rw' ]
						then
							echo "ERROR: You cannot create or overwrite an" \
								"HDD backend file when using the '-s' or" \
								"'-r' command line flags." >&2
							return 1
						fi

						if [ "${cfg_ui_verbosity:?}" -lt 4 ]
						then
							params='-q'
						else
							params=''
						fi

						rm -f -- "$backend" || return 1
						# `qemu-img' leaves partially generated files when
						# aborting...
						cleanup_add rm -f -- "$backend"
						# COW systematically disabled on Btrfs (`-o nocow=on')
						# See https://bugzilla.redhat.com/show_bug.cgi?id=689127
						qemu-img 'create' "$params" -f qcow2 -o nocow=on -- \
							"$backend" "$createsize" || return 1

						rwmode=${rwmode:-"${vm_storage_rwmode:?}"}

					else
						# Use and already existing backend file.
						if [ ! -r "$backend" ]
						then
							# `storage_iswritable()' does not guaranty file
							# existence.
							echo "ERROR: ${backend}: file not found or not" \
								"readable." >&2
							return 1
						fi

						case "$( file -b "$backend" )" in
							"DOS/MBR boot sector"*|"QEMU QCOW Image (v3)"*)
								# Raw / QCow3 images
								# Qemu utilities still show QCow3 as QCow2.
								rwmode=${rwmode:-"${vm_storage_rwmode:?}"}
								;;

							"QEMU QCOW Image (v2)"*)
								# QCow2 are slower, but still fully suported.
								# QCow3 achieve near raw performances.
								# See:
								# http://wiki.qemu-project.org/Features/Qcow3
								if [ "${cfg_ui_verbosity:?}" -ge 1 ]
								then
									echo "INFO: ${backend}: this file uses" \
										"an old format, converting it will" \
										"improve the virtual machine" \
										"performances." >&2
									echo "See 'vmcp'(1), 'qemu-img'(1)." >&2
								fi
								rwmode=${rwmode:-"${vm_storage_rwmode:?}"}
								;;

							*)
								# Legacy / third-party images
								# `qemu-img'(1) man page states that the main
								# purpose of the block driver supporting
								# third-party (vmdk, vdi, etc.) and legacy
								# (qcow1, qed, etc.) formats is to allow to
								# import such images.
								# Write access may be unreliable, partial or
								# not implemented at all.
								# List of supported formats:
								# https://en.wikibooks.org/wiki/QEMU/Images
								echo "WARNING: ${backend}: This file seems to" \
									"be either a third-party or a legacy" \
									"file, it is recommended to convert it" \
									"using 'qemu-img'(1) for regular use." >&2
								if [ -z "$rwmode" ]
								then
									if [ "${vm_storage_rwmode:?}" = 'rw' ]
									then
										echo "${backend}: Using snapshot mode" \
											"by default to avoid any" \
											"corruption, prefix its path" \
											"with 'rw:' to try to force" \
											"read-write mode." >&2
										rwmode="snap"
									else
										rwmode="${vm_storage_rwmode:?}"
									fi
								fi
								;;
						esac
					fi
				fi

				# Except VVFAT and except the default value for `$rwmode', all
				# HDD backend images produce a similar Qemu command-line.
				drive="file=$( str_escape_comma -- "$backend" )"
				drive="${drive},if=ide,index=$(( i - 1 )),media=disk"
				case "$rwmode" in
					'rw')
						# The following parameters may allows under some
						# conditions the space occupied by disk image to shrink
						# upon data deletion by the guest.
						# See also:
						# https://pve.proxmox.com/wiki/Shrink_Qcow2_Disk_Files
						drive="${drive},discard=unmap,detect-zeroes=unmap"
						;;
					"snap")
						drive="${drive},snapshot=on"
						;;
					'ro')
						drive="${drive},readonly"
						;;
					*)
						echo "ERROR (BUG): invalid value for '\$rwmode'" \
							"(${rwmode})." >&2
						return 1
						;;
				esac
				str_list_add 'ret' '-drive' "$drive" || return 1
			fi
		fi
	done

	eval "$varname=\$ret"
}

################################################################################
### /usr/local/share/vmtools/modules/buildcmd/storage.inc.sh END
################################################################################
