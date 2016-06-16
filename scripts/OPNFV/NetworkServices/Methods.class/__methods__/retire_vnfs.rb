def retire_vnfs(network_service)
  
  found_stack = false
  
  network_service.direct_service_children.each do |vnf_service| 
    
    if !vnf_service.name.include? "_networks"
      
      stack = $evm.vmdb('ManageIQ_Providers_Openstack_CloudManager_Vnf').find_by_name(vnf_service.name)
      
      if stack != nil
        begin
          if vnf_service.retirement_state != 'retiring' and vnf_service.retirement_state != 'retired'
            stack.raw_delete_stack()
            $evm.log(:info, "AJB retiring #{vnf_service.name}")
            vnf_service.retire_now()
            found_stack = true
          end
        rescue => err
        end
      end
    end
  end  
  
  if found_stack == true
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '30.seconds'
    exit MIQ_OK
  end
end

begin
  nsd = $evm.get_state_var(:nsd)
  network_service = nil
  $evm.log("info", "Listing nsd #{nsd}")
  $evm.log("info", "Listing Root Object Attributes:")
  $evm.root.attributes.sort.each { |k, v| 
    $evm.log("info", "\t#{k}: #{v}") 
  }
  $evm.log("info", "===========================================")
  
  network_service = $evm.root["service"]  
  
  retire_vnfs(network_service)
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
