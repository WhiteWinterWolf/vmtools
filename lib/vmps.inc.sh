################################################################################
### /usr/local/lib/vmtools/vmps.inc.sh BEGIN
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
# You should have received a copy off the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# ------------------------------------------------------------------------------
#
# This library allows to list and get information on virtual machines currently
# running on the local host.
#
# This library data structure must be explicitely initialized using
# `vmps_init()' before any other member function can be called.
#
# Public functions:
#   vmps_get_cmdline [pid]
#         Get running virtual machines command-line.
#   vmps_get_display [pid]
#         Get running virtual machines display method and URL.
#   vmps_get_homedir [pid]
#         Get running virtual machines home directory when available.
#   vmps_get_monitorfile [pid]
#         Get running virtual machines monitor file path when available.
#   vmps_get_name [pid]
#         Get running virtual machines name when available.
#   vmps_get_pcpu [pid]
#         Get running virtual machines CPU consumption when available.
#   vmps_get_pid [pid]
#         Get running virtual machines (Qemu process) PID.
#   vmps_get_user [pid]
#         Get running virtual machines user (Qemu process owner).
#   vmps_get_vsz [pid]
#         Get running virtual machines memory consumption (kilobytes).
#   vmps_init [-q] [-d vmhome_dir|-p pid|-u user]
#         Initialize this library data structure.
#   vmps_isempty
#         Check if any running virtual machine has been found.
#
################################################################################

################################################################################
# Global variables
################################################################################

# Field separator used in `$vmps_list'
vmps_fs=''

# Has the `ps`(1) command been executed?
vmps_initdone='no'

# Output of `ps'(1) executed with the format string "pid,user,vsz,pcpu,args".
vmps_list=''


### Locally supported features ###

# POSIX leaves several parts of `ps' behavior unspecified (mainly regarding
# the "args" and "pcpu" columns and the handling of special characters) and
# some implementations do not even attempt to implement specified parts (like
# BusyBox `ps' used on distros like Alpine Linux).
# This script therefore does its best to try to automatically adapt itself
# to the local `ps' behavior, and use the `/proc' tree if available to complete
# its information.

# `ps' seems to support basic POSIX options (like `-e').
vmps_feat_posix=''

# `ps' supports the "pcpu" column (`-o pcpu').
vmps_feat_pcpu=''

# The `/proc' tree is enabled and contains the `cmdline' file.
vmps_feat_proc=''

# `ps' supports the `-ww' option for non-truncated output.
vmps_feat_ww=''


################################################################################
# Functions
################################################################################

###
# vmps_clear
#
# Reset this library's data.
#
# This function is automatically invoked by `vmps_init()' when required, there
# should be no need to call it directly.
#
vmps_clear() {
	# Do not clear the other `$vmps_feat_*' variables, only `$vmps_feat_proc'.
	vmps_feat_proc=''
	vmps_fs=''
	vmps_initdone='no'
	vmps_list=''
}

###
# vmps_get [pid]
#
# Helper for the various getter function of this library (`vmps_get_*()').
#
# This function is not meant to be called directly.
#
# This functions selects the rows matching PID `pid' if one has been provided
# (all rows are matched otherwise) and provides them on stdout to the caller.
# The caller then just has to filter the columns to build its own output.
#
vmps_get() {
	local 'pid' 'res'
	[ "${1-}" = '--' ] && shift
	pid=${1:-}

	if [ -n "$pid" ]
	then
		printf '%s\n' "$vmps_list" \
			| awk -F "$vmps_fs" -v "PID=${pid}" '$1 == PID'
	else
		printf '%s\n' "$vmps_list"
	fi
}

###
# vmps_get_cmdline [pid]
#
# Outputs on stdout the command-line (the Qemu command + arguments) matching
# PID `pid', or matching all entries previously selected by `vmps_init()'.
#
vmps_get_cmdline() {
	local 'IFS'
	[ "${1-}" = '--' ] && shift
	vmps_isinitdone || return 1
	vmps_list_checkproc

	if [ "$vmps_feat_proc" = 'yes' ]
	then
		IFS=$vmps_fs
		str_escape -s ' ' -- $( vmps_get "$@" | cut -d "$vmps_fs" -f 5- )
	else
		vmps_get "$@" | tr -s ' ' | cut -d ' ' -f 5-
	fi
}

