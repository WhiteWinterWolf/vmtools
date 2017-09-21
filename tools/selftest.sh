#! /bin/sh -efu
################################################################################
### tools/selftest.sh BEGIN
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
# This tool provides a set of automated tests to help detect regressions.
#
# The full test set requires some time to execute, however overwriting
# `$list_names' to a single value allows to speed things up and still detect
# most logic flaws (there will be no test against improper character escaping
# though).
#
# When an issue is detected, everything is left in place allowing in most cases
# to manually reproduce and study the issue.
#
################################################################################

# TODO: Explode `check_all()' into modules.
# Make each module more independant: each should generate their own tree
# so there is no dependency anymore on the actions made by previous modules
# (also check vmtree(): the function to create and to check the tree should
# have similar syntaxes).
# Gold solution: use dynamic dependency between modules (see make, rcorder),
# otherwise simply use a numeric prefix.
#
# TODO: Do a first full cycle with the first name of the list, and if it
# succeeds loop with each names on each tests, this provides the fastest
# feedback:
# - Allows to first check for any logic error using by cycling on all modules
#   using the first name.
# - Then cycling on the names allows to detect special caracter handling issues,
#   knowing that such issues are mostly encountered in the first modules as
#   serve as a fundation for the latest ones.
#
# TODO: Express the evolution as a percentage instead of number of steps:
# 23%: vmfork: foo/foo_A/foo_B
# Percentage is calculated from the number of modules * number of names to try.

################################################################################
# Global variables
################################################################################

# Loading vmtools general settings
. '/usr/local/share/vmtools/vmtools.conf'
if [ -r '/etc/vmtools/vmtools.conf' ]
then
	. '/etc/vmtools/vmtools.conf'
fi
if [ "$cfg_include_userhome" = 'yes' \
	-a -r "${XDG_CONFIG_HOME:-"${HOME}/.config"}/vmtools/vmtools.conf" ]
then
	. "${XDG_CONFIG_HOME:-"${HOME}/.config"}/vmtools/vmtools.conf"
fi


### Settings ###

# Local bootable ISO file.
file_iso='images/Core-8.0.iso'

# Local OVA virtual machine.
# The file must have the '.ova' extension.
file_ova='images/yVM-5.4.ova'

# VMDK file stored in the OVA file above.
file_vmdk='yVM-disk1.vmdk'

# Use the line feed as the only field separator.
IFS='
'

# Available display modes.
# `none', `spice' and `vnc' are assumed to be always available, `gtk' and `sdl'
# are optional and depend on the local Qemu compilation parameters and if a
# window server is available.
list_display='none
sdl
spice
vnc'

# Names used for files and directories.
# SC2089: `$list_names' is expected to be multiline.
# SC1004: Backslashes are expected to be litterals.
# shellcheck disable=SC2089,SC1004
list_names='foo
[f]oo
.foo
foobar.iso
foobar.vmdk
foobar.ova
*
>
\
$$
^"'\''`({[\[^$,+?)}];\\\n#%$
foo,,bar
foo bar
foo	bar baz?qux
foo?bar baz	qux
fóò⁄ƀâř
-
--
-n
 '
# To execute a quick rundown of all tests, simply overwrite `$list_names' with
# a single value.
# list_names='foo'

# Read-only remotely bootable files.
# Set these variables to an empty value to disable the associated tests.
# Currently there is a hardcoded timeout of 5 seconds, depending on the local
# connectivity (and the possibility that the remote host may trigger DOS
# protection systems) the associated tests may not be reliable and fail due
# to timeout errors.
# Qemu V3 will add a configurable setting for this timeout:
# https://lists.gnu.org/archive/html/qemu-devel/2014-08/msg02065.html
list_urls_cdrom='' # 'http://tinycorelinux.net/8.x/x86/release/Core-current.iso'
# Starting this VM with 48M of RAM results in a kernel panic, but this is
# enough to check vmtools.
list_urls_hdd_ro='' # 'https://dl.fedoraproject.org/pub/fedora/linux/releases/25/CloudImages/x86_64/images/Fedora-Cloud-Base-25-1.3.x86_64.qcow2'

# RAM size allocated to a single virtual machine.
# Up to six may be launched simultaneously.
ram_size='48M'

# Subdirectory of `vmtools/test/` storing generated data.
# When a failure is detected, generated data will be left as-is allowing to
# manually reproduce the issue.
out_dir='out'

# Log file.
out_log="${out_dir}/${out_dir}.log"


### Global variables ###

# Indentation for log entries generated by `check()'.
check_indent=''

# Current and total number of sections (titles).
# These counters are only used for display purposes.
title_count=0
title_total=17
# Last title label
title_label=''


################################################################################
# Functions
################################################################################

###
# boot vmup_args...
#
# TODO: Ensure that the gues OS has correctly started.
# A good way to do this: boot the VM with some defined networking
# configuration, then try to ping the guest: if the ping fails for more than
# a reasonable time, assume that the guest OS fails to boot and that the VM
# is broken (this will however make the complete self-test *way* longer, add an
# option to bypass this feature to allow quicker small tests).
#
boot() {
	local 'lastarg'
	eval "lastarg=\$$#"

	boot_display 'none' "$@"

	if [ -d "$lastarg" ]
	then
		# The VM home dir is the last parameter.
		boot_down "$lastarg"
	else
		boot_down
	fi
}

###
# boot_display display_type vmup_args...
#
boot_display() {
	local 'display_type'
	display_type=${1:?"ERROR (SELFTEST BUG): boot_display: Missing parameter."}
	: "${1:?"ERROR (SELFTEST BUG): boot_display: Missing parameter."}"

	# No other virtual machine must be running.
	check ! vmps
	check boot_display_up "$@"
	check vmps
	case "$( vmps -r -o d )" in
		"$display_type"*) ;;
		*)
			printf 'TEST FAILED: %s\n' \
				"Unexpected display type (should be '${display_type}')." >&2
			return 1
			;;
	esac
}

###
# boot_display_up display_type vmup_args...
#
boot_display_up() {
	local 'display'
	display=${1:?"ERROR (SELFTEST BUG): boot_display_up: Missing parameter."}
	shift
	: "${1:?"ERROR (SELFTEST BUG): boot_display_up: Missing parameter."}"

	check vmup -qy -o "vm_ram_size=${ram_size}" \
		-o "vm_display_type=${display}" "$@"
}

###
# boot_down [vmhome]
#
boot_down() {
	local 'vmhome'
	vmhome=${1-}

	if [ -n "$vmhome" ]
	then
		check vmdown -tw -- "$vmhome"
	else
		check vmdown -atw
	fi

	check ! vmps
}

###
# boot_media_cdrom file
#
# Attempt to boot a virtual machine using an ISO file.
# Local and remote ISO files shall have identical behavior.
#
boot_media_cdrom() {
	local 'file'
	[ "$1" = '--' ] && shift
	file=${1:?"ERROR (SELFTEST BUG: check_boot_cdrom: Missing parameter."}

	# ISO images cannot be accessed in read-write mode (even through
	# snapshoting).
	check boot -- "$file"
	check ! boot -- "rw:${file}"
	check ! boot -- "snap:${file}"
	check boot -- "ro:${file}"
	check ! boot -- "invalid:${file}"
}

###
# boot_media_hdd_ro file
#
boot_media_hdd_ro() {
	local 'file'
	[ "$1" = '--' ] && shift
	file=${1:?"ERROR (SELFTEST BUG: check_boot_hdd_ro: Missing parameter."}

	# IDE hard-disk drive cannot be read-only.
	check boot -- "$file"
	check ! boot -- "rw:${file}"
	check boot -- "snap:${file}"
	check ! boot -- "ro:${file}"
	check ! boot -- "invalid:${file}"
}

###
# boot_media_hdd_rw file
#
boot_media_hdd_rw() {
	local 'file'
	[ "$1" = '--' ] && shift
	file=${1:?"ERROR (SELFTEST BUG: check_boot_hdd_rw: Missing parameter."}

	# IDE hard-disk drive cannot be read-only.
	check boot -- "$file"
	check boot -- "rw:${file}"
	check boot -- "snap:${file}"
	check ! boot -- "ro:${file}"
	check ! boot -- "invalid:${file}"
}

###
# check command [arg...]
#
check() {
	local 'cmd' 'cmd_out' 'rc'
	: "${1:?"ERROR (SELFTEST BUG): check: Missing parameter."}"
	rc=0
	cmd=$( escape "$@" )

	# Add a blank line between each check.
	printf '%s\n%s%s\n' "$check_indent" "$check_indent" "$cmd" >&3

	check_indent="${check_indent}.  "
	if [ "$1" = '!' ]
	then
		cmd_out=$( ! ( eval "${cmd#"!"}" 2>&1 ) ) || rc=$?
		# Commands with a non-null exit code do not necessarily output any
		# error message (`vmps' is a typical example).
	else
		cmd_out=$( eval "$cmd" 2>&1 ) || rc=$?
		if [ "$rc" -eq 0 ]
		then
			# Catch odd behaviors which did not impact the exit code.
			# Command with a null exit code are not expected to raise anything
			# above NOTICE messages.
			case "$cmd_out" in *'WARNING'*|*'ERROR'*)
				rc=1
			esac
		fi
	fi
	check_indent="${check_indent%".  "}"

	if [ -n "$cmd_out" ]
	then
		printf '%s\n' "$cmd_out" | sed "s/^/${check_indent}    /" >&3
		if [ "$rc" -eq 0 ]
		then
			case "$cmd_out" in *'BUG'*)
				# A bug has been detected, enforce test failure.
				rc=1
			esac
		fi
	fi

	if [ "$rc" -ne 0 ]
	then
		printf '%sExit code: %d\n' "$check_indent" "$rc" >&3

		if [ -z "$check_indent" ]
		then
			printf '\nCHECK FAILED: %s\n' "$cmd" >&3
			printf 'Current step: %s\n' "$title_label"  >&3
			printf 'Test ended (error): %s\n' "$( date )" >&3

			printf '\nCHECK FAILED: %s\n' "$cmd" >&2
			printf 'Check %s for more details.\n' "$out_log" >&2
		fi

		exit 1
	fi
}

