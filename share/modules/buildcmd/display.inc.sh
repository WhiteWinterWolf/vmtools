################################################################################
### /usr/local/share/vmtools/modules/buildcmd/display.inc.sh BEGIN
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
# This module sets guest system display devices nd services.
#
################################################################################

mod_buildcmd() {
	local 'firstport' 'ret' 'usedports' 'varname'
	varname=${1:?"ERROR (BUG): mod_buildcmd: Missing parameter."}
	eval "ret=\$$varname"

	if [ "${vm_display_device:?}" = 'none' ]
	then
		# If no display device is present, no display is possible.
		str_list_add 'ret' '-display' 'none'
		str_list_add 'ret' '-vga' 'none'
		eval "$varname=\$ret"
		return 0
	fi

	case "${vm_display_type:?}" in
		"sdl"|"gtk"|"none")
			str_list_add 'ret' '-display' "${vm_display_type:?}" || return 1
			str_list_add 'ret' '-vga' "${vm_display_device:?}" || return 1
			;;

		"vnc"|"spice")
			if [ -n "$vm_display_port" ]
			then
				if [ "$vm_display_port" -lt ${vm_display_portmin:?} \
					-o "$vm_display_port" -gt 65535 ]
				then
					echo "ERROR: Invalid value for 'vm_display_port'" \
						"(${vm_display_port}): the port number must be" \
						"between ${vm_display_portmin} and 65535 inclusive." >&2
					return 1
				fi
			else
				vm_display_port=$( net_free_port "${vm_display_iface:?}" \
					"${vm_display_portmin:?}" ) || return 1
			fi

			case "${vm_display_type:?}" in
				"vnc")
					str_list_add 'ret' '-display' \
						"vnc=${vm_display_iface:?}:$(( \
						vm_display_port - ${vm_display_portmin:?} ))" \
						|| return 1
					str_list_add 'ret' '-vga' "${vm_display_device:?}" \
						|| return 1
					echo "${vm_name}: Listening URL:" \
						"vnc://${vm_display_iface}:${vm_display_port}" >&2
					;;
				"spice")
					str_list_add 'ret' '-chardev' \
						'spicevmc,id=spicechannel0,name=vdagent' || return 1
					str_list_add 'ret' '-device' 'virtio-serial-pci' || return 1
					str_list_add 'ret' '-device' \
						'virtserialport,chardev=spicechannel0,name=com.redhat.spice.0' \
						 || return 1
					str_list_add 'ret' '-spice' \
						"addr=$( str_escape_comma -- "${vm_display_iface:?}" \
						),port=$( str_escape_comma -- "${vm_display_port:?}" \
						),disable-ticketing" || return 1
					str_list_add 'ret' '-vga' 'qxl' || return 1
					echo "${vm_name}: Listening URL:" \
						"spice://${vm_display_iface}:${vm_display_port}" >&2
					;;
				*)
					echo "ERROR (BUG): Invalid display type:" \
						"'${vm_display_type}'." >&2
					return 1
					;;
			esac
			;;

		*)
			echo "ERROR: Invalid value for 'vm_display_type':" \
				"'${vm_display_type}'." >&2
			return 1
			;;
	esac

	eval "$varname=\$ret"
}

################################################################################
### /usr/local/share/vmtools/modules/buildcmd/display.inc.sh END
################################################################################
