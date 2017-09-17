################################################################################
### /usr/local/share/modules/configure/vmsettings/storage_hdd_import.inc.sh BEGIN
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
# This module helps the user to detect legacy and third-party images files and
# to convert them into QCow2 format.
#
# This modules also implement a basic conversion process for `.ova' files which
# are not handled by Qemu itself: when such files contain a single hard-disk
# image it is extracted and converted into QCow2 format, all other VM metadata
# from the `.ova' file are ignored.
#
################################################################################

mod_configure() {
	local 'backend' 'createsize' 'destdir' 'i' 'new_backend' 'qemu_opts'
	local 'tmpdir' 'vmdkfile'

	for i in 1 2
	do
		eval "createsize=\$vm_storage_hdd${i}_createsize"
		if [ -n "$createsize" ]
		then
			continue
		fi

		eval "backend=\$vm_storage_hdd${i}_backend"
		if [ -z "$backend" ]
		then
			continue
		fi
		backend=$( storage_get_path -- "$backend" ) || return 1

		if [ ! -f "$backend" -o ! -r "$backend" ]
		then
			continue
		fi

		if ! storage_isreadable -- "$backend"
		then
			# Most common case: file opened in read-write mode by another
			# running VM for instance.
			return 1
		fi

		case "$( file -b "$backend" )" in
			'DOS/MBR boot sector'*|'QEMU QCOW Image (v3)'*)
				continue
				;;
		esac

		if [ "$cfg_ui_assumeyes" != 'yes' ]
		then
			printf '\nAuto-conversion: %s\n' "${backend}" >&2
			echo "This file seems to be either a third-party or a legacy" \
				"file, it is recommended to convert it for regular usage." >&2
			cli_confirm "Create a Qcow2 copy of this file [yN]? " || continue
		fi
		destdir=${vm_home:-"$( dirname -- "$backend" )"}
		if [ "${backend%.*}" != "${backend%/*}/" ]
		then
			# Attempt to remove `$backend' extension if there is any.
			new_backend=$( storage_createpath -s '.qcow2' -t "$destdir" \
				-- "${backend%.*}" ) || return 1
		else
			# `$backend' is a dotted file with no extension.
			new_backend=$( storage_createpath -s '.qcow2' -t "$destdir" \
				-- "$backend" ) || return 1
		fi

		# Specific handling of .ova files (technically they are tar archives).
		# Sadly `qemu-img' does not support .ova files natively.
		# Found no feature request about this.
		tmpdir=''
		case "$( file -b -- "$backend" )" in *'POSIX tar archive'*)
			vmdkfile=$( tar -t -f "$backend" | grep '\.vmdk$' )
			case "$vmdkfile" in
				'')
					echo "ERROR: No hard-disk image found, conversion failed." \
						>&2
					return 1
					;;
				*"$newline"*)
					echo "ERROR: This archive contains too many hard-disk" \
						"images, extract them manually using the 'tar'" \
						"command, conversion failed." >&2
					return 1
					;;
				*)
					cli_trace 3 "storage_hdd_import: ${backend}: Extracting" \
						"OVA file content..."
					# `tar' content listing escapes file names, we therefore
					# `cannot trust it to reflect real file names.
					tmpdir=$( mktemp -d -- "$( dirname -- "$backend" \
						)/.vmtools-import.XXXXXXXXXX" ) || return 1
					cleanup_add rm -rf -- "$tmpdir"
					tar -x -C "$tmpdir" -f "$backend" || return 1
					backend=$( find "$tmpdir" -name '*.vmdk' ) || return 1
					;;
			esac
		esac

		qemu_opts=''
		if [ "${cfg_ui_verbosity:?}" -ge 2 ]
		then
			qemu_opts="${qemu_opts}p"
		fi
		if [ "$vm_qemu_compress" = 'yes' ]
		then
			qemu_opts="${qemu_opts}c"
		fi
		cli_trace 3 "storage_hdd_import: ${backend}: Converting the disk" \
			"image..."
		# `qemu-img' leaves partially generated files when aborting...
		cleanup_add rm -f -- "$new_backend"
		# COW systematically disabled on Btrfs (`-o nocow=on')
		# See https://bugzilla.redhat.com/show_bug.cgi?id=689127
		qemu-img convert ${qemu_opts:+"-${qemu_opts}"} -O 'qcow2' \
			-o 'nocow=on' -- "$backend" "$new_backend" || return 1

		if [ -n "$tmpdir" ]
		then
			rm -rf -- "$tmpdir" || return 1
			cleanup_remove rm -rf -- "$tmpdir" || return 1
		fi

		settings_override "vm_storage_hdd${i}_backend" "$new_backend" \
			|| return 1
	done
}

################################################################################
### /usr/local/share/modules/configure/vmsettings/storage_hdd_import.inc.sh END
################################################################################
