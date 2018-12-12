## %"Argonaut 1.2.2" - 2018-12-12

### Added

#### argonaut
- argonaut#5729 argonaut-fai needs to support cryptsetup

### Changed

#### argonaut
- argonaut#5734 Merge 1001_add-documentation-key-to-service-files.patch from debian
- argonaut#5738 migrate changelog to changelog.md

## %"Argonaut 1.2.1" - 2018-04-20

### Added

#### argonaut
- argonaut#5695 No manpage is available for argonaut.conf

### Changed

#### argonaut
- argonaut#5690 Use ##no critic to desactive perlcritic on modules names not exactly the same as files names
- argonaut#5710 Support UTF-8 in user-reminder
- argonaut#5717 Change the url for the bug tracker into the argonaut manpages

### Removed

#### argonaut
- argonaut#5691 Remove the agent ldap backend for fusioninventory

### Fixed

#### argonaut
- argonaut#5679 Crash of argonaut-ldap2zone --slave when Ldap2zone slave list is empty on a DNS argonaut service
- argonaut#5681 argonaut-server is crashing on Debian Stretch
- argonaut#5693 add missing use if for json library selection
- argonaut#5696 argonaut-ldap2zone does not take the right SOA when refreshing a zone and its reverse
- argonaut#5700 argonaut-user-reminder has errors in ppolicy mode
- argonaut#5722 Error when we use argonaut-user-reminder

## %"Argonaut 1.2" - 2018-04-20

### Added

#### argonaut
- argonaut#5635 Document argonaut-client -X

### Changed

#### argonaut
- argonaut#5646 changing the library used to send mail in argonaut-user-reminder

### Fixed

#### argonaut
- argonaut#5402 documentation should explain limits of user-reminder with ppolicy
- argonaut#5513 netboot stayed in uninstall state
- argonaut#5523 Periodical schedule is not repeated
- argonaut#5541 Errors when trying to schedule actions
- argonaut#5544 Periodical jobs miss the first launch
- argonaut#5546 OPSI update software stay in deployement queue with "in progress" status
- argonaut#5558 Use some trim on argonaut.conf
- argonaut#5559 Argonaut client and server systemd service definition fails

## %"Argonaut 1.1" - 2017-04-06

### Added

#### argonaut
- argonaut#5332 argonaut-user-reminder should support ppolicy
- argonaut#5439 we should add the directive check-names into the argonaut-dns service
- argonaut#5440 argonaut-ldap2zone should be able to get data from a branch
- argonaut#5447 argonaut ldap2zone should be able to create config for dns slave also, but not create the data

### Changed

#### argonaut
- argonaut#5379 Argonaut should support fdMode instead of gotoMode for FD 1.1

## %"Argonaut 1.0" - 2017-01-23

### Added

#### argonaut
- argonaut#5281 create a function in argonaut to read correctly the fusiondirectory config

### Changed

#### argonaut
- argonaut#5275 redesign the argonaut-fusiondirectory tools
- argonaut#5288 function branch_exists should go into common.pm

### Fixed

#### argonaut
- argonaut#5273 Incompatibility between recovery password and user-reminder
- argonaut#5300 Errors when I try to start argonaut-client

## %"Argonaut 0.9.8" - 2016-11-13

### Added

#### argonaut
- argonaut#5059 module for creating samba shares

### Changed

#### argonaut
- argonaut#5147 removed man file created in pxelinux.cfg and replace it by a default file
- argonaut#5148 the default mode stored inside the argonaut-fuse should be used in argonaut-fuse

### Fixed

#### argonaut
- argonaut#5146 argonaut fuse is broken and doesnt add the  initrd=initrd.img-install line to pxe configuration for fai
- argonaut#5158 FAI_ARGONAUT variable is not used inside the script
- argonaut#5159 we should add some debug to the ldap query in fai.pm
- argonaut#5164 argonaut-fai-monitor typo

## %"Argonaut 0.9.7" - 2016-07-12

### Added

#### argonaut
- argonaut#4864 migrate the script for user-reminder to the argonaut-framework
- argonaut#4865 create argonaut-clean-audit to remove old audit entries from ldap

### Changed

#### argonaut
- argonaut#4995 put all fusiondirectory script inside the argonaut-fusiondirectory package

### Fixed

#### argonaut
- argonaut#4691 the systemd unit files have a syntax error

## %"Argonaut 0.9.6" - 2016-03-18

### Added

#### argonaut
- argonaut#4494 Add aaaa record in argonaut-ldap2zone
- argonaut#4506 Support for split horizon should be added
- argonaut#4607 add a --ldap2acl optkion in ldap2zone

