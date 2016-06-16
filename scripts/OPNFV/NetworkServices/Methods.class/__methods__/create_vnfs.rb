begin
  nsd = $evm.get_state_var(:nsd)
  inputs = nsd['topology_template']['node_templates']
    
  # Service parent for VNFs
  vnf_parent = $evm.vmdb('service').create(:name => 'VNFs')
  vnf_parent.display = true
  vnf_parent.parent_service = $evm.root['service_template_provision_task'].destination
  
  # Service parent for VNFd templates
  vnfd_parent = $evm.vmdb('service').create(:name => 'VNF templates')
  vnfd_parent.display = true
  vnfd_parent.parent_service = $evm.root['service_template_provision_task'].destination

  vnf_types = []
  inputs.each do |name, value|
    $evm.log(:info, "Input: #{name}, Value: #{value}")
    if name =~ /VNF\d/
      new_service = $evm.vmdb('service').create(:name => name)
      new_service.display = true
      new_service.parent_service = vnf_parent
      vnf_types << value['type']
    end
  end
  
  vnf_types.uniq.each do |vnf_type|
    new_service = $evm.vmdb('service').create(:name => vnf_type)
    new_service.display = true
    new_service.parent_service = vnfd_parent
  end
    
  exit MIQ_OK

rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
