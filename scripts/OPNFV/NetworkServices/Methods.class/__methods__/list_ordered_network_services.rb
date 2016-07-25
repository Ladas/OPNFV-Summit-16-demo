values_hash = {}
values_hash['!'] = '-- select ordered service from list --' 

network_service_id = $evm.root['dialog_parent_network_service']
$evm.log(:info, "Parent Network Service ID for ordered service: #{network_service_id}")
if !network_service_id.nil? && !network_service_id.empty? && network_service_id != '!'
  network_service = $evm.vmdb(:service, network_service_id)
  if network_service.nil?
    values_hash['!'] = '-- No ordered network services found --'
  else
    $evm.log(:info, "LADas 1 #{$evm.vmdb(:service).first}")
    $evm.log(:info, "LADas all #{$evm.vmdb(:service).all}")
    $evm.vmdb(:service).all.select { |x| x.get_dialog_option('dialog_network_service') ==  network_service_id && x.parent_service.nil? }.each do |ordered_service|
      values_hash[ordered_service.id.to_s] = ordered_service.name
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
