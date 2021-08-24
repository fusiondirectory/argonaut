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

### Community support

There are a couple ways you can try [to get help][get help].You can also join the `#fusiondirectory` IRC channel at libera.chat.

### Professional support

Professional support is provided through of subscription.

We have two type of subscription :

* [FusionDirectory][subscription-fusiondirectory] : Global subscription for FusionDirectory and all the plugins
* [FusionDirectory Plus][subscription-fusiondirectory-plus] : Expert Support on Education, Deployement and Infrastructure plugins

The subscription provides access to FusionDirectory's stable enterprise repository, providing reliable software updates and security enhancements,
as well as technical help and support.

Choose the plan that's right for you. Our subscriptions are flexible and scalable according to your needs

The subscription period is one year from the date of purchase and gives you access to the extensive infrastructure of enterprise-class software and services.

## IRC Etiquette

* If we don't answer right away then just hang out in the channel.  Someone will
  eventually write back to you as it just means we are away from keyboard,
  working on something else, or in a different timezone than you.
* You should treat IRC as what it is: asynchronous chat.  Sure the messages can
  be instant but in most channels people are in different time zones.  At times
  chat replies can be in excess of 24hrs.
  
## Crowfunding

If you like us and want to send us a small contribution you can use the following crowfunding services

* [liberapay] [donate-liberapay]: https://liberapay.com/fusiondirectory/donate

* [kofi][donate-kofi]: https://ko-fi.com/fusiondirectory

* [opencollective][donate-opencollective]: https://opencollective.com/fusiondirectory

* [communitybridge][donate-communitybridge]: https://funding.communitybridge.org/projects/fusiondirectory
  
## License

[Argonaut][Argonaut] is  [GPL 2 License](COPYING).

[Argonaut]: https://www.argonaut-project.org/

[FAI]: http://fai-project.org/

[OPSI]: http://opsi.org/en/

[FusionDirectory]: https://www.fusiondirectory.org/

[get help]: https://www.fusiondirectory.org/en/communaute/

[subscription-fusiondirectory]: https://www.fusiondirectory.org/en/subscription-fusiondirectory/

[subscription-fusiondirectory-plus]: https://www.fusiondirectory.org/en/subscriptions-fusiondirectory-plus/

[donate-liberapay]: https://liberapay.com/fusiondirectory/donate

[donate-kofi]: https://ko-fi.com/fusiondirectory

[donate-opencollective]: https://opencollective.com/fusiondirectory

[donate-communitybridge]: https://funding.communitybridge.org/projects/fusiondirectory
