def template_interface(name, subnet_id, security_group, subnet_name)
  eip = "#{name}Address"
  eip_association = "Associate#{name}"
  network_interface = "#{name}"
  interface = {
    network_interface => {
      "Type"=>"AWS::EC2::NetworkInterface",
      "Properties" => {
        "SubnetId"=> subnet_id,
        "Description"=>"",
        "GroupSet"=>[{"Ref"=>security_group}],
        "SourceDestCheck"=>"true",
        "Tags"=>[{"Key"=>"Network", "Value"=>"Control"}]}},
  }
  if subnet_name == "CloudExternal"
    interface.merge!(
      eip => {
        "Type"=>"AWS::EC2::EIP",
        "Properties"=>{"Domain"=>"vpc"}},
      eip_association => {
        "Type"=>"AWS::EC2::EIPAssociation",
        "Properties"=>
        {"AllocationId"=>{"Fn::GetAtt"=>[eip, "AllocationId"]},
          "NetworkInterfaceId"=>{"Ref"=>network_interface}}},
    )
  end  
  interface
end

def security_group(security_group, vpc_id)
  {
    security_group => {
      "Type"=>"AWS::EC2::SecurityGroup",
      "Properties"=> {
        "VpcId"=> vpc_id,
        "GroupDescription"=>"Enable all",
        "SecurityGroupIngress"=> [{
          "IpProtocol"=>"tcp",
          "FromPort"=>"0",
          "ToPort"=>"65535",
          "CidrIp"=>"0.0.0.0/0"
        }, {
          "IpProtocol"=>"udp",
          "FromPort"=>"0",
          "ToPort"=>"65535",
          "CidrIp"=>"0.0.0.0/0"
        }, {
          "IpProtocol"=>"icmp",
          "FromPort"=>"-1",
          "ToPort"=>"-1",
          "CidrIp"=>"0.0.0.0/0"  
        }]
      }
    },
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

def instance(name, network_interfaces, keyname, image_id,availability_zone,instance_type)
  nics = network_interfaces.each_with_index.map do |x, i|
    {"NetworkInterfaceId" => {"Ref" => x}, "DeviceIndex" => i.to_s}
  end

  {
    name =>
      {"Type"=>"AWS::EC2::Instance",
      "Properties"=> {
        "InstanceType" => instance_type,
        "ImageId"=> image_id,
        "KeyName"=> keyname,
        "AvailabilityZone"=>availability_zone,
        "NetworkInterfaces"=> nics,
        "Tags"=>[{"Key"=>"Role", "Value"=>"Test Instance"}],
        "UserData"=>
        {"Fn::Base64"=>
          {"Fn::Join"=>
            ["",
              ["#!/bin/bash -ex",
                "\n",
                "echo \"GATEWAYDEV=eth0\" | tee -a /etc/sysconfig/network",
                "\n",
                "rm /etc/sysconfig/network-scripts/ifcfg-ens2",
                "\n",
                "#{ethx_config('eth1')}",
                "\n",
                "#{ethx_config('eth2')}",
                "\n",
                "#{ethx_config('eth3')}",
                "\n",
                "ip r",
                "\n",
                "systemctl restart network",
                "\n",
                "ip r",
                "\n",
                "\n"]]}}}}
  }
end

def base_template(name)
  {
    "Description" => "#{name} CFN template",
    "Resources"   => {}
  }
end

def create_template(name,nsd_properties,nsd_requirements)
  vpc_id = nsd_properties['vpc_id'] #'vpc-303bc157'
  image_id = nsd_properties['image_id']
  subnet=nil
  security_group=nil
  availability_zone=nsd_properties['availabilityzone']
  key_name=nsd_properties['key_name']
  instance_type=nsd_properties['image_type']
  template_content = base_template(name)
  nic = []

  network=$evm.vmdb('ManageIQ_Providers_Amazon_NetworkManager_CloudNetwork').find_by_name(vpc_id.strip)
  image=$evm.vmdb('ManageIQ_Providers_Amazon_CloudManager_Template').find_by_name(image_id.strip)
  
  if network==nil
    raise "vpc_id #{vpc_id} for amazon is not valid."
  elsif image==nil
    raise "Image id #{image_id} for amazon is not valid."
  elsif availability_zone==nil
    raise "availabilityzone is nil"
  end
  # set default instance_type
  if  instance_type==nil
    instance_type="t2.medium"
  end

  nsd_requirements.each do|requirement|
    requirement.each do|key,value|
      $evm.log(:info ,"finding #{key}  and #{value}")
      if value!=nil
        #check if manageIQ database has the interface and get it's id
        $evm.log(:info ,"finding #{value} subnet in amazon")
        subnet=$evm.vmdb('ManageIQ_Providers_Amazon_NetworkManager_CloudSubnet').find_by_name(value.strip)
        if subnet==nil
          raise "#{value} subnet not found in amazon"
        end
        nic<< value.gsub("\s", "").gsub("_", "")
        security_group_name="DefaultSecurity"+value.gsub("\s", "").gsub("_", "")
        template_content["Resources"].merge!(security_group(security_group_name, network.ems_ref))
        template_content["Resources"].merge!(template_interface(value.gsub("\s", "").gsub("_", ""), subnet.ems_ref, security_group_name, subnet.name))
      end
    end
  end
  
  $evm.log(:info ,"nic array==> #{nic}")
  template_content["Resources"].merge!(instance("Ec2Instance", nic, key_name, image.ems_ref,availability_zone,instance_type))

  resource = {:name      => name,
              :type      => "OrchestrationTemplateCfn",
              :orderable => true,
              :content   => JSON.pretty_generate(template_content)}

  url     = "http://localhost:3000/api/orchestration_templates"
  options = {:method     => :post,
             :url        => url,
             :verify_ssl => false,
             :payload    => {"action"   => "create",
                             "resource" => resource}.to_json,
             :headers    => {"X-Auth-Token" => MIQ_API_TOKEN,
                             :accept        => :json}}
  $evm.log("info", "Creating CFN template #{options}")

  body = JSON.parse(RestClient::Request.execute(options))

  $evm.vmdb('orchestration_template_cfn', body["results"].first["id"])
end

def deploy_amazon_stack(orchestration_manager, parent_service, vnf_service)
  nsd_properties = JSON.parse(vnf_service.custom_get('properties'))
  nsd_requirements = JSON.parse(vnf_service.custom_get('requirements'))
  nsd_capabilities = JSON.parse(vnf_service.custom_get('capabilities'))

  $evm.log("info", "Listing nsd_properties #{nsd_properties}")
  $evm.log("info", "Listing nsd_requirements #{nsd_requirements}")
  $evm.log("info", "Listing nsd_capabilities #{nsd_capabilities}")

  name = "#{parent_service.name} #{vnf_service.name} #{parent_service.id}"
  template = create_template(name,nsd_properties,nsd_requirements)

  resource = {:name                   => "#{parent_service.name} #{vnf_service.name}",
              :type                   => "ServiceOrchestration",
              :orchestration_template => {:id => template.id},
              :orchestration_manager  => {:id => orchestration_manager.id},
              :parent_service         => {:id => parent_service.id},
              :stack_name             => name.gsub("\s", "-").gsub("_", "-"),
              :stack_options          => {},
              :display                => true}

  url     = "http://localhost:3000/api/services"
  options = {:method     => :post,
             :url        => url,
             :verify_ssl => false,
             :payload    => {"action"   => "create",
                             "resource" => resource}.to_json,
             :headers    => {"X-Auth-Token" => MIQ_API_TOKEN,
                             :accept        => :json}}
  $evm.log("info", "Creating CFN service #{options}")

  body = JSON.parse(RestClient::Request.execute(options))

  orchestration_service = $evm.vmdb('service', body["results"].first["id"])
  orchestration_service.custom_set('properties', nsd_properties.to_json)
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

def ethx_config(ethx)
  <<-EOS
cat > /etc/sysconfig/network-scripts/ifcfg-#{ethx} << EOF
DEVICE="#{ethx}"
BOOTPROTO="dhcp"
ONBOOT="yes"
TYPE="Ethernet"
PERSISTENT_DHCLIENT="yes"
NM_CONTROLLED=no
EOF
  EOS
end

def dialog_value(key)
  bundle_dialog = YAML.load($evm.root['service_template_provision_task'].get_option(:parsed_dialog_options) || "{}")
  $evm.log("info", "Listing bundle_dialog_options #{bundle_dialog}")

  $evm.root.attributes[key] || bundle_dialog[:dialog].try(:[], key)
end

begin
  require 'rest-client'

  nsd = $evm.get_state_var(:nsd)
  $evm.log("info", "Listing nsd #{nsd}")
  $evm.log("info", "Listing Root Object Attributes:")
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================")

  parent_service = $evm.root['service_template_provision_task'].destination
  parent_service.name = dialog_value('dialog_service_name')

  network_service = $evm.vmdb('service', dialog_value('dialog_network_service'))

  deploy_cfns(network_service, parent_service)
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
