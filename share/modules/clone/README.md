## *clone" modules

These modules are invoked during virtual machines copying process, typically
when the command `vmcp` or `vmfork` has been used (see *lib/vmcp.inc.sh*).

These modules review the settings of the destination virtual machine, updating
some settings and letting other to be inherited from the source virtual machine.

The modules are named after the `$vm_*` settings they are updating, and are
enabled through the `$cfg_modules_clone`setting.

The modules enabled by default are the following ones:

    cfg_modules_clone="networking_iface_mac storage_backend"

The default *clone* modules are not order dependant.

Custom modules may be used to implement any kind of new behavior related to
virtual machine cloning, for instance maybe forked virtual machines may not use
the same display server port than the base ones, they may use a specific
template depending on the user cloning it, etc.


### Customization

These modules implement a `mod_clone()` function which takes no parameter but
modify `$vm_*` variable to alter the copied virtual machine settings.

Moreover, the two following variable may be important to determine the
processing workflow:

 - `$vmcp_clone_inherit`: If set to *yes*, the user has request for the copied
   virtual machine to keep the same unique settings as the source one.
 - `$vmcp_action`: Define the current copy type, it may be either:
   - *copy*: This is the default copy type, the copied vitual machine shares
     the same parent as its source.
   - *fork*: The copied virtual machine is a fork of its source and use it as
     a direct parent.
   - *autonomous copy*: The copied virtual machine has no parent.

 Use `settings_override()` to properly override the virtual machine settings.

Here is a commented example (taken from *networking_iface_mac.inc.sh*):

	mod_clone() {
		local 'child_value' 'entry' 'src_value' 'setting'

		# Random MAC address is done for the sole purpose of ensuring that
		# two VM do not share the same MAC address.
		# If the user wants both VM to keep the same unique features, we must
		# keep the same VM and therefore have nothing more to do.
		if [ "$vmcp_clone_inherit" = 'yes' ]
		then
			return 0
		fi

		# We cycle through each MAC addresses defined in the currently active
		# VM settings.
		for entry in $( set | grep '^vm_networking_iface[0-9]\+_mac=' )
		do
			# `$setting' gets the setting name.
			setting=${entry%%"="*}
			# `$src_value' gets the current setting value, ie. the value from
			# the source VM.
			src_value=$( str_unescape -- "${entry#*"="}" ) || return 1
			if [ -z "$src_value" ]
			then
				continue
			fi

			# We do some stuff, here generating a new MAC address.
			child_value=$( net_random_mac ) || return 1

			# We use `settings_override()' to properly override VM settings
			# with the new value.
			settings_override "$setting" "$child_value"
		done
	}
