# Argonaut

[Argonaut][Argonaut] Manage your systems, services and also Integrate FusionDirectory backend Fonctionnalities

[Argonaut][Argonaut] is an effective tool for managing services, systems, task.

Integrate Argonaut with your own tools or with deployment tools like [FAI], [OPSI], Debconf.

## Features

Argonaut is a modular client/server system based on JSON-RPCprotocol. Both client and server sides can load modules at start. Argonaut has two primary functions.

### Run a given operation on a system through a client

Two basic functions: restart service and switch on/off a system. 

Modules can provide some more functionalities :

* argonaut-ldap2zone: update a dns zone, create view, create acls
* argonaut-quota: apply a quota
* argonaut-fai-mirror: create a synchronization script Mirror
* argonaut-fai-monitor: follow FAI installation and report states to FusionDirectory
* argonaut-dovecot: create the mailbox quota and applies it
* argonaut-user-reminder : to manage the accoun reminder plugin of FusionDirectory
* argonaut-clean-audit : to clean the audit branch of FusionDirectory
* argonaut-user-reminder : to send email reminder coordonated with the user-reminder plugin of FusionDirectory

### Allow integration with deployment tools [FAI], [OPSI], Debconf

* FAI integration (argonaut-server-module-fai and argonaut-common-fai) and the complement to integrate into the nfsroot and FAI server (argonaut-fai-nfsroot argonaut-fai-server, argonaut-fai-mirror)
* OPSI integration (argonaut-server-module-opsi)
* Manage the pxelinux.cfg directory using argonaut-fuse (argonaut-fuse-fai-module and argonaut-fuse-opsi-module): get information and create pxelinux.cfg file that matches the type of machine to be deployed, allowing automatic boot during an install by pxe

## Get help

There are a couple ways you can try [to get help][get help].You can also join the `#fusiondirectory` IRC channel at freenode.net.

You can [register on our system][register] and enter your bug [on the forge][issues-forge] or [here at github][issues-github] even if the forge is the prefered way of dealing with bugs

## IRC Etiquette

* If we don't answer right away then just hang out in the channel.  Someone will
  eventually write back to you as it just means we are away from keyboard,
  working on something else, or in a different timezone than you.
* You should treat IRC as what it is: asynchronous chat.  Sure the messages can
  be instant but in most channels people are in different time zones.  At times
  chat replies can be in excess of 24hrs.
  
## Donate

If you like [Argonaut][Argonaut] and would like to [donate][donate-liberapay] even a small amount you can go to our Liberapay account
  
## License

[Argonaut][Argonaut] is  [GPL 2 License](COPYING).

[Argonaut]: https://www.argonaut-project.org/

[FAI]: http://fai-project.org/

[OPSI]: http://opsi.org/en/

[get help]: https://www.fusiondirectory.org/contact-us/

[register]: https://register.fusiondirectory.org

[issues-forge]: https://forge.fusiondirectory.org/projects/fd-plugins/issues/new

[issues-github]: https://github.com/fusiondirectory/fusiondirectory-plugins/issues

[donate-liberapay]: https://liberapay.com/fusiondirectory/donate

