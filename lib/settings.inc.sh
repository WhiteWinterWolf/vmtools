################################################################################
### /usr/local/lib/vmtools/settings.inc.sh BEGIN
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
# This library allows to load and manage virtual machine settings.
#
# Active settings are defined as shell variable. This leaves little room to
# control how and when these settings may be overriden (for instance
# command-line parameters are parsed before loading the VM settings file but
# are expected to override them).
#
# This library therefore also provides a separate data structure storing
# more permanent settings, with a more finegrain way to either set their
# initial value (`settings-set()') or override them (`settings_override()'),
# and is also used to generate new or updated VM settings files.
#
# Public functions:
#   settings_apply
#         Apply settings defined in this library over active VM settings.
#   settings_gen [comment]
#         Generate a VM settings file content on stdout.
#   settings_get
#         Retrieve all settings set using this library.
#   settings_import [-as] [vmhome_path...]
#         Import a VM settings file content into this library data structure.
#   settings_loadvm [-s] [vmhome_dir]
#         Import a VM settings file content into as active settings.
#   settings_override name value
#         Override a variable value and store this value in this library.
#   settings_remove name...
#         Remove a variable from this library.
#   settings_reset
#         Reset nearly VM settings and data to their default values.
#   settings_save [comment [vmhome_path]]
#         Generate or update a VM settings file.
#   settings_set name value
#         Set the initial value of a variable if it wasn't previously defined.
#   settings_setparent newparent_path child_path...
#         Set the new parent of one or several childs at once.
#   settings_setstorage device backend
#         Dynamically add a new storage image file to the VM.
#
################################################################################

################################################################################
# Global variables
################################################################################

# SC2034: These variables are mainly populated by command-line parameters and
# user's input.
# shellcheck disable=SC2034

# List of VM settings to override.
# Use `settings_set()', `settings_remove()' and `settings_apply()' to modify
# this variable from an external module.
# Internally, variables assignements stored in this variable are prefixed using
# a space to distinguish them from actual assignement in `set' output (doing
# `set | grep '^vm_...' will not match assignements made within
# `$settings_list'.
settings_list=''

# Storage devices overrides
settings_cdrom1=''
settings_cdrom2=''
settings_hdd1=''
settings_hdd2=''


################################################################################
# Functions
################################################################################

###
# settings_apply
#
# Override currently active VM settings (`$vm_*' variables) with the settings
# stored in this library data structure.
#
# This is a required step to complete the VM settings (for instance to include
# supplementary settings provided through command-line) before booting the VM.
#
settings_apply() {
	local 'backend1' 'backend2' 'device' 'enable' 'new_backend1' 'new_backend2'
	local 'ok'

	eval "$settings_list" || return 1

	# Apply `$settings_[device]' values (see `settings_setstorage()').
	ok='yes'
	for device in "cdrom" "hdd"
	do
		eval "new_backend1=\$settings_${device}1"
		if [ -n "$new_backend1" ]
		then
			new_backend1=$( storage_get_canonical -- "$new_backend1" ) \
				|| return 1
			eval "new_backend2=\$settings_${device}2"
			eval "backend1=\$vm_storage_${device}1_backend"
			eval "backend2=\$vm_storage_${device}2_backend"
			eval "enable1=\$vm_storage_${device}1_enable"
			eval "enable2=\$vm_storage_${device}2_enable"
			# Clear $settings_{cdrom,hdd}* so that several calls to
			# settings_apply() doesn't double the devices.
			eval "settings_${device}1="
			eval "settings_${device}2="

			if [ -z "$backend1" -o "$enable1" != 'yes' ]
			then
				settings_set "vm_storage_${device}1_backend" "$new_backend1"
				settings_set "vm_storage_${device}1_enable" 'yes'
				if [ "$device" = "hdd" ]
				then
					vm_storage_hdd1_createsize=''
				fi

				if [ -n "$new_backend2" ]
				then
					new_backend2=$( storage_get_canonical -- "$new_backend2" ) \
						|| return 1
					if [ -z "$backend2" -o "$enable2" != 'yes' ]
					then
						settings_set "vm_storage_${device}2_backend" \
							"$new_backend2"
						settings_set "vm_storage_${device}2_enable" 'yes'
						if [ "$device" = "hdd" ]
						then
							vm_storage_hdd2_createsize=''
						fi
					else
						ok='no'
					fi
				fi
			elif [ -z "$backend2" -o "$enable2" != 'yes' ]
			then
				settings_set "vm_storage_${device}2_backend" "$new_backend1"
				settings_set "vm_storage_${device}2_enable" 'yes'
				if [ "$device" = "hdd" ]
				then
					vm_storage_hdd2_createsize=''
				fi

				if [ -n "$new_backend2" ]
				then
					ok='no'
				fi
			else
				ok='no'
			fi

			if [ "$ok" = 'no' ]
			then
				case "$device" in
					"cdrom")
						echo "ERROR: You cannot add more than two CD-ROM" \
							"devices." >&2
						;;
					"hdd")
						echo "ERROR: You cannot add more than two hard-disk" \
							"devices." >&2
						;;
					*)
						echo "ERROR (BUG): Unknown device type: $device" >&2
						;;
				esac
				return 1
			fi
		fi
	done
}

