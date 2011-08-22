PATH=/sbin:/bin:/usr/sbin:/usr/bin

@reboot	root	ldap2repository -n -p;  [ -f /etc/fusiondirectory/fai/update-cronjob ] && sh /etc/fusiondirectory/fai/update-cronjob > /dev/null
@daily	root	ldap2repository -n -p;  [ -f /etc/fusiondirectory/fai/update-cronjob ] && sh /etc/fusiondirectory/fai/update-cronjob > /dev/null
