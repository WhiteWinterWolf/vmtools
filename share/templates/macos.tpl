################################################################################
### /usr/local/share/templates/macos.tpl BEGIN
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
# This template sets base settings to allow booting the Intel version of Mac OS
# X operating system.
#
################################################################################

# TODO: Clarify the various IDE settings parameters
# TODO: Add a setting for the kernel parameters? Clarify its role.

# Enable handling of the MacOS specific features ($vm_macos_* settings).
vm_mod_buildcmd="$vm_mod_buildcmd macos"

# OSX VM minimum requirements.
vm_cpu_type="core2duo"
vm_ram_size="4G"

# Supplementary Qemu parameters.
vm_qemu_args="$vm_qemu_args -machine q35 -usb -device usb-kbd"

################################################################################
### /usr/local/share/templates/macos.tpl END
################################################################################