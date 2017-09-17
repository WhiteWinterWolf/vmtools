################################################################################
### /usr/local/share/vmtools/modules/buildcmd/macos.inc.sh BEGIN
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
# This modules handles MacOS specific extensions, like the AppleSMC device
# storing the MacOS' hardware verification key.
#
################################################################################

mod_buildcmd() {
	local 'ret' 'varname'
	varname=${1:?"ERROR (BUG): mod_buildcmd: Missing parameter."}

	if [ -n "$vm_macos_osk" ]
	then
		eval "ret=\$$varname"
		str_list_add 'ret' '-device' "isa-applesmc,osk=$( \
			str_escape_comma -- "$vm_macos_osk" )" || return 1
		eval "$varname=\$ret"
	fi
}

################################################################################
### /usr/local/share/vmtools/modules/buildcmd/macos.inc.sh END
################################################################################
