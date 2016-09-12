def get_template_contents(network_service)
  template_contents = {}
  network_service.direct_service_children.detect { |x| x.name == 'VNF templates' }.direct_service_children.each do |vnfd_service|
    orchestration_template_service = vnfd_service.direct_service_children.first
    raise "Undefined VNF template for #{vnfd_service.name}" if orchestration_template_service.nil?

    template_content = JSON.parse(orchestration_template_service.custom_get('vnfd_template'))
    $evm.log("info", "Template VNFd #{template_content}")
    
    template_contents[vnfd_service.name] = template_content
  end 
  
  template_contents
end  

def get_template(orchestration_manager, network_service, parent_service, vnf_service)
  # Load our general VNFDs per type
  template_contents = get_template_contents(network_service)
  
  # Upload specific VNFD per VNF, defined in NSD, into Tacker
  unused_cps    = []
  virtual_links = {}
  
  # We normally rename network targets here (because we make them unique in create_networks_and_subnets,
  # but we don't want to do this for flat networks, so find them (if any)
  skip_rename_networks = []  
  
  network_service.direct_service_children.detect { |x| x.name == 'VNF Networks' }.direct_service_children.each do |vnf_network|
    
    vnf_network_properties = JSON.parse(vnf_network.custom_get('properties'))
    network_type = vnf_network_properties['network_type']
    
    # Don't create flat networks
    if network_type == 'flat'
      skip_rename_networks << vnf_network.name
    end
  end
    
  template_content = JSON.parse(template_contents[vnf_service.custom_get('type')].to_json.dup)
  $evm.log("info", "Template VNFD: #{template_content}")
  $evm.log("info", "Template Type: #{vnf_service.custom_get('type')}")
    
  # substitution_mappings_requirements format {virtualLink1:    [CP1, virtualLink]}
  substitution_mappings_requirements = template_content['topology_template']['substitution_mappings']['requirements']
  $evm.log("info", "Substitution mappings requirements Type: #{substitution_mappings_requirements}")  
  
  vnf_template_name = "#{parent_service.name} #{vnf_service.name} #{vnf_service.custom_get('type')} #{parent_service.id}"
  $evm.log("info", "VNF template name: #{vnf_template_name}")

  vnf_service_properties = JSON.parse(vnf_service.custom_get('properties'))
  $evm.log("info", "VNF service properties: #{vnf_service_properties}")

  template_content['topology_template']['node_templates'].each do |name, value|
    $evm.log(:info, "Node template: #{name}, Value: #{value}")
    if name =~ /VDU\d+/        
      value['properties'].each do |property_name, property_value|
        next if property_value =~ /\{.*?get_input\d/
        next if ['mgmt_driver'].include?(property_name)
        next if property_value.is_a?(Hash)
          
        if (new_value = vnf_service_properties[property_name])
          $evm.log(:info, "Replacing: #{property_name}, with value #{new_value}")
          value['properties'][property_name] = new_value
        end
      end  
    elsif name =~ /CP\d+/
      # vnf_service_requiremements format: [virtualLink1: VL1])
      vnf_service_requirements = JSON.parse(vnf_service.custom_get('requirements'))
      $evm.log("info", "VNF service requirements : #{vnf_service_requirements}")
      
      substitution_mapping = substitution_mappings_requirements.detect { |k, v| v.first == name }
      link_name = substitution_mapping.first
      link_type = substitution_mapping.second.second
      network_name = vnf_service_requirements.detect { |x| x.keys.first == link_name }.values.first
       
      $evm.log("info", "VNF service procesing requirement: #{link_type}: #{link_name} with value: #{network_name}")

      if network_name.blank?
        # Mark CP as unused and delete it later from VNFD
        $evm.log("info", "CP: #{name}, is unused and will be removed from the VNFD")
        unused_cps << name
      else
        $evm.log("info", "Requirement: #{link_type} {node: #{link_name}}, is being added to #{name}")
        # Add link under CP
        # requirements:
        #   - virtualLink: 
        #       node: virtualLinkMgmt
        value['requirements'] << { 
          link_type => {
            'node' =>link_name}}
        
        $evm.log("info", "#{link_type}: #{link_name} with network name #{network_name}, is being added to VNFD node_templates section")
        # And store Virtual Link that will be added later
        
        if !skip_rename_networks.include? network_name
          network_name = "#{parent_service.name}_#{$evm.root['service_template_provision_task_id']}_#{network_name}"
        end
        
        virtual_links[link_name] = {
          'type'       => 'tosca.nodes.nfv.VL',
          'properties' => {
            'network_name' => network_name,
            'vendor'       => 'Tacker'}}
      end  
    end
  end  
    
  template_content['topology_template']['node_templates'].merge!(virtual_links)
  unused_cps.each { |x| template_content['topology_template']['node_templates'].delete(x) }

  resource = {:name         => vnf_template_name,
              :type         => "OrchestrationTemplateVnfd",
              :orderable    => true,
              :remote_proxy => true,
              :ems_id       => orchestration_manager.id,
              :content      => YAML.dump(template_content)}

  url     = "http://localhost:3000/api/orchestration_templates"
  options = {:method     => :post,
             :url        => url,
             :verify_ssl => false,
             :payload    => {"action"   => "create",
                             "resource" => resource}.to_json,
             :headers    => {"X-Auth-Token" => MIQ_API_TOKEN,
                             :accept        => :json}}
  $evm.log("info", "Creating VNFd template #{options}")

  body = JSON.parse(RestClient::Request.execute(options))

  $evm.vmdb('orchestration_template_vnfd', body["results"].first["id"])
end

def deploy_vnfs(network_service, parent_service)
  network_service.direct_service_children.detect { |x| x.name == 'VNFs' }.direct_service_children.each do |vnf_service| 
    # TODO if Openstack stack or amazon VM
    properties = JSON.parse(vnf_service.custom_get('properties'))
    orchestration_manager = $evm.vmdb('ManageIQ_Providers_Openstack_CloudManager').find_by_name(properties['vim_id'])
    next unless orchestration_manager
    
    deploy_vnf_stack(orchestration_manager, network_service, parent_service, vnf_service)
  end  
end

def deploy_vnf_stack(orchestration_manager, network_service, parent_service, vnf_service)
  template = get_template(orchestration_manager, network_service, parent_service, vnf_service)
  
  # TODO should we filter passed params based on inputs in VNFD?
  params = JSON.parse(vnf_service.custom_get('properties'))
  params['type'] = vnf_service.custom_get('type')
  
  params = params.to_json

  resource = {:name                   => "#{parent_service.name} #{vnf_service.name}",
              :type                   => "ServiceOrchestration",
              :orchestration_template => {:id => template.id},
              :orchestration_manager  => {:id => orchestration_manager.id},
              :parent_service         => {:id => parent_service.id},
              :stack_name             => "#{parent_service.name} #{vnf_service.name} #{parent_service.id}",
              :stack_options          => {:attributes => {:param_values => params}},
              :display                => true}

  url     = "http://localhost:3000/api/services"
  options = {:method     => :post,
             :url        => url,
             :verify_ssl => false,
             :payload    => {"action"   => "create",
                             "resource" => resource}.to_json,
             :headers    => {"X-Auth-Token" => MIQ_API_TOKEN,
                             :accept        => :json}}
  $evm.log("info", "Creating Vnf service #{options}")

  body = JSON.parse(RestClient::Request.execute(options))

  orchestration_service = $evm.vmdb('service', body["results"].first["id"])
  orchestration_service.custom_set('properties', params)
  orchestration_service.deploy_orchestration_stack 
end  

begin
  require 'rest-client'

  nsd = $evm.get_state_var(:nsd)
  $evm.log("info", "Listing nsd #{nsd}")
  $evm.log("info", "Listing Root Object Attributes:")
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================")
  
  parent_service = $evm.root['service_template_provision_task'].destination
  parent_service.name = $evm.root.attributes['dialog_service_name']
  
  network_service = $evm.vmdb('service', $evm.root.attributes['dialog_network_service'])
  
  deploy_vnfs(network_service, parent_service)
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