###
# settings_gen [comment]
#
# Output a `vm.settings' file content from current parent, templates and
# settings overrides on stdout.
#
# An optional string `comment' may be included in the resulting header.
# This string may be several lines long.
#
# See also `settings_save()' to store the output in a VM settings file.
#
settings_gen() {
	local 'comment' 'createsize' 'i' 'storage_header_done' 'templates_list'
	comment=$( printf '%s\n' "${1-}" | sed 's/^/# /' )

	cat <<-__EOF__
		############################################################
		# Virtual machine configuration generated on:
		# $( date )
		# by $( id -un )
		${comment}
		# See vm.settings(5) man page for available settings.
		############################################################

		### General ###

	__EOF__

	if ! parent_isempty
	then
		printf 'parent %s\n' "$( str_escape -- "$( parent_get_nearest )" )"
	fi

	if ! template_isempty
	then
		templates_list=$( template_get_list ) || return 1
		# SC2046, SC2086: Word splitting expected on `$templates_list'.
		# shellcheck disable=SC2046,SC2086
		printf 'template %s\n' "$( str_escape -- $templates_list )"
	fi

	printf 'vm_name=%s\n' "$( str_escape -- "$vm_name" )"
	case "$settings_list" in *"vm_ram_size="*)
		printf 'vm_ram_size=%s\n' "$( str_escape -- "$vm_ram_size" )"
	esac
	case "$settings_list" in *"vm_cpu_count="*)
		printf 'vm_cpu_count=%s\n' "$( str_escape -- "$vm_cpu_count" )"
	esac
	printf '\n'

	storage_header_done='no'
	for i in 1 2
	do
		case "$settings_list" in *"vm_storage_hdd${i}_"*)
			if [ "$storage_header_done" != 'yes' ]
			then
				printf '### Storage ###\n'
				storage_header_done='yes'
			fi

			eval "createsize=\$vm_storage_hdd${i}_createsize"
			if [ -n "$createsize" ]
			then
				printf '\n# HDD %d - initial size: %s\n' "$i" \
					"$( str_escape -- "$createsize" )"
			else
				printf '\n# HDD %d\n' "$i"
			fi

			settings_get | grep "^vm_storage_hdd${i}_" | LC_ALL=C sort
		esac
	done
	for i in 1 2
	do
		case "$settings_list" in *"vm_storage_cdrom${i}_"*)
			if [ "$storage_header_done" != 'yes' ]
			then
				printf '### Storage ###\n'
				storage_header_done='yes'
			fi

			printf '\n# CD-ROM %d\n' "$i"

			# Mounted image is commented (given only for information) as it is
			# usually not desirable to strongly tie the VM to its installation
			# media (ie. the VM would refuse to boot if the installation ISO is
			# not found).
			settings_get | grep "^vm_storage_cdrom${i}_" | LC_ALL=C sort \
				| sed "s/^vm_storage_cdrom${i}_backend=/# &/"
		esac
	done
	if [ "$storage_header_done" = 'yes' ]
	then
		printf '\n'
	fi

	printf '### Misc settings ###\n\n'
	settings_get | grep -v -e '^\(cfg_\|vm_boot_order=\|vm_cpu_count=\)' \
		-e '^\(vm_name=\|vm_ram_size=\|vm_storage_cdrom\|vm_storage_hdd\)'
	printf '\n'
}

