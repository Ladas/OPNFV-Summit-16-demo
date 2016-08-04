#
# Description: <Method description here>
#
require 'rest-client'

begin
  url = 'http://localhost:3000'
  request_ids  = $evm.get_state_var(:automation_requests_ids)
  
  all_finished = true
  
  request_ids.each do |request_id|
    $evm.log(:info, "Checking status of request #{request_id}")
    # We call poll this to check on status:
    query = "/api/automation_requests/#{request_id}"
    rest_return = RestClient::Request.execute(
                                    method: :get, 
                                    url: url + query, 
                                    :user => 'admin',
                                    :password => 'smartvm',
                                    :headers => {:accept => :json},
                                    verify_ssl: false)
    result = JSON.parse(rest_return)
    request_state = result['request_state']
    
    $evm.log(:info, "Status of request #{request_id} is #{request_state}")
    
    all_finished = false if request_state != "finished"
  end 
  
  if all_finished
    $evm.root['ae_result'] = 'ok'
  else
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '30.seconds'    
  end  

  exit MIQ_OK
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
