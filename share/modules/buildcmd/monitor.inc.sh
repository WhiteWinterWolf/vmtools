################################################################################
### /usr/local/share/vmtools/modules/buildcmd/monitor.inc.sh BEGIN
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
# This module handles the creation of the Qemu monitor file.
#
# This file provides an interactive shell to control the Qemu hypervisor.
#
################################################################################

mod_buildcmd() {
	local 'ret' 'varname'
	varname=${1:?"ERROR (BUG): mod_buildcmd: Missing parameter."}
	# In most cases Qemu should be the first command, however some people may
	# need to set some environment variable or use some wrapper so we stick in
	# including any previously set value.
	eval "ret=\$$varname"

	if [ "$vm_qemu_daemonize" = 'yes' ]
	then
		if [ -n "$vm_home" ]
		then
			# TODO: Qemu also proposes Json-based QMP shell, seems less
			# practical but may be an alternative if the user wants to keep
			# the Monitor shell reachable through the display?

			# Use a relative path as socket file path length is limited to
			# around 100 chars (Unix kernel limitation).
			# https://unix.stackexchange.com/q/367008/53965
			str_list_add 'ret' '-monitor' "unix:$( str_escape_comma -- \
				"./${cfg_file_monitor:?}" ),server,nowait" || return 1
			cleanup_backup -m -- "${vm_home}/${cfg_file_monitor:?}"
		else
			# TODO: Any clean way to keep monitor when there is no home dir?
			# - TCP port: potential security issue if no authentication.
			# - Temporary file/folder: no way to automatically delete them
			#   when Qemu exits.
			# For now, do not allow the daemonize settings to change the
			# display behavior.
			# In Qemu source code, file `monitor.c', function
			# `monitor_read_password': it seems that it is somehow possible to
			# set a password to access the monitor, but this is not documented
			# in the man page.
			str_list_add 'ret' '-monitor' 'none'
		fi
	else
		str_list_add 'ret' '-monitor' 'stdio'
	fi

	eval "$varname=\$ret"
}

################################################################################
### /usr/local/share/vmtools/modules/buildcmd/monitor.inc.sh END
################################################################################
