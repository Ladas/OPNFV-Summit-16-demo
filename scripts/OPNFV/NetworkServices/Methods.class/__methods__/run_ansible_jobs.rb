def launch_ansible_job(configuration_manager, network_service, parent_service, template, vms)
  orchestration_service = $evm.vmdb('ServiceAnsibleTower').create(
    :name => "#{parent_service.name} ansible test")
  
  vm_names = vms.collect(&:name).join(",")
  $evm.log(:info, "Running Ansible Tower template: #{template.name} on VMs: #{vm_names}")
  
  orchestration_service.job_template          = template
  orchestration_service.configuration_manager = configuration_manager
  orchestration_service.job_options           = {:limit => vm_names}
  orchestration_service.display               = true
  orchestration_service.parent_service        = parent_service
  orchestration_service.launch_job 
end

begin
  nsd = $evm.get_state_var(:nsd)
  $evm.log("info", "Listing nsd #{nsd}")
  $evm.log("info", "Listing Root Object Attributes:")
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================")
  
  parent_service = $evm.root['service_template_provision_task'].destination
  parent_service.name = $evm.root.attributes['dialog_service_name']
  
  template_name         = 'HelloOS'
  ansible_manager_name  = 'ansible Configuration Manager'
  
  network_service       = $evm.vmdb('service', $evm.root.attributes['dialog_network_service'])
  configuration_manager = $evm.vmdb('ManageIQ_Providers_AnsibleTower_ConfigurationManager').find_by_name(ansible_manager_name)
  template              = $evm.vmdb('ConfigurationScript').find_by_name(template_name)
  
  vms = parent_service.direct_service_children.collect(&:vms).flatten
  vms                   = [vms[0], vms[1]]
    
  launch_ansible_job(configuration_manager, network_service, parent_service, template, vms)
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
