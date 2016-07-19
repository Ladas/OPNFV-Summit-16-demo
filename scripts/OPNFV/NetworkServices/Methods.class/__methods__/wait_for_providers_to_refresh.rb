#
# Description: This method checks to see if all service providers has been refreshed
#

def refresh(provider)
  $evm.log("info", "Refreshing provider #{provider.name}")
  provider.refresh
end

def refreshed?(provider)  
  $evm.log("info", "Checking provider refresh #{provider.name}, Condition: #{provider.last_refresh_date.to_i} > #{$evm.get_state_var('provider_last_refresh')}")
  provider_refreshed = provider.last_refresh_date.to_i > $evm.get_state_var('provider_last_refresh')
  errors             = provider.last_refresh_error if provider.last_refresh_error
  
  return provider_refreshed, errors
end

def service_providers_refresh(parent_service)
  all_service_providers(parent_service).each do |provider|
    refresh(provider)
  end  
end

def service_providers_refreshed?(parent_service)
  all_providers_refreshed = true
  error_reasons           = ""
  
  all_service_providers(parent_service).each do |provider|
    all_providers_refreshed, error_reason = all_providers_refreshed && refreshed?(provider)
    error_reasons += error_reason if error_reason
  end
  return all_providers_refreshed, error_reasons
end

def all_service_providers(parent_service)
  all_providers = []
  parent_service.direct_service_children.each do |orchestration_service|
    cloud_manager   = orchestration_service.try(:orchestration_manager)
    network_manager = cloud_manager.try(:network_manager)
    
    all_providers += [cloud_manager, network_manager]
  end
  all_providers.compact.uniq
end

begin
  parent_service = $evm.root['service_template_provision_task'].destination
  
  if $evm.state_var_exist?('provider_last_refresh')
    all_services_providers_refreshed, error_reasons = service_providers_refreshed?(parent_service)
  else
    $evm.set_state_var('provider_last_refresh', Time.now.to_i)
    service_providers_refresh(parent_service)
    all_services_providers_refreshed = false
    error_reasons                    = nil
  end

  if !error_reasons.blank?
    $evm.root['ae_result'] = 'error'
    $evm.root['ae_reason'] = error_reasons
  elsif all_services_providers_refreshed
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
