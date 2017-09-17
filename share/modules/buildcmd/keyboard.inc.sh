################################################################################
### /usr/local/share/vmtools/modules/buildcmd/keyboard.inc.sh BEGIN
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
# This module defines keyboard mapping, usefull in particular when VNC display
# mode is used.
#
################################################################################

mod_buildcmd() {
	local 'ret' 'varname'
	varname=${1:?"ERROR (BUG): mod_buildcmd: Missing parameter."}

	if [ -n "$vm_keyboard_mapping" ]
	then
		eval "ret=\$$varname"
		str_list_add 'ret' '-k' "$vm_keyboard_mapping" || return 1
		eval "$varname=\$ret"
	fi
}

################################################################################
### /usr/local/share/vmtools/modules/buildcmd/keyboard.inc.sh END
################################################################################
