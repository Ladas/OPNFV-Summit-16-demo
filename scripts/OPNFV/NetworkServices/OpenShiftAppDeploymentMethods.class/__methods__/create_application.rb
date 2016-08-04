require 'json'

ose_config = $evm.object['ose_config']
ose_config[:password] = $evm.current.decrypt('ose_password')
$evm.log(:info, "OSE Config: #{ose_config.inspect}")

environment = $evm.object['environment']
openshift_project = "#{$evm.get_state_var(:gitlab_group)['name']}-#{environment}"
openshift_template = "#{$evm.get_state_var(:service_hash)['template_root']}-#{environment}"

service_hash = $evm.get_state_var(:service_hash)
parameters = ''
$evm.log(:info, "Service Hash: #{service_hash.inspect}")
$evm.log(:info, "Service Parameters: #{service_hash['parameters'].inspect}")
JSON.parse(service_hash['parameters']).each do |k,v|
  parameters += ',' unless parameters.empty?
  parameters += "#{k}=#{v}"
end.empty?

cmd  = "oc project #{openshift_project} ; "
cmd += "oc new-app"
cmd += " --template=#{openshift_template}"
cmd += " -p '#{parameters}'" unless parameters.empty?

$evm.log(:info, "COMMAND: #{cmd}")
raise 'OpenShift 3 application deployment failed.' unless system(cmd)
