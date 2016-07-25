values_hash = {}
values_hash['!'] = '-- select ansible job template from list --' 

network_service_id = $evm.root['dialog_ordered_network_service']
$evm.log(:info, "Ordered Network Service ID for job template: #{network_service_id}")
if !network_service_id.nil? && !network_service_id.empty? && network_service_id != '!'
  parent_service = $evm.vmdb(:service, network_service_id)
  if parent_service.nil?
    values_hash['!'] = '-- No ansible job template found --'
  else
    configuration_manager_ids = []
    parent_service.direct_service_children.each do |vnf_service|
      # There can be more types of services, we are interested in services with ansible job name defined
      # under properties
      json_properties = vnf_service.custom_get('properties') || '{}'
      properties = JSON.parse(json_properties) 

      configuration_manager_ids << properties['ansible_vim_id']
    end
    
    configuration_manager_ids.compact.uniq.each do |configuration_manager_id|
      configuration_manager = $evm.vmdb('ManageIQ_Providers_AnsibleTower_ConfigurationManager').find_by_name(configuration_manager_id)
      $evm.log(:info, "LADas manager: #{configuration_manager}")
      $evm.log(:info, "LADas manager fir: #{configuration_manager.configuration_scripts.first}")
      
      configuration_manager.configuration_scripts.each do |configuration_script|
        values_hash[configuration_script.name] = configuration_script.name
      end  
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
