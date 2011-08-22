#!/bin/sh
###############################################################################

. /etc/argonaut/argonaut-support.lib
. /etc/argonaut/argonaut-agents.conf

# We're talking about this user
user=vador

# Get some user informations
if [ $(ldap_count "(uid=$user)") -eq 1 ]; then
	ldap_import "(uid=$user)"

	echo "Here is a list of ${ldap_import_cn[0]}'s phone numbers:"
    for n in $(seq 1 ${#ldap_import_telephoneNumber[@]}); do
		echo "$n: ${ldap_import_telephoneNumber[$n-1]}"
	done
else
	echo "Can't load entries for filter uid=$user"
	exit 1
fi

# Analyze the DISPLAY variable
echo "We are operating from host: $(get_hostname_from_display)"

# Group membership example
echo -n "User is member of the following groups: "
for group in $(ldap_get_group_membership_of $user); do
	echo -n "$group "
done; echo

# Application membership example
echo -n "User has the following applications assigned: "
for app in $(ldap_get_applications_of $user); do
	echo -n "$app "
done; echo