###
# settings_get
#
# Get the settings currently defined in this library data structure.
#
settings_get() {
	printf '%s' "$settings_list" | sed 's/^ //'
}

###
# settings_import [-as] [vmhome_path...]
#
# Import the VM settings from `vmhome_path' (or `$vm_home' if not specified)
# into this library data structure so that a similar VM settings file content
# can be regenerated using `settings_gen()'.
#
# See `settings_loadvm()' to load a VM settings file into the calling
# environment without modifying this library data structure.
#
# Options:
#   -a    Append to the current settings, do not overwrite basic settings
#         (only `vm_home', `vm_name', the parent and template are overwritten).
#   -s    Load only the given VM settings, do not recurse through its parents.
#
settings_import() {
	local 'append' 'opt' 'OPTARG' 'OPTIND' 'path' 'single' 'statements'
	local 'templates_list'
	append='no'
	single='no'

	OPTIND=1
	while getopts 'as' opt
	do
		case "$opt" in
			'a') append='yes' ;;
			's') single='yes' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))
	path=${1:-"${vm_home:?}"}

	statements=$(
		# Load only the variables defined in the VM settings.
		str_list_remove settings_list '^ vm_'
		# SC2046: Word splitting expected on `awk' output.
		# shellcheck disable=SC2046
		unset $( set | awk -F '=' '/^vm_/ && $1 != "vm_home" { print $1 }' )
		parent_clear
		if [ "$single" = 'yes' ]
		then
			settings_loadvm -s -- "$path" || exit 1
		else
			settings_loadvm -- "$path" || exit 1
		fi

		# Output the result.
		if [ "$append" != 'yes' ]
		then
			printf 'settings_reset\n'
		fi

		printf 'vm_home=%s\n' "$( str_escape -- "${vm_home:?}" )"
		printf 'vm_name=%s\n' "$( str_escape -- "$vm_name" )"
		printf 'parent_clear\n'
		if ! parent_isempty
		then
			if [ "$single" = 'yes' ]
			then
				printf 'parent_add %s\n' "$( str_escape -- \
					"$( parent_get_nearest )" )"
			else
				printf 'parent %s\n' "$( str_escape -- \
					"$( parent_get_nearest )" )"
			fi
		fi

		if ! template_isempty
		then
			templates_list=$( template_get_list ) || return 1
			# SC2046, SC2086: Word splitting expected on `$templates_list'.
			# shellcheck disable=SC2046,SC2086
			printf 'template %s\n' "$( str_escape -- $templates_list )"
		fi
		set | awk '/^vm_/ && ! /^vm_(home|name)=/' \
			| sed 's/\([^=]*\)=\(.*\)$/settings_set \1 \2/'
	) || return 1

	eval "$statements" || return 1
}

###
# settings_loadvm [-s] [vmhome_dir]
#
# Load and apply the VM settings from `vmhome_dir' (or `$vm_home if it is not
# specified).
#
# In case the calling environment must be preserved, this function should be
# called from a subshell.
#
# This function does not alter settings defined in this library data structure.
# On the contrary it uses them to override the settings read from the file.
#
# See `settings_import()' to import VM settings in this library data structure
# without altering the calling environment.
#
# Options:
#   -s    Load only the given VM settings, do not recurse through its parents.
#
settings_loadvm() {
	local 'opt' 'OPTARG' 'OPTIND' 'vmsettings_path'
	parent_follow='yes'

	OPTIND=1
	while getopts 's' opt
	do
		case "$opt" in
			's') parent_follow='no' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))

	# SC2031: `settings_loadvm()' may be called from a subshell.
	# shellcheck disable=SC2031
	vm_home=${1:-"${vm_home:?}"}
	vm_home=$( realpath -- "$vm_home" ) || return 1
	case "$vm_home" in *"$newline"*)
		echo "ERROR: New line characters are not allowed in path:" \
			"'${vm_home}'." >&2
		return 1
	esac

	vmsettings_path="${vm_home:?}/${cfg_file_vmsettings:?}"
	if [ ! -r "$vmsettings_path" ]
	then
		echo "ERROR: '${vm_home}' does not seem to be a virtual machine home" \
			"directory (the file '${cfg_file_vmsettings}' is missing)." >&2
		return 1
	fi

	cli_trace 4 "settings_loadvm: ${vm_home}: Loading VM settings" \
		"(\$parent_follow='${parent_follow:-}')."

	parent_clear
	# `settings_apply()' must be called before loading templates to setup
	# storage, then after VM settings has been loaded to ensure that
	# command-line settings properly override anything else.
	# See also `vmup_inputsettings()'.
	include_vmsettings -- "${vmsettings_path}" || return 1
	settings_apply || return 1
	template_apply || return 1
	settings_apply || return 1
}

