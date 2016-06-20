#
# Description: This method checks to see if the job of all services has been provisioned
#   and whether the refresh has completed
#

def check_job_finished(service)
  # check whether the AnsibleTower job completed
  finished     = false
  error_reason = ""
  
  $evm.log("info", "Check service #{service.name} ansible job deployed")
  # check whether the stack deployment completed
  job = service.job
  status, reason = job.normalized_live_status
  $evm.log("info", "Service #{service.name} ansible job status. Status: '#{status}', Job: '#{job.name}', Reason: '#{reason}'")
  
  case status.downcase
  when 'create_complete', 'active'
    finished = true
  when 'rollback_complete', 'delete_complete', /failed$/, /canceled$/
    error_reason = reason
  end

  $evm.log("error", "Please examine ansible tower for more details. Service '#{service.name}' failed to deploy '#{job.name}'") unless error_reason.blank?

  # This will not work for longer jobs, we can do something like refresh every fifth retry? I need to fetch retry count
  job.refresh_ems unless $evm.root['ae_result'] == 'retry'

  return finished, error_reason
end  

begin
  all_services_deployed = true
  error_reasons         = ""
  parent_service        = $evm.root['service_template_provision_task'].destination
  parent_service.direct_service_children.each do |vnf_service|
    vnf_service.direct_service_children.each do |ansible_service|
      next unless ansible_service.try(:job)

      service_deployed, service_error_reason = check_job_finished(ansible_service)

      all_services_deployed = all_services_deployed && service_deployed
      error_reasons += service_error_reason
    end  
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
