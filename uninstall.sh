#! /bin/sh -eu
################################################################################
### uninstall.sh BEGIN
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
# This file uninstall vmtools from the current system.
#
################################################################################

usage="Uninstall vmtools from the local system.

Usage: sh ./install.sh [-h] [-p prefix]

Options:
  -h    Show usage information.
  -p prefix
        Uninstall the files below 'prefix' path instead of '/usr/local'.
"


################################################################################
# Global variables
################################################################################

# Installation prefix.
prefix='/usr/local'


################################################################################
# Parse parameters
################################################################################

OPTIND=1
while getopts "hp:" opt
do
	case "$opt" in
		'h')
			echo "$usage"
			exit 0
			;;
		'p')
			prefix=$OPTARG
			;;
		*)
			echo "Invalid parameter: '$opt'." >&2
			exit 2
			;;
	esac
done
shift $(( OPTIND - 1 ))


################################################################################
# Main
################################################################################

cd "$( dirname -- "$0" )"


### vmtools own files ###

# Automatically delete them, but list every deleted file.

# Executable files.
find 'bin' -name 'vm*' | sed "s#^#${prefix%/}/#" | xargs rm -fv

# Common ressources.
rm -rfv "${prefix%/}/lib/vmtools" "${prefix%/}/share/vmtools"

# Man pages.
find 'man' -name '*.1' \
	| sed "s#^man/\(.*\)\$#${prefix%/}/share/man/man1/\\1.gz#" \
	| xargs rm -fv
rm -fv "${prefix%/}/share/man/man5/vmtools.conf.5.gz"
rm -fv "${prefix%/}/share/man/man7/vmtools.7.gz"


### User's customized files ###

# Ask the user before deleting any of them.

if [ -e '/etc/vmtools' ]
then
	rm -rfi '/etc/vmtools'
fi

# We must use invoking user's home dir, not root's one.
eval homedir="~${SUDO_USER:-$( who am i | cut -d ' '  -f 1 )}"
if [ -e "${XDG_CONFIG_HOME:-"${homedir}/.config"}/vmtools" ]
then
	rm -rfi -- "${XDG_CONFIG_HOME:-"${homedir}/.config"}/vmtools"
fi

echo
echo "vmtools successfully uninstalled."

################################################################################
### uninstall.sh END
################################################################################
