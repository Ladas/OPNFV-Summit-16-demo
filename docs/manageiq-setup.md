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

## Import dialogs
The dialogs related to the OPNFV demo are located in the dialogs directory.
1. Go to Automate/Customization/'Import/Export'/'Service Dialog Import/Export'
2. Pick a yaml file from a dialogs/ directory and click upload
3. Select all dialogs and click commit

These steps will cause that all selected custom dialogs will be uploaded to ManageIQ.


## ManageIQ Custom Tag 
1. Under Settings/Configuration/CFME region, go to *My Company Categories*, and create a new entry with name: *service_type* description: *NFV tagging*
2. Under *My Company Tags*, pick *service_type* and one value *network_service*

These steps create a tag service_type/network_service, that is usable in the ManageIQ for NFV.