###
# vmps_get_display [pid]
#
# Outputs on stdout the display method and URL (if applicable) of the VM
# bearing PID `pid', or of all VMs previously selected by `vmps_init()'.
#
# The output may be one of the following:
#   disabled
#         Qemu display output has been disabled.
#   gtk   Qemu uses the GTK library.
#   none  No graphical device has been enabled for the guest.
#   sdl   Qemu uses the SDL library.
#   spice://<address>:<port>
#         A SPICE server is listening on the given address and port.
#   vnc://<address>:<port>
#         A VNC server is listening on the given address and port. If the VNC
#         client requires a display ID instead of a port number, substract 5900
#         to get it (port 5900 is equivalent to VNC display ID 0, pot 5901 to
#         VNC display ID 1, etc.).
#   ?     The display mode used has not been recognized.
#
vmps_get_display() {
	local 'errhandler' 'iface' 'line' 'port'
	[ "${1-}" = '--' ] && shift
	vmps_isinitdone || return 1
	vmps_list_checkproc

	errhandler="
		echo \"WARNING (BUG): vmps_get_display: 'expr' failed to parse:\" >&2
		echo \"\$line\" >&2
		echo >&1
		continue
	"

	vmps_get "$@" | {
		while read -r line
		do
			case "$line" in
				*"${vmps_fs}-vga${vmps_fs}none"*)
					printf 'disabled\n'
					;;
				*"${vmps_fs}-display${vmps_fs}gtk"*)
					printf 'gtk\n'
					;;
				*"${vmps_fs}-display${vmps_fs}none"*)
					printf 'none\n'
					;;
				*"${vmps_fs}-display${vmps_fs}sdl"*)
					printf 'sdl\n'
					;;
				*"${vmps_fs}-display${vmps_fs}vnc="*)
					iface=$( expr "$line" : \
						".*${vmps_fs}-display${vmps_fs}vnc=\\([^:]*\\):" ) \
						|| eval "$errhandler"
					# When `expr' matches '0' it considers it failed to match
					# anything...
					port=$( expr "$line" : \
						".*${vmps_fs}-display${vmps_fs}vnc=${iface}\\(:[0-9]*\\)" ) \
						|| eval "$errhandler"
					port=$(( ${port#:} + ${vm_display_portmin:?} ))
					printf 'vnc://%s:%d\n' "$iface" "$port"
					;;
				*"${vmps_fs}-spice${vmps_fs}"*)
					iface=$( expr "$line" : \
						".*${vmps_fs}-spice${vmps_fs}.*addr=\\([^,${vmps_fs}]*\\)" ) \
						|| eval "$errhandler"
					port=$( expr "$line" : \
						".*${vmps_fs}-spice${vmps_fs}.*port=\\([^,${vmps_fs}]*\\)" ) \
						|| eval "$errhandler"
					printf 'spice://%s:%d\n' "$iface" "$port"
					;;
				*"${vmps_fs}-vnc${vmps_fs}"*)
					iface=$( expr "$line" : ".*${vmps_fs}-vnc${vmps_fs}\\([^:]*\\):" ) \
						|| eval "$errhandler"
					# When `expr' matches '0' it considers it failed to match
					# anything...
					port=$( expr "$line" : ".*${vmps_fs}-vnc${vmps_fs}${iface}\\(:[0-9]*\\)" ) \
						|| eval "$errhandler"
					port=$(( ${port#:} + ${vm_display_portmin:?} ))
					printf 'vnc://%s:%d\n' "$iface" "$port"
					;;
				*)
					printf '?\n'
					;;
			esac
		done
	}
}

###
# vmps_get_homedir [pid]
#
# Outputs on stdout the home directory of the VM bearing PID `pid', or of all
# VMs previously selected by `vmps_init()'.
#
# This function returns empty values for virtual machines without home
# directories (image files directly booted via `vmup' for instance).
#
vmps_get_homedir() {
	local 'args' 'home_ps' 'home_real' 'pid_ps' 'pid_real' 'pids_homes'
	[ "${1-}" = '--' ] && shift

	vmps_isinitdone || return 1
	vmps_list_checkproc
	pids_homes=$( vmps_get "$@" | sed \
		-e "s/\\([0-9]*\\).*${vmps_fs}-pidfile${vmps_fs}\\(.*\\)\\/$( \
		str_escape_sed -- "${cfg_file_pid:?}" ).*/\\1 \\2/" \
		-e 't' \
		-e 's/.*//' )

	# GNU `ps' replaces field separator characters (tab and newline) with a
	# question mark in its output.
	# TODO: Check non GNU `ps' behavior and implement appropriate compatiblity
	# measures (this however would only affect system where `/proc' tree is not
	# used).
	case "$pids_homes" in
		*'?'*)
			printf '%s\n' "$pids_homes" | while \
				IFS=' ' read -r 'pid_ps' 'home_ps'
			do
				IFS=$newline
				case "$home_ps" in
					*'?'*)
						# We will rely on the PID file to identify the home dir.
						ok='no'
						set +f
						for home_real in $home_ps
						do
							if [ -r "${home_real}/${cfg_file_pid:?}" ]
							then
								pid_real=$( cat -- \
									"${home_real}/${cfg_file_pid:?}" )
								if [ "$pid_real" -eq "$pid_ps" ]
								then
									ok='yes'
									break
								fi
							fi
						done
						set -f

						if [ "$ok" = 'yes' ]
						then
							printf '%s\n' "$home_real"
						else
							echo "WARNING: ${home_ps}: Directory not found." >&2
							printf '%s\n' "$home_ps"
						fi


						;;
					*)
						printf '%s\n' "$home_ps"
						;;
				esac
			done
			;;
		*)
			printf '%s\n' "$pids_homes" | cut -d ' ' -f 2-
			;;
	esac
}