### Changed

#### argonaut
- argonaut#4493 It would be nice to accept more than one reverse zone with argonaut-ldap2zone
- argonaut#4503 Merge reverse zone with argonaut-ldap2zone

### Fixed

#### argonaut
- argonaut#4513 Argonaut-ldap2zone have an perl error when we not have a reverse zone in the LDAP

## %"Argonaut 0.9.5" - 2016-01-07

### Changed

#### argonaut
- argonaut#4432 renomed and added the Service.systemd.pm and System.systemd.pm

### Fixed

#### argonaut
- argonaut#4293 Problem when I try to restart a service on Centos7

## %"Argonaut 0.9.4" - 2015-12-16

### Added

#### argonaut
- argonaut#4291 Error when I try to grab centos packages with an argonaut-server on centos

### Changed

#### argonaut
- argonaut#4323 generate-fusioninventory-schema should be renamed argonaut-generate-fusioninventory-schema
- argonaut#4355 Use App::Daemon for argonaut-fai-monitor and argonaut-fuse

### Removed

#### argonaut
- argonaut#4110 Remove all uses of gotoBootKernel

### Fixed

#### argonaut
- argonaut#4316 argonaut-freeradius-get-vlan doesnt look for Argonaut common.pm in the right place
- argonaut#4322 generate-fusioninventory-schema should read Agent/Inventory.pm directly from an installed fusioninventory-agent

## %"Argonaut 0.9.3" - 2015-09-25

### Added

#### argonaut
- argonaut#943 argonaut should work on ssl mode https
- argonaut#3803 ldap2zone needs an option to not write reverse zone
- argonaut#3945 Add a option to not touch at the reverse zone
- argonaut#4055 Rewrite initscript in systemd

### Changed

#### argonaut
- argonaut#2464 cleaning the argonaut debconf source
- argonaut#4048 read the configuration from argonaut-fai-monitor service
- argonaut#4049 split argonaut-fai-monitor in his own package
- argonaut#4166 update all manpages for 0.9.3

### Removed

#### argonaut
- argonaut#4053 the server is know to not work correctly into wheezy, so we must remove the libs for it from our repos

### Fixed

#### argonaut
- argonaut#3791 Add TXT values in global zone record
- argonaut#4046 I have an error in argonaut-fai-monitor log when I try to use it
- argonaut#4052 Argonaut-server must support that we send a MAC in uppercase

## %"Argonaut 0.9.2" - 2015-04-22

### Added

#### argonaut
- argonaut#2007 update action
- argonaut#2229 adding software on demand onto the opsi service
- argonaut#2906 debconf2ldif is missing an help option
- argonaut#3314 optional "named-checkconf -z" after running argonaut-ldap2zone on dns servers with output to see if configuration is correct
- argonaut#3328 argonaut documentation should be rewiewed and enhanced
- argonaut#3556 Support de Centos dans argonaut-common-fai
- argonaut#3612 argonaut fuse module fai should check if the system is lock or not
- argonaut#3662 Convert yumgroup to ldif
- argonaut#3714 argonaut-repository should have a --verbose option

### Changed

#### argonaut
- argonaut#3390 rename ldap2fai into argonaut-ldap2fai to remove potential clash with the goto software from gonicus
- argonaut#3481 adding centos/rpm support to argonaut Packages.pm library
- argonaut#3526 add a switch to select the good library when in wheezy or jessie for argonaut-client
- argonaut#3576 clean and rename the freeradius argonaut code
- argonaut#3611 we should merge fai-monitor and argonaut-fai-monitor
- argonaut#3646 argonaut-fuse should be cleaned up
- argonaut#3664 Daemon for argonaut-fai-monitor
- argonaut#3707 update all man pages to 0.9.2 and adapt date also

### Removed

#### argonaut
- argonaut#2454 gotoLdapServer seems unused
- argonaut#3665 remove debconf code as it is glpv3 only

### Fixed

