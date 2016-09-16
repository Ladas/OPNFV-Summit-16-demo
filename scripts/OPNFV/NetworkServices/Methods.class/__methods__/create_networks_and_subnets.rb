def get_networks_template(network_service, parent_service)
  # Get all networks for this service and create a Heat template to represent them
  
  template = nil
  template_content = {}
  
  template_content['heat_template_version'] = '2013-05-23'
  template_content['resources'] = {}
  
  network_service.direct_service_children.detect { |x| x.name == 'VNF Networks' }.direct_service_children.each do |vnf_network|
    
    vnf_network_properties = JSON.parse(vnf_network.custom_get('properties'))
    cidr = vnf_network_properties['cidr']
    network_type = nil
    
    if vnf_network_properties.include? 'network_type'
      network_type = vnf_network_properties['network_type']
    end
    
    # Don't create flat networks
    if network_type != nil and network_type == 'flat'
      next
    end
    
    network_name = "#{parent_service.name}_#{vnf_network.name}_net"
    
    template_content['resources'][network_name] = {}
    template_content['resources'][network_name]['properties'] = {}
    template_content['resources'][network_name]['properties']['name'] = "#{parent_service.name}_#{$evm.root['service_template_provision_task_id']}_#{vnf_network.name}"
    template_content['resources'][network_name]['type'] = 'OS::Neutron::Net'
    
    subnet_name = "#{parent_service.name}_#{vnf_network.name}_subnet"
    
    template_content['resources'][subnet_name] = {}
    template_content['resources'][subnet_name]['properties'] = {}
    template_content['resources'][subnet_name]['properties']['name'] = "#{parent_service.name}_#{$evm.root['service_template_provision_task_id']}_#{vnf_network.name}_subnet"
    template_content['resources'][subnet_name]['properties']['cidr'] = cidr
    template_content['resources'][subnet_name]['properties']['gateway_ip'] = ''
    template_content['resources'][subnet_name]['properties']['network_id'] = {}
    template_content['resources'][subnet_name]['properties']['network_id']['get_resource'] = network_name
    template_content['resources'][subnet_name]['type'] = 'OS::Neutron::Subnet'
  end
  
  if template_content['resources'].length == 0
    return nil
  end
  
  vnf_networks_template_name = "#{parent_service.name} networks #{parent_service.id}"

  resource = {:name      => vnf_networks_template_name,
              :type      => "OrchestrationTemplateHot",
              :orderable => true,
              :content   => YAML.dump(template_content)}

  url     = "http://localhost:3000/api/orchestration_templates"
  options = {:method     => :post,
             :url        => url,
             :verify_ssl => false,
             :payload    => {"action"   => "create",
                             "resource" => resource}.to_json,
             :headers    => {"X-Auth-Token" => MIQ_API_TOKEN,
                             :accept        => :json}}
  $evm.log("info", "Creating HOT template #{options}")

  body = JSON.parse(RestClient::Request.execute(options))

  $evm.vmdb('orchestration_template_hot', body["results"].first["id"])
end

def deploy_networks(network_service, parent_service)
  
  network_orchestration_manager = $evm.vmdb('ManageIQ_Providers_Openstack_CloudManager').find_by_name("openstack-nfvpe")
  
  networks_orchestration = $evm.vmdb('ServiceOrchestration').find_by_name("#{parent_service.name} networks")
  
  if networks_orchestration == nil
    networks_template = get_networks_template(network_service, parent_service)
    
    if networks_template == nil
      # No networks to create, so we're done here
      $evm.log(:info, "No networks require creation for #{parent_service.name} networks")
      exit MIQ_OK
    end
    
    networks_orchestration = deploy_networks_stack(network_orchestration_manager, parent_service, networks_template)
  end
 
  if networks_orchestration == nil
    $evm.log(:warn, "Network orchestration service still missing for #{parent_service.name} networks")
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '5.seconds'
    exit MIQ_OK
  end
  
  if networks_orchestration.orchestration_stack_status[0].include? 'rollback'
    $evm.log(:error, "Stack for #{parent_service.name} networks failed")
    exit MIQ_ERROR
  end 
 
  if networks_orchestration.orchestration_stack_status[0] != 'create_complete'
    $evm.log(:info, "Waiting for networks to spawn: #{networks_orchestration.orchestration_stack_status} (current state)")
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '5.seconds'
    exit MIQ_OK
  end
end

def deploy_networks_stack(orchestration_manager, parent_service, template)
  resource = {:name                   => "#{parent_service.name} networks",
              :type                   => "ServiceOrchestration",
              :orchestration_template => {:id => template.id},
              :orchestration_manager  => {:id => orchestration_manager.id},
              :parent_service         => {:id => parent_service.id},
              :stack_name             => "#{parent_service.name}_#{$evm.root['service_template_provision_task_id']}_networks",
              :stack_options          => {:attributes => {}},
              :display                => true}

  url     = "http://localhost:3000/api/services"
  options = {:method     => :post,
             :url        => url,
             :verify_ssl => false,
             :payload    => {"action"   => "create",
                             "resource" => resource}.to_json,
             :headers    => {"X-Auth-Token" => MIQ_API_TOKEN,
                             :accept        => :json}}
  $evm.log("info", "Creating HOT service #{options}")

  body = JSON.parse(RestClient::Request.execute(options))

  orchestration_service = $evm.vmdb('service', body["results"].first["id"])
  orchestration_service.deploy_orchestration_stack
  
  orchestration_service
end  

begin
  require 'rest-client'

  nsd = $evm.get_state_var(:nsd)
  $evm.log("info", "Listing nsd #{nsd}")
  $evm.log("info", "Listing Root Object Attributes:")
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================")

  $evm.log("info", "Listing task options #{$evm.root['service_template_provision_task'].destination.options}")
  options = $evm.root['service_template_provision_task'].destination.options || {}
  $evm.root.attributes.merge!(options)

  $evm.log("info", "Listing Changed Root Object Attributes:")
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }

  parent_service = $evm.root['service_template_provision_task'].destination
  parent_service.name = $evm.root.attributes['dialog_service_name']
  
  network_service = $evm.vmdb('service', $evm.root.attributes['dialog_network_service'])
  
  deploy_networks(network_service, parent_service)
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
