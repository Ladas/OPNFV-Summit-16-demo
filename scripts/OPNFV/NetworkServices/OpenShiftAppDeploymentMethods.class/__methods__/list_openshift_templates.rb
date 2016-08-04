#
# Description: List OpenShift Templates
#
require 'rubygems'
require 'httpclient'
require 'json'

ose_config = $evm.object['ose_config']
ose_config[:password] = $evm.current.decrypt('ose_password') 
ose_config[:templates_project] = 'cfme-templates'
$evm.log(:info, "OSEv3 Config: #{ose_config.inspect}")

dialog_field = $evm.object
dialog_field['sort_by'] = 'description'
dialog_field['sort_order'] = 'ascending'
dialog_field['data_type'] = 'string'
dialog_field['values'] = nil

http = HTTPClient.new
http.ssl_config.add_trust_ca(ose_config[:ca_cert])
#http.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE
headers = { "Content-Type" => "application/json", "Accept" => "application/json,version=2" }
base_uri = "https://#{ose_config[:server]}:#{ose_config[:port]}/oapi/v1"

# Authentication against OpenShift OAuth endpoint
auth_uri = "https://#{ose_config[:server]}:#{ose_config[:port]}/oauth/authorize?client_id=openshift-challenging-client&response_type=token"
http.set_auth(auth_uri, ose_config[:username], ose_config[:password])
http.www_auth.basic_auth.challenge(auth_uri)
result = http.get(auth_uri)
token = result.headers['Location'].scan(/access_token=([^&]*)&/).first.first
headers["Authorization"] = "Bearer #{token}"

uri = base_uri + "/namespaces/#{ose_config[:templates_project]}/templates"
result = http.get(uri, nil, headers)
raise JSON.parse(result.content)['reason'] unless result.status_code == 200

templates_hash = Hash.new
JSON.parse(result.content)['items'].each do |t|
  templates_hash[t['metadata']['name']] = "[#{t['metadata']['name']}] #{t['metadata']['annotations']['description']}"
end

# Clean up access token to prevent session hijacking
http.delete("https://#{ose_config[:server]}:#{ose_config[:port]}/oapi/v1/oauthaccesstokens/#{token}", nil, headers)

$evm.log(:info, "Templates: #{templates_hash.inspect}")
dialog_field['values'] = templates_hash