#### argonaut
- argonaut#2577 Reboot with Opsi Client
- argonaut#3146 OPSI havewrong module place
- argonaut#3155 when I want to configure OPSI softwarelist with FD I got  : Erreur: Request error: Error : No such a method : 'Argonaut.ClientDaemon.Modules.OPSI.get_localboots'.
- argonaut#3286 put comment around pod explanation in argonaut-server to correct error in manpage
- argonaut#3541 fail2ldif manpage is wrong in the description
- argonaut#3543 when asking for the help of the fai2ldif command we get an extra h 1
- argonaut#3558 argonaut-common-fai - Création de partition LVM
- argonaut#3649 fai2ldif -o missed some information
- argonaut#3656 fai2ldif doesnt convert the script associated to a class inside a class
- argonaut#3658 logfile name is wrong in argonaut-repository
- argonaut#3661 fai2ldif creates a package list even if there is no need
- argonaut#3668 timeout when using distant repository for debian packages
- argonaut#3697 Ask task id back with the error "This task does not exists"
- argonaut#3715 argonaut2repository tell it cannot find parent servers of parent servers
- argonaut#3717 https://documentation.argonaut-project.org/en/documentation_admin/argonaut_protocol

## %"Argonaut 0.9.1" - 2014-06-24

### Added

#### argonaut
- argonaut#319 add an option to ldap2repository to have a debian installer mirror also
- argonaut#323 add new option to ldap2fai
- argonaut#744 rewrite ldap2zone in perl
- argonaut#926 we need to add the custom release management for creating the source.list with ldap2fai
- argonaut#1426 (re)start and stop buttons should not depend on some weird LDAP field
- argonaut#1915 - opsi management argonaut server module
- argonaut#1954 OPSI module should be able to handle global import
- argonaut#1967 OPSI module should allow to get info about products
- argonaut#1973 OPSI module should handle Deployment.reinstall action
- argonaut#1989 OPSI module shoud be able to report task progress and errors
- argonaut#2151 for opsi we need to manage list of products
- argonaut#2274 quota must be considered as a classic daemon
- argonaut#2330 Add a param to launch argonaut in debug mode
- argonaut#2459 create an argonaut-client module for dovecot
- argonaut#2887 adding manpages and licence
- argonaut#2905 ldap2fai should have a mode when given a directory containing fai config file it make ldif out of them
- argonaut#2911 argonaut server service should have an option to not get packages even if a mirror is created in FusionDirectory
- argonaut#2965 create a replacement for fai-monitor-gui that send status about fai client to argonaut
- argonaut#2972 Argonaut doesn't do TLS (with beginnings of patch)
- argonaut#2992 we need a subroutine in ldap2fai to create dirs in the config space of fai client
- argonaut#3046 adding three variable into argonaut-nfsroot-integration
- argonaut#3093 add an option to not refresh zone when running ldap2zone from console
- argonaut#3094 add an option to wirte the zone file in an other location for testing purpose
- argonaut#3166 put back the opsi.pm argonaut server component back into argonaut 0.9.1
- argonaut#3167 put back the opsi.pm fuse component back into argonaut 0.9.1
- argonaut#3180 fai2ldif misses a man page
- argonaut#3183 argonaut-fai-monitor need a manpage

### Changed

#### argonaut
- argonaut#571 Depends change to allow better upgrading
- argonaut#723 create a service for argonaut
- argonaut#743 we must create a service to store the config of all the argonaut tools
- argonaut#747 renaming ldap2zone package to argonaut-ldap2zone and cleaning it
- argonaut#876 the argonaut server is fixed to i386 only is should get this data from the ldap in the attribute argonautMirrorArch
- argonaut#882 Architectures should be in FAIrepository value
- argonaut#887 the protocol of json rpc (http or https) should not be encoded in the code and be saved into the ldap
- argonaut#911 ldap2fai need to read is config from argonaut.conf
- argonaut#925 Service names should go into the LDAP
- argonaut#1016 Argonaut should ease client extension
- argonaut#1348 zone file and  named filed are in the same folder
- argonaut#1486 replace console-tools by console-utilities in argonaut-fai-nfsroot
- argonaut#2023 OPSI profile should allow to select the requested action
- argonaut#2048 putting the deconf perl code in a argonaut-debconf package
- argonaut#2059 putting the freeradius perl code in a argonaut-freeradius package
- argonaut#2239 Argonaut should not schedule immediatly scheduled only actions
- argonaut#2889 cleanup copyright and manpages
- argonaut#2891 move code into the correct directories
- argonaut#2961 make-fai-nfsroot is now called fai-make-nfsroot
- argonaut#2968 removing the argonaut-fai-client package and moving tools into argonaut-nfsroot packages
- argonaut#2985 group membership checking in argonaut-fuse should be reworked
- argonaut#2990 moving the get-config-dir-argonaut to the argonaut-fai-nfsroot package
- argonaut#2995 options of ldap2fai should be reorganised to be more logical
- argonaut#2999 the protocol is stored as http inside the argonautProtocol attribute but the code does no add :// after it
- argonaut#3001 remove fixed code inside ldap2fai
- argonaut#3003 redo the get-config-dir-argonaut to make it more standard
- argonaut#3004 Config file read code is duplicated
- argonaut#3016 rename argonaut-apply-quota to argonaut-quota to be more in sync with all the tools
- argonaut#3017 rename argonaut-client-fai-getid to remove the fai inside the name
- argonaut#3025 moving fai2ldif to argonaut-fai-server
- argonaut#3130 add a switch to select the good library when in wheezy or jessie for argonaut-client

