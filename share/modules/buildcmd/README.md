## *buildcmd* modules

These modules are invoked just before booting a virtual machine, typically when
a command such as `vmup` or `vmcreate` has been used (see *lib/vmup.inc.sh*).

These modules read the virtual machine settings and build the final Qemu
command-line to execute in order to boot the guest system.

They are named after the `$vm_*` settings they are using to generate the
correspoding Qemu options, and are enabled through the `$cfg_modules_buildcmd`
setting.

The modules enabled by default are the following ones:

	cfg_modules_buildcmd="qemu boot cpu display keyboard monitor name \
		networking ram storage_cdrom storage_hdd"

The *qemu* module should remain one of the first invoked module as it generates
the Qemu command itself (`qmue-system-*`). Other than that default *buildcmd*
modules are not order dependant.

Custom modules will typically be used when new settings name have been added,
or if one wants to change the behavior of an existing setting (for instance
to make all monitor socket files stored in a unique location instead of the
virtual machines home directory).


### Customization

These module implement a `mod_buildcmd()` function which take as parameter the
name of a variable (usually `$cmd`, see `vmup_runqemu()`, but don't rely on
this).

This variable stores the complete Qemu command-line as it is being built by
these modules, therefore one module has access to the part of the command
already created by previous modules and may either check or modify it at will.

However, the most common operation will be simply to check the value of some
`$vm_*` VM setting variables and append the matching Qemu command-line
parameters.

Note that certain Qemu options use commas as parameters separator. You
need to escape any variable part of such parameter using `str_escape_comma()`.

Here is a commented example (taken from *cpu.inc.sh*):

	mod_buildcmd() {
		local 'ret' 'varname'
		# This module expect a variable name as mandatory parameter.
		varname=${1:?"ERROR (BUG): mod_buildcmd: Missing parameter."}
		# Get the value of the variable whose name is stored in `$varname'.
		eval "ret=\$$varname"
		# `$ret' now contains the Qemu command-line in its current shape.

		# Check if various VM settings are efined and complete the Qemu
		# command-line accordingly.
		if [ -n "$vm_cpu_count" ]
		then
			# We add `-smp $vm_cpu_count' to the Qemu command-line.
			str_list_add 'ret' '-smp' "$vm_cpu_count" || return 1
		fi
		if [ -n "$vm_cpu_type" ]
		then
			# The same way we add `-cpu $vm_cpu_type' to the Qemu command-line.
			str_list_add 'ret' '-cpu' "$vm_cpu_type" || return 1
		fi

		# Now affect the updated command-line to the caller's variable whose
		# name is stored in `$varname'.
		eval "$varname=\$ret"
	}
