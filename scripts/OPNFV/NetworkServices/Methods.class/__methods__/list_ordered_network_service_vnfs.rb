values_hash = {}
values_hash['!'] = '-- select VNF from list --' 

network_service_id = $evm.root['dialog_ordered_network_service']
$evm.log(:info, "Ordered Network Service ID for VNFs: #{network_service_id}")
if !network_service_id.nil? && !network_service_id.empty? && network_service_id != '!'
  network_service = $evm.vmdb(:service, network_service_id)
  if network_service.nil?
    values_hash['!'] = '-- No VNF found --'
  else
    network_service.direct_service_children.select { |x| x.name.include?('VNF') }.each do |child_service|
      values_hash[child_service.id.to_s] = child_service.name 
    end
  end
end
list_values = {
  'sort_by'   => :value, 
  'data_type' => :string, 
  'required'  => false, 
  'values'    => values_hash
}
list_values.each { |key, value| $evm.object[key] = value }