### Removed

#### argonaut
- argonaut#1485 removed man pages for argonaut.conf now that everything is in ldap
- argonaut#2236 remove the old and crappy argonaut-agents and argonaut-cd
- argonaut#2237 removed all debian packaging info from the various programs
- argonaut#2890 remove old code
- argonaut#2959 removing argonaut-fai-progress
- argonaut#2960 removing argonaut-fusioninventory
- argonaut#2974 Useless functions in Argonaut::Common
- argonaut#2975 argonaut-fuse is using old code and should be migrated to argonaut-common ldap code
- argonaut#2976 removing old obsolete option from argonaut-fuse
- argonaut#2982 remove tftp_static_root fonctionnality from argonaut-fuse
- argonaut#2983 remove commented module option loading
- argonaut#2986 remove old integration scripts inside the nfsroot
- argonaut#3018 argonaut-client-fai-sendmon should be removed now that we are using argonaut-fai-monitor to integrate directly with faimond
- argonaut#3139 since argonaut-fai-monitor argonaut-getid is not needed anymore

### Fixed

#### argonaut
- argonaut#186 ldap2bind
- argonaut#498 ldap2zone when given ldap:/// return nothing
- argonaut#525 /var/log/argonaut not created
- argonaut#574 MAC address shouldn't be case sensitive
- argonaut#575 ldap2fai should be called with -m
- argonaut#579 argonaut-fuse doesn't include reqd info in boot config
- argonaut#583 FAIstate stuck at "install"
- argonaut#738 Only one repository line by server is used
- argonaut#871 the cron mirror-update-cronjob is broken and doesnt get the repositories
- argonaut#908 Only one section and one arch is used per repo
- argonaut#912 ldap2repository doesnt get correctly the data for the 4th repo
- argonaut#993 there is an uninitialized value used in Ldap2zone.pm
- argonaut#995 argonaut server doesnt remove its pid like it should
- argonaut#996 argonaut-client doesnt remove his pid like it should
- argonaut#1001 there is no checking of correct execution of the system call in clientdaemon.pm
- argonaut#1319 i c annot stop the argonaut client
- argonaut#1320 server and client don't start at boot time
- argonaut#1342 description in argonaut-quota package is wrong
- argonaut#1344 argonaut-apply-quota as a wrong name inside command
- argonaut#1364 mirror-update-cronjob couldn't be executed
- argonaut#1373 MX record isn't read and not write in bind config
- argonaut#1376 There is a wrong error message
- argonaut#1413 server_settings should contain ip
- argonaut#1428 make all init script lsb compatible
- argonaut#1543 wrong error message when starting argonaut client
- argonaut#1544 when start the argonaut agent on a debian squeeze
- argonaut#1641 when using argonaut-ldap2zone, only the first record is taken ( for NS and MX record)
- argonaut#1918 we renamed argonaut-client management to argonaut-client but forgot to rename log file
- argonaut#1919 we renamed argonaut-client management to argonaut-client but forgot to rename pid name
- argonaut#1963 Can't use string ("MY.DOMAINS.") as an ARRAY ref while "strict refs" when reloading zone trough FD
- argonaut#2001 incompatibility between argonautClient and OPSI service
- argonaut#2005 error when try to import opsi server - argonaut server 1.0-1~1302211055
- argonaut#2032 clean the fai classes in ldif format to be more easy to use
- argonaut#2264 argonaut-apply-quota not functionnal
- argonaut#2345 on an windows workstation in fd without dns the argonaut opsi module trigger an error
- argonaut#2455 Argonaut FAI server module is not working
- argonaut#2909 Could not download deb http://debian.der.edf.fr/debian-security//dists/wheezy/main/binary-amd64/Packages.bz2 in the case of an update repository
- argonaut#2964 clean the argonaut-fai-server source
- argonaut#2980 in argonaut-fuse when it create the file to be put in pxeling.cfg it doesnt put the ip in the commentary
- argonaut#2981 in argonaut-nfsroot-integration script we can not symlink vmlinuz-install and initrd.img
- argonaut#2991 bug with verbose mode in fai when running ldap2fai
- argonaut#2994 ldap2fai crash when trying to export variables
- argonaut#3000 error in the filter when running argonaut-server and FAi module
- argonaut#3008 perl error : Global symbol "$client_ip"
- argonaut#3009 perl error : Global symbol "$server_ip"
- argonaut#3010 error when trying to create the cronjob for creating debian mirror
- argonaut#3012 Name "main::ID" used only once: possible typo at /usr/sbin/argonaut-fai-monitor line 98, <DATA> line 558.
- argonaut#3013 argonaut-repository make use of /usr/lib/argonaut, but it doesnt exist anymore
- argonaut#3043 OPSI.pm needs a task_processed method
- argonaut#3057 argonaut-server doesn't run
- argonaut#3062 argonaut-fuse
- argonaut#3068 Weird issues with custom ldap.conf in argonaut.conf
- argonaut#3069 fai.conf isn't copied in the livefs when runninf fai-setup
- argonaut#3070 argonaut.conf copied on new FAI setup isn't correct (wrong IP)
- argonaut#3101 Can't call method "start_tls" on an undefined value at /usr/share/perl5/Argonaut/Libraries/Common.pm line 176
- argonaut#3119 argonaut.conf isn't copied in right place during fai-setup
- argonaut#3131 add a switch to select the good library when in wheezy or jessie for argonaut-server
- argonaut#3133 fetching list of package
- argonaut#3135 all the argonaut tools should check for the presence of the console tools they need and abort if not present
- argonaut#3142 Clearer error messages are needed for fai-monitor
- argonaut#3143 the fai installing does not work
- argonaut#3176 Switch modules is uselessly loaded

