## *configure* modules

These modules are invoked during the virtual machine configuration process,
typically when the command `vmcreate` has been used to create a new virtual
machine or when the `vmup` command has been used to start a standalone image
file (booting an ISO live CD or URL for instance).

Most of these modules interactively prompts the user to set or select some
configuration values (or accept the default). Some of them however do not
prompt anything but instead apply some context-dependant automatic
configuration.

These files define the `mod_configure()` function.

Custom modules may range from helping to setup a few additional setting to a
larger wizard assisting the user in a fully custom virtual machine creation
process.


## Invocation

These modules are invoked at configuration time:

- When starting a standalone file or URL (eg. `vmup` applied on a .iso file).
- When creating a new virtual machine (`vmcreate`).

Templates configuration scripts are called first in order to update the list
of templates to be used. Settings configuration scripts are called as a second
step, once the selected templates have been applied.

None of these files is called when starting an already existing virtual machine.


## Implementation

This function takes no parameter, and directly affect the properties of the
current virtual machine:

- Templates configuration scripts update the list of template to be used using
  the `template_add()` and `template_set()` functions, they should
  not attempt to apply the template or otherwise modify the VM settings yet.
- Settings configuration scripts update the VM settings typically using the
  `settings_set()` function.