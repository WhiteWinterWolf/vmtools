################################################################################
### /usr/local/share/vmtools/modules/buildcmd/qemu.inc.sh BEGIN
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
# This modules sets the actual command (binary executable name and location)
# to run to start the Qemu hypervisor, and also set a few basic parameters.
#
# This module should usually be one of the first invoked in the
# `$cfg_modules_buildcmd' setting variable.
#
################################################################################

mod_buildcmd() {
	local 'params' 'qemu_cmd' 'ret' 'varname'
	varname=${1:?"ERROR (BUG): mod_buildcmd: Missing parameter."}
	# In most cases Qemu should be the first command, however some people may
	# need to set some environment variable or use some wrapper so we stick in
	# including any previously set value.
	eval "ret=\$$varname"

	case "${vm_qemu_arch:?}" in *[![:alnum:]_]*)
		echo "ERROR: Invalid Qemu architecture name: '${vm_qemu_arch}'." >&2
		return 1
	esac

	qemu_cmd="${cfg_qemu_cmdprefix:?}${vm_qemu_arch:?}"
	# `type' doesn't accept '--' on Dash.
	if ! type "$qemu_cmd" >/dev/null 2>&1
	then
		echo "ERROR: The command to run Qemu ('${qemu_cmd}') has not been" \
			"found, please check 'cfg_qemu_cmdprefix' setting value." >&2
		return 1
	fi

	str_list_add 'ret' "$qemu_cmd" || return 1

	if [ -n "$vm_qemu_params" ]
	then
		params=$( str_explode -- "$vm_qemu_params" ) || return 1
		# SC2086: Word splitting expected on `$params'.
		# shellcheck disable=SC2086
		str_list_add 'ret' $params || return 1
	fi

	if [ -n "$vm_home" ]
	then
		# `vmps` relies on the PID file path to determine a VM home.
		str_list_add 'ret' '-pidfile' "${vm_home:?}/${cfg_file_pid:?}" \
			|| return 1
	fi

	if [ "$vm_qemu_daemonize" = 'yes' ]
	then
		str_list_add 'ret' '-daemonize' || return 1
	fi

	eval "$varname=\$ret"
}

################################################################################
### /usr/local/share/vmtools/modules/buildcmd/qemu.inc.sh END
################################################################################
