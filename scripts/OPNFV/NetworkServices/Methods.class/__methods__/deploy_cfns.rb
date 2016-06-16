def template_interface(name, subnet_id, security_group)
  eip = "#{name}Address"
  eip_association = "Associate#{name}"
  network_interface = "#{name}"  
  {
    eip => {
      "Type"=>"AWS::EC2::EIP", 
      "Properties"=>{"Domain"=>"vpc"}},
    eip_association => {
      "Type"=>"AWS::EC2::EIPAssociation",
      "Properties"=>
        {"AllocationId"=>{"Fn::GetAtt"=>[eip, "AllocationId"]},
          "NetworkInterfaceId"=>{"Ref"=>network_interface}}},
    network_interface => {
      "Type"=>"AWS::EC2::NetworkInterface",
      "Properties" => {
        "SubnetId"=> subnet_id,
        "Description"=>"",
        "GroupSet"=>[{"Ref"=>security_group}],
        "SourceDestCheck"=>"true",
        "Tags"=>[{"Key"=>"Network", "Value"=>"Control"}]}},
  }
end  

def security_group(security_group, vpc_id)
  {
    security_group =>
      {"Type"=>"AWS::EC2::SecurityGroup",
       "Properties"=>
          {"VpcId"=> vpc_id,
           "GroupDescription"=>"Enable SSH access via port 22",
           "SecurityGroupIngress"=>
            [{"IpProtocol"=>"tcp",
              "FromPort"=>"22",
              "ToPort"=>"22",
              "CidrIp"=>"0.0.0.0/0"}]}},
  }
end  

def security_group_1(security_group, vpc_id)
  {
    security_group =>
      {"Type"=>"AWS::EC2::SecurityGroup",
       "Properties"=>
          {"VpcId" => vpc_id,
           "GroupDescription"=>"Enable HTTP access via user defined port",
           "SecurityGroupIngress"=>
            [{"IpProtocol"=>"tcp",
              "FromPort"=>80,
              "ToPort"=>80,
              "CidrIp"=>"0.0.0.0/0"}]}},
  }  
end  

def instance(name, network_interfaces, keyname, image_id)
  nics = network_interfaces.each_with_index.map do |x, i| 
    {"NetworkInterfaceId" => {"Ref" => x}, "DeviceIndex" => i.to_s}
  end
  
  {
    name =>
    {"Type"=>"AWS::EC2::Instance",
     "Properties"=> {
       "InstanceType" => "t1.micro",
       "ImageId"=> image_id,
       "KeyName"=> keyname,
       "NetworkInterfaces"=> nics,
       "Tags"=>[{"Key"=>"Role", "Value"=>"Test Instance"}],
       "UserData"=>
        {"Fn::Base64"=>
          {"Fn::Join"=>
            ["",
             ["#!/bin/bash -ex",
              "\n",
              "\n",
              "yum install ec2-net-utils -y",
              "\n",
              "ec2ifup eth1",
              "\n",
               "service httpd start"]]}}}}
   }
end  


def base_template(name)
  { 
    "Description" => "#{name} CFN template",
    "Resources"   => {}
  }
end

def create_template(name)
  vpc_id = 'vpc-a06de3c5' 
  security_group_1 = "ControlSecurityGroup"
  security_group_2 = "WebSecurityGroup"
  nic1 = "ControlXface"
  nic2 = "WebXface"
  
  template_content = base_template(name)
  template_content["Resources"].merge!(security_group(security_group_1, vpc_id))
  template_content["Resources"].merge!(security_group(security_group_2, vpc_id))
  template_content["Resources"].merge!(template_interface(nic1, 'subnet-ac904787', security_group_1))
  template_content["Resources"].merge!(template_interface(nic2, 'subnet-1852bb33', security_group_2)) 
  template_content["Resources"].merge!(instance("Ec2Instance", [nic1, nic2], "EmsRefreshSpec-KeyPair", 'ami-5769193e'))

  $evm.vmdb('orchestration_template_cfn').create(
    :name      => name, 
    :orderable => true, 
    :content   => JSON.pretty_generate(template_content))
end

# TODO change above code to generate a real CFN template

def deploy_amazon_stack(orchestration_manager, parent_service, vnf_service)
  nsd_properties = JSON.parse(vnf_service.custom_get('properties'))
  nsd_requirements = JSON.parse(vnf_service.custom_get('requirements'))
  nsd_capabilities = JSON.parse(vnf_service.custom_get('capabilities'))
  
  $evm.log("info", "Listing nsd_properties #{nsd_properties}")
  $evm.log("info", "Listing nsd_requirements #{nsd_requirements}")
  $evm.log("info", "Listing nsd_capabilities #{nsd_capabilities}")
  
  name = "#{parent_service.name} #{vnf_service.name}"
  # TODO generate a CFN template according to VNF properties, requirements and capabilities
  template = create_template(name)
  
  $evm.log("info", "Deploying CFN template #{name}")
  orchestration_service = $evm.vmdb('ServiceOrchestration').create(
    :name => "#{parent_service.name} #{vnf_service.name}")

  orchestration_service.stack_name             = name.gsub("\s", "-").gsub("_", "-")
  orchestration_service.orchestration_template = template
  orchestration_service.orchestration_manager  = orchestration_manager
  orchestration_service.stack_options          = {}
  orchestration_service.display                = true
  orchestration_service.parent_service         = parent_service
  orchestration_service.deploy_orchestration_stack 
end  

def deploy_cfns(network_service, parent_service)
  network_service.direct_service_children.detect { |x| x.name == 'VNFs' }.direct_service_children.each do |vnf_service| 
    properties = JSON.parse(vnf_service.custom_get('properties'))
    orchestration_manager = $evm.vmdb('ManageIQ_Providers_Amazon_CloudManager').find_by_name(properties['vim_id'])
    next unless orchestration_manager
    
    deploy_amazon_stack(orchestration_manager, parent_service, vnf_service)
  end  
end

begin
  nsd = $evm.get_state_var(:nsd)
  $evm.log("info", "Listing nsd #{nsd}")
  $evm.log("info", "Listing Root Object Attributes:")
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================")
  
  parent_service = $evm.root['service_template_provision_task'].destination
  parent_service.name = $evm.root.attributes['dialog_service_name']
  
  network_service = $evm.vmdb('service', $evm.root.attributes['dialog_network_service'])
  
  deploy_cfns(network_service, parent_service)
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
