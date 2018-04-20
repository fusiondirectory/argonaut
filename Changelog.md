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
