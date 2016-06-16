exit MIQ_OK # remove this if you wish to create networks

require 'fog/openstack'
begin
  tenant_name = 'admin'
  $evm.log(:info, "Tenant name: #{tenant_name}")

  ems = $evm.vmdb('ManageIQ_Providers_Openstack_CloudManager', $evm.root.attributes['dialog_openstack_manager'])
  
  raise "ems not found" if ems.nil?

  neutron_service = Fog::Network.new({
    :provider => 'OpenStack',
    :openstack_api_key => ems.authentication_password,
    :openstack_username => ems.authentication_userid,
    :openstack_auth_url => "http://#{ems.hostname}:5000/v2.0/tokens",
    :openstack_tenant => tenant_name
  })

  keystone_service = Fog::Identity.new({
    :provider => 'OpenStack',
    :openstack_api_key => ems.authentication_password,
    :openstack_username => ems.authentication_userid,
    :openstack_auth_url => "http://#{ems.hostname}:5000/v2.0/tokens",
    :openstack_tenant => tenant_name
  })

  net = neutron_service.networks.create(:name => 'test_network')
  subnet = neutron_service.subnets.create(
    :name       => 'test_subnet', 
    :network_id => net.id,
    :cidr       => '192.168.2.0/24',
    :ip_version => 4)
 
  $evm.log("info", "Network #{net.name} and subnet #{subnet.name} are created")
  exit MIQ_OK
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end
