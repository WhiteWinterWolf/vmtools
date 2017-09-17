################################################################################
### /usr/local/lib/vmtools/vmup.inc.sh BEGIN
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
# This library provides functions to start a virtual machine.
#
# Public functions:
#   vmup_inputsettings
#         Interactively ask the user to input the virtual machine settings.
#   vmup_parseargs_args arg...
#         Command-line argument parsing for `vmup' and `vmcreate'.
#   vmup_runqemu
#         Start the Qemu hypervisor process.
#
################################################################################

################################################################################
# Global variables
################################################################################

# If set to "yes", `vmup_runqemu()' will build Qemu command-line and run it,
# otherwise this function will only output some diagnostic messages depending
# on the verbosity level and exit without starting Qemu.
vmup_runqemu_enable='yes'


################################################################################
# Functions
################################################################################

###
# vmup_inputsettings
#
# Interactively ask the user to input the virtual machine settings.
#
# The exact user interaction is controlled by the `configure/settings' modules.
#
vmup_inputsettings() {
	local 'mods_list' 'module'

	if [ "$cfg_ui_assumeyes" != 'yes' ]
	then
		echo "-----------------------------------------------------------------"
		echo "Answer to the questions below to define the guest properties."
		echo "You can type '?' to display the help screen at any time."
		echo "-----------------------------------------------------------------"
	fi

	# `settings_apply()' must be called before loading templates
	# to setup storage and after it to ensure that command-line settings
	# properly override anything else. Interactive settings input comes on top
	# of this.
	# See also `settings_loadvm()'.
	settings_apply || return 1
	mods_list=$( str_explode -- "$cfg_modules_configure_templates" ) || return 1
	for module in $mods_list
	do
		cli_trace 3 "vmup_inputsettings: ${vm_name}: configuring templates:" \
			"${module}."
		include_module -- "configure/templates/${module}.inc.sh" || return 1
		mod_configure || return 1
	done
	template_apply || return 1
	settings_apply || return 1

	mods_list=$( str_explode -- "$cfg_modules_configure_settings" ) || return 1
	for module in $mods_list
	do
		cli_trace 3 "vmup_inputsettings: ${vm_name}: configuring VM settings:" \
			"${module}."
		include_module -- "configure/settings/${module}.inc.sh" || return 1
		mod_configure || return 1
	done
}

