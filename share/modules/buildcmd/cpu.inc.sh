################################################################################
### /usr/local/share/vmtools/modules/buildcmd/cpu.inc.sh BEGIN
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
# This module sets guest system CPU type and number.
#
################################################################################

mod_buildcmd() {
	local 'ret' 'varname'
	varname=${1:?"ERROR (BUG): mod_buildcmd: Missing parameter."}
	eval "ret=\$$varname"

	if [ -n "$vm_cpu_count" ]
	then
		str_list_add 'ret' '-smp' "$vm_cpu_count" || return 1
	fi

	if [ -n "$vm_cpu_type" ]
	then
		str_list_add 'ret' '-cpu' "$vm_cpu_type" || return 1
	fi

	eval "$varname=\$ret"
}

################################################################################
### /usr/local/share/vmtools/modules/buildcmd/cpu.inc.sh END
################################################################################
