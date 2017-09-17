################################################################################
### /usr/local/share/modules/configure/vmsettings/ram_size.inc.sh BEGIN
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
# This module asks the user to input the amount of RAM to allocate to the guest.
#
################################################################################

mod_configure() {
	local 'reply' 'unit' 'usage'

	usage=$( cat <<-__EOF__

		RAM SIZE

		Define the size of RAM available for your guest.

		Recommended values:
		- Minimum: 1M
		- Maximum: $( free -h | awk 'NR == 2 {print $4}' )
		(the maximum value is the free physical RAM remaining on the current host)

		__EOF__
	)

	if [ "$cfg_ui_assumeyes" = 'yes' ]
	then
		cli_trace 3 "ram_size: ${vm_name}: Using default value: ${vm_ram_size}."
	else
		reply=$noreply
		while test -n "$reply" && ! expr "$reply" : '[1-9][0-9]*[MG]$' >/dev/null
		do
			if [ "$reply" = '?' ]
			then
				printf '%s\n' "$usage" >&2
			fi
			printf '\nRAM size (default: %s)? ' "$vm_ram_size" >&2
			read reply || return 2
			reply=$( str_toupper -- "$reply" )

			# Common typo: enter `2' instead of `2G' then wonder why the VM fails...
			if expr "$reply" : '[1-9][0-9]*$' >/dev/null
			then
				printf '\nYou did not mention any unit.\n' >&2
				unit=$noreply
				while test -n "$unit" && ! expr "$unit" : '^[MG]$' >/dev/null
				do
					if [ "$unit" = '?' ]
					then
						{
							echo
							echo "You must enter either 'm' or 'g' to confirm" \
								"the unit."
						} >&2
					fi
					printf 'Did you mean Megabytes or Gigabytes [mG]? ' >&2
					read unit || return 2
					unit=$( str_toupper -- "$unit" )
				done
				reply="${reply}${unit:-"G"}"
			fi
		done

		if [ -n "$reply" ]
		then
			settings_set 'vm_ram_size' "$reply"
		fi
	fi
}

################################################################################
### /usr/local/share/modules/configure/vmsettings/ram_size.inc.sh END
################################################################################
