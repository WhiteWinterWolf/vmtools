#! /bin/sh -eu
################################################################################
### install.sh BEGIN
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
# This file installs vmtools on the current system.
#
# vmtools files are located in the following places:
#   /usr/local/bin
#         Executables files.
#   /usr/local/lib/vmtools
#         Common libraries.
#   /usr/local/share/man
#         General documentation.
#   /usr/local/share/vmtools
#         Default modules and configuration files.
#
# The location prefix may be overwritten at install time using the '-p' option.
# Common prefixes include:
#   /usr/local
#         Default value, install vmtools system-wide as a local package.
#   ~/local
#         Installs vmtools in the user's home dir, this does not require any
#         administrative privilege.
#   /usr
#         Installs vmtools system-wide, it is recommended to reserve this
#         prefix for files installed by system packages.
#
################################################################################

usage="Install vmtools, a virtual machines manager based on Qemu.

Usage: sh ./install.sh [-fhmv] [-p prefix]

Options:
  -f    Force installation: overwrite any existing file.
  -h    Show usage information.
  -m    Do not install the manual pages.
  -p prefix
        Install the files below 'prefix' path instead of '/usr/local'.
  -v    Enable verbose mode.

To install vmtools as an unprivileged user, create a '~/.local' directory and
use it as installation prefix '-p ~/local'.
"


################################################################################
# Global variables
################################################################################

# If 'yes', overwrite any existing file.
force='no'

# If 'yes', install the man pages.
manpages='yes'

# Installation prefix.
prefix='/usr/local'

# If 'yes', enable verbose mode.
verbose='no'


################################################################################
# Functions
################################################################################

###
# check_environment
#
# Check the environment prerequisites to ensure vmtools will be usable.
#
check_environment() {
	local 'kvm' 'rc'
	rc=0

	### Required commands ###

	trace "Checking required commands..."
	# These commands are part of most base-systems.
	if ! type 'hexdump' 'lsof' 'mktemp' 'realpath' 'ss' >/dev/null
	then
		# The `type' command should already have displayed the missing commands.
		echo "ERROR: Some required commands do not seem to be available on" \
			"your system." >&2
		echo "Either install the required packages or open an issue on the" \
			"vmtools project page, telling the exact you are using." >&2
		rc=1
	fi

	trace "Checking optional commands..."
	if ! type 'genisoimage' 'socat' >/dev/null
	then
		echo "WARNING: Some optional commands are not installed on your" \
			"system." >&2
		echo "These commands are not strictly required but some vmtools" \
			"functionalities will not be available." >&2
	fi

	trace "Checking Qemu..."
	if ! type 'qemu-img' >/dev/null 2>&1
	then
		echo "ERROR: Qemu doesn't seem installed on your system." >&2
		echo "Please install it first." >&2
		rc=1
	elif ! type 'qemu-system-x86_64' >/dev/null 2>&1
	then
		echo "WARNING: The command 'qemu-system-x86_64' is not available on" \
			"this  system, you may have to update the 'cfg_qemu_cmdprefix'" \
			"setting in '/etc/vmtools/vmtools.conf' to match the Qemu command" \
			"to use on this system (see 'vmtools.conf'(5) man page)." >&2
	fi

	trace "Checking \$PATH environment variable..."
	if ! printf ':%s:' "$PATH" | grep -q ":${prefix}/bin:"
	then
		echo "WARNING: '${prefix}/bin' doesn't seem to be part of your" \
			"\$PATH." >&2
		echo "You will have to either update the \$PATH environment variable" \
			"or provide the absolute path to execute any vmtools command." >&2
	fi

	### KVM ###

	kvm='yes'

	trace "Checking system support of KVM features..."
	if ! grep -q -e 'vmx' -e 'svm' '/proc/cpuinfo'
	then
		echo "WARNING: You CPU does not support KVM extensions or you are" \
			"running this tool inside a virtualized guest." >&2
		kvm='no'
	fi

	# We need to check the group of the invoking user, not root's one.
	username=${SUDO_USER:-$( who am i | cut -d ' '  -f 1 )}
	trace "Checking user '${username}' groups..."
	if ! id -Gn "$username" | grep -q -e 'kvm' -e 'libvirtd'
	then
		echo "WARNING: The current user does not seem to be part of neither" \
			"the 'kvm' nor the 'libvirtd' group." >&2
		echo "Depending on your distribution, you may need to add your user" \
			"to at least one of these group to be able to use KVM" \
			"extensions." >&2
		kvm='no'
	fi

	if [ "$kvm" != 'yes' ]
	then
		echo "Running virutal machines is still be possible but will be MUCH" \
			"slower." >&2
		echo "To proceed you will have to change 'vm_qemu_params' setting in" \
			"'vmtools.conf' to remove KVM usage (see 'vmtools.conf'(5))." >&2
	fi

	return "$rc"
}

