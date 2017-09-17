################################################################################
### /usr/local/share/modules/configure/vmsettings/cpu_count.inc.sh BEGIN
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
# This module asks the user to input the number of virtual CPUs available to
# the guest.
#
################################################################################

mod_configure() {
	local 'reply' 'usage'

	usage=$( cat <<-__EOF__

		NUMBER OF VCPUS

		Define the number the vCPUs available for your guest.

		Recommended value:
		- Minimum: 1
		- Maximum: $( getconf "_NPROCESSORS_ONLN" )
		(The maximum value is the number of CPU cores available on the current host.)
		__EOF__
	)

	if [ "$cfg_ui_assumeyes" = 'yes' ]
	then
		cli_trace 3 "cpu_count: ${vm_name}: Using default value: ${vm_cpu_count}."
	else
		reply=$noreply
		while test -n "$reply" && ! expr "$reply" : '[1-9][0-9]*$' >/dev/null
		do
			if [ "$reply" = '?' ]
			then
				printf '%s' "$usage" >&2
			fi
			printf '\nNumber of vCPUs (default: %d)? ' "$vm_cpu_count" >&2
			read reply || return 2
		done

		if [ -n "$reply" ]
		then
			settings_set 'vm_cpu_count' "$reply"
		fi
	fi
}

################################################################################
### /usr/local/share/modules/configure/vmsettings/cpu_count.inc.sh END
################################################################################
