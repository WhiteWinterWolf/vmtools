################################################################################
### /usr/local/lib/vmtools/template.inc.sh BEGIN
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
# This library allows to apply virtual machines templates and manage a list
# of selected templates.
#
# Functions taking a template name as parameter accept only a name, not a path.
# A valid template name may be composed of the following characters:
#   - Alphanumeric characters.
#   - Underscore.
#
# The template is located in the `template' subdirectory in the locations
# searched by the `include_module()' function.
#
# A template file shares the same characteristic as a VM settings file except
# that it cannot use the `parent' keyword. It is allowed for a template to
# invoke another template to implement a form of template inheritance.
#
# Public functions:
#   template name...
#         Apply a template and add it to the selected templates list.
#   template_add name...
#         Add a template to the selected templates list.
#   template_apply [-n] [name...]
#         Apply a template (apply all selected templates by default).
#   template_get_list
#         Get the list of selected templates names.
#   template_isempty
#         Check if the selected templates list is empty.
#   template_set name...
#         Replace the content of the selected templates list.
#
################################################################################

################################################################################
# Global variables
################################################################################

# List of templates to apply (see `template()' below).
# This is a simple space separated list of template names to be fed to the
# `template()' function (the same function used in VM settings files).
# Do not directly access this variable, use `tmeplate_*()' functions instead.
template_list=''

# Template nesting level.
# This variable is increased for each new nested template and allows to detect
# infinite loops.
# It is also used by `parent()' to ensure that it is not called from within
# a template.
# TODO: The direct access from `parent' is dirty, if this is a recurrent need
# create a proper getter or check function.
template_nestinglvl=0


################################################################################
# Functions
################################################################################

###
# template name...
#
# Apply the template named `name', and add it to the list of selected templates.
# Do nothing if no parameter is provided.
#
# This function is intended to be used as a keyword in VM settings files.
#
# This function expects only templates names as parameters, file paths are
# rejected as errors.
#
# See also `template_add()' to add a template without applying it.
# See also `template_apply()' to apply a template without adding it.
#
template() {
	[ "${1-}" = '--' ] && shift
	if [ $# -gt 0 ]
	then
		template_add -- "$@" || return 1
		template_apply -- "$@" || return 1
	fi
}

###
# template_add name...
#
# Add a new template to the list of selected templates.
#
# Template existence is not checked by this function but later upon templates
# execution. Use `template_apply -n...` before this one if you need to check
# them.
#
# This function expects only templates names as parameters, file paths are
# rejected as errors.
#
# See `templates_set()' to replace the selected template list content.
# See `template()' to also apply added templates.
#
template_add() {
	local 'name'
	[ "${1-}" = '--' ] && shift

	for name
	do
		case " ${template_list} " in
			*" $name "*)
				# Template already in the list.
				;;
			*)
				case "$name" in *[![:alnum:]_]*)
					echo "ERROR: ${name}: Invalid template name (it must" \
						"contain only alphanumeric and underscore" \
						"characters)." >&2
					return 1
				esac
				template_list="${template_list:+"${template_list} "}${name}"
				;;
		esac
	done
}

###
# template_apply [-n] [name...]
#
# Apply the template named `name', or previously selected templates if
# no parameter is provided.
#
# This function does not alter the list of selected templates.
#
# See `template()' to also add applied template to the list of selected
# templates.
# See `template_add()' to only add a template to the list.
#
# Options:
#   -n    Do not apply the template, only check the names validity.
#
template_apply() {
	local 'include_opts' 'opt' 'OPTARG' 'OPTIND' 'toapply'
	[ "${1-}" = '--' ] && shift
	include_opts=''

	OPTIND=1
	while getopts 'n' opt
	do
		case "$opt" in
			'n') include_opts='-n' ;;
			*) return 1 ;;
		esac
	done
	shift $(( OPTIND - 1 ))

	if [ $# -gt 0 ]
	then
		case "$*" in *[![:alnum:]_${IFS}]*)
			invalid=''
			for name
			do
				case "$name" in *[![:alnum:]_]*)
					invalid="$invalid ${name}"
				esac
			done
			printf 'ERROR: Invalid template names:%s.\n' "$invalid" >&2
			return 1
		esac

		toapply=$*
	else
		toapply=$( template_get_list ) || return 1
	fi

	if [ -n "$toapply" ]
	then
		if [ "$template_nestinglvl" -ge "${cfg_limit_nesting:?}" ]
		then
			echo "ERROR: A loop has been detected in templates nesting." >&2
			echo "Current templates:" >&2
			printf '    %s\n' "$toapply" >&2
			return 1
		fi

		template_nestinglvl=$(( template_nestinglvl + 1 ))
		# SC2086: Special characters are forbidden in templates names.
		# shellcheck disable=SC2086
		toapply=$( printf 'templates/%s.tpl\n' $toapply )
		# shellcheck disable=SC2086
		include_module ${include_opts:+"$include_opts"} -- $toapply || return 1
		template_nestinglvl=$(( template_nestinglvl - 1 ))
	fi
}

###
# template_get_list
#
# Outputs the content of the selected templates list on stdout.
#
# The outputed list is a space separated words-list suitable to be used as
# argument to the `template' keyword in VM settings files.
#
# See `template_isempty()' as a more efficient way to check if the templates
# list is empty.
#
template_get_list() {
	str_explode -- "$template_list" || return 1
}

###
# template_isempty
#
# Return 0 if the selected templates list is empty.
#
# This function allows to check if a virtual machine relies on any template
# after having loaded its VM settings files.
#
# See `templates_get_list()' to get the content of the selected templates list.
#
template_isempty() {
	test -z "$template_list"
}

###
# template_set name...
#
# Replace the content of the selected templates list.
#
# Use an empty string as `name' to clear the selected templates list.
#
# Template existence is not checked by this function but later upon templates
# execution. Use `template_apply -n...` before this one if you need to check
# them.
#
# See `templates_get_list()' to get the content of the selected templates list.
# See `templates_add()' to add new entries to the templates list without
# loosing existing ones.
#
template_set() {
	local name
	[ "${1-}" = '--' ] && shift

	case "$*" in *[![:alnum:]_${IFS}]*)
		echo "ERROR: ${name}: The template names contain an invalid character" \
			"(it must contain only alphanumeric and underscore characters)." >&2
		return 1
	esac

	template_list="$*"
}


################################################################################
### /usr/local/lib/vmtools/template.inc.sh END
################################################################################
