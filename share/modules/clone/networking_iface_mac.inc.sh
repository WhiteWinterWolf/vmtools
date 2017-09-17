################################################################################
### /usr/local/share/modules/configure/networking_iface_mac.inc.sh BEGIN
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
# This modules ensures that each copied virtual machines gets a unique random
# MAC address.
#
################################################################################

mod_clone() {
	local 'child_value' 'entry' 'src_value' 'setting'

	if [ "$vmcp_clone_inherit" = 'yes' ]
	then
		return 0
	fi

	for entry in $( set | grep '^vm_networking_iface[0-9]\+_mac=' )
	do
		setting=${entry%%"="*}
		src_value=$( str_unescape -- "${entry#*"="}" ) || return 1
		if [ -z "$src_value" ]
		then
			continue
		fi

		child_value=$( net_random_mac ) || return 1
		settings_override "$setting" "$child_value"
	done
}


################################################################################
### /usr/local/share/modules/configure/networking_iface_mac.inc.sh END
################################################################################
