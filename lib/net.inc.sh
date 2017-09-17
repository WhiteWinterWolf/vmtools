################################################################################
### /usr/local/lib/vmtools/net.inc.sh BEGIN
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
# This library provides a few shared network-related utilities.
#
# Public functions:
#   net_free_port iface [port]
#         Find a free TCP port to listen on it.
#   net_random_port
#         Generate random port numbers in the ephemeral port range.
#   net_random_mac [prefix]
#         Generate random a MAC address.
#
################################################################################


################################################################################
# Functions
################################################################################

###
# net_free_port iface [port]
#
# Find an unused TCP port on interface `iface' usable as a listen port.
#
# This function either:
#   - Search sequentially for the first unused port equal to or greater than
#     `port'.
#   - If `port' is not provided, pick a random unused port in the ephemeral
#     port range (between 49152 and 65535).
#
net_free_port() {
	local 'iface' 'port_first' 'port_tried' 'port_used'
	iface=${1:?"ERROR (BUG): net_freeport: Missing parameter."}
	port_first=${2:-}
	port_used=$( ss -nlt4 "( sport >= ${iface}:${port_first} )")

	port_tried=${port_first:-"$( net_random_port )"} || return 1
	ok='no'
	while [ "$ok" != 'yes' ]
	do
		case "$port_used" in
			*":${port_tried} "*)
				if [ -n "$port_first" ]
				then
					port_tried=$(( port_tried + 1 ))
					if [ "$port_tried" -gt 65535 ]
					then
						echo "ERROR: Failed to find a free TCP port above" \
							"${port_first}." >&2
						return 1
					fi
				else
					port_tried=$( net_random_port ) || return 1
				fi
				;;
			*)
				ok='yes'
				;;
		esac
	done

	printf '%s' "$port_tried"
}

###
# net_random_port
#
# Generate a random number between 49152 and 65535, suitable range for
# ephemeral ports.
#
# This function does not do any check regarding the current port status, it
# only generates random numbers.
#
net_random_port() {
	local port

	port=$( od -A n -N 2 -t u2 /dev/urandom ) || return 1
	port=$(( port | 49152 ))

	printf '%s' "$port"
}


###
# net_random_mac [prefix]
#
# Generate a random MAC address starting with  `prefix', or
# `$vm_networking_default_mac' if no `prefix' was given.
#
# The MAC address prefix should be a valid Organizationally Unique Identifier
# (OUI), or at least the multicast bit must be set to 0 to avoid networking
# issues. Multicast MAC addresses are indeed not allowed as sender in
# Ethernet frames, some network devices consider such frames as corrupted and
# silently drop them.
# From <http://standards.ieee.org/about/get/802/802.3.html>:
# > In the Source Address field, the first bit is reserved and set
# > to 0.
# It is also recommended to set the locally administered bit to 1.
#
# If an empty string is passed as `prefix', or if `$vm_networking_default_mac',
# then a MAC address will be generated with the administered bit set to 1, the
# multicast bit set to 0, and all other bits random.
#
net_random_mac() {
	local 'mac' 'prefix' 'suffix' 'suffix_bytes'
	[ "${1-}" = '--' ] && shift
	prefix=${1:-"$vm_networking_default_mac"}

	if [ -n "$prefix" ]
	then
		prefix=${prefix%":"}
		if ! expr "$prefix" : '\([0-9A-Fa-f]\{2\}:\)\{0,5\}[0-9A-Fa-f]\{2\}$' \
			>/dev/null
		then
			echo "ERROR: Invalid MAC address prefix: wrong structure:" \
				"'${prefix}'." >&2
			return 1
		fi
		# Locally administered bit value is left for the user to choose.
		# It is mandatory however to the multicast bit to remain unset.
		case "$prefix" in ?[13579BbDdFf]*)
			echo "ERROR: Invalid MAC address prefix: the multicast bit must" \
				"be set to 0: '${prefix}'." >&2
			return 1
		esac
	fi

	suffix_bytes=$(( 6 - ( ${#prefix} + 1 ) / 3 ))

	if [ "$suffix_bytes" -eq 0 ]
	then
		mac=$prefix
	else
		# `od' output has a one leading space, thus producing a leading comma.
		suffix=$( od -A n -N "$suffix_bytes" -t x1 /dev/urandom  | tr ' ' ':' )

		if [ "$suffix_bytes" -eq 6 ]
		then
			suffix=${suffix#":"}
			# The only second digits fulfilling both the locally administered
			# and the unicast prerequisites are `2', `6', `A', and `E'.
			# Note that a few IEEE assigned OUI use `2' and `A', see:
			# <https://networkengineering.stackexchange.com/q/18747/27387>
			# So easiest and safest choice seems to lock this digit to `6'.
			case "$suffix" in
				?[f01]*)
					mac=$( printf '%s' "$suffix" | sed 's/\(.\).\(.*\)/\12\2/' )
					;;
				?[345]*)
					mac=$( printf '%s' "$suffix" | sed 's/\(.\).\(.*\)/\16\2/' )
					;;
				?[789]*)
					mac=$( printf '%s' "$suffix" | sed 's/\(.\).\(.*\)/\1a\2/' )
					;;
				?[bcd]*)
					mac=$( printf '%s' "$suffix" | sed 's/\(.\).\(.*\)/\1e\2/' )
					;;
				*)
					mac=$suffix
					;;
			esac
		else
			mac="${prefix}${suffix:?}"
		fi
	fi

	printf '%s' "$mac"
}

################################################################################
### /usr/local/lib/vmtools/net.inc.sh END
################################################################################
