require 'json'
begin

  def label_child_service(parent_service, service_name, service_attributes)
    child_service = parent_service.all_service_children.detect { |x| x.name == service_name }
    raise "Can't find service name #{service_name}" if child_service.nil?
    service_attributes.each do |key, value|
      set_attribute(child_service, key, value)
    end
  end

  def set_attribute(service, key, value)
    if value.nil?
      service.custom_set(key, " ")
    elsif value.class.to_s == 'String'
      service.custom_set(key, value)
    elsif value.is_a?(Hash) || value.is_a?(Array)
      service.custom_set(key, value.to_json)
    end
  end
  #
  # Tag the parent service
  #
  network_service = $evm.root['service_template_provision_task'].destination
  network_service.tag_assign("service_type/network_service")
  #
  # Retrieve the saved parsed NSD
  #
  nsd = $evm.get_state_var(:nsd)
  nsd.each do |nsd_key, nsd_value|
    if nsd_key =~ /topology_template/
      inputs = nsd['topology_template']['node_templates']
      inputs.each do |input_key, input_value|
        if input_key =~ /VNF\d/ or input_value['type'] == 'tosca.nodes.nfv.VL'
          label_child_service(network_service, input_key, input_value)
        else
          set_attribute(network_service, input_key, input_value)
        end
      end
    else
      set_attribute(network_service, nsd_key, nsd_value)
    end
  end

  exit MIQ_OK
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