###
# vmps_get_monitorfile [pid]
#
# Outputs on stdout the path of the monitor file of the VM bearing PID `pid',
# or of all VMs previously selected by `vmps_init()'.
#
# If the VM has no monitor file, an empty string is returned.
#
vmps_get_monitorfile() {
	local 'pid' 'pids_sockfiles' 'sockfile' 'vmhome'
	[ "${1-}" = '--' ] && shift

	vmps_isinitdone || return 1
	vmps_list_checkproc
	pids_sockfiles=$( vmps_get "$@" | sed \
		-e 's/,,/,/g' \
		-e "s/\\([0-9]*\\).*${vmps_fs}-monitor${vmps_fs}unix:\\(.*\\/$( \
		str_escape_sed -- "${cfg_file_monitor:?}" )\\).*/\\1 \\2/" \
		-e 't' \
		-e 's/.*//' )

	printf '%s\n' "$pids_sockfiles" | while IFS=' ' read -r 'pid' 'sockfile'
	do
		IFS=$newline
		case "$sockfile" in
			'./'*)
				# Path relative to the VM home dir.
				vmhome=$( vmps_get_homedir -- "$pid" )
				printf '%s\n' "${vmhome%/}/${sockfile#"./"}"
				;;
			*)
				printf '%s\n' "$sockfile"
				;;
		esac
	done
}

###
# vmps_get_name [pid]
#
# Outputs on stdout the name of the VM bearing PID `pid', or of all VMs
# previously selected by `vmps_init()'.
#
# If the VM has no name, an empty string is returned.
#
vmps_get_name() {
	[ "${1-}" = '--' ] && shift
	vmps_isinitdone || return 1
	vmps_list_checkproc

	if [ "$vmps_feat_proc" = 'yes' ]
	then
		# The command-line has been read from the '/proc' tree, we have access
		# to a reliable VM name.
		vmps_get "$@" | sed \
			-e 's/,,/,/g' \
			-e "s/.*${vmps_fs}-name${vmps_fs}\\([^${vmps_fs}]*\\).*/\\1/" \
			-e 't' \
			-e 's/.*//'
	else
		# The regex below will not fully match names containing " -" (a space
		# followed by a dash). `ps' blindly appends every process parameters,
		# making it impossible to reliably parse its command-line field.
		vmps_get "$@" | sed \
			-e 's/,,/,/g' \
			-e 's/.* -name \(\([^ ]*\( [^-]\)\{0,1\}\)*\).*/\1/' \
			-e 't' \
			-e 's/.*//'
	fi
}