###
# vmup_parseargs_args arg...
#
# Parse the command-line argument for the `vmup' and `vmcreate' commands.
#
# Sets the global variable OPTIND to allow shifting the parameters in the
# calling context (see http://pubs.opengroup.org/onlinepubs/9699919799/utilities/getopts.html).
#
# TODO: Add -a and -A with same behavior as -c/-C/-d/-D but with floppies
# instead of CD-ROMs (this will also require a proper template to support
# legacy platforms, maybe create `legacy90' and `legacy2k' templates with the
# presence of floppy drives trigerring the first one in the autodetect module).
#
vmup_parseargs() {
	# `$OPTIND' must not be available to the caller, do not set it local!
	local 'OPTARG' 'param' 'usage' 'writable_flag'

	if [ -z "${usage:-}" ]
	then
		echo "WARNING (BUG): \$usage undefined." >&2
		usage=""
	fi

	# Global variable preventing any forbidden combination of -r and -s flags.
	writable_flag=''

	OPTIND=1
	while getopts "bC:c:D:d:hino:qrst:vyz" param
	do
		case "$param" in
			'b') # Enable BIOS' boot media selection menu.
				settings_set 'vm_boot_menu' 'yes'
				;;

			'C') # Like `-c', but also set boot order to boot from the HDD.
				settings_setstorage 'hdd' "$OPTARG" || return 2
				settings_set 'vm_boot_order' 'c'
				;;

			'c') # Add a hard-disk drive image file.
				settings_setstorage "hdd" "$OPTARG" || return 2
				;;

			'D') # Like `-d', but also set boot order to boot from CD-ROM.
				settings_setstorage "cdrom" "$OPTARG" || return 2
				settings_set 'vm_boot_order' 'd'
				;;

			'd') # Add a CD-ROM image file.
				settings_setstorage "cdrom" "$OPTARG" || return 2
				;;

			'h') # Show usage information.
				printf '%s\n' "$usage"
				exit 0
				;;

			'i') # Interactive mode, do not daemonize but provide a QMP shell.
				settings_set 'vm_qemu_daemonize' 'no'
				;;

			'n') # Do not start the VM, only generate the configuration.
				vmup_runqemu_enable='no'
				;;

			'o') # Override a setting.
				value=$( str_unescape -- "${OPTARG#*=}" ) || return 2
				settings_override "${OPTARG%%=*}" "$value" || return 2
				;;

			'q') # Decrease verbosity.
				if [ "${cfg_ui_verbosity:?}" -gt 0 ]
				then
					cfg_ui_verbosity=$(( cfg_ui_verbosity - 1 )) || return 1
				fi
				;;

			'r') # Read-only access to all storage image files.
				if [ -z "$writable_flag" ]
				then
					writable_flag="r"
					settings_set 'vm_storage_rwmode' 'ro'
				elif [ "$writable_flag" != "r" ]
				then
					echo "ERROR: You cannot mix options such as 'read-only'" \
						"(-r) and 'snapshot-mode' (-s) together." >&2
					return 1
				fi
				;;

			's') # Do not modify storage (Qemu snapshot / non-persistent mode).
				if [ -z "$writable_flag" ]
				then
					writable_flag="s"
					settings_set 'vm_storage_rwmode' 'snap'
				elif [ "$writable_flag" != "s" ]
				then
					echo "ERROR: You cannot mix options such as 'read-only'" \
						"(-r) and 'snapshot' (-s) together." >&2
					return 1
				fi
				;;

			't') # Apply a template.
				template_add "$OPTARG"
				;;

			'v') # Increase verbosity.
				cfg_ui_verbosity=$(( ${cfg_ui_verbosity:?} + 1 )) || return 1
				;;

			'y') # Never ask any confirmation, always assume `y' as answer.
				settings_override 'cfg_ui_assumeyes' 'yes'
				;;

			'z') # Compress copied or converted images.
				settings_set 'vm_qemu_compress' 'yes'
				;;

			*)
				echo "Unexpected argument: $1" >&2
				return 2
				;;
		esac
	done

	settings_set 'cfg_ui_verbosity' "${cfg_ui_verbosity:?}"
	if [ "${cfg_ui_verbosity:?}" -ge 5 ]
	then
		set -x
	fi
}

###
# vmup_runqemu
#
# Start the Qemu hypervisor process, effectively booting the virtual machine.
#
# If the current verbosity level is greater or equal to 3, this function will
# also display on stderr the Qemu commmand-line which will be used.
# If the current verbosity level is greater or equal to 4, it will also dump
# current VM settings.
#
vmup_runqemu() {
	local 'cmd' 'mods_list' 'module'
	cmd=''

	if [ "${cfg_ui_verbosity:?}" -ge 4 ]
	then
		echo "*** START of VM settings dump:"
		set | awk '$0 ~ /^cfg_/ || $0 ~ /^vm_/ { print "    ",$0 }'
		echo "*** END of VM settings dump."
	fi

	mods_list=$( str_explode -- "$cfg_modules_buildcmd" ) || return 1
	for module in $mods_list
	do
		cli_trace 3 "vmup_runqemu: ${vm_name}: building Qemu command-line:" \
			"${module}."
		include_module -- "buildcmd/${module}.inc.sh" || return 1
		mod_buildcmd 'cmd' || return 1
	done

	cmd=$( str_escape -s ' ' -- $cmd )

	if [ "${cfg_ui_verbosity:?}" -ge 3 ]
	then
		printf '\nQemu command-line:\n'
		printf '%s\n' "$cmd"
	fi

	if [ "$vmup_runqemu_enable" = 'yes' ]
	then
		if [ -n "$vm_home" ]
		then
			lock_check -e || return 1

			# QEMU does not overwrite PID files correctly: it simply overwrites
			# the new PID over the current content of the file, which results
			# in a corrupted content when the new PID is shorter than the old
			# one currently stored in the file.
			# We therefore need to delete any PID file before starting QEMU.
			rm -f -- "${vm_home}/${cfg_file_pid:?}" || return 1

			# Some path may be relative to the VM home dir (monitor socket
			# file for instance).
			# TODO: Should the directory be placed earlier? No too early though
			# as path passed by the user as command-line parameter must remain
			# relative to the user's current directory.
			cd -- "$vm_home" || return 1
		fi
		eval "$cmd" || return 1
	fi
}

################################################################################
### /usr/local/lib/vmtools/vmup.inc.sh END
################################################################################
