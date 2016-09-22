#
# Description: This method updates the service provisioning status
# Required inputs: status
#

prov = $evm.root['service_template_provision_task']

unless prov
  $evm.log(:error, "Service Template Provision Task not provided")
  exit(MIQ_STOP)
end

status = $evm.inputs['status']

# Update Status Message
updated_message  = "[#{$evm.root['miq_server'].name}] "
updated_message += "Step [#{$evm.root['ae_state']}] "
updated_message += "Status [#{status}] "
# TODO the message is missleading, figure out why, always says it's processed
# updated_message += "Message [#{prov.message}] "
updated_message += "Current Retry Number [#{$evm.root['ae_state_retries']}]"
prov.miq_request.user_message = updated_message
prov.message = status
