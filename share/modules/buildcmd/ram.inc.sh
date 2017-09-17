################################################################################
### /usr/local/share/vmtools/modules/buildcmd/ram.inc.sh BEGIN
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
# This modules sets the amount of RAM allocated to the guest.
#
################################################################################

mod_buildcmd() {
	local 'ret' 'varname'
	varname=${1:?"ERROR (BUG): mod_buildcmd: Missing parameter."}

	if [ -n "$vm_ram_size" ]
	then
		if ! expr "$vm_ram_size" : '[0-9]\+[MG]$' >/dev/null
		then
			echo "ERROR: Invalid RAM amount specification, a unit must be" \
				"explicitely given (either 'M' or 'G'): '${vm_ram_size}'." >&2
			return 1
		fi

		eval "ret=\$$varname"
		str_list_add 'ret' '-m' "$vm_ram_size" || return 1
		eval "$varname=\$ret"
	fi
}

################################################################################
### /usr/local/share/vmtools/modules/buildcmd/ram.inc.sh END
################################################################################
