values_hash = {}
values_hash['!'] = '-- select OpenStack manager from list --' 

managers = $evm.vmdb('ManageIQ_Providers_Openstack_CloudManager').all
managers.each do |manager|
  values_hash[manager.id.to_s] = manager.name 
end
list_values = {
  'sort_by'   => :value, 
  'data_type' => :string, 
  'required'  => true, 
  'values'    => values_hash
}
list_values.each { |key, value| $evm.object[key] = value }
