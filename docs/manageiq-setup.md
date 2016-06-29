## ManageIQ VM
 * ManageIq ran on a Fedora 23 VM  
 * The VM was created/managed by Vagrant
 * The Vagrantile is located in the ...

## ManageIQ Custom Tag 
1. Under Settings/Configuration/CFME region, go to *My Company Categories*, and create a new entry with name: *service_type* description: *NFV tagging*
2. Under *My Company Tags*, pick *service_type* and one value *network_service*

These steps create a tag service_type/network_service, that is usable in the ManageIQ for NFV.
