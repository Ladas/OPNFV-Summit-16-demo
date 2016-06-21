def launch_ansible_job(configuration_manager, network_service, parent_service, template, vms, properties)
  orchestration_service = $evm.vmdb('ServiceAnsibleTower').create(
    :name => "Ansible job - #{template.name}")
  
  $evm.log(:info, "Running Ansible Tower template on VM of the type: #{vms.first.type}")
  if vms.first.type == "ManageIQ::Providers::Amazon::CloudManager::Vm"
    # TODO figure out, how to pass elastic ip as part of VM inventory, this will work only
    # with 1 VM per stack
    properties['elastic_ip'] = vms.first.floating_ips.detect { |x| x.network_port.cloud_subnets.detect { |subnet| subnet.name == 'InterCloud' } }.try(:address)
    vm_names = vms.collect(&:ipaddresses).join(",")
  else
    vm_names = vms.collect(&:name).join(",")
  end
  $evm.log(:info, "Running Ansible Tower template: #{template.name} on VMs: #{vm_names}")
  
  orchestration_service.job_template          = template
  orchestration_service.configuration_manager = configuration_manager
  orchestration_service.job_options           = {:limit => vm_names, :extra_vars => properties}
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
  
  parent_service.direct_service_children.each do |vnf_service|
    # There can be more types of services, we are interested in services with ansible job name defined
    # under properties
    json_properties = vnf_service.custom_get('properties') || '{}'
    properties = JSON.parse(json_properties) 
    ansible_manager_name  = properties['ansible_vim_id']
    template_name         = properties['ansible_template_name']
    
    next if !template_name || !ansible_manager_name
    
    network_service       = $evm.vmdb('service', $evm.root.attributes['dialog_network_service'])
    configuration_manager = $evm.vmdb('ManageIQ_Providers_AnsibleTower_ConfigurationManager').find_by_name(ansible_manager_name)
    template              = $evm.vmdb('ConfigurationScript').find_by_name(template_name)
    
    next if !template || !configuration_manager
    $evm.log("info", "Found template #{template.name}")

    launch_ansible_job(configuration_manager, network_service, vnf_service, template, vnf_service.vms, properties)
  end
 
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
