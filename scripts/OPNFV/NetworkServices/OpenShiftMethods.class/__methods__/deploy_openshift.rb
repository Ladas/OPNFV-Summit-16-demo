#
# Description: <Method description here>
#
require 'rest-client'

begin
  post_params = {
      "action" => "create",
      "resource" => {
          "provider_name" => "pleasework2d3d_centos",
          "provider_type" => "openshiftEnterprise",
          "method_type" => "unmanaged",
          "nodes"=> [{
              "name" => "54.84.213.105",
              "roles" => {
                  "node" => true,
                  "master" => true,
                  "dns" => false,
                  "etcd" => false,
                  "infrastructure" => false,
                  "load_balancer" => false,
                  "storage" => true}
               }
           ],
          "identity_authentication" => {
              "type" => "AuthenticationAllowAll"
          },
          "ssh_authentication" => {
            "auth_key" => "#{$evm.root['dialog_aws_auth_key']}",
            "userid" => "ec2-user"
          },
          "rhsm_authentication" => {
              "userid" => "#{$evm.root['dialog_rhn_user']}",
              "password" => "#{$evm.root['dialog_rhn_password']}",
              "rhsm_sku" => "ES0113909"
          }
      }
  }.to_json

  url = 'http://localhost:3000'
  query = '/api/container_deployments'
  $evm.log(:info, "Trying to deploy openshift, with #{post_params}")
  rest_return = RestClient::Request.execute(
                                  method: :post,
                                  url: url + query,
                                  :user => 'admin',
                                  :password => 'smartvm',
                                  :headers => {:accept => :json},
                                  :payload => post_params,
                                  verify_ssl: false)
  $evm.log(:info, "Deployed openshift, with #{rest_return}")
  result = JSON.parse(rest_return)

  container_deployment_id = result['results'][0]['id']
  query = "/api/container_deployments/#{container_deployment_id}"
  
  request_id = nil
  rest_return = RestClient::Request.execute(
    method: :get, 
    url: url + query, 
    :user => 'admin',
    :password => 'smartvm',
    :headers => {:accept => :json},
    verify_ssl: false)
  result = JSON.parse(rest_return)

  $evm.log(:info, "Automation task result is #{result }")
  $evm.log(:info, "Automation task ID is  #{result['automation_task_id']}")
  request_id = result['automation_task_id']
  
  # Set requests to wait for in a next state
  $evm.set_state_var(:automation_requests_ids, [request_id])
  
  $evm.root['ae_result'] = 'ok'
  exit MIQ_OK
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
