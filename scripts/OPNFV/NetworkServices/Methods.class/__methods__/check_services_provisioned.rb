#
# Description: This method checks to see if the service stacks has been provisioned
#

def check_deployed(service)
  finished     = false
  error_reason = ""
  
  $evm.log("info", "Check service #{service.name} orchestration deployed")
  # check whether the stack deployment completed
  status, reason = service.orchestration_stack.normalized_live_status
  $evm.log("info", "Service #{service.name} deployment status. Status: #{status}, reason: #{reason}")
  
  case status.downcase
  when 'create_complete', 'active'
    finished = true
  when 'rollback_complete', 'delete_complete', 'error', /failed$/, /canceled$/
    error_reason = reason
  end
  
  $evm.log("info", "Please examine stack resources for more details") unless error_reason.blank?

  $evm.set_state_var('deploy_result', $evm.root['ae_result'])
  $evm.set_state_var('deploy_reason', $evm.root['ae_reason'])

  return finished, error_reason
end

begin
  all_services_deployed = true
  error_reasons         = ""
  parent_service        = $evm.root['service_template_provision_task'].destination
  parent_service.direct_service_children.each do |orchestration_service|
    service_deployed, service_error_reason = check_deployed(orchestration_service)

    all_services_deployed = all_services_deployed && service_deployed
    error_reasons += service_error_reason
  end  

  if !error_reasons.blank?
    $evm.root['ae_result'] = 'error'
    $evm.root['ae_reason'] = error_reasons
  elsif all_services_deployed
    $evm.root['ae_result'] = 'ok'
  else
    # deployment not done yet in provider
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '30.seconds'
  end
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
