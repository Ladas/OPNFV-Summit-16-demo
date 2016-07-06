## ManageIQ VM
 * ManageIq ran on a Fedora 23 VM  
 * The VM was created/managed by Vagrant
 * The Vagrantile is located in the files directory

## Import datastore
The artifacts related to the OPNFV demo are located in scripts/OPNFV.
ManageIQ stores additional artifacts as a ZIP file.  In order to use
the artifacts, do the following...
   cd scripts
   zip -r datastore.zip OPNFV

## ManageIQ Custom Tag 
1. Under Settings/Configuration/CFME region, go to *My Company Categories*, and create a new entry with name: *service_type* description: *NFV tagging*
2. Under *My Company Tags*, pick *service_type* and one value *network_service*

These steps create a tag service_type/network_service, that is usable in the ManageIQ for NFV.