###
# vmps_get_pcpu [pid]
#
# Outputs on stdout the CPU usage of the VM bearing PID `pid', or of all VMs
# previously selected by `vmps_init()'.
#
# This value is expressed as a percentage and reflects `ps'(1) "pcpu" field
# which is loosely defined as follow in POSIX.1-2008:
#
#   > The ratio of CPU time used recently to CPU time available in the same
#   > period, expressed as a percentage. The meaning of "recently" in this
#   > context is unspecified. The CPU time available is determined in an
#   > unspecified manner.
#
# The goal of this indicator is therefore more to get a rough idea of the
# relative load caused by virtual machines than to obtain any precise measure
#
# This value may be empty if the local `ps' command does not support the "pcpu"
# field (this is notably the case on BusyBox-based environments).
#
# See the POSIX page about `ps'(1):
# http://pubs.opengroup.org/onlinepubs/9699919799/utilities/ps.html#tag_20_96_10
#
vmps_get_pcpu() {
	[ "${1-}" = '--' ] && shift
	vmps_isinitdone || return 1
	vmps_get "$@" | awk -F "$vmps_fs" '{ print $4 }'
}

###
# vmps_get_pid [pid]
#
# Outputs on stdout the PID of the VM bearing PID `pid' (see bellow), or of all
# VMs previously selected by `vmps_init()'.
#
# Passing a PID parameter here can be useful to check whether a given is indeed
# a Qemu hypervisor process.
#
vmps_get_pid() {
	[ "${1-}" = '--' ] && shift
	vmps_isinitdone || return 1
	vmps_get "$@" | awk -F "$vmps_fs" '{ print $1 }'
}

###
# vmps_get_user [pid]
#
# Outputs on stdout the user owning the Wemu process of the VM bearing PID
# `pid', or of all VMs previously selected by `vmps_init()'.
#
vmps_get_user() {
	[ "${1-}" = '--' ] && shift
	vmps_isinitdone || return 1
	vmps_get "$@" | awk -F "$vmps_fs" '{ print $2 }'
}

###
# vmps_get_vsz [pid]
#
# Outputs on stdout the size of the virtual memory, in kilobytes, allocated to
# the VM bearing PID `pid', or to each of VMs previously selected by
# `vmps_init()'.
#
vmps_get_vsz() {
	[ "${1-}" = '--' ] && shift
	vmps_isinitdone || return 1
	vmps_get "$@" | awk -F "$vmps_fs" '{ print $3 }'
}