###
# check_files
#
# Abort the installation if some files will be overwritten.
#
check_files() {
	local 'files'

	trace "Checking existing files..."
	files=$(
		# Executable files.
		find 'bin' -name 'vm*' | sed "s#^#${prefix%/}/#" | xargs ls

		# Shared ressources.
		ls -d "${prefix%/}/lib/vmtools" "${prefix%/}/share/vmtools"

		# Man pages.
		if [ "$manpages" = 'yes' ]
		then
			find 'man' -name '*.1' \
				| sed "s#^man/\(.*\)\$#${prefix%/}/share/man/man1/\\1.gz#" \
				| xargs ls
			ls "${prefix%/}/share/man/man5/vmtools.conf.5.gz"
			ls "${prefix%/}/share/man/man7/vmtools.7.gz"
		fi
	) 2>/dev/null

	if [ -n "$files" ]
	then
		echo "ERROR: Some files already exist on your system." >&2
		echo "Use 'uninstall.sh' to uninstall any previous version of vmtools" \
			"first, or use the '-f' (force) flag to overwrite them." >&2

		# Display the files list by default only if it is short (ie. it is not
		# a complete install of vmtools which is already present).
		if [ "$verbose" = 'yes' \
			-o "$( printf '%s' "$files" | wc -l )" -le 10 ]
		then
			echo "Conflicting files:" >&2
			printf '%s\n' "$files" | sed 's/^/    /'
		else
			echo "More than ten conflicting files have been found, use the" \
				"'-v' (verbose) flag to get a complete listing." >&2
		fi

		return 1
	fi
}

###
# install_files
#
# Install vmtools files.
#
install_files() {
	local 'filename' 'section'

	trace "Copying main files..."

	if [ ! -d "$prefix" ]
	then
		echo "ERROR: ${prefix}: The installation target does not exists or is" \
			"not a directory." >&2
		return 1
	fi

	# Executable files.
	install -m 755 -D -t "${prefix%/}"/bin bin/vm*
	# Common libraries.
	install -m 644 -D -t "${prefix%/}"/lib/vmtools lib/*.inc.sh
	# Main configuration file.
	install -m 644 -D -t "${prefix%/}"/share/vmtools share/vmtools.conf

	# Modules and template files.
	for p in 'modules/configure/settings' 'modules/configure/templates' \
		'modules/buildcmd' 'modules/clone' 'templates'
	do
		# `README.md' files are also copied, this is the expected behavior.
		install -m 644 -D -t "${prefix%/}/share/vmtools/${p}" "share/${p}/"*
	done
	# Also copy the 'configure' modules README file.
	install -m 644 -D -t "${prefix%/}"/share/vmtools/modules/configure \
		share/modules/configure/README.md

	if [ "$manpages" = 'yes' ]
	then
		trace "Copying manual pages..."
		for p in man/*.[1-8]
		do
			filename=${p##*/}
			section=${p##*.}
			mkdir -p -- "${prefix%/}/share/man/man${section}" || return 1
			gzip -c -- "$p" \
				>"${prefix%/}/share/man/man${section}/${filename}.gz" \
				|| return 1
		done
	fi
}

###
# update_prefix
#
# Create a copy of each file to install with the prefix path updated.
#
update_prefix() {
	local 'fname' 'tmpdir'

	trace "Updating prefix:"

	# There is no reason why a user would use a prefix containing a '#', but we
	# still want to avoid the user to be bothered with some obscure sed message.
	case "$prefix" in *'#'*)
		echo "ERROR: The prefix must not contain the '#' character:" \
			"'${prefix}'." >&2
		return 1
	esac

	tmpdir=$( mktemp -d "${TMPDIR:-"/tmp"}/vmtools-install.XXXXXXXXXX" ) \
		|| return 1
	trap 'rm -rf "$tmpdir"' INT TERM QUIT EXIT

	find 'bin' 'lib' 'man' 'share' \! -path "$( printf '*\n*' )" \
		| while read -r 'fname'
	do
		if [ -L "$fname" ]
		then
			trace "    Link: $fname"
			cp -P -- "$fname" "${tmpdir}/${fname}" || return 1

		elif [ -f "$fname" ]
		then
			trace "    File: $fname"
			# TODO: Replacing `/etc/vmtools' here allows unprivileged users to
			# fully use vmtools, however this will cause an unexpected behavior
			# if for some reason the user uses '/usr' for instance as prefix.
			# => provide an option to explicitely keep or alter the `/etc' path.
			sed \
				-e "s#/usr/local#${prefix%/}#g" \
				-e "s#/etc/vmtools#${prefix%/}&#g" \
				"$fname" >"${tmpdir}/${fname}" \
				|| return 1

		elif [ -d "$fname" ]
		then
			trace "    Dir:  $fname"
			mkdir -- "${tmpdir}/${fname}"

		else
			echo "ERROR: Unknown file type: '${fname}'." >&2
			return 1
		fi
	done

	# Now the installation proceeds using the new files version.
	cd "$tmpdir"
}

###
# trace
#
# Output debug messages on stdout when verbose mode is enabled.
#
trace() {
	local 'IFS'

	if [ "$verbose" = 'yes' ]
	then
		IFS=' '
		printf '%s\n' "$*"
	fi
}


################################################################################
# Parse parameters
################################################################################

OPTIND=1
while getopts "fhmp:v" opt
do
	case "$opt" in
		'f')
			force='yes'
			;;
		'h')
			echo "$usage"
			exit 0
			;;
		'm')
			manpages='no'
			;;
		'p')
			prefix=$OPTARG
			;;
		'v')
			verbose='yes'
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

check_environment || exit 1

if [ "$force" != 'yes' ]
then
	check_files || exit 1
fi

# The default prefix is hardcoded in vmtools scripts.
if [ "$prefix" != '/usr/local' ]
then
	update_prefix || exit 1
fi

install_files || exit 1

echo "vmtools successfully installed."

################################################################################
### install.sh END
################################################################################