###
# check_all
#
# This is the main function which contains all the tests to be done.
#
check_all() {
	local 'name'

	title "vmtools utilities."
	{
		# TODO: Check additional utilities (vmmon, ...).

		progress "vmrndmac"
		# `vmrndmac' relies on the same MAC generation library than VM creation
		# commands.
		check vmrndmac
		check vmrndmac '12:34:ab:cd'
		check vmrndmac '12:34:ab:cd:'
		check ! vmrndmac ':12:34:ab:cd'
		check vmrndmac '12:34:56:78:9A:BC'
		check ! vmrndmac '12:34:56:78:9A:BC:DE'
		check ! vmrndmac '123'
	}

	if [ -n "$list_urls_cdrom" ]
	then
		title "Boot from remote ISO images."
		{
			for name in $list_urls_cdrom
			do
				progress "${name:?}"
				check boot_media_cdrom -- "$name"
			done
		}
	else
		title "Boot from remote ISO images. (skipped)"
	fi

	if [ -n "$list_urls_hdd_ro" ]
	then
		title "Boot from remote read-only HDD images."
		{
			for name in $list_urls_hdd_ro
			do
				progress "${name:?}"
				check boot_media_hdd_ro -- "$name"
			done
		}
	else
		title "Boot from remote read-only HDD images. (skipped)"
	fi

	title "Boot from local ISO images."
	{
		# GNU `touch' will not create a file named `-' (against POSIX, but does
		# not impact the tests as long a `-f' flag is used for `rm').
		# SC2086,SC2090: Word splitting of `$list_names' expected.
		# shellcheck disable=SC2086,SC2090
		touch -- $list_names || exit 1
		name_previous=${file_iso:?}
		for name in $list_names
		do
			progress "${name:?}"
			mv -f -- "$name_previous" "$name" || exit 1
			touch -- "$name_previous" || exit 1

			check boot_media_cdrom -- "$name"
			name_previous=$name
		done
		mv -f -- "$name_previous" "$file_iso" || exit 1
		# SC2086,SC2090: Word splitting of `$list_names' expected.
		# shellcheck disable=SC2086,SC2090
		rm -f -- $list_names || exit 1
	}

	title "Use various display types."
	{
		for name in $list_display
		do
			progress "${name:?}"
			check boot_display "$name" -- "$file_iso"
			check boot_down
		done
		progress 'invalid'
		check ! boot_display 'invalid' -- "$file_iso"
		check boot_down

		progress "spice & vnc (parallel instances)"
		check ! vmps
		check boot_display_up 'vnc' -- "$file_iso"
		check boot_display_up 'spice' -- "$file_iso"
		check boot_display_up 'vnc' -- "$file_iso"
		check boot_display_up 'vnc' -- "$file_iso"
		check boot_display_up 'spice' -- "$file_iso"
		check boot_display_up 'spice' -- "$file_iso"

		# Take advantage of the fact several VMs are running to check `vmps'.
		progress "vmps"
		check vmps -o cdehmnpqu
		vmps -o cdehmnpqu | check ! grep -F 'WARNING' || exit 1
		check vmps -n
		check test -z "$( vmps -n 2>&1 )"
		# POSIX mandates that `sort' can handle at least nine sorting keys.
		# Trying to use more falls out of standard scope.
		check vmps -s cdehm
		# Some warning messages may not affect the exit code.
		vmps -s cdehm | check ! grep 'ERROR\|WARNING' || exit 1
		check vmps -s mnpqu
		vmps -s mnpqu | check ! grep 'ERROR\|WARNING' || exit 1

		progress "spice & vnc (old ports reuse)"
		check vmps -o pd -s d
		vmps_out=$( vmps -r -o d -s d | LC_ALL=C sort ) || exit 1
		# SC2046: Word splitting is expected on `awk' output.
		# shellcheck disable=SC2046
		check vmdown -ptw $( vmps -r -o p -s d | awk 'NR==2 || NR==4 || NR==6' )
		check boot_display_up 'spice' -- "$file_iso"
		check boot_display_up 'vnc' -- "$file_iso"
		check boot_display_up 'spice' -- "$file_iso"
		check vmps -o pd
		# Ensure that previously used ports are correctly reused.
		check test "$vmps_out" != "$( vmps -r -o d -s d | LC_ALL=C sort )"

		check vmdown -atw
		check ! vmps
		check ! vmps -n
		check test -z "$( vmps -n 2>&1 )"
	}

	# Generates a QCOW2 image ("${file_ova%".ova"}.qcow2") and a VMDK image
	# ("images/${file_vmdk}") from `$file_ova'.
	title "Convert OVA virtual machines to QCOW2."
	{
		progress "OVA file name: ${file_ova}"

		file_qcow2="${file_ova%".ova"}.qcow2"

		check test ! -e "$file_qcow2"
		check vmup -nqy -- "$file_ova"
		check test -s "$file_qcow2"

		# SC2086,SC2090: Word splitting of `$list_names' expected.
		# shellcheck disable=SC2086,SC2090
		touch -- $list_names || exit 1
		name_previous=$file_ova

		for name in $list_names
		do
			progress "OVA file name: ${name}"

			if [ "$name_previous" != "$file_ova" ]
			then
				: >"$name_previous" || exit 1
			fi
			cp -f -- "$file_ova" "$name" || exit 1

			if [ -n "${name%.*}" ]
			then
				if [ "${name%".qcow2"}" = "$name" ]
				then
					newname="${name%.*}.qcow2"
					check test ! -s "${newname}"
				else
					# `$name' is already a `.qcow2' file, it will get
					# overwritten.
					newname=$name
					check file -b -- "$newname"
					file -b -- "$newname" | check grep -F 'POSIX tar archive' \
						|| exit 1
				fi
			else
				# `$name' is dotted file with no extension.
				newname="${name}.qcow2"
				check test ! -s "${newname}"
			fi
			check vmup -nqy -- "$name"
			check test -s "$newname"
			check file -b -- "$newname"
			file -b -- "$newname" | check grep -F 'QEMU QCOW Image' || exit 1

			rm -f -- "$newname"
			name_previous=$name
		done

		touch -- "$name_previous" || exit 1

		mkdir -p 'images' || exit 1
		tar -x -f "$file_ova" -C 'images' -- "$file_vmdk" || exit 1

		for name in $list_names
		do
			progress "VMDK file name: ${name}.vmdk"

			cp -f "images/${file_vmdk}" "${name}.vmdk" || exit 1
			# GNU tar violates the standard by attempting to "unquote" by
			# default file names passed as parameter.
			# https://lists.gnu.org/archive/html/bug-tar/2010-11/msg00025.html
			tar --no-unquote -cP -f "images.ova" -- "${name}.vmdk" || exit 1
			rm -- "${name}.vmdk" || exit 1

			check test ! -e "images.qcow2"
			check vmup -nqy -- "images.ova"
			check test -s "images.qcow2"

			rm -- "images.ova" "images.qcow2" || exit 1
		done

		# SC2086,SC2090: Word splitting of `$list_names' expected.
		# shellcheck disable=SC2086,SC2090
		rm -f -- $list_names || exit 1
	}

	# Relies on previously created QCOW2 file ("${file_ova%".ova"}.qcow2").
	title "Boot from local QCOW2 image."
	{
		# GNU `touch' will not create a file named `-' (against POSIX, but does
		# not impact the tests as long a `-f' flag is used for `rm').
		# SC2086,SC2090: Word splitting of `$list_names' expected.
		# shellcheck disable=SC2086,SC2090
		touch -- $list_names || exit 1
		name_previous="${file_ova%".ova"}.qcow2"

		for name in $list_names
		do
			progress "${name:?}"
			mv -f -- "$name_previous" "$name" || exit 1
			touch -- "$name_previous" || exit 1

			check boot_media_hdd_rw -- "$name"
			name_previous=$name
		done

		mv -- "$name_previous" "${file_ova%".ova"}.qcow2"
		# SC2086,SC2090: Word splitting of `$list_names' expected.
		# shellcheck disable=SC2086,SC2090
		rm -f -- $list_names || exit 1
	}

	# Uses ISO files booting, so should be tested after it.
	# Requires the 'image' directory to be created and populated.
	# TODO: Check that the guest OS can indeed access the shared drive content.
	title "Use shared storage devices."
	{
		# SC2086,SC2090: Word splitting of `$list_names' expected.
		# shellcheck disable=SC2086,SC2090
		touch -- $list_names || exit 1
		cp -R 'images' 'images_copy' || exit 1
		name_previous='images_copy'

		for name in $list_names
		do
			rm -f -- "$name" || exit 1
			mv -f -- "$name_previous" "$name" || exit 1
			touch -- "$name_previous" || exit 1

			progress "${name:?} (ISO CD-ROM device)"
			check boot -d "$name" -- "${file_iso:?}"

			progress "${name:?} (VVFAT HDD device)"
			check boot -c "$name" -- "${file_iso:?}"

			name_previous=$name
		done

		rm -fr -- "$name_previous" || exit 1
		# SC2086,SC2090: Word splitting of `$list_names' expected.
		# shellcheck disable=SC2086,SC2090
		rm -f -- 'images_copy' $list_names || exit 1
	}

	# Relies on previously created VMDK file ("images/${file_vmdk}").
	# Creates virtual machines for each name in `$list_names'.
	title "Create new virtual machines."
	{
		name_previous=${file_vmdk%".vmdk"}

		for name in $list_names
		do
			progress "$name (create)"
			# Creating the VM from .ova files instead of .qcow2 to get the
			# largest code coverage.
			# These are fake .ova files but should not make any difference
			# regarding vmtools behavior.
			mv "images/${name_previous}.vmdk" "images/${name}.vmdk" \
				|| exit 1
			# GNU tar violates the standard by attempting to "unquote" by
			# default file names passed as parameter.
			# https://lists.gnu.org/archive/html/bug-tar/2010-11/msg00025.html
			tar --no-unquote -cP -f "${name}.ova" -C 'images' -- \
				"${name}.vmdk" || exit 1
			cp -- "$file_iso" "${name}.iso"

			# `vmcreate' automatically starts the newly created VM by default.
			check ! vmps
			check vmcreate -qy -o "vm_ram_size=${ram_size}" \
				-o 'vm_display_type=none' -C "${name}.ova" -D "${name}.iso" -- \
				"$name"
			check vmps
			check vmdown -atw
			check vmsettingsfile -- "$name"

			progress "$name (boot + vminfo)"
			# Ensure that the VM can also be started outside of `vmcreate'.
			# Take this opportunity to also check `vminfo' behavior.
			check boot_display 'none' -- "$name"
			check vminfo -- "$name"
			check vminfo -l -- "$name"
			vminfo_out=$( vminfo -l -- "$name" )
			printf '%s' "$vminfo_out" | check ! grep 'ERROR\|WARNING' || exit 1
			printf '%s' "$vminfo_out" | check grep 'State: RUNNING' || exit 1
			printf '%s' "$vminfo_out" | check ! grep 'State: not running' \
				|| exit 1

			check boot_down
			check vminfo -- "$name"
			check vminfo -l -- "$name"
			vminfo_out=$( vminfo -l -- "$name" )
			printf '%s' "$vminfo_out" | check ! grep 'ERROR\|WARNING' || exit 1
			printf '%s' "$vminfo_out" | check ! grep 'State: RUNNING' || exit 1
			printf '%s' "$vminfo_out" | check grep 'State: not running' \
				|| exit 1

			rm -- "${name}.iso" "${name}.ova"
			name_previous=$name
		done

		mv "images/${name_previous}.vmdk" "images/${file_vmdk}" \
			|| exit 1
	}

	# Relies on VM already created for each name in `$list_names'.
	# Generates forks under each VM home dir.
	# Create the `${name}.tree' file.
	# TODO: Check that all copy mode combination is tested, including forks
	# in snapshot mode in this case ensure that the child directly uses parent's
	# storage image file, with normal forks ensure that the disk image contains
	# no data (not a copy from the source disk image).
	title "Virtual machine forking."
	{
		for name in $list_names
		do
			progress "$name"
			# Create a several level deep ($name/A/B/C/D/E) nested tree with at
			# several forks at some levels.

			# Raw $name as source.
			check test -e "./${name}" -a ! -e "${name}/${name}_A" \
				-a ! -e "${name}/${name}_bis_A"
			check vmfork -qy -- "$name" "${name}/${name}_A" \
				"${name}/${name}_bis_A"
			check test -d "${name}/${name}_A" -a -d "${name}/${name}_bis_A"

			# Forked VM must contain only modified settings and inherit the
			# rest from their ancestors.
			# This allows to centralize common settings for a whole VM tree.
			check ! grep 'vm_ram_size\|vm_storage_[[:alnum:]]*_enable' \
				"${name}/${name}_A/${cfg_file_vmsettings:?}"

			check vmtree -- "$name"
			check related -- "$name" "${name}/${name}_A"
			check related -- "$name" "${name}/${name}_bis_A"

			progress "${name}/${name}_A"

			# Dot as source, raw $name as target.
			cd -- "${name}/${name}_A" || exit 1
			check test ! -e "./${name}" -a ! -e "${name}_B" \
				-a ! -e "${name}_bis_B"
			check vmfork -qy -- . "$name" "${name}_B" "${name}_bis_B"
			check test -d "./${name}" -a -d "${name}_B" -a -d "${name}_bis_B"

			check vmtree '..'
			check related '..' "../${name}_A"
			check related '..' "../${name}_bis_A"
			check related '..' "$name"
			check related '..' "${name}_B"
			check related '..' "${name}_bis_B"

			progress "${name}/${name}_A/${name}_B"

			# Leading dot and trailing slashes on both source and targets.
			cd -- "${name}_B" || exit 1
			check test ! -e "${name}_C"
			check vmfork -qy -- './' "./${name}_C/"
			check test -d "${name}_C"

			check vmtree '../..'
			check related '../..' "${name}_C"

			progress "${name}/${name}_A/${name}_B/${name}_C"

			# Add `-f' flag to do an explicit fork (should not change anything).
			check test ! -e "${name}_C/${name}_D" \
				-a ! -e "${name}_C/${name}_bis_D"
			check vmfork -fqy -- "${name}_C/" "${name}_C/${name}_D/" \
				"${name}_C/${name}_bis_D/"
			check test -d "${name}_C/${name}_D" -a -d "${name}_C/${name}_bis_D"

			check vmtree '../..'
			check related '../..' "${name}_C/${name}_D"
			check related '../..' "${name}_C/${name}_bis_D"

			progress "${name}/${name}_A/${name}_B/${name}_C/${name}_D"

			# Use `vmcp' instead of `vmfork'.
			check test ! -e "${name}_C/${name}_D/${name}_E"
			check vmcp -fqy -- "${name}_C/${name}_D" \
				"${name}_C/${name}_D/${name}_E"
			check test -d "${name}_C/${name}_D/${name}_E"

			check vmtree '../..'
			check related '../..' "${name}_C/${name}_D/${name}_E"

			progress "${name} (booting VMs)"

			cd '../../..'

			# A VM with childs can only be started in snapshot mode.
			check ! boot -- "${name}"
			check boot -s -- "${name}"
			# It should be sufficient to check both ends of the tree to assume
			# it should be correctly built.
			check boot -- \
				"${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"

 			dirtree -c -- "$name" || exit 1
		done
	}

	# Requires each name in `$list_names' to contain a forked VM tree.
	# A lot of checks rely on `vmfix' results (mostly through `vmtree()', it
	# makes sense to ensure it works correctly as soon as possible.
	title "Detect and solve issues using 'vmfix'."
	{
		for name in $list_names
		do
			progress "${name} (Initial status, recursive)"

			check vmfix -ran -- "$name"
			check ! vmfix -rAn -- "$name"
			check ! vmfix -rA -- "$name"
			check vmfix -rAn -- "$name"

			for path in "$name" "${name}/${name}_A/${name}_B" \
				"${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"
			do
				subpath="${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"
				subpath=${subpath#"$path"}
				subpath=${subpath#/}

				progress "${path} (Initial status, local)"

				check vmfix -n -a -- "$name"

				progress "${path} (remaining backup directory)"

				# Non-recursive
				dir=$( mktemp -d "./${path}/${cfg_file_tmpdir:?}" ) || exit 1
				check test -d "$dir"
				check vmfix_multi -N -b -- "$path"
				check vmfix_multi -n -lps -- "$path"

				check ! vmfix -b -- "$path"
				check test ! -e "$dir"
				check vmfix_multi -n -b -- "$path"

				# Recursive:
				dir=$( mktemp -d "./${path}/${cfg_file_tmpdir:?}" ) || exit 1
				check test -d "$dir"
				check vmfix_multi -Nr -b -- "$name"
				check vmfix_multi -nr -lps -- "$name"

				check ! vmfix -rb -- "$name"
				check test ! -e "$dir"
				check vmfix -rb -- "$name"

				progress "${path} (remaining lock file)"

				# Non-recursive
				ln -s "${cfg_file_vmsettings:?}" "${path}/${cfg_file_lock:?}" \
					|| exit 1
				check test -e "${path}/${cfg_file_lock:?}"
				ts1=$( date '+%s' )
				check ! boot -s -o 'cfg_limit_waitlock=2' -- "$path"
				# Ensure that the `cfg_limit_waitlock' settings has been
				# overwritten.
				ts2=$( date '+%s' )
				check test $(( ts1 + 1 )) -lt "$ts2" \
					-a "$ts2" -lt $(( ts1 + 5 ))
				# Remaining lock files may prevent other checks from working
				# correctly (lock acquire timeout), this is expected.
				check vmfix_multi -N -l -- "$path"

				check ! vmfix -l -- "$path"
				check test ! -e "${path}/${cfg_file_lock:?}"
				check boot -s -o 'cfg_limit_waitlock=2' -- "$path"
				check vmfix_multi -n -l -- "$path"

				# Recursive
				ln -s "${cfg_file_vmsettings:?}" "${path}/${cfg_file_lock:?}" \
					|| exit 1
				check test -e "${path}/${cfg_file_lock:?}"
				ts1=$( date '+%s' )
				check ! boot -s -o 'cfg_limit_waitlock=0' -- "$path"
				ts2=$( date '+%s' )
				check test "$ts2" -lt $(( ts1 + 5 ))
				check test -e "${path}/${cfg_file_lock:?}"
				check vmfix_multi -Nr -l -- "$name"

				check ! vmfix -rl -- "$name"
				check test ! -e "${path}/${cfg_file_lock:?}"
				check boot -s -o 'cfg_limit_waitlock=0' -- "$path"
				check vmfix_multi -nr -l -- "$name"

				progress "${path} (invalid child)"

				# Non-recursive
				printf '/nonexistent\n' >>"${path}/${cfg_file_childs:?}" || exit 1
				check grep -- '/nonexistent' "${path}/${cfg_file_childs:?}"
				check vmfix_multi -N -p -- "$path"
				check vmfix_multi -n -bls -- "$path"

				check ! vmfix -p -- "$path"
				check ! grep -- '/nonexistent' "${path}/${cfg_file_childs:?}"
				# Also ensure that vmfix didn't screwed the VM tree up.
				check related -- "$name" \
					"${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"
				check vmfix_multi -n -p -- "$path"

				# Recursive
				printf '/nonexistent\n' >>"${path}/${cfg_file_childs:?}" || exit 1
				check grep -- '/nonexistent' "${path}/${cfg_file_childs:?}"
				check vmfix_multi -Nr -p -- "$name"
				check vmfix_multi -nr -bls -- "$name"

				check ! vmfix -pr -- "$name"
				check ! grep -- '/nonexistent' "${path}/${cfg_file_childs:?}"
				# Also ensure that vmfix didn't screwed the VM tree up.
				check related -- "$name" \
					"${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"
				check vmfix_multi -nr -p -- "$name"

				progress "${path} (remaining working files)"

				# Non-recursive
				if [ ! -e "./${path}/${cfg_file_monitor:?}" ]
				then
					touch "./${path}/${cfg_file_monitor:?}" || exit 1
				fi
				if [ ! -e "./${path}/${cfg_file_pid:?}" ]
				then
					touch "./${path}/${cfg_file_pid:?}" || exit 1
				fi
				check test -e "./${path}/${cfg_file_monitor:?}" \
					-a -e "./${path}/${cfg_file_pid:?}"
				check ! vmfix -nd -- "$path"

				check ! vmfix -d -- "$path"
				check test ! -e "./${path}/${cfg_file_monitor:?}" \
					-a ! -e "./${path}/${cfg_file_pid:?}"
				check vmfix -nd -- "$path"

				# Recursive:
				touch "./${path}/${cfg_file_monitor:?}" \
					"./${path}/${cfg_file_pid:?}" || exit 1
				check test -e "./${path}/${cfg_file_monitor:?}" \
					-a -e "./${path}/${cfg_file_pid:?}"
				check ! vmfix -rnd -- "$name"

				check ! vmfix -rd -- "$name"
				check test ! -e "./${path}/${cfg_file_monitor:?}" \
					-a ! -e "./${path}/${cfg_file_pid:?}"
				check vmfix -rnd -- "$name"

				progress "${path} (renamed directory)"

				mv -- "$path" "${path}_renamed"
				check test ! -e "./${path}" -a -d "${path}_renamed/${subpath}"
				check vmfix_multi -N -ps -- "${path}_renamed"
				check vmfix_multi -n -bl -- "${path}_renamed"
				check ! boot -- "${path}_renamed/${subpath}"

				if [ "$path" = "$name" ]
				then
					check ! vmfix -rps -- "${name}_renamed"
				else
					check ! vmfix -rps -- "$name"
				fi
				check vmfix_multi -n -ps -- "${path}_renamed"
				check boot -- "${path}_renamed/${subpath}"

				progress "${path} (mixed issues)"

				if [ "$path" = "$name" ]
				then
					name="${name}_renamed"
				fi
				path="${path}_renamed"

				# Non-recursive:
				# - Remaining backup directory.
				dir=$( mktemp -d "./${path}/${cfg_file_tmpdir:?}" ) || exit 1
				check test -d "$dir"
				# - Remaining lock file.
				ln -s "${cfg_file_vmsettings:?}" "${path}/${cfg_file_lock:?}" \
					|| exit 1
				check test -e "${path}/${cfg_file_lock:?}"
				check ! boot -s -o 'cfg_limit_waitlock=0' -- "$path"
				# - Non-existent child.
				printf '/nonexistent\n' >>"${path}/${cfg_file_childs:?}" || exit 1
				check grep -- '/nonexistent' "${path}/${cfg_file_childs:?}"

				check ! vmfix -an -- "$path"

				check ! vmfix -a -- "$path"
				check test ! -e "$dir"
				check test ! -e "${path}/${cfg_file_lock:?}"
				check boot -s -o 'cfg_limit_waitlock=0' -- "$path"
				check ! grep -- '/nonexistent' "${path}/${cfg_file_childs:?}"
				check related -- "$name" "${path}/${subpath}"
				check vmfix -an -- "$path"

				# Recursive:
				# - Renamed directory (restoring initial name).
				if [ "$path" = "$name" ]
				then
					name="${name%"_renamed"}"
				fi
				path="${path%"_renamed"}"
				mv -- "${path}_renamed" "$path"
				check test ! -e "${path}_renamed" -a -d "${path}/${subpath}"
				check ! boot -- "${path}/${subpath}"
				# - Remaining backup directory.
				dir=$( mktemp -d "./${path}/${cfg_file_tmpdir:?}" ) || exit 1
				check test -d "$dir"
				# - Remaining lock file.
				ln -s "${cfg_file_vmsettings:?}" "${path}/${cfg_file_lock:?}" \
					|| exit 1
				check test -e "${path}/${cfg_file_lock:?}"
				check ! boot -s -o 'cfg_limit_waitlock=0' -- "$path"
				# - Non-existent child.
				printf '/nonexistent\n' >>"${path}/${cfg_file_childs:?}" \
					|| exit 1
				check grep -- '/nonexistent' "${path}/${cfg_file_childs:?}"

				check ! vmfix -ran -- "$name"

				check ! vmfix -ra -- "$name"
				check boot -- "${path}/${subpath}"
				check test ! -e "$dir"
				check test ! -e "${path}/${cfg_file_lock:?}"
				check boot -s -o 'cfg_limit_waitlock=0' -- "$path"
				check ! grep -- '/nonexistent' "${path}/${cfg_file_childs:?}"
				check related -- "$name" "${path}/${subpath}"
				check vmfix -ran -- "$name"
			done

			check dirtree -- "$name"
		done
	}

	# Requires each name in `$list_names' to contain a forked VM tree.
	title "VM default copy and removal."
	{
		for name in $list_names
		do
			# Tree top-level, middle and leaf
			for path in "$name" "${name}/${name}_A/${name}_B" \
				"${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"
			do
				progress "$path"

				check test -d "./$path" -a ! -e "${name}_tmp"
				check vmcp -qy -- "$path" "${name}_tmp"
				check test -d "./$path" -a -d "${name}_tmp"
				check nosubdir -- "${name}_tmp"

				if [ "$path" = "$name" ]
				then
					# Tree top-level
					check vmtree -- "${name}_tmp"
					check ! related -- "$name" "${name}_tmp"
				else
					# Tree middle and leaf
					check vmtree -p "${path%/*}" -- "${name}_tmp"
					check related -- "$name" "${name}_tmp"
				fi

				# Rename to reveal any hidden dependency (mainly around storage
				# location or backing file).
				mv -- "$path" "${path}_renamed" || exit 1
				check boot -- "${name}_tmp"
				mv -- "${path}_renamed" "$path" || exit 1
				mv -- "${name}_tmp" "${name}_tmp_renamed" || exit 1
				check boot -s -- "$path"
				mv -- "${name}_tmp_renamed" "${name}_tmp" || exit 1
				check vmrm -qy -- "${name}_tmp"
				check test ! -e "${name}_tmp"
				check ! related -- "$name" "${name}_tmp"
			done

			check dirtree -- "$name"
		done
	}

	# Requires each name in `$list_names' to contain a forked VM tree.
	# Stores a recursive copy of the top, middle and leaf below
	# `${name}/${name}_bis_A' (original names kept).
	title "VM child-recursive copy and removal."
	{
		for name in $list_names
		do
			# Tree top-level, middle and leaf
			for path in "$name" "${name}/${name}_A/${name}_B" \
				"${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"
			do
				subpath="${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"
				subpath=${subpath#"$path"}
				subpath=${subpath#/}

				progress "${path} (copy from source to a new directory)"

				check test -d "${path}/${subpath}" -a ! -e "${name}_tmp"
				dirtree -c -f 'tmp.tree' -- "$path" || exit 1

				check vmcp -qRy -- "$path" "${name}_tmp"
				# After the `vmcp' command, both the source and destination
				# exists (as opposed to `vmmv').
				check test -d "${path}/${subpath}" -a -d "${name}_tmp/${subpath}"
				check dirtree -f 'tmp.tree' -- "${name}_tmp"

				if [ "$path" = "$name" ]
				then
					# Tree top-level
					check vmtree -- "${name}_tmp"
					check ! related -- "$name" "${name}_tmp"
				else
					# Tree middle and leaf
					check vmtree -p "${path%/*}" -- "${name}_tmp"
					check related -- "$name" "${name}_tmp"
				fi
				mv -- "$path" "${path}_renamed" || exit 1
				check boot -- "${name}_tmp/${subpath}"
				mv -- "${path}_renamed" "$path" || exit 1
				mv -- "${name}_tmp" "${name}_tmp_renamed" || exit 1
				check boot -- "${path}/${subpath}"
				mv -- "${name}_tmp_renamed" "${name}_tmp" || exit 1

				progress "${path} (copy back to the source)"

				check vmrm -qry -- "$path"
				check test ! -e "./${path}"
				check vmcp -qRy -- "${name}_tmp" "$path"
				check test -d "$path/${subpath}" -a -d "${name}_tmp/${subpath}"
				check dirtree -f 'tmp.tree' -- "$path"

				if [ "$path" = "$name" ]
				then
					# Tree top-level
					check vmtree -- "$path"
					check ! related -- "${name}_tmp" "$path"
				else
					# Tree middle and leaf
					check vmtree -p "${path%/*}" -- "$path"
					check related -- "${name}_tmp" "$path"
				fi
				mv -- "${name}_tmp" "${name}_tmp_renamed" || exit 1
				check boot -- "${path}/${subpath}"
				mv -- "${name}_tmp_renamed" "${name}_tmp" || exit 1
				mv -- "$path" "${path}_renamed" || exit 1
				check boot -- "${name}_tmp/${subpath}"
				mv -- "${path}_renamed" "$path" || exit 1

				check vmrm -qry -- "${name}_tmp"
				check test ! -e "${name}_tmp"

				progress "${path} (copy to an already existing directory)"

				check test ! -e "${name}/${name}_bis_A/${path##*/}"
				check vmcp -qRy -- "$path" "${name}/${name}_bis_A"
				check test -d "${name}/${name}_bis_A/${path##*/}/${subpath}"
				check dirtree -f 'tmp.tree' -- \
					"${name}/${name}_bis_A/${path##*/}"

				if [ "$path" = "$name" ]
				then
					# Tree top-level
					check vmtree -- "${name}/${name}_bis_A/${path##*/}"
					check ! related -- "$name" \
						"${name}/${name}_bis_A/${path##*/}"
				else
					# Tree middle and leaf
					check vmtree -p "${path%/*}" -- \
						"${name}/${name}_bis_A/${path##*/}"
					check related -- "$name" "${name}/${name}_bis_A/${path##*/}"
				fi
				check boot -- "${name}/${name}_bis_A/${path##*/}/${subpath}"
				check boot -- "${path}/${subpath}"

				rm 'tmp.tree' || exit 1
			done

			progress "${name} (subdirectories handling)"

			# Non-related sub-directories are not copied (as opposed to
			# directory-recursive copy).
			check test ! -e "${name}_tmp"
			check ! nosubdir -- "${name}/${name}_bis_A"
			check vmcp -qRy -- "${name}/${name}_bis_A" "${name}_tmp"
			check test -d "${name}_tmp"
			check nosubdir -- "${name}_tmp"
			check vmrm -qry -- "${name}_tmp"
			check test ! -e "${name}_tmp"

			# Outer childs are copied as new subdirectories.
			# The VMs `${name}_B' and `${name}_E' located below `${name}_bis_A'
			# are respectively the childs of `${name}_A' and `${name}_D' and
			# as such will be moved below their parents in the resulting
			# copied tree.
			# However there are already VMs bearing these names below the
			# parents, new names will be automatically (`-y') used:
			# `${name}_B_1' and `${name}_E_1'.
			check test -d "${name}/${name}_bis_A/${name}_B" \
				-a -d "${name}/${name}_bis_A/${name}_E"
			check test ! -e "${name}/${name}_A/${name}_B_1" -a ! -e \
				"${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E_1"
			check vmcp -qRy -- "$name" "${name}_tmp"
			check test ! -e "${name}_tmp/${name}_bis_A/${name}_B" \
				-a ! -e "${name}_tmp/${name}_bis_A/${name}_E"
			check test -d "${name}_tmp/${name}_A/${name}_B_1" -a -d \
				"${name}_tmp/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E_1"

			check vmtree -- "${name}_tmp"
			check vmrm -qry -- "${name}_tmp"
			check test ! -e "${name}_tmp"

			# Update the tree listing with the new directories below
			# `${name}/${name}_bis_A'.
			rm -- "${name}.tree" || exit 1
			dirtree -c -- "$name" || exit 1
		done
	}

	# Requires each name in `$list_names' to contain a forked VM tree.
	title "VM directory-recursive copy and removal."
	{
		for name in $list_names
		do
			# Tree top-level and leaf
			# Removed middle ("${name}/${name}_A/${name}_B") as the `vmrm -r'
			# also delete the second VM `${name}_E' located below
			# `${name}_bis_A
			for path in "$name" \
				"${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"
			do
				subpath="${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"
				subpath=${subpath#"$path"}
				subpath=${subpath#/}

				progress "${path} (copy from source to a new directory)"

				check test -d "${path}/${subpath}" -a ! -e "${name}_tmp"
				dirtree -c -f 'tmp.tree' -- "$path" || exit 1

				check vmcp -qry -- "$path" "${name}_tmp"
				# After the `vmcp' command, both the source and destination
				# exists (as opposed to `vmmv').
				check test -d "$path/${subpath}" -a -d "${name}_tmp/${subpath}"
				check dirtree -f 'tmp.tree' -- "${name}_tmp"

				if [ "$path" = "$name" ]
				then
					# Tree top-level
					# Contrary to child-recursive VM copying, directory-based
					# recursion also copy unrelated VM stored in subfolders.
					check vmtree -l 1 -- "${name}_tmp"
					check vmtree -p "${name}_tmp" -- "${name}_tmp/${name}_A"
					check vmtree -- "${name}_tmp/${name}_bis_A/${name}"
					check vmtree -p "${name}_tmp/${name}_A" -- \
						"${name}_tmp/${name}_bis_A/${name}_B"
					check vmtree -p \
						"${name}_tmp/${name}_A/${name}_B/${name}_C/${name}_D" \
						-- "${name}_tmp/${name}_bis_A/${name}_E"
					check ! related -- "$name" "${name}_tmp"

					# Boot `_tmp/_bis_A/_B/_C/_D/_E'
					mv -- "$path" "${path}_renamed" || exit 1
					check boot -- "${name}_tmp/${name}_bis_A/${subpath#*/}"
					mv -- "${path}_renamed" "$path" || exit 1
					mv -- "${name}_tmp" "${name}_tmp_renamed" || exit 1
					check boot -- "${path}/${subpath}"
					mv -- "${name}_tmp_renamed" "${name}_tmp" || exit 1
				else
					# Tree middle and leaf
					check vmtree -p "${path%/*}" -- "${name}_tmp"
					check related -- "$name" "${name}_tmp"

					if [ "$path" =  "${name}/${name}_A/${name}_B" ]
					then
						# Contrary to child-recursive VM copying,
						# directory-based recursion ignores outer VMs.
						check ! test -e "${name}_tmp/${name}_B_1"
					fi
				fi
				mv -- "$path" "${path}_renamed" || exit 1
				check boot -- "${name}_tmp/${subpath}"
				mv -- "${path}_renamed" "$path" || exit 1
				mv -- "${name}_tmp" "${name}_tmp_renamed" || exit 1
				check boot -- "${path}/${subpath}"
				mv -- "${name}_tmp_renamed" "${name}_tmp" || exit 1

				progress "${path} (copy back to the source)"

				check vmrm -qry -- "$path"
				check test ! -e "./${path}"
				check vmcp -qry -- "${name}_tmp" "$path"
				check test -d "$path/${subpath}" -a -d "${name}_tmp/${subpath}"
				check dirtree -f 'tmp.tree' -- "$path"

				if [ "$path" = "$name" ]
				then
					# Tree top-level
					check vmtree -l 1 -- "${name}"
					check vmtree -p "${name}" -- "${name}/${name}_A"
					check vmtree -- "${name}/${name}_bis_A/${name}"
					check vmtree -p "${name}/${name}_A" -- \
						"${name}/${name}_bis_A/${name}_B"
					check vmtree -p \
						"${name}/${name}_A/${name}_B/${name}_C/${name}_D" \
						-- "${name}/${name}_bis_A/${name}_E"
					check ! related -- "$name" "${name}_tmp"
				else
					# Tree middle and leaf
					check vmtree -p "${path%/*}" -- "$path"
					check related -- "$name" "$path"
				fi
				mv -- "${name}_tmp" "${name}_tmp_renamed" || exit 1
				check boot -- "${path}/${subpath}"
				mv -- "${name}_tmp_renamed" "${name}_tmp" || exit 1
				mv -- "$path" "${path}_renamed" || exit 1
				check boot -- "${name}_tmp/${subpath}"
				mv -- "${path}_renamed" "$path" || exit 1

				check vmrm -qry -- "${name}_tmp"
				check test ! -e "${name}_tmp"
				rm 'tmp.tree' || exit 1
			done

			check dirtree -- "$name"
		done
	}

	# Requires each name in `$list_names' to contain a forked VM tree.
	title "VM autonomous copy and removal."
	{
		for name in $list_names
		do
			# Tree top-level, middle and leaf
			for path in "$name" "${name}/${name}_A/${name}_B" \
				"${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"
			do
				progress "$path"

				check test -d "./$path" -a ! -e "${name}_tmp"
				check vmcp -qay -- "$path" "${name}_tmp"
				check test -d "./$path" -a -d "${name}_tmp"
				check nosubdir -- "${name}_tmp"

				check vmtree -- "${name}_tmp"
				check ! related -- "${name}" "${name}_tmp"
				mv -- "$path" "${path}_renamed" || exit 1
				check boot -- "${name}_tmp"
				mv -- "${path}_renamed" "$path" || exit 1
				mv -- "${name}_tmp" "${name}_tmp_renamed" || exit 1
				check boot -s -- "$path"
				mv -- "${name}_tmp_renamed" "${name}_tmp" || exit 1
				check vmrm -qy -- "${name}_tmp"
				check test ! -e "${name}_tmp"
			done

			check dirtree -- "$name"
		done
	}

	# Requires each name in `$list_names' to contain a forked VM tree.
	# Requires copy below `${name}/${name}_bis_A' to be created.
	title "VM move and rename."
	{
		for name in $list_names
		do
			# Tree top-level, middle and leaf
			for path in "$name" "${name}/${name}_A/${name}_B" \
				"${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"
			do
				subpath="${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E"
				subpath=${subpath#"$path"}
				subpath=${subpath#/}

				progress "${path} (the target is an already existing directory)"

				mkdir -- "${name}_tmp" || exit 1
				dirtree -c -f 'tmp.tree' -- "$path" || exit 1

				# Move from the original location to the temporary directory:

				check test -d "${path}/${subpath}" -a ! -e "${name}_tmp/${name}"
				check vmmv -- "$path" "${name}_tmp"
				# After the `vmmv' command, only the target exists (as opposed
				# to `vmcp').
				check test ! -e "./${path}" \
					-a -d "${name}_tmp/${path##*/}/${subpath}"
				check dirtree -f 'tmp.tree' -- "${name}_tmp/${path##*/}"

				if [ "$path" = "$name" ]
				then
					# Tree top-level
					check vmtree -l 1 -- "${name}_tmp/${name}"
					check vmtree -p "${name}_tmp/${name}" -- \
						"${name}_tmp/${name}/${name}_A"
					check vmtree -- "${name}_tmp/${name}/${name}_bis_A/${name}"
					check vmtree -p "${name}_tmp/${name}/${name}_A" -- \
						"${name}_tmp/${name}/${name}_bis_A/${name}_B"
					check vmtree -p \
							"${name}_tmp/${name}/${name}_A/${name}_B/${name}_C/${name}_D" \
							-- "${name}_tmp/${name}/${name}_bis_A/${name}_E"
					check ! related -- "$name" "${name}_tmp/${name}"
				else
					# Tree middle and leaf
					check vmtree -p "${path%/*}" -- "${name}_tmp/${path##*/}"
					check related -- "$name" "${name}_tmp/${path##*/}"

					# Check the source VM tree integrity
					check vmtree -l 1 -- "$name"
					check vmtree -p "$name" -- "${name}/${name}_A"
					check vmtree -- "${name}/${name}_bis_A/${name}"
					check vmtree -p "${name}/${name}_A" -- \
						"${name}/${name}_bis_A/${name}_B"
					if [ "$path" = "${name}/${name}_A/${name}_B" ]
					then
						check vmtree -p \
							"${name}_tmp/${name}_B/${name}_C/${name}_D" \
							-- "${name}/${name}_bis_A/${name}_E"
					else
						check vmtree -p \
							"${name}/${name}_A/${name}_B/${name}_C/${name}_D" \
							-- "${name}/${name}_bis_A/${name}_E"
					fi
				fi
				check boot -- "${name}_tmp/${path##*/}/${subpath}"

				# Move back to the original location:

				# Use `dirname' as the tree root parent must be translated as
				# `.' (no parent directory in the path).
				check vmmv -- "${name}_tmp/${path##*/}" \
					"$( dirname -- "$path" )"
				check test -d "${path}/${subpath}" \
					-a ! -e "${name}_tmp/${path##*/}"
				check dirtree -- "$name"
				check vmtree -l 1 -- "$name"
				check vmtree -p "$name" -- "${name}/${name}_A"
				check vmtree -- "${name}/${name}_bis_A/${name}"
				check vmtree -p "${name}/${name}_A" -- \
					"${name}/${name}_bis_A/${name}_B"
				check vmtree -p \
						"${name}/${name}_A/${name}_B/${name}_C/${name}_D" \
						-- "${name}/${name}_bis_A/${name}_E"
				check ! related -- "$name" "${name}_tmp/${path##*/}"
				check rmdir -- "${name}_tmp"
				check boot -- "${path}/${subpath}"

				progress "${path} (the target is a new name)"

				# Rename from the original name to a temporary one

				check test -d "${path}/${subpath}" -a ! -e "${path}_tmp"
				check vmmv -- "$path" "${path}_tmp"
				check test ! -e "./${path}" -a -d "${path}_tmp/${subpath}"
				check dirtree -f 'tmp.tree' -- "${path}_tmp"

				if [ "$path" = "$name" ]
				then
					# Tree top-level
					check vmtree -l 1 -- "${name}_tmp"
					check vmtree -p "${name}_tmp" -- "${name}_tmp/${name}_A"
					check vmtree -- "${name}_tmp/${name}_bis_A/${name}"
					check vmtree -p "${name}_tmp/${name}_A" -- \
						"${name}_tmp/${name}_bis_A/${name}_B"
					check vmtree -p \
							"${name}_tmp/${name}_A/${name}_B/${name}_C/${name}_D" \
							-- "${name}_tmp/${name}_bis_A/${name}_E"
					check ! related -- "$name" "${path}_tmp"
				else
					# Tree middle and leaf
					check vmtree -p "${path%/*}" -- "${path}_tmp"
					check related -- "$name" "${path}_tmp"

					# Check the source VM tree integrity
					check vmtree -l 1 -- "$name"
					check vmtree -p "$name" -- "${name}/${name}_A"
					check vmtree -- "${name}/${name}_bis_A/${name}"
					check vmtree -p "${name}/${name}_A" -- \
						"${name}/${name}_bis_A/${name}_B"
					if [ "$path" = "${name}/${name}_A/${name}_B" ]
					then
						check vmtree -p \
							"${path}_tmp/${name}_C/${name}_D" \
							-- "${name}/${name}_bis_A/${name}_E"
					else
						check vmtree -p \
							"${name}/${name}_A/${name}_B/${name}_C/${name}_D" \
							-- "${name}/${name}_bis_A/${name}_E"
					fi
				fi
				check boot -- "${path}_tmp/${subpath}"

				# Rename back to the original name

				# Use `dirname' as the tree root parent must be translated as
				# `.' (no parent directory in the path).
				check vmmv -- "${path}_tmp" "$path"
				check test -d "${path}/${subpath}" -a ! -e "${path}_tmp"
				check dirtree -- "$name"
				check vmtree -l 1 -- "$name"
				check vmtree -p "$name" -- "${name}/${name}_A"
				check vmtree -- "${name}/${name}_bis_A/${name}"
				check vmtree -p "${name}/${name}_A" -- \
					"${name}/${name}_bis_A/${name}_B"
				check vmtree -p \
					"${name}/${name}_A/${name}_B/${name}_C/${name}_D" \
					-- "${name}/${name}_bis_A/${name}_E"
				check ! related -- "$name" "${path}_tmp"
				check boot -- "${path}/${subpath}"

				rm 'tmp.tree' || exit 1
			done
		done
	}

	# Requires each name in `$list_names' to contain a forked VM tree.
	# Generates merged tree below each VM home dir.
	# Merge relies on `vmmv_move()' and `homedir_delete()' which are
	# respectively the core of the `vmmv' and `vmrm' commands, so it makes more
	# sense to test it after having tested these other commands commands.
	#
	# TODO: Inspect the content of the merged storages, in particular do the
	# following test:
	# 1. For a VM.
	# 2. Add a file in the forked VM storage.
	# 3. Fork the new VM.
	# 4. Merge the first fork.
	# 5. Check that the file is still here. If the file is missing, this means
	#    that the merge process simply rebased the storage file without really
	#     merging its content. This cannot be checked by simply booting the VM
	#     as the VM still works fine (and imppleting this should actually be
	#     easier than testing if the OS boots correctly).
	title "Virtual machines merging."
	{
		for name in $list_names
		do
			progress "${name} (parent merge)"

			# Main tree structure:
			#    ${name}                    ${name}
			#    ├─ ${name}_A               ${name}/${name}_A
			#    │  ├─ ${name}              ${name}/${name}_A/${name}
			#    │  ├─ ${name}_B            ${name}/${name}_A/${name}_B
			#    │  │  └─ ${name}_C         ${name}/${name}_A/${name}_B/${name}_C
			#    │  │     ├─ ${name}_D      ${name}/${name}_A/${name}_B/${name}_C/${name}_D
			#    │  │     │  ├─ ${name}_E   ${name}/${name}_A/${name}_B/${name}_C/${name}_D/${name}_E
			#    │  │     │  └─ ${name}_E   ${name}/${name}_bis_A/${name}_E
			#    │  │     └─ ${name}_bis_D  ${name}/${name}_A/${name}_B/${name}_C/${name}_bis_D
			#    │  ├─ ${name}_bis_B        ${name}/${name}_A/${name}_bis_B
			#    │  └─ ${name}_B            ${name}/${name}_bis_A/${name}_B
			#    │     └─ ${name}_C         ${name}/${name}_bis_A/${name}_B/${name}_C
			#    │        ├─ ${name}_D      ${name}/${name}_bis_A/${name}_B/${name}_C/${name}_D
			#    │        │  └─ ${name}_E   ${name}/${name}_bis_A/${name}_B/${name}_C/${name}_D/${name}_E
			#    │        └─ ${name}_bis_D  ${name}/${name}_bis_A/${name}_B/${name}_C/${name}_bis_D
			#    └─ ${name}_bis_A           ${name}/${name}_bis_A

			# Parent merge on 'D' should fail as it has a sibling brother.
			check test -d "${name}/${name}_A/${name}_B/${name}_C/${name}_D" \
				-a -d "${name}/${name}_A/${name}_B/${name}_C/${name}_bis_D"
			check ! vmmerge -y -- "${name}/${name}_A/${name}_B/${name}_C/${name}_D"
			# Deleting it shall allow the merge to proceed.
			check vmrm -y -- "${name}/${name}_A/${name}_B/${name}_C/${name}_bis_D"
			check test -d "${name}/${name}_A/${name}_B/${name}_C/${name}_D" \
				-a ! -e "${name}/${name}_A/${name}_B/${name}_C/${name}_bis_D"

			# Parent merge on `D'.
			check test -d "${name}/${name}_A/${name}_B/${name}_C" \
				-a ! -e "${name}/${name}_A/${name}_B/${name}_D"
			# The same merge command as above should now work.
			check vmmerge -y -- "${name}/${name}_A/${name}_B/${name}_C/${name}_D"
			check test -d "${name}/${name}_A/${name}_B/${name}_C" \
				-a ! -e "${name}/${name}_A/${name}_B/${name}_C/${name}_D" \
				-a ! -e "${name}/${name}_A/${name}_B/${name}_D"

			check vmtree -l 1 -- "$name"
			check vmtree -p "$name" -- "${name}/${name}_A"
			check vmtree -- "${name}/${name}_bis_A/${name}"
			check vmtree -p "${name}/${name}_A" -- \
				"${name}/${name}_bis_A/${name}_B"
			check vmtree -p "${name}/${name}_A/${name}_B/${name}_C" -- \
				"${name}/${name}_bis_A/${name}_E"

			progress "${name} (parent merge to root)"

			# Need to delete "${name}/${name}_bis_A" first
			check vmmv -y -- "${name}/${name}_bis_A/${name}" \
				"${name}/${name}_bis_A/${name}_B" \
				"${name}/${name}_bis_A/${name}_E" \
				"${name}"
			check vmrm -y -- "${name}/${name}_bis_A"

			check test ! -e "${name}/${name}_bis_A"
			check vmtree -l 0 -- "$name"
			check vmtree -- "${name}/${name}"
			check vmtree -p "$name" -- "${name}/${name}"
			check vmtree -p "$name" -- "${name}/${name}_A"
			check vmtree -p "${name}/${name}_A/${name}_B/${name}_C" \
				-- "${name}/${name}_E"

			check test -d "${name}/${name}_A/${name}" \
				-a -d "${name}/${name}_A/${name}_B" \
				-a -d "${name}/${name}_A/${name}_bis_B" \
				-a -d "${name}/${name}" \
				-a -d "${name}/${name}_B" \
				-a ! -e "${name}/${name}_1" \
				-a ! -e "${name}/${name}_B_1" \
				-a ! -e "${name}/${name}_bis_B"
			check vmmerge -y -- "${name}/${name}_A"
			# "${name}/${name}_A/${name}" will be moved to "${name}/${name}_1"
			check test ! -e "${name}/${name}_A" \
				-a -d "${name}/${name}_1" \
				-a -d "${name}/${name}_B_1" \
				-a -d "${name}/${name}_bis_B"

			check test ! -e "${name}/${name}_A"
			check vmtree -l 0 -- "$name"
			check vmtree -- "${name}/${name}"
			check vmtree -p "$name" -- "${name}/${name}_1"
			check vmtree -p "${name}" -- "${name}/${name}_B_1"
			check vmtree -p "${name}" -- "${name}/${name}_bis_B"
			check vmtree -p "${name}/${name}_B_1/${name}_C" -- "${name}/${name}_E"

			check boot -s -- "${name}/${name}_B_1/${name}_C"
			check boot -- "${name}/${name}_B_1/${name}_C/${name}_E"

			progress "${name} (child merge)"

			# The tree below "${name}/${name}" (previously
			# "${name}/${name}_bis_A/${name}" before the deletion of
			# "${name}_bis_A") is an independant copy:
			#     ${name}
			#     ├─ ${name}_A
			#     │  ├─ ${name}
			#     │  ├─ ${name}_B
			#     │  │  └─ ${name}_C
			#     │  │     ├─ ${name}_D
			#     │  │     │  └─ ${name}_E
			#     │  │     └─ ${name}_bis_D
			#     │  └─ ${name}_bis_B
			#     └─ ${name}_bis_A
			#
			# It will be used to test child merges.

			# Child merge on "${name}" makes "${name}_A" and "${name}_bis_A"
			# become indepedant roots.
			check test -d "${name}/${name}/${name}_A" \
				-a -d "${name}/${name}/${name}_bis_A" \
				-a ! -e "${name}/${name}_A" \
				-a ! -e "${name}/${name}_bis_A"
			check vmmerge -cy -- "${name}/${name}"
			check test ! -e "${name}/${name}" \
				-a -d "${name}/${name}_A" \
				-a -d "${name}/${name}_bis_A"

			check vmtree -- "${name}/${name}_A"
			check vmtree -- "${name}/${name}_bis_A"

			# "${name}_A/${name}_B" has one child, a child merge uses fast
			# merge by default.
			check test -d "${name}/${name}_A/${name}_B/${name}_C" \
				-a ! -e "${name}/${name}_A/${name}_C"
			check vmmerge -cy -- "${name}/${name}_A/${name}_B"
			check test ! -e "${name}/${name}_A/${name}_B" \
				-a -d "${name}/${name}_A/${name}_C"

			check vmtree -- "${name}/${name}_A"

			# "${name}_A/${name}_C" has two child, a child merge uses safe
			# merge by default.
			check test -d "${name}/${name}_A/${name}_C/${name}_D" \
				-a -d "${name}/${name}_A/${name}_C/${name}_bis_D" \
				-a ! -e "${name}/${name}_A/${name}_D" \
				-a ! -e "${name}/${name}_A/${name}_bis_D"
			check vmmerge -cy -- "${name}/${name}_A/${name}_C"
			check test ! -e "${name}/${name}_A/${name}_C" \
				-a -d "${name}/${name}_A/${name}_D" \
				-a -d "${name}/${name}_A/${name}_bis_D"

			check vmtree -- "${name}/${name}_A"

			# Child merge to the leaf VM "${name}_A/${name}_D".
			check test -d "${name}/${name}_A/${name}_D/${name}_E" \
				-a ! -e "${name}/${name}_A/${name}_E"
			check vmmerge -cy -- "${name}/${name}_A/${name}_D"
			check test ! -e "${name}/${name}_A/${name}_D" \
				-a -d "${name}/${name}_A/${name}_E"

			check vmtree -- "${name}/${name}_A"

			check boot -s -- "${name}/${name}_A"
			check boot -- "${name}/${name}_A/${name}_E"
		done

		# Update the tree listing with the newly merged directories.
		rm -- "${name}.tree" || exit 1
		dirtree -c -- "$name" || exit 1
	}
}

###
# dirtree [-c] [-f tree_file] path
#
# Options:
# -c: Create a new `.tree' file.
# -f: `.tree' file name.
#
dirtree() {
	local 'create' 'file' 'opt' 'opt_list' 'OPTARG' 'OPTIND' 'path' 'tree'
	create='no'

	OPTIND=1
	while getopts 'cf:' opt
	do
		case "$opt" in
			'c') create='yes' ;;
			'f') file=$OPTARG ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	path=${1:?"ERROR (SELFTEST BUG): dirtree: Missing parameter."}
	file=${file:-"${path}.tree"}

	tree=$( find "./${path}" -mindepth 1 \
		! \( -name "${cfg_file_pid:?}" -o -name "${cfg_file_monitor:?}" \) ) \
		|| return 1
	tree=$( printf '%s' "$tree" | cut -c "$(( ${#path} + 4 ))-" \
		| LC_ALL=C sort )

	if [ -e "./${file}" ]
	then
		if [ "$create" = 'yes' ]
		then
			printf "ERROR (SELFTEST BUG): dirtree: %s: %s\\n" "$file" \
				"The file already exists." >&2
			return 1
		fi
		check test -d "./$path"
		printf '%s' "$tree" | check diff -- "./$file" - || return 1
	else
		if [ "$create" != 'yes' ]
		then
			printf "ERROR: '%s' doesn't exist yet, creating it now.\\n" \
				"$file" >&2
			return 1
		fi
		printf '%s' "$tree" >"./${file}" || return 1
	fi
}

###
# escape string...
#
escape() {
	local 'filter' 'ret' 'str'
	filter="s/'/'\\\\''/g"

	if [ "${1-}" = '!' ]
	then
		ret='!'
		shift
	else
		ret=''
	fi

	for str
	do
		case "$str" in
			*[![:alnum:]._/-]*)
				case "$str" in *\'*)
					str=$( printf '%s' "$str" | sed "$filter" )
				esac
				str="'${str}'"
				;;
			'')
				str="''"
				;;
		esac
		ret="${ret:+"$ret "}${str}"
	done

	printf '%s' "$ret"
}

###
# escape_grep string...
#
escape_grep() {
	local 'chars' 'filter' 'ret' 'str'
	# Escaping non-special characters leads to undefined behavior.
	# List of BRE special characters:
	# http://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap09.html#tag_09_03
	# '^'and '$' are handled separately, see below.
	chars='\\.*['
	filter='s#['"${chars}"']#\\&#g'
	ret=''

	for str
	do
		case "$str" in *[${chars}^\$]*)
			# Only escape '^' and '$' when they are respectively the first and
			# last characters.
			str=$( printf '%s' "$str" | sed -e "$filter" \
				-e 's/^^/\\^/' -e 's/$$/\\$/' )
			;;
		esac
		ret="${ret:+"$ret "}${str}"
	done

	printf '%s' "$ret"
}

###
# progress message
#
progress() {
	local 'message'
	message=${1:?"ERROR (SELFTEST BUG): _progress: Missing parameter."}

	printf '\33[G\33[KProcessing: %s... ' "$message" >&2

	printf '\n\n%s##### Processing: %s #####\n' "$check_indent" "$message" >&3
}

###
# related VM1 VM2
#
# Returns 1 if one of the VM exists but does not list the other one.
# The fact that one of VM does not exist anymore is not considered an error in
# order to properly check that the other one does not still references it.
#
related() {
	local 'rc' 'vm1' 'vm2'
	[ "${1-}" = '--' ] && shift
	vm1=${1:?"ERROR (SELFTEST BUG): related: Missing parameter."}
	vm2=${2:?"ERROR (SELFTEST BUG): related: Missing parameter."}
	rc=0

	# Check the link in both direction: can we find the child from the parent
	# and the other way around.

	if [ -e "$vm1" ]
	then
		check vminfo -alt -- "$vm1"
		vminfo -alt -- "$vm1" | check grep -- " $( escape_grep \
			"$( realpath -- "$vm2" )" )\$" || rc=1
	else
		printf "%s: This VM does not exists.\n" "$vm1"
	fi

	if [ -e "$vm2" ]
	then
		check vminfo -alt -- "$vm2"
		vminfo -alt -- "$vm2" | check grep -- " $( escape_grep \
			"$( realpath -- "$vm1" )" )\$" || rc=1
	else
		printf "%s: This VM does not exists.\n" "$vm2"
	fi

	return "$rc"
}

###
# title message
#
title() {
	title_label=${1:?"ERROR (SELFTEST BUG): title: Missing parameter."}

	title_count=$(( title_count + 1 ))
	title_label="Step ${title_count}/${title_total}: ${title_label}"

	# Terminal output.
	printf '\33[G\33[K* %s\n' "$title_label" >&2

	# Log file output.
	printf '\n\n' >&3
	printf '############################################################\n' >&3
	printf '# %s\n' "$title_label" >&3
	printf '############################################################\n' >&3
}

###
# nosubdir path
#
nosubdir() {
	local 'path'
	[ "${1-}" = '--' ] && shift
	path=${1:?"ERROR (SELFTEST BUG): nosubdir: Missing parameter."}

	if [ -z "$( find "./${path}" -mindepth 1 -maxdepth 1 -type d )" ]
	then
		return 0
	else
		return 1
	fi
}

###
# vmfix_multi [-abclnprs] path
#
# Options:
# -a, -b, -c, l, -s: Execute each test successively.
# -n: Only ensure that no check detect an issue, do not correct anything.
# -N: Only ensure that *each* of the checks detect an issue, do not correct
#     anything.
# -r: Tell `vmfix' to act recursively.
#
vmfix_multi() {
	local 'check_opt' 'opt' 'opt_list' 'OPTARG' 'OPTIND' 'path' 'recurse_opt'
	check_opt=''
	opt_list=''
	recurse_opt=''

	OPTIND=1
	while getopts 'AabdlnNprs' opt
	do
		case "$opt" in
			'A'|'a'|'b'|'l'|'p'|'s') opt_list="${opt_list}${IFS}${opt}" ;;
			'n') check_opt='n' ;;
			'N') check_opt='N' ;;
			'r') recurse_opt='r' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	path=${1:?"ERROR (SELFTEST BUG): vmfix_multi: Missing parameter."}

	for opt in $opt_list
	do
		case "$check_opt" in
			'n') check vmfix -n ${recurse_opt:+'-r'} "-${opt}" -- "$path" ;;
			'N') check ! vmfix -n ${recurse_opt:+'-r'} "-${opt}" -- "$path" ;;
			*)
				echo "ERROR (SELFTEST BUG): vmfix_multi: Invalid value for" \
					"\$check_opt: '${check_opt}'." >&2
				return 1
				;;
		esac
	done
}

