require 'yaml'

begin
  nsd = YAML.load($evm.root['dialog_nsd'])
  $evm.set_state_var(:nsd, nsd)
  $evm.root['ae_result'] = 'ok'
  exit MIQ_OK

rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
