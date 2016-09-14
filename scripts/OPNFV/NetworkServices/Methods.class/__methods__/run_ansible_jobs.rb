def launch_ansible_job(configuration_manager, network_service, parent_service, template, vms, properties)
  if !$evm.root.attributes['dialog_ansible_job_label'].blank?
    job_name = "#{Time.now.utc} #{$evm.root.attributes['dialog_ansible_job_label']} (#{template.name})"
  else
    job_name = "#{Time.now.utc} #{template.name}"
  end  

  $evm.log(:info, "Running Ansible Tower template on VM of the type: #{vms.first.type}")
  if vms.first.type == "ManageIQ::Providers::Amazon::CloudManager::Vm"
    # TODO figure out, how to pass elastic ip as part of VM inventory, this will work only
    # with 1 VM per stack
    vm_names = vms.collect(&:ipaddresses).join(",")
  else
    vm_names = vms.collect(&:name).join(",")
  end
  $evm.log(:info, "Running Ansible Tower template: #{template.name} on VMs: #{vm_names} with properties: #{properties}")

  resource = {:name                  => job_name,
              :type                  => "ServiceAnsibleTower",
              :job_template          => {:id => template.id},
              :parent_service        => {:id => parent_service.id},
              :job_options           => {:limit => vm_names, :extra_vars => properties}.to_yaml,
              :display               => true}

  url     = "http://localhost:3000/api/services"
  options = {:method     => :post,
             :url        => url,
             :verify_ssl => false,
             :payload    => {"action"   => "create",
                             "resource" => resource}.to_json,
             :headers    => {"X-Auth-Token" => MIQ_API_TOKEN,
                             :accept        => :json}}
  $evm.log("info", "Creating Ansible Tower service #{options}")

  body = JSON.parse(RestClient::Request.execute(options))

  orchestration_service = $evm.vmdb('service', body["results"].first["id"])
  orchestration_service.launch_job

  orchestration_service.custom_set(:extra_vars, JSON.pretty_generate(properties))
  orchestration_service.custom_set(:limit, vm_names)

  # Store the ansible service ids, so we can wait for them in next step
  ansible_service_ids = $evm.get_state_var(:ansible_service_ids)
  ansible_service_ids << orchestration_service.id
  $evm.set_state_var(:ansible_service_ids, ansible_service_ids)
end

def cps_for_id(network_service, id)
  # Returns list of capabilities for each VNF, e.g.: ["CloudExternal", "VL1", "VL2", "net_mgmt"]
  cps = []
  network_service.direct_service_children.detect { |x| x.name == 'VNFs' }.direct_service_children.each do |vnf_service| 
    if JSON.parse(vnf_service.custom_get('properties'))['id'].to_s == id.to_s
      cps = JSON.parse(vnf_service.custom_get('requirements')).map { |x| x.values.first }.compact
    end
  end
  cps
end

def get_cluster_info(parent_service, network_service)
  cluster = {}
  subnets = {}
  parent_service.direct_service_children.each do |vnf_service|
    json_properties = vnf_service.custom_get('properties') || '{}'
    properties      = JSON.parse(json_properties)
    id              = properties['id']
    vim_id          = properties['vim_id']
    next unless id
    
    cluster[id] = {}
    subnets[vim_id] ||= {}
    # TODO handle more vms per VNF
    vm = vnf_service.vms.first
    cps_for_id(network_service, id).each_with_index do |connection_point, index|
      network_port = vm.network_ports.detect { |x| x.cloud_subnets.detect { |subnet| subnet.name.include?(connection_point) }}
      cluster[id][connection_point] = {
        :fixed_ips    => network_port.try(:fixed_ip_addresses), 
        :floating_ips => network_port.try(:floating_ip_addresses),
        :interface    => "eth#{index}"}
      
      if network_port
        cidrs = network_port.cloud_subnets.collect(&:cidr)
        subnets[vim_id][connection_point] ||= {:cidrs => cidrs} 
        cidrs.each_with_index do |cidr, index|
          ipaddr  = IPAddr.new(cidr)
          address = ipaddr.to_s
          mask    = /.*?\/(.*?)\>/.match(ipaddr.inspect)[1]
          
          (subnets[vim_id][connection_point][:addresses] ||= [])[index] = address
          (subnets[vim_id][connection_point][:masks] ||= [])[index]     = mask
        end  
      end
    end
  end
  
  return cluster, subnets
end  

begin
  require 'ipaddr'
  require 'rest-client'

  nsd = $evm.get_state_var(:nsd)
  $evm.set_state_var(:ansible_service_ids, [])
  
  $evm.log("info", "Listing nsd #{nsd}")
  $evm.log("info", "Listing Root Object Attributes:")
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================")
  network_service = nil
  
  if !$evm.root.attributes['dialog_ordered_network_service'].blank?
    parent_service = $evm.vmdb(:service, $evm.root.attributes['dialog_ordered_network_service'])
    network_service = $evm.vmdb(:service, parent_service.get_dialog_option('dialog_network_service'))
    
    ansible_job_reconfiguration_service = $evm.root['service_template_provision_task'].destination
    ansible_job_reconfiguration_service.name = $evm.root.attributes['dialog_ansible_job_label']
    ansible_job_reconfiguration_service.display = false
    ansible_job_reconfiguration_service.parent_service = parent_service
   
    raise "Can't find network service with id #{parent_service.get_dialog_option('dialog_network_service')}" if network_service.nil?
  else
    parent_service = $evm.root['service_template_provision_task'].destination
    parent_service.name = $evm.root.attributes['dialog_service_name']
  
    network_service = $evm.vmdb('service', $evm.root.attributes['dialog_network_service'])
  end
  
  cluster, subnets = get_cluster_info(parent_service, network_service)
  
  parent_service.direct_service_children.each do |vnf_service|
    # There can be more types of services, we are interested in services with ansible job name defined
    # under properties
    json_properties = vnf_service.custom_get('properties') || '{}'
    properties = JSON.parse(json_properties) 
    properties['cluster'] = cluster
    properties['subnets'] = subnets
    
    if !$evm.root.attributes['dialog_extra_variables'].blank?
      extra_variables = JSON.parse($evm.root.attributes['dialog_extra_variables'])
      properties.merge!(extra_variables)
    end  
    
    ansible_manager_name = properties['ansible_vim_id']
    if $evm.root.attributes['dialog_ansible_template_name']
      template_name = $evm.root.attributes['dialog_ansible_template_name']
    else
      template_name = properties['ansible_template_name']
    end  
    
    next if !template_name || !ansible_manager_name
    
    configuration_manager = $evm.vmdb('ManageIQ_Providers_AnsibleTower_ConfigurationManager').find_by_name(ansible_manager_name)
    template              = $evm.vmdb('ConfigurationScript').find_by_name(template_name)
    
    $evm.log("info", "Template #{template_name} not found") unless template
    $evm.log("info", "Configuration manager #{ansible_manager_name} not found") unless configuration_manager
    next if !template || !configuration_manager
    $evm.log("info", "Found template #{template.name}")

    skip_vnf = false
    if !$evm.root.attributes['dialog_limited_to_vnf'].blank? && $evm.root.attributes['dialog_limited_to_vnf'] != "!"
      skip_vnf = $evm.root.attributes['dialog_limited_to_vnf'].to_s != vnf_service.id.to_s
      $evm.log("info", "Skipping ansible job on #{vnf_service.name}") if skip_vnf
    end
    launch_ansible_job(configuration_manager, network_service, vnf_service, template, vnf_service.vms, properties) unless skip_vnf
  end
 
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
