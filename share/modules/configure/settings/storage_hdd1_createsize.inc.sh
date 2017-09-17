################################################################################
### /usr/local/share/modules/configure/vmsettings/storage_hdd1_createsize.inc.sh BEGIN
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
# This module asks the user to input the size of the primary hard-disk storage
# media to create for the guest.
#
# This modules does nothing if the virtual machine has no home directory to
# store the disk image file (when directly booting an ISO file for instance) or
# when the virtual machine as no hard-disk drive enabled.
#
################################################################################

mod_configure() {
	local 'default' 'reply' 'unit' 'usage'
	default="40G"

	usage=$( cat <<-'__EOF__'

		MAIN HARD-DISK SIZE

		Define the size of the main virtual hard-disk to create for your guest:
		- Set it to '0' (zero) to create no hard-disk.
		- Append a unit such as M (megabytes) or G (gigabytes) to define a size
		  (for instance '20G' to create a 20GB virtual hard-disk.

		From the host perspective, this size is to be understood as a maximum
		size: the backend file size won't directly allocate this space, but its
		size will grow following space usage in the guest (for instance a guest
		storing 10GB of data will result in a backend file of about 10GB, even
		if the virtual hard-disk space is set to 20GB).

		The "best" value really depends on your intended use. For graphical
		environment, 40GB is a reasonnable default: the most common issue is
		not the backend file being too large (remember it does not allocate the
		space immediately) but instead lack of space in the guest due to too
		wary initial setup.

		__EOF__
	)


	# A hard-disk can be configured only if there is any directory where its
	# backing file can be stored (this is not the case when booting ISO images).
	if [ -n "$vm_home" -a "$vm_storage_hdd1_enable" != 'yes' ]
	then
		if [ "$cfg_ui_assumeyes" = 'yes' ]
		then
			reply=''
			cli_trace 3 "${vm_name}: storage_hdd1_createsize: using default" \
				"value: $default"
		else
			reply=$noreply
			while test -n "$reply" \
				&& ! expr "$reply" : '[1-9][0-9]*[MGT]$\|0$' >/dev/null
			do
				if [ "$reply" = '?' ]
				then
					printf '%s\n' "$usage" >&2
				fi
				printf '\nMain hard-disk size (default: %s)? ' "$default" >&2
				read reply || return 2
				reply=$( str_toupper -- "$reply" )

				if expr "$reply" : '[1-9][0-9]*$' >/dev/null
				then
					echo "You did not mention any unit." >&2
					unit=$noreply
					while test -n "$unit" && ! expr "$unit" : '[MGT]$' \
						>/dev/null
					do
						if [ "$unit" = '?' ]
						then
							{
								echo
								echo "You must enter either 'm', 'g'or 't' to" \
									"confirm the unit."
							} >&2
						fi
						printf '\n'
						printf '%s ' "Did you mean Megabytes, Gigabytes or" \
							"Terabytes [mGt]? " >&2
						read unit || return 2
						unit=$( str_toupper -- "$unit" )
					done
					reply="${reply}${unit:-'G'}"
				fi
			done
		fi

		if [ "$reply" != '0' ]
		then
			settings_set 'vm_storage_hdd1_backend' "$( storage_createpath \
				-s '.qcow2' -- "${vm_home}/hdd.qcow2" )" || return 1
			settings_set 'vm_storage_hdd1_enable' 'yes'
			# The storage creation must occur only once, don't set it in the
			# VM setting file.
			# SC2034: This variable is used by the caller and other modules.
			# shellcheck disable=SC2034
			vm_storage_hdd1_createsize="${reply:-"${default}"}"
		fi
	fi
}

################################################################################
### /usr/local/share/modules/configure/vmsettings/storage_hdd1_createsize.inc.sh END
################################################################################
