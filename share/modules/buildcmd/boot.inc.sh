################################################################################
### /usr/local/share/vmtools/modules/buildcmd/boot.inc.sh BEGIN
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
# This modules generates guest OS boot options:
#   - Boot order (as can be influenced by `-C' and `-D' command-line options).
#   - Boot media selection menu (enable by the `-b' command-line option).
#
# The boot media selection menu depends on the capabilities of the BIOS ROM
# used. See `qemu-system'(1) for more information.
#
################################################################################

mod_buildcmd() {
	local 'params' 'ret' 'varname'
	varname=${1:?"ERROR (BUG): mod_buildcmd: Missing parameter."}
	eval "ret=\$$varname"
	params=''

	if [ -n "$vm_boot_order" ]
	then
		params="${params:+"${params},"}order=$( str_escape_comma -- \
			"$vm_boot_order" )"
	fi

	if [ "$vm_boot_menu" = 'yes' ]
	then
		params="${params:+"${params},"}menu=on"
	fi

	if [ -n "$params" ]
	then
		str_list_add 'ret' '-boot' "$params" || return 1
		eval "$varname=\$ret"
	fi
}

################################################################################
### /usr/local/share/vmtools/modules/buildcmd/boot.inc.sh END
################################################################################
