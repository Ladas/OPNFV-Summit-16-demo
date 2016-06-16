#
# Description: This method checks to see if the stack has been provisioned
#   and whether the refresh has completed
#

def refresh_provider(service)
  provider = service.orchestration_manager

  $evm.log("info", "Refreshing provider #{provider.name}")
  $evm.set_state_var('provider_last_refresh', provider.last_refresh_date.to_i)
  provider.refresh
end

def refresh_may_have_completed?(service)
  provider = service.orchestration_manager
  provider.last_refresh_date.to_i > $evm.get_state_var('provider_last_refresh')
end

def check_deployed(service)
  finished     = false
  error_reason = ""
  
  $evm.log("info", "Check service #{service.name} orchestration deployed")
  # check whether the stack deployment completed
  status, reason = service.orchestration_stack_status
  $evm.log("info", "Service #{service.name} deployment status. Status: #{status}, reason: #{reason}")
  
  case status.downcase
  when 'create_complete', 'active'
    finished = true
  when 'rollback_complete', 'delete_complete', /failed$/, /canceled$/
    error_reason = reason
  end

  $evm.log("info", "Please examine stack resources for more details") unless error_reason.blank?

  $evm.set_state_var('deploy_result', $evm.root['ae_result'])
  $evm.set_state_var('deploy_reason', $evm.root['ae_reason'])

  refresh_provider(service)

  return finished, error_reason
end

def check_refreshed(service)
  $evm.log("info", "Check refresh status of stack (#{service.stack_name})")

  if refresh_may_have_completed?(service)
    $evm.root['ae_result'] = $evm.get_state_var('deploy_result')
    $evm.root['ae_reason'] = $evm.get_state_var('deploy_reason')
    $evm.log("info", "Refresh completed.")
  else
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '30.seconds'
  end
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