###
# settings_override name value
#
# Affects `value' to the variable named `name' and record this in this library
# data structure so this value could be recalled later.
#
# If this variable has already been defined, it is overwritten with the
# new value.
# If this variable doesn't exists yet, this function has the same effect than
# `settings_set()'.
#
# See also `settings_set()' to avoid overriding already defined variables.
#
settings_override() {
	local 'name' 'value'
	name=${1:?"ERROR (BUG): settings_override: Missing parameter."}
	value=${2:?"ERROR (BUG): settings_override: Missing parameter."}

	settings_remove "$name" || return 1
	settings_set "$name" "$value" || return 1
}

###
# settings_remove name...
#
# Remove a variable named `name' from this library data structure.
#
# If this variable does not already exist this function has no effect.
#
settings_remove() {
	local 'name'

	for name
	do
		case "$name" in *[![:alnum:]_]*)
			# Abort on illegal character.
			echo "ERROR (BUG): settings_remove: Illegal characters: '$*'." >&2
			return 1
		esac

		# `$name' content has been validated and is safe.
		str_list_remove settings_list "^ ${name}="
	done
}

###
# settings_reset
#
# Reset all VM settings to their default value and clear this VM data structure
# except for vmtools settings (`$cfg_*' varaibles) which are kept as-is.
#
# This function allows to go back to a pristine state before loading a new VM
# settings for instance.
#
# SC2034: Most of these variables are modified in the calling environment.
# shellcheck disable=SC2034
settings_reset() {
	cli_trace 4 "settings_reset: Reset VM settings."
	settings_cdrom1=''
	settings_cdrom2=''
	settings_hdd1=''
	settings_hdd2=''
	# Clear only `$vm_*' settings, keep for instance `$cfg_*' entries (like
	# `$cfg_ui_verbosity' for intance).
	str_list_remove settings_list '^ vm_'
	include_globalconf || return 1
	parent_clear
	# Reapply kept settings.
	settings_apply || return 1
}

###
# settings_save [comment [vmhome_path]]
#
# Save the settings stored in this library data structure into a VM settings
# file under `vmhome_path' (or `$vm_home' if not provided).
#
# An optional string `comment' may be included in the resulting header.
# This string may be several lines long.
#
# See also `settings_gen()' to generate the content of the VM settings file.
#
settings_save() {
	local 'comment' 'destfile' 'dir'
	[ "${1-}" = '--' ] && shift
	comment=${1:-}
	dir=${2:-${vm_home:?}}
	destfile="${dir}/${cfg_file_vmsettings:?}"
	cli_trace 4 "settings_save: ${dir}: Save VM settings."

	lock_check -e -- "$dir" || return 1
	cleanup_backup -- "$destfile" || return 1

	settings_gen "$comment" >"$destfile" || return 1
}