###
# vmsettingsfile [-p parent_path] vm_path...
#
# Check the integrity of an automatically generated VM settings file.
#
# This function is only meant to check the expected content of an automaically
# generated file, it does not attempt to cover the modifications which may be
# manually done later in the VM life cycle.
#
vmsettingsfile() {
	local 'content' 'file' 'filter' 'opt' 'OPTARG' 'OPTIND' 'parent'
	local 'grep_rc'
	filter='vm_'
	parent=''

	OPTIND=1
	while getopts 'p:' opt
	do
		case "$opt" in
			'p')
				if [ -n "$parent" ]
				then
					printf 'ERROR (SELFTEST BUG): vmsettingsfile: %s\n' \
						"Option '-p' used multiple times." >&2
					return 1
				fi
				parent=$( realpath -- "$OPTARG" ) || return 1
				check test -d "$parent"
				filter="${filter:+"${filter}\\|"}parent $( \
					escape_grep "$( escape "$parent" )" )\$"
				;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))

	if [ $# -gt 1 ]
	then
		# Invoke a new `check' for each file, this produces clearer logs.
		for f
		do
			if [ -n "$parent" ]
			then
				check vmsettingsfile -p "$parent" -- "$f"
			else
				check vmsettingsfile -- "$f"
			fi
		done
		return 0
	elif [ $# -eq 0 ]
	then
		printf 'ERROR (SELFTEST BUG): vmsettings: Missing parameter.\n' >&2
		return 1
	fi

	file="${1%"/${cfg_file_vmsettings}"}/${cfg_file_vmsettings}"
	check test -s "$file"

	# Get VM settings file content without empty line and comments.
	grep_rc=0
	content=$( grep -v -- '^\(#\|$\)' "$file" ) || grep_rc=$?
	if [ "$grep_rc" -ge 2 ]
	then
		printf "ERROR (SELFTEST BUG?): 'grep' failed.\\n" >&2
		return 1
	fi

	# The VM settings file must contain only expected entries.
	printf '%s' "$content" | check ! grep -v "^\\(${filter}\\)" || return 1

	# Backend files path shall be absolute paths.
	printf '%s' "$content" \
		| grep 'vm_storage_[[:alnum:]]*_backend=' \
		| check ! grep -v "vm_storage_[[:alnum:]]*_backend=\\(/\\|'/\\)" \
		|| return 1

	# No OVA files as they are not natively supported by Qemu (VMDK is OK).
	printf '%s' "$content" \
		| check ! grep 'vm_storage_hdd[12]_backend=.*\.[oO][vV][aA]$' \
		|| return 1

	# Each statement must appear only once, no duplicates.
	check test -z "$( printf '%s' "$content" | LC_ALL=C sort | cut -d '=' -f 1 \
		| uniq -cd )"
}

###
# vmtree [-l depth_level] [-p parent_path] vm_path
#
# TODO: Modify this function to that the caller has to call `vmtree` only
# once instead of putting a block of vmtree, this should avoid to execute the
# same test on the same VM several times (see the call to `vmfix`).
# For instance, replace:
#     check vmtree -- "${name}/${name}"
#     check vmtree -p "$name" -- "${name}/${name}_1"
#     check vmtree -p "${name}/${name}_C" -- "${name}/${name}_E"
# With something like:
#     check vmtree \
#         -p ''                  -d "${name}/${name}" \
#         -p "${name}"           -d "${name}/${name}_1"
#         -p "${name}/${name}_C" -d "${name}/${name}_E"
#
vmtree() {
	local 'depth_level' 'dir' 'opt' 'OPTARG' 'OPTIND' 'parent_path' 'startdir'
	depth_level=''
	parent_path=''

	OPTIND=1
	while getopts 'l:p:' opt
	do
		case "$opt" in
			'l') depth_level=$OPTARG ;;
			'p') parent_path=$OPTARG ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	startdir=${1:?"ERROR (SELFTEST BUG): vmtree: Missing parameter."}

	check test -d "$startdir"
	check vmfix -anr -- "$startdir"
	# SC2086: Word splitting around `$IFS' expected.
	# shellcheck disable=SC2086
	check vmsettingsfile ${parent_path:+-p${IFS}"${parent_path}"} -- "$startdir"

	if [ -z "$depth_level" -o "$depth_level" != "0" ]
	then
		# SC2044: Parameter expansion disabled and IFS set to newline.
		# SC2086: Word splitting expected around `$IFS'.
		# shellcheck disable=SC2044,SC2086
		for dir in $( find "./${startdir}" -mindepth 1 \
			${depth_level:+-maxdepth${IFS}"${depth_level}"} -type d \
			-a ! -path "$( printf '*\n*' )" )
		do
			check vmsettingsfile -p "${dir%/*}" -- "$dir"
		done
	fi
}


