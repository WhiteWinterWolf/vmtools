################################################################################
### /usr/local/share/modules/configure/template/autodetect.inc.sh BEGIN
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
# This module attempt to automatically enable certains templates.
#
# Currently, this modules only enables the `macos' template when a MacOS X
# installation media is detected.
#
################################################################################

# TODO: When floppy drives (-a & -A) and template legacy90 are made, automatically
# select the template legacy90 when a floppy drive is enabled.

mod_configure() {
	local 'finfo'

	if [ -n "$vm_storage_cdrom1_backend" ]
	then
		finfo=$( file -- "$( storage_get_path -- \
			"$vm_storage_cdrom1_backend" )" ) || return 1
		case "$finfo" in *"BOOTCAMP"*|*"Apple_HFS"*)
			cli_trace 3 "CD-ROM 1: MacOS X installation media detected," \
				"enabling 'macos' template."
			template_add 'macos'
		esac
	fi
}

################################################################################
### /usr/local/share/modules/configure/template/autodetect.inc.sh END
################################################################################
