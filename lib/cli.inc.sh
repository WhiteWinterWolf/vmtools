################################################################################
### /usr/local/lib/vmtools/cli.inc.sh BEGIN
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
# This library provides user interaction functions for a command-line interface.
#
# Public functions:
#   cli_confirm [prompt]
#         Interactively ask confirmation to the user.
#   cli_trace level string...
#         Output trace messages depending on the verbosity level.
#   cli_unit [-k|-m|-g|-t] number...
#         Convert a kilobyte number to another unit.
#
################################################################################

################################################################################
# Functions
################################################################################

###
# cli_confirm [prompt]
#
# Interactively ask confirmation to the user.
#
# This function outputs `prompt' (by default "Are you sure you want to
# continue?") on stderr and wait for the user to reply either "y" or "n".
#
# This function returns 0 if the user replied "y", 1 otherwise.
#
# If the setting variable `$cfg_ui_assumeyes' is "yes", no prompt is displayed
# and this function directly returns 0. This is usually triggered by using
# vmtools utilities' '-y' command-line flag.
#
cli_confirm() {
	local 'prompt' 'reply'
	[ "${1-}" = '--' ] && shift
	prompt=${1:-"Are you sure you want to continue [yN]? "}
	reply=$noreply

	if [ "$cfg_ui_assumeyes" = 'yes' ]
	then
		# The `-y' command-line flag bypasses the whole thing.
		return 0
	fi

	while test -n "$reply" && ! expr "$reply" : '[yYnN]$' >/dev/null
	do
		printf '%s' "$prompt" >&2
		read reply || return 1
	done

	case "$reply" in
		"y"|"Y") ;;
		*)
			printf 'Operation cancelled by the user.\n' >&2
			return 2
			;;
	esac
}

###
# cli_trace level string...
#
# Output `string' on stderr if the setting variable `$cfg_ui_verbosity' is equal
# or higher than `level'.
#
cli_trace() {
	local 'IFS' 'level'
	level=${1:?"ERROR (BUG): cli_trace: Missing parameter."}
	shift

	if [ "$level" -le "${cfg_ui_verbosity:?}" ]
	then
		IFS=' '
		printf '%s\n' "$*" >&2
	fi
}

###
# cli_unit [-k|-m|-g|-t] number...
#
# Takes `number' in kilobytes and outputs it in another unit.
#
# Available units are:
#   -k    Kilobytes.
#   -m    Megabytes.
#   -g    Gigabytes.
#   -t    Terabytes.
#
# If no unit flag is used, the most user-friendly unit is automatically chosen.
#
cli_unit() {
	local 'div' 'force_unit' 'number' 'size' 'size_k' 'size_m' 'size_g' 'size_t'
	local 'unit' 'symb'
	size_k=1
	size_m=1024
	size_g=1048576
	size_t=1073741824

	case "${1:-}" in
		'-k')
			force_unit='yes'
			size=$size_k
			symb='KB'
			shift
			;;
		'-m')
			force_unit='yes'
			size=$size_m
			symb='MB'
			shift
			;;
		'-g')
			force_unit='yes'
			size=$size_g
			symb='GB'
			shift
			;;
		'-t')
			force_unit='yes'
			size=$size_t
			symb='TB'
			shift
			;;
		*)
			force_unit='no'
			;;
	esac
	: "${1:?"ERROR (BUG): cli_unit: Missing parameter."}"
	[ "${1-}" = '--' ] && shift

	for number
	do
		if [ "$force_unit" != 'yes' ]
		then
			if [ "$number" -ge "$size_t" ]
			then
				size=$size_t
				symb='TB'
			elif [ "$number" -ge "$size_g" ]
			then
				size=$size_g
				symb='GB'
			elif [ "$number" -ge "$size_m" ]
			then
				size=$size_m
				symb='MB'
			else
				size=$size_k
				symb='KB'
			fi
		fi

		number=$( printf 'scale=2; %d/%d\n' "$number" "$size" | bc )
		printf '%s %s' "$number" "$symb"
	done
}


################################################################################
### /usr/local/lib/vmtols/cli.inc.sh END
################################################################################
