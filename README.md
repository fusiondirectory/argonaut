# Argonaut

[Argonaut][Argonaut] Manage your systems, services and also Integrate FusionDirectory backend Fonctionnalities

[Argonaut][Argonaut] is an effective tool for managing services, systems, task.

Integrate Argonaut with  [FusionDirectory], your own tools or with deployment tools like [FAI], [OPSI], Debconf.

## Features

Argonaut is a modular client/server system based on JSON-RPC protocol. Both client and server sides can load modules at start. Argonaut has many  functions.

### Run a given operation on a system through a client

Two basic functions: restart service and switch on/off a system. 

Argonaut server and argonaut client can booth load modules at startup

### Integration with [FusionDirectory] and Services

* Services modules :

  * argonaut-dovecot: Create the directory needed by dovecot to create the mailbox
  * argonaut-ldap2zone: Create, update dns zones, create views, create acls
  * argonaut-quota: Apply a file quota
  * argonaut-samba : Create share from ldap information stored in FusionDirectory

### Integration with [FusionDirectory]

  * argonaut-clean-audit : Clean the audit branch of FusionDirectory
  * argonaut-user-reminder : Send an email reminder coordinated with the user-reminder plugin of FusionDirectory

### Integration with deployment tools [FAI], [OPSI], Debconf

* Deployment systems modules :

  * argonaut-fai-mirror: Create a local mirror with the help of *argonaut-debconf-crawler* and *argonaut-repository* 
  * argonaut-fai-monitor : Monitor FAI installation and report states to FusionDirectory
  * argonaut-fai-nfsroot : Integrate Argonaut into the FAI nfsroot
  * argonaut-fai-server : Contains fai2ldif to create ldif from FAI text classes and yumgroup2yumi for creating in ldif the yum groups for centos/rhel deployment 

* Intelligent PXE Management : 


  * argonaut-fuse : Get information and create pxelinux.cfg file that matches the type of machine to be deployed directly from LDAP, allowing automatic boot during an install by pxe

  * argonaut-fuse-fai-module : Read Information from the fai tab of a system in FusionDirectory
  * argonaut-fuse-opsi-module : Read Information from the opsi tab of a system in FusionDirectory an talk to the opsi webservice


## Get help

There are a couple ways you can try [to get help][get help].You can also join the `#fusiondirectory` IRC channel at freenode.net.

You can [register on our system][register] and enter issues [Argonaut][issues-core].

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

[FusionDirectory]: https://www.fusiondirectory.org/

[get help]: https://www.fusiondirectory.org/contact-us/

[register]: https://register.fusiondirectory.org

[issues-core]: https://gitlab.fusiondirectory.org/argonaut/argonaut/issues

[donate-liberapay]: https://liberapay.com/fusiondirectory/donate
