################################################################################
### /usr/local/share/modules/configure/template/prompt.inc.sh BEGIN
################################################################################
#
# Copyright 2017 WhiteWinterWolf (www.whitewinterwolf.com)
#f
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
# This module interactively asks the user to manually select vmtools templates.
#
# This module is not enabled by default.
#
################################################################################

mod_configure() {
	local 'ok' 'reply' 'templates_list'

	if [ "$cfg_ui_assumeyes" = 'yes' ]
	then
		templates_list=$( template_get_list ) || return 1
		cli_trace 3 "Using default templates: $templates_list."
		return 0
	fi

	reply=$noreply
	ok='no'
	while [ "$ok" != 'yes' ]
	do
		if [ "$reply" = '?' ]
		then
			# TODO: Find a clean way to associate a description to the templates.
			echo
			echo "TEMPLATES SELECTION"
			echo "Choose one or several templates, each template name must" \
				"be separated using space characters."
			echo "Available templates:"
			basename -s ".tpl" /usr/local/share/vmtools/templates/*.tpl
		fi
		templates_list=$( template_get_list ) || return 1
		printf '\nTemplates to use (default: %s)? ' \
			"$templates_list" >&2
		read reply || return 2

		case "$reply" in *[![:alnum:]_\ ]*)
				echo "ERROR: Invalid input: templates name can contain" \
					"only alphanumerical characters and underscores and" \
					"be separated by spaces." >&2
				continue
				;;
		esac

		if test -z "$reply"
		then
			ok='yes'
		else
			templates_list=$( str_explode -- "$reply" ) || return 1
			# SC2046, SC2086: Word splitting is expected on `$templates_list'.
			# shellcheck disable=SC2046,SC2086
			if template_apply -n -- $templates_list
			then
				ok='yes'
			fi
		fi
	done

	if [ -n "$reply" ]
	then
		# SC2046, SC2086: Word splitting is expected on `$templates_list'.
		# shellcheck disable=SC2046,SC2086
		template_set -- $templates_list || return 1
	fi
}

################################################################################
### /usr/local/share/modules/configure/template/prompt.inc.sh END
################################################################################