### Security

#### argonaut
- argonaut#2973 error message in argonaut tools should not send critical data to the console

## %"Argonaut 0.9" - 2013-11-29

### Added

#### argonaut
- argonaut#2022 OPSI profile should allow to set product properties
- argonaut#2468 adding the perl ldap libraries needed for the argonaut-debconf module
- argonaut#2539 Wake on lan is not working anymore
- argonaut#2591 We should have a plugin for FusionInventory

### Changed

#### argonaut
- argonaut#763 The code for applying should go trought argonaut
- argonaut#879 the cleanup option should be removed from the argonaut config service because its mandatory
- argonaut#895 split the argonautconfig service
- argonaut#1468 Argonaut-fuse should let modules read their own config
- argonaut#1707 argonaut-server should use modules for handling clients
- argonaut#2073 making argonaut multithreaded
- argonaut#2328 opsiClient should be object group compliant
- argonaut#2428 opsi multithread
- argonaut#2880 split argonautes client in a different directory
- argonaut#2881 move libraries into argonaut / libraries
- argonaut#2883 cleanup copyright and manpages

### Removed

#### argonaut
- argonaut#2465 Argonaut::Fuse::Common is unused
- argonaut#2737 removing the ltsp code
- argonaut#2882 remove argonaut-agents leftover

### Fixed

#### argonaut
- argonaut#915 Different arch means duplicated versions number
- argonaut#987 argonaut-ldap2zone doesnt check return code of bind comands
- argonaut#1002 clientdaemon.pm does not log his actions
- argonaut#1105 argonaut-fuse should use the same method to load his plugin with module::plugable
- argonaut#1677 named.conf.ldap2zone pas mis par defautl dans /etc/bind/named.conf.local
- argonaut#1706 get_generic_settings should check group config
- argonaut#1920 ldap2zone could have better error messages
- argonaut#1962 when removing a windows pc, it should be removed from opsi if activated
- argonaut#1966 argonaut-server is not encoding in utf-8 its JSON answer
- argonaut#2016 when a system is locked there sould be no order send to him
- argonaut#2231 Problem with argonaut-repository?
- argonaut#2322 don't remove opsi-client-agent from winstation
- argonaut#2372 We can't reboot argonaut machines
- argonaut#2398 script generated by argonaut-repository not functional
- argonaut#2401 argonaut-repository error when verbose is unchecked
- argonaut#2427 Invalid value for shared scalar
- argonaut#2469 File::Pid usage is wrong in argonaut-fuse
- argonaut#2472 argonaut-fuse silently fail if the folder is already mounted
- argonaut#2572 argonaut tell me i have several ip associated to a computer when no argonaut server is activated
- argonaut#2886 getipfrommac should use the ldapbase + the sytem branch