###
# settings_set name value
#
# Set a VM setting in a persistent manner.
#
# Use this function to set VM settings changed by the user (command-line
# parameters, interactive input), this ensure that these choice will correctly
# override any default setting (default, templates and `vm.setting' file).
#
# If a new VM is being created, this setting will be saved as part of the VM
# definition.
#
# If several calls are made to this function trying to define the same variable
# name, only the first one will be taken into account.
#
# See `settings_override()' to override any previous definition.
#
settings_set() {
	local 'name' 'p' 'value'
	if [ $# -ne 2 ]
	then
		echo "ERROR (BUG): settings_set: 2 arguments required (${#}" \
			"given)." >&2
		return 1
	fi

	name=$( str_escape_grep -- "$1" )
	# If `str_escape_grep()' change the name in any way, this means it
	# contained invalid characters.
	if test "$name" != "$1"
	then
		echo "ERROR: This setting name contains invalid characters: '${1}'." >&2
		return 1
	fi
	if ! set | grep -q "^${name}=" && ! expr "$name" : \
		"vm_networking_iface[0-9]\{1,\}_\(device\|enable\|mac\|mode\)" \
		>/dev/null
	then
		echo "ERROR: This setting does not exists: '${1}'." >&2
		return 1
	fi
	if printf '%s' "$settings_list" | grep -q "^ ${name}="
	then
		# Variable already set, do not overwrite.
		return 0
	fi

	value=$( str_escape -- "$2" )
	str_list_add 'settings_list' " ${name}=${value}" || return 1
	eval "${name}=${value}" || return 1

	# If user's local configuration is being enabled/disabled, we need to
	# reload vmtools config.
	if [ "$name" = 'cfg_include_userhome' ]
	then
		settings_reset || return 1
	fi
}

###
# settings_setparent newparent_path child_path...
#
# Update `child_path' VM settings file to set `newparent_path' as the new
# parent.
#
# To not set any parent, set `newparent_path' to an empty string.
#
settings_setparent() {
	local 'child' 'newparent'
	[ "${1-}" = '--' ] && shift
	newparent=${1-}
	shift

	for child
	do
		cleanup_backup -- "${child}/${cfg_file_vmsettings:?}"

		(
			cleanup_reset
			settings_import -s -- "$child"|| exit 1
			parent_clear

			if [ -n "$newparent" ]
			then
				parent_add -- "$newparent" || exit 1
			fi

			settings_save "parent changed" || exit 1
			cleanup_end
		) || return 1
	done
}

###
# settings_setstorage device backend
#
# Dynamically add a new storage image file `backend' of type `device'.
#
# The `device' type may be either "cdrom" or "hdd".
#
# This allows to easily add a new image file without risking to overwrite any
# virtual drive already defined in the VM and by cleanly aborting if the VM
# doesn't have any free slot.
#
# The generation of the actual settings entry is postponned to the
# `settings_apply()' function in order to collect first all devices statically
# defined in the VM settings, its ancestors and its templates.
#
# This static device list is then completed as follow:
#   - For "cdrom" devices, `backend` is linked to the first virtual CDROM
#     reader with no image already attached. If there is none and there is a
#     free slot, a new virtual CDROM reader device is added to the VM with
#     the `bakend' image attached. Otherwise booting the VM fails.
#   - For "hdd" devices, there is no concept of HDD drive with no image
#     so the second step directly applies. If there is a free slot, a new
#     virtual HDD drive is added to the VM with the `bakend' image attached.
#     Otherwise booting the VM fails.
#
settings_setstorage() {
	local 'backend1' 'backend2' 'device' 'new_backend'
	device=${1:?"ERROR (BUG): settings_setstorage: Missing parameter."}
	# SC2034 `$new_backend' is accessed indirectly through eval'd strings.
	# shellcheck disable=SC2034
	new_backend=${2:?"ERROR (BUG): settings_setstorage: Missing parameter."}

	eval "backend1=\$settings_${device}1"
	eval "backend2=\$settings_${device}2"
	if [ -z "$backend1" ]
	then
		eval "settings_${device}1=\$new_backend"
	elif [ -z "$backend2" ]
	then
		eval "settings_${device}2=\$new_backend"
	else
		case "$device" in
			"cdrom")
				echo "ERROR: You cannot define more than two CD-ROM" \
					"readers." >&2
				;;
			"hdd")
				echo "ERROR: You cannot define more than two hard-disk" \
					"devices." >&2
				;;
			*)
				echo "ERROR (BUG): settings_setstorage: Unknown device type:" \
					"$new_device" >&2
				;;
		esac
	fi
}

################################################################################
### /usr/local/lib/vmtools/settings.inc.sh END
################################################################################
