################################################################################
### /usr/local/share/modules/configure/vmsettings/networking_auto.inc.sh BEGIN
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
# This file does not provides any interactive configuration, but is instead in
# charge of enabling the first network interface using default parameters if it
# isn't defined yet
#
# If you want to generate a virtual machine with no network interface, you can:
#  - Set `$vm_networking_iface1_enable' to 'no'.
#  - Or remove the call to this module from `$cfg_modules_configure_settings'.
#  - Or override this module in the system-wide or user customized version
#    matching your needs.
#
################################################################################

mod_configure() {
	local 'macaddr'

	if [ -z "${vm_networking_iface1_enable:-}" ]
	then
		macaddr=$( net_random_mac ) || return 1
		settings_set 'vm_networking_iface1_enable' 'yes'
		settings_set 'vm_networking_iface1_mac' "$macaddr"
	fi
}

################################################################################
### /usr/local/share/modules/configure/vmsettings/networking_auto.inc.sh END
################################################################################
