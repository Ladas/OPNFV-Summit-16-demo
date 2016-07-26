values_hash = {}
values_hash[''] = '-- select service from list --' 

tag = "/managed/service_type/network_service"
services = $evm.vmdb(:service).find_tagged_with(:all => tag, :ns => "*")
services.each do |service|
  values_hash[service.id.to_s] = service.name 
end
list_values = {
  'sort_by'   => :value, 
  'data_type' => :string, 
  'required'  => true, 
  'values'    => values_hash
}
list_values.each { |key, value| $evm.object[key] = value }
