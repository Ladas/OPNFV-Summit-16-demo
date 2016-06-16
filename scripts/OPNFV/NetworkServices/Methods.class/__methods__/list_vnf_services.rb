values_hash = {}
values_hash['!'] = '-- select service from list --' 

network_service_id = $evm.root['dialog_network_service']
unless network_service_id.nil? || network_service_id.empty?
  $evm.log(:info, "Network Service ID: #{network_service_id}")
  network_service = $evm.vmdb(:service, network_service_id)
  if network_service.nil?
    values_hash['!'] = '-- No network services found --'
  else
    vnf_template_parent = network_service.direct_service_children.detect { |x| x.name == 'VNF templates'}  
    vnf_template_parent.direct_service_children.each do |child_service|
      values_hash[child_service.id.to_s] = child_service.name 
    end
  end
end
list_values = {
  'sort_by'   => :value, 
  'data_type' => :string, 
  'required'  => true, 
  'values'    => values_hash
}
list_values.each { |key, value| $evm.object[key] = value }


