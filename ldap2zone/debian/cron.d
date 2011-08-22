PATH=/sbin:/bin:/usr/sbin:/usr/bin

@reboot   bind  /usr/sbin/ldap2bind
@hourly   bind  /usr/sbin/ldap2bind
