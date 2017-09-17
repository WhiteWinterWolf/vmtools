################################################################################
### /usr/local/share/vmtools/modules/buildcmd/networking.inc.sh BEGIN
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
# This modules set networking capabilities for the guest system.
#
################################################################################

mod_buildcmd() {
	local 'device' 'enable' 'entry' 'i' 'mac' 'mode' 'new' 'ret' 'varname'
	varname=${1:?"ERROR (BUG): mod_buildcmd: Missing parameter."}
	new=''
	eval "ret=\$$varname"

	for entry in $( set | grep '^vm_networking_iface[0-9]\{1,\}_enable=' )
	do
		enable=$( str_unescape -- "${entry#*"="}" ) || return 1
		if [ "$enable" != 'yes' ]
		then
			continue
		fi

		i=$( expr "$entry" : 'vm_networking_iface\([0-9]\{1,\}\)_' )

		eval "device=\${vm_networking_iface${i}_device:-}"
		if [ -z "$device" ]
		then
			device=${vm_networking_default_device:?}
		fi

		eval "mac=\${vm_networking_iface${i}_mac:-}"
		mac=$( net_random_mac -- ${mac:+"$mac"} )

		eval "mode=\${vm_networking_iface${i}_mode:-}"
		if [ -z "$mode" ]
		then
			mode=${vm_networking_default_mode:?}
		fi

		# `$device' and `$mode' are expected to contain multiple
		# comma-separated Qemu parameters, don't apply `str_escape_comma()' to
		# them.
		str_list_add 'new' '-device' "${device},mac=$( \
			str_escape_comma -- "$mac" ),netdev=nd${i}" || return 1
		str_list_add 'new' '-netdev' "${mode},id=nd${i}" || return 1
	done

	if [ -n "$new" ]
	then
		str_list_add 'ret' $new
	else
		# Networking must be explicitely disabled, otherwise if no network
		# option is provided Qemu will by default setup a (user mode) network
		# interface.
		str_list_add 'ret' '-net' 'none'
	fi

	eval "$varname=\$ret"
}

################################################################################
### /usr/local/share/vmtools/modules/buildcmd/networking.inc.sh END
################################################################################