###
# vmps_init [-q] [-d vmhome_dir|-p pid|-u user]
#
# Initialize this library data by listing all Qemu processes running on the
# local system.
#
# To be recognized as such, the name of the Qemu binary execuabl must begin
# with the string "qemu-system-".
# There is no particular limitation regarding the path preceding the binary
# name (it is possible to test freshly compiled Qemu versions located in
# non-standard directories, see `$vm_qemu_cmd' setting).
#
# Filtering options:
#   -d vmhome_dir
#         Select the virtual machine from the home directory `vmhome_dir'.
#   -p pid
#         Select the virtual machine whose Qemu process bears the PID `pid'.
#   -u user
#         Match all virtual machines running as the user `user'.
#
# Only one filtering criteria can be used at a time.
# When no filtering options is given, all virtual machines running on the local
# host are selected.
#
# Options:
#   -q    Quiet: do not output error message on stopped VMs.
#
vmps_init() {
	local 'filter_crit' 'filter_val' 'opt' 'OPTARG' 'OPTIND' 'quiet'
	local 'vmhome_dir'
	filter_crit=''
	filter_val=''
	quiet='no'
	vmhome_dir=''

	OPTIND=1
	while getopts 'd:p:qu:' opt
	do
		if [ -n "$filter_crit" ]
		then
			echo  "ERROR (BUG): vmps_init: Too many arguments." >&2
			return 1
		fi
		case "$opt" in
			'd') # Find a process from the VM home dir path.
				vmhome_dir=$OPTARG
				;;
			'p') # Find a process from its PID.
				filter_crit='pid'
				filter_val=$OPTARG
				;;
			'q') # Quiet: do not output error message on stopped VMs.
				quiet='yes'
				;;
			'u') # Find all processes belonging to a certain user.
				filter_crit='user'
				filter_val=$OPTARG
				;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))

	# Deduce the PID from the VM home dir.
	if [ -n "$vmhome_dir" ]
	then
		if [ ! -s "${vmhome_dir}/${cfg_file_pid:?}" ]
		then
			if [ "$quiet" != 'yes' ]
			then
				echo "ERROR: ${OPTARG}/${cfg_file_pid}: File not found or" \
					"not readable, check that the virtual machine is" \
					"currently running." >&2
			fi
			return 1
		fi
		filter_crit='pid'
		filter_val=$( cat -- "${OPTARG}/${cfg_file_pid:?}" ) || return 1
	fi

	if [ "$filter_crit" = 'pid' ]
	then
		case "$filter_val" in *[!0-9]*)
			echo "ERROR: Invalid PID value: '${filter_val}'." >&2
			return 1
		esac
	fi

	# Autodetect `ps' features.
	if ps -e >/dev/null 2>&1
	then
		vmps_feat_posix='yes'
	else
		vmps_feat_posix='no'
	fi
	if ps -o pcpu >/dev/null 2>&1
	then
		vmps_feat_pcpu='yes'
	else
		vmps_feat_pcpu='no'
	fi
	if ps -ww >/dev/null 2>&1
	then
		vmps_feat_ww='yes'
	else
		vmps_feat_ww='no'
	fi
	cli_trace 4 "vmps_init: detected 'ps' features:" \
		"posix='${vmps_feat_posix}', pcpu='${vmps_feat_pcpu}'," \
		"ww='${vmps_feat_ww}'."

	# Execute 'ps'.
	if ! vmps_list_set -- "$filter_crit" "$filter_val"
	then
		echo "ERROR: Failed to get the process list." >&2
		return 1
	fi

	vmps_initdone='yes'

	if [ -n "$vmhome_dir" ]
	then
		if vmps_isempty || test "$( vmps_get_homedir )" != "$vmhome_dir"
		then
			if [ "$quiet" != 'yes' ]
			then
				echo "ERROR: ${vmhome_dir}: The virtual machine is not" \
					"currently running." >&2
			fi
			vmps_clear
			return 1
		fi
	fi
}

###
# vmps_isempty
#
# Returns 0 if at least one virtual machine has been selected.
#
# See also `vmps_init()' to check the filter to select running virtual machines.
#
vmps_isempty() {
	if ! vmps_isinitdone || test -n "$vmps_list"
	then
		return 1
	fi
}

###
# vmps_isinitdone
#
# This is an internal function for this library, it is not designed to be
# used by calling modules.
#
# This function ensures that `vmps_init()' has been correctly invoked by the
# caller.
#
vmps_isinitdone() {
	if [ "$vmps_initdone" != 'yes' ]
	then
		echo "ERROR (BUG): vmps functions invoked but not initialized." >&2
		return 1
	fi
}

###
# vmps_list_checkproc
#
# This is an internal function for this module and is not designed to be used
# by non-members.
#
# Try to make the commad-line information in `$vmps_list' more robust by using
# `/proc' tree.
#
# In particular, this functions ensures that:
#   - A more robust field separator than the space character is used. The
#     `$vmps_fs' variable is updated acordingly.
#   - Only one single field separator is used to separate two fields.
#   - This field separator is used to properly separate each parameters in the
#     command-line column of `$vmps_list'.
#
# Upon success, `$vmps_feat_proc' is set to "yes", othewise it is set to "no".
#
# This function always return 0 even if the tree cannot be read: in such case
# it jut leaves `$vmps_list' untouched.
#
vmps_list_checkproc() {
	local 'entry' 'newfs' 'newlist'

	# Process only once.
	if [ -n "$vmps_feat_proc" ]
	then
		return 0
	fi

	# Use the ASCII "Unit Separator" character as the new field separator.
	newfs=$( printf '\037' )

	if [ -r '/proc/self/cmdline' ]
	then
		vmps_feat_proc='yes'

		newlist=$(
			for entry in $( printf '%s' "$vmps_list" | awk -v OFS="$newfs" \
				'{ print $1,$2,$3,$4 }' )
			do
				pid=$( printf '%s' "$entry" | cut -d "$newfs" -f 1 )
				cmdline=$( tr "\000${newfs}" "${newfs}?" \
					<"/proc/${pid}/cmdline" ) || exit 1
				printf '%s\n' "${entry}${newfs}${cmdline}"
			done
		) || vmps_feat_proc='no'

		if [ "$vmps_feat_proc" = 'yes' ]
		then
			cli_trace 4 "vmps_list_checkproc: Using information from '/proc'."
			vmps_fs=$newfs
			vmps_list=$newlist
		else
			# Need to display an explanation to the user which should already
			# have got an automatic error message from the system.
			echo "WARNING: '/proc' tree ignored due to a read error." >&2
		fi
	else
		cli_trace 4 "vmps_list_checkproc: '/proc' tree missing or incomplete."
		vmps_feat_proc='no'
	fi
}

