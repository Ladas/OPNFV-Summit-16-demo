def retire_vnfs(network_service)
  
  found_stack = false
  
  network_service.direct_service_children.each do |vnf_service| 
    if !vnf_service.name.include? " networks"
      # This a VNF service
      
      stack = $evm.vmdb('ManageIQ_Providers_Openstack_CloudManager_Vnf').find_by_name("#{vnf_service.name} #{network_service.id}")
      
      if stack
        # Tacker stack
        if vnf_service.orchestration_stack_status[0] == 'create_complete'
          stack.raw_delete_stack()
          $evm.log(:info, "Retiring #{vnf_service.name}")
          vnf_service.retire_now()
          found_stack = true
        elsif vnf_service.orchestration_stack_status[0] == 'transient'
          found_stack = true
        end
      else
        # Could be a Tacker template remaining...    
        type = JSON.parse(vnf_service.custom_get('properties') || '{}').try(:[], 'type') || ""
        template = $evm.vmdb('orchestration_template_vnfd').find_by_name("#{vnf_service.name} #{type} #{network_service.id}")

        if template
          if vnf_service.orchestration_stack_status[0] == 'create_complete' or vnf_service.orchestration_stack_status[0] == 'transient'
            found_stack = true
            next
          end
          
          $evm.log(:info, "Deleting #{vnf_service.name} VNFD orchestration template")
          temp_vnfd = $evm.vmdb('orchestration_template_vnfd')
          temp_vnfd.destroy(template.id)
        end
        
        # ...but also could be an AWS (CFN) stack
        stack_name = "#{vnf_service.name.gsub('\s', '-').gsub('_', '-').gsub(' ', '-')}-#{network_service.id}"
        stack = $evm.vmdb('ManageIQ_Providers_Amazon_CloudManager_OrchestrationStack').find_by_name(stack_name)
        
        if stack != nil
          if vnf_service.orchestration_stack_status[0] == 'create_complete'
            stack.raw_delete_stack()
            $evm.log(:info, "Retiring #{vnf_service.name}")
            vnf_service.retire_now()
            found_stack = true
          elsif vnf_service.orchestration_stack_status[0] == 'transient'
            found_stack = true
          end
        else
          if vnf_service.respond_to?(:orchestration_stack_status) && (vnf_service.orchestration_stack_status[0] == 'create_complete' or vnf_service.orchestration_stack_status[0] == 'transient')
            found_stack = true
          else
            template = $evm.vmdb('orchestration_template_cfn').find_by_name("#{vnf_service.name} #{network_service.id}")

            if template != nil
              $evm.log(:info, "Deleting #{vnf_service.name} CFN orchestration template")
              $evm.vmdb('orchestration_template_cfn').destroy(template.id)
            end
          end
        end
      end
    else      
      # This is the networks service
      template = $evm.vmdb('orchestration_template_hot').find_by_name("#{network_service.name} networks #{network_service.id}")
      
      if template != nil
        $evm.log(:info, "Deleting #{vnf_service.name} networks HOT orchestration template")
        $evm.vmdb('orchestration_template_hot').destroy(template.id)
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