################################################################################
# Main
################################################################################

# Explicitely set the flag when invoked as `sh ./selftest.sh'.
set -efu

if vmps
then
	printf 'ERROR: Some virtual machines are currently running.\n' >&2
	printf "Stop them ('vmdown -a') then try again.\\n" >&2
	exit 1
fi

cd "$( dirname -- "$0" )"
out_dir=$( realpath -- "${out_dir:?}" ) || exit 1
if [ -e "$out_dir" ]
then
	reply='*null*'
	while test -n "$reply" && ! expr "$reply" : '[yYnN]$' >/dev/null
	do
		printf '%s' \
			"${out_dir}: This directory already exists, remove it [yN]? " >&2
		read reply || exit 1
	done

	case "$reply" in
		'y'|'Y')
			rm -rf -- "$out_dir" || exit 1
			;;
		*)
			printf 'Operation cancelled by the user.\n' >&2
			exit 2
			;;
	esac
fi
mkdir -p -- "${out_dir}/images" || exit 1

# Copy images files
cp -- "${file_iso:?}" "${file_ova:?}" "${out_dir}/images"
file_iso="${out_dir}/images/${file_iso##*/}"
file_ova="${out_dir}/images/${file_ova##*/}"
out_log=$( realpath -- "${out_log:?}" ) || exit 1

# Setup current directory.
cd -- "$out_dir"

printf "# Test started: %s\n" "$( date )" >"$out_log"
rc=0
check_all 3>>"$out_log" || rc=$?
printf "# Test ended (success): %s\n" "$( date )" >>"$out_log"

printf "\33[G\33[KAll tests passed successfully.\n"

exit "$rc"

################################################################################
### tools/selftest.sh END
################################################################################
