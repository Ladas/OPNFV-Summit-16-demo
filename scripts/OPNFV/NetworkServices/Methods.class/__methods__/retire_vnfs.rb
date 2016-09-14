def retire_vnfs(network_service)
  
  found_stack = false
  
  network_service.direct_service_children.each do |vnf_service| 
    if !vnf_service.name.include? " networks"
      # This a VNF service
      
      stack = $evm.vmdb('ManageIQ_Providers_Openstack_CloudManager_Vnf').find_by_name("#{vnf_service.name} #{network_service.id}")
      
      if stack
        # Tacker stack
        if vnf_service.orchestration_stack_status[0] == 'create_complete'
          delete_stack(stack)
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

          url     = "http://localhost:3000/api/orchestration_templates/#{temp_vnfd.id}"
          options = {:method     => :delete,
                     :url        => url,
                     :verify_ssl => false,
                     :headers    => {"X-Auth-Token" => MIQ_API_TOKEN,
                                     :accept        => :json}}
          RestClient::Request.execute(options)
        end
        
        # ...but also could be an AWS (CFN) stack
        stack_name = "#{vnf_service.name.gsub('\s', '-').gsub('_', '-').gsub(' ', '-')}-#{network_service.id}"
        stack = $evm.vmdb('ManageIQ_Providers_Amazon_CloudManager_OrchestrationStack').find_by_name(stack_name)
        
        if stack != nil
          if vnf_service.orchestration_stack_status[0] == 'create_complete'
            delete_stack(stack)
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
              url     = "http://localhost:3000/api/orchestration_templates/#{template.id}"
              options = {:method     => :delete,
                         :url        => url,
                         :verify_ssl => false,
                         :headers    => {"X-Auth-Token" => MIQ_API_TOKEN,
                                         :accept        => :json}}
              RestClient::Request.execute(options)
            end
          end
        end
      end
    else      
      # This is the networks service
      template = $evm.vmdb('orchestration_template_hot').find_by_name("#{network_service.name} networks #{network_service.id}")
      
      if template != nil
        $evm.log(:info, "Deleting #{vnf_service.name} networks HOT orchestration template")
        url     = "http://localhost:3000/api/orchestration_templates/#{template.id}"
        options = {:method     => :delete,
                   :url        => url,
                   :verify_ssl => false,
                   :headers    => {"X-Auth-Token" => MIQ_API_TOKEN,
                                   :accept        => :json}}
        RestClient::Request.execute(options)
      end
    end
  end  
  
  if found_stack == true
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '30.seconds'
    exit MIQ_OK
  end
end

def delete_stack(stack)
  begin
    $evm.log(:info, "Deleting stack #{stack}")
    stack.raw_delete_stack()
  rescue NotImplementedError => e
    $evm.log(:info, "Stack #{stack} does not have a raw_delete_stack action")
  end
end

begin
  require 'rest-client'

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
