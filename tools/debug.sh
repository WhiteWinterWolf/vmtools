#! /bin/sh -efu
################################################################################
### tools/debug.sh BEGIN
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
# This tool provides an interactive shell allowing to manually call or emulate
# vmtools internal functions.
#
################################################################################

################################################################################
# Functions
################################################################################

# Loading shared libs (loading them all is faster than nitpicking).
# SC2044: Parameter expansion disabled, filenames have no space.
# shellcheck disable=SC2044
for f in $( find '/usr/local/lib/vmtools' -name '*.inc.sh' )
do
	. "$f" || exit 1
done


################################################################################
# Parse parameters
################################################################################

include_globalconf || exit 1


################################################################################
# Main
################################################################################

echo "vmtools debug shell, press 'Ctrl-D' to exit."

while printf 'vmtools> ' >&2; read -r cmd
do
	# SC2086: Word splitting expected on `$cmd'.
	# shellcheck disable=SC2086
	eval $cmd || printf 'EXIT CODE: %d\n' "$?" >&2
done

printf '\nExiting...\n' >&2

################################################################################
### tools/debug.sh END
################################################################################