###
# vmps_list_set [filter_crit filter_val]
#
# This is an internal function for this module and is not designed to be used
# by non-members.
#
# This function executes `ps' relying on the various `$vmps_feat_*' variables
# to determine the exact command to execute.
#
# Upon success this function returns 0 and `$vmps_list' is updated, otherwise
# this function returns 1.
#
vmps_list_set() {
	local 'filter_crit' 'filter_val' 'psflags'
	[ "${1-}" = '--' ] && shift
	filter_crit=${1-}
	if [ -n "$filter_crit" ]
	then
		filter_val=${2:?"ERROR (BUG): vmps_list_set: Missing parameter."}
	fi
	psflags=''

	# `ps' uses spaces as fields separator.
	vmps_fs=' '

	# If `ps' supports POSIX options or more, we can ask it to do most of the
	# filtering job.
	if [ "$vmps_feat_posix" = 'yes' ]
	then
		case "$filter_crit" in
			'') str_list_add 'psflags' '-e' || return 1 ;;
			'pid') str_list_add 'psflags' '-p' "$filter_val" || return 1 ;;
			'user') str_list_add 'psflags' '-u' "$filter_val" || return 1 ;;
			*)
				echo "ERROR (BUG) : vmps_list_set: Invalid filter criteria:" \
					"'${filter_crit}'." >&2
				;;
		esac

		if [ "$vmps_feat_ww" = 'yes' ]
		then
			# `-ww' is not POSIX, but may be required to enable full output and
			# seems widely supported among feature-rich `ps' implementations.
			str_list_add 'psflags' '-ww' || return 1
		fi
	fi

	# Execute `ps'.
	if [ "$vmps_feat_pcpu" = 'yes' ]
	then
		str_list_add 'psflags' '-o' 'pid,user,vsz,pcpu,args' || return 1
		# 'ps' exit code is unusable: it returns '1' no matter if invalid
		# arguments were used, a temporary error occured or if everything
		# went fine but there is just no process mathing the criterion :( ...
		# SC2086: `$psflags' has been generated using `str_list_add()'.
		# shellcheck disable=SC2086
		vmps_list=$( ps $psflags ) || true
		vmps_list=$( printf '%s' "$vmps_list" \
			| awk '$5 ~ /^(.*\/)?qemu-system-/' )
	else
		str_list_add 'psflags' '-o' 'pid,user,vsz,args' || return 1
		# SC2086: `$psflags' has been generated using `str_list_add()'.
		# shellcheck disable=SC2086
		vmps_list=$( ps $psflags ) || return 1
		vmps_list=$( printf '%s' "$vmps_list" \
			| awk '$4 ~ /^(.*\/)?qemu-system-/ { print $1,$2,$3,"",$4 }' )
	fi

	# If `ps' is not POSIX, we still have to filter its output ourselves.
	if [ "$vmps_feat_posix" != 'yes' ]
	then
		case "$filter_crit" in
			'') ;;   # No filter to apply.
			'pid')
				vmps_list=$( printf '%s' "$vmps_list" \
					| awk -v PID="$filter_val" '$2 == PID' )
				;;
			'user')
				vmps_list=$( printf '%s' "$vmps_list" \
					| awk -v USER="$filter_val" '$1 == USER' )
				;;
			*)
				echo "ERROR (BUG) : vmps_list_set: Invalid filter criteria:" \
					"'${filter_crit}'." >&2
				;;
		esac
	fi
}

################################################################################
### /usr/local/lib/vmtools/vmps.inc.sh END
################################################################################
