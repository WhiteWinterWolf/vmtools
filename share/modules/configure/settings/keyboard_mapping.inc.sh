################################################################################
### /usr/local/share/modules/configure/vmsettings/keyboard_mapping.inc.sh BEGIN
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
# This modules asks the user to select a keyboard mapping.
#
# This module is not enabled by default, in favor of configuring a global
# default keyboard mapping in `/etc/vmtools/vmtools.conf'.
#
################################################################################

mod_configure() {
	local 'layouts_list' 'layouts_dir' 'ok' 'reply' 'usage'
	layouts_dir='/usr/share/qemu/keymaps'

	if [ -d "$layouts_dir" ]
	then
		layouts_list=$( find "$layouts_dir" -mindepth 1 -maxdepth 1 -type f \
			\! -name 'common' \! -name 'modifiers' -exec basename -- '{}' \; |
			LC_ALL=C sort | column )
	else
		layouts_list=''
	fi

	usage=$( cat <<-__EOF__

		KEYBOARD LAYOUT

		Define the host's keyboard layout.

		Available layouts:
		${layouts_list:-"(layout directory not found)"}

		__EOF__
	)

	if [ "$cfg_ui_assumeyes" = 'yes' ]
	then
		cli_trace 3 "${vm_name}: keyboard_mapping: using default value:" \
			"'$vm_keyboard_mapping'."
	else
		ok='no'
		reply=$noreply
		while [ "$ok" != 'yes' ]
		do
			if [ "$reply" = '?' ]
			then
				printf '%s\n' "$usage" >&2
			fi
			printf '\nKeyboard layout (default: %s)? ' "$vm_keyboard_mapping" >&2
			read reply || return 2

			if [ -z "$reply" ]
			then
				ok='yes'
			elif [ -n "$layouts_list" ]
			then
				if [ -e "${layouts_dir}/${reply}" ]
				then
					ok='yes'
				else
					echo "ERROR: Invalid layout name." >&2
				fi
			elif expr "$reply" : '[a-z][a-z-]*[a-z]$' >/dev/null
			then
				ok='yes'
			else
				echo "ERROR: Invalid layout name." >&2
			fi
		done

		if [ -n "$reply" ]
		then
			settings_set 'vm_keyboard_mapping' "$reply"
		fi
	fi
}

################################################################################
### /usr/local/share/modules/configure/vmsettings/keyboard_mapping.inc.sh END
################################################################################
