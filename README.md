# vmtools

*vmtools* is a Qemu virtual machines manager which strives to be **easy**,
**versatile** and **modular** while adhering to the
**principle of least privileges**, to respect users' freedom and security.

It offers advanced features such as the ability to freely fork and merge
virtual machines, is extensible through the use of plugins and templates,
respects your security by not using any root daemon and is entirely
developed using POSIX Shell.


# Get it

*vmtools* is [freely available][github] (GPL v3).

Latest news on the project can be found on the [project's main page][news].

[news]: https://www.whitewinterwolf.com/tags/vmtools/
	"vmtools project homepage"

[github]: https://github.com/WhiteWinterWolf/vmtools/
	"vmtools page on GitHub"


# Documentation

## Guided tour

-	[Part 1 - introduction and basic usage][tour1]:
	Install vmtools and use vmup to boot disk image files.
-	[Part 2 - manage virtual machines][tour2]:
	Fork, merge, move, rename and delete virtual machines.


[tour1]: https://www.whitewinterwolf.com/posts/2017/09/18/vmtools-guided-tour-part-1-introduction-and-basic-usage/
	"vmtools guided tour, part 1: introduction and basic usage"
[tour2]: https://www.whitewinterwolf.com/posts/2017/09/21/vmtools-guided-tour-part-2-manage-virtual-machines/
	"vmtools guided tour, part 2: manage virtual machines"


## Man pages

The man pages cover regular usage of *vmtools*:

-	[Overview][vmtools] (*vmtools(7)*) provides a high level description of *vmtool* features,
	from its design to its customization.

-	[Configuration][vmtools.conf] (*vmtools.conf(5)*) contains a reference guide on *vmtools*
	configuration.

-	User commands:

	| Command      | Description                                              |
	|--------------|----------------------------------------------------------|
	| [vmcp][]     | Copy or fork virtual machines.                           |
	| [vmcreate][] |  Create a new virtual machine.                           |
	| [vmdown][]   | Shutdown a virtual machine.                              |
	| [vmfix][]    | Detect and fix virtual machines issues.                  |
	| [vmfork][]   | Copy or fork virtual machines.                           |
	| [vminfo][]   | Report information on a virtual machine.                 |
	| [vmmerge][]  | Merge two related virtual machines.                      |
	| [vmmon][]    | Access the Qemu monitor shell of a virtual machine.      |
	| [vmmv][]     | Move or rename a virtual machine home directory.         |
	| [vmps][]     | Report information on running virtual machines.          |
	| [vmrm][]     | Delete a virtual machine home directory.                 |
	| [vmrndmac][] | Generate a random MAC address.                           |
	| [vmup][]     | Start virtual machine or a bootable file or media.       |

[vmtools]: https://www.whitewinterwolf.com/man/7/vmtools/
[vmcp]: https://www.whitewinterwolf.com/man/1/vmcp/
[vmcreate]: https://www.whitewinterwolf.com/man/1/vmcreate/
[vmdown]: https://www.whitewinterwolf.com/man/1/vmdown/
[vmfix]: https://www.whitewinterwolf.com/man/1/vmfix/
[vmfork]: https://www.whitewinterwolf.com/man/1/vmfork/
[vminfo]: https://www.whitewinterwolf.com/man/1/vminfo/
[vmmerge]: https://www.whitewinterwolf.com/man/1/vmmerge/
[vmmon]: https://www.whitewinterwolf.com/man/1/vmmon/
[vmmv]: https://www.whitewinterwolf.com/man/1/vmmv/
[vmps]: https://www.whitewinterwolf.com/man/1/vmps/
[vmrm]: https://www.whitewinterwolf.com/man/1/vmrm/
[vmrndmac]: https://www.whitewinterwolf.com/man/1/vmrndmac/
[vmup]: https://www.whitewinterwolf.com/man/1/vmup/
[vmtools.conf]: https://www.whitewinterwolf.com/man/5/vmtools.conf


## Other documentation sources

For developers and more advanced users:

-	Several *README.txt* files provide more information on the project tree as
	well as guidance on plugins and templates development.

-	As last resort, you can directly check the code.
	I documented in a way which, I hope, will make it easy for you to find the
	information you are looking for.


# Upcoming features

Here are the main planned features:

-	**Rank 1**:
	-	Support of guests sleep mode, including starting sleeping guests in
		snapshot mode (ie. restore the same content to RAM on each start).
	-	Add a command to easily insert/eject removable medias while a guest is
		running.

-	**Rank 2**:
	-	Develop templates and features (including floppy drives) to both
		support legacy guests and offer better performance for modern ones
		(disk I/O in particular may be easily improvable).

-	**Rank 3**:
	-	Implement auto-snapshoting: automatically keep the last *n* snapshots
		to allow easier guest rollback.

*vmtools* is currently in early development stage, in particular expect
settings names and default values to change.


# Report an issue

Please send bug reports to the [vmtools issues page][issues] on GitHub.


[issues]: http://github.com/WhiteWinterWolf/vmtools/issues
	"vmtools issues (GitHub)"
