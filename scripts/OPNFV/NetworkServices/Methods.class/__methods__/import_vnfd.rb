begin
  nsd = $evm.get_state_var(:nsd)
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================")
  
  template_service = $evm.root['service_template_provision_task'].destination
  parent_service = $evm.vmdb(:service, $evm.root.attributes['dialog_vnf_type'])
  raise "Can't find service with id #{$evm.root.attributes['dialog_vnf_type']}" if parent_service.nil?
  template_service.parent_service = parent_service
  template_service.custom_set('vnfd_template', JSON.dump(YAML.load($evm.root.attributes['dialog_vnfd_content'])))

rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
