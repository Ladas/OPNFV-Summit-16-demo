require 'rubygems'
require 'json'
require 'uri'
require 'openssl'
require 'openshift_client'

def get_client
  manager = $evm.vmdb('ManageIQ_Providers_ContainerManager', $evm.root['dialog_openshift_manager'])
  $evm.log(:info, "Loading manager #{manager.inspect}")
  
  OpenshiftClient::Client.new(
    URI::HTTPS.build(:host => manager.hostname, :port => manager.port.presence.try(:to_i)),
    'v1',
    :ssl_options    => {:verify_ssl => OpenSSL::SSL::VERIFY_NONE},
    :auth_options   => {:bearer_token => manager.authentication_token},
    :http_proxy_uri => nil
  )
end  

def create_project(client)
  $evm.log(:info, "openshift_project: #{openshift_project.inspect}")
  content = {
    :kind => 'ProjectRequest',
    :metadata => { :name => openshift_project['name'] },
    :displayName => openshift_project['displayname'],
    :description => openshift_project['description']
  }

  $evm.log(:info, "Creating project with: #{content}")
  result = client.create_project(content)
  $evm.log(:info, "Creating project result: #{result.inspect}")
end  

def create_role_bindings(client)
  content = {
    :metadata => { :name => 'edit', :namespace => openshift_project['name'] },
    :userNames => nil,
    :groupNames => [ openshift_project['group'] ],
    :subjects => [],
    :roleRef => { :name => 'edit' }
  }	

  $evm.log(:info, "Create cluster role bindings with: #{content}")
  # TODO figure out what rights to set
  #result = client.create_cluster_role_binding(content)
  $evm.log(:info, "Create cluster role bindings result: #{result.inspect}")
end

def create_template(client)
  $evm.log(:info, "Create template with textarea: #{$evm.root['dialog_openshift_template']}")
  template = JSON.parse($evm.root['dialog_openshift_template']).symbolize_keys
  template[:metadata][:namespace] = openshift_project['name']
 
  $evm.log(:info, "Create template with: #{template}")
  result = client.create_template(template)
  $evm.log(:info, "Create template result #{result}")
end  

def openshift_project
  {
    'name'        => $evm.root['dialog_openshift_project_name'],
    'displayname' => $evm.root['dialog_openshift_project_display_name'],
    'description' => "",
    'group'       => 'authenticated'
  }
end

begin
  $evm.log(:info, "*********** Creating project #{$evm.object['dialog_openshift_project_name']}")
 
  client = get_client

  create_project(client)
  create_template(client)

  $evm.root['ae_result'] = 'ok'
  exit MIQ_OK
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
