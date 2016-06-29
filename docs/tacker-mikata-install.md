## Tacker in Mikata installation

1. yum install -y git
2. easy_install pip
3. Ensure that **/etc/neutron/plugins/ml2/ml2_conf.ini** uses port_security as an extension_driver:

       [ml2]
       extension_drivers = port_security
4. Modify **/etc/heat/policy.json** like so:

       "resource_types:OS::Nova::Flavor": "role:admin"
5. Create database:mysql -uroot -p

       CREATE DATABASE tacker;
         GRANT ALL PRIVILEGES ON tacker.* TO 'tacker'@'localhost' \
           IDENTIFIED BY '<create a password>';
         GRANT ALL PRIVILEGES ON tacker.* TO 'tacker'@'%' \
           IDENTIFIED BY '<same password as above>';
       exit;
6. source overcloudrc
7. openstack user create --password <use password from above> tacker
8. openstack role add --project admin --user tacker admin
9. openstack service create --name tacker --description "Tacker Project" nfv-orchestration
10. Create endpoints:

        openstack endpoint create --region regionOne \
          --publicurl 'http://<controller IP>:8888/' \
          --adminurl 'http://<controller IP>:8888/' \
          --internalurl 'http://<controller IP>:8888/' <SERVICE-ID>
11. git clone -b stable/mitaka https://github.com/openstack/tacker
12. yum install libffi-devel -y
13. mkdir /etc/tacker
14. cp -r <Tacker source dir>/etc/tacker/* /etc/tacker/
15. cp <Tacker source dir>/etc/init.d/tacker-server /etc/init.d/tacker-server
16. cd tacker
17. pip install -r requirements.txt
18. pip install six --upgrade
19. pip install tosca-parser
20. Execute the following command, replacing "username", "password" and "project_name" with something else if you don't want to use admin:  

        cat << EOF > ~/vim_config.yaml  
        auth_url: http://<controller IP>:5000  
        username: admin  
        password: <admin password from overcloudrc>  
        project_name: admin  
        domain_id: default  
        EOF  
21. python setup.py install
22. mkdir /var/log/tacker
23. Modify **/etc/tacker/tacker.conf**:
    1. Assuming Keystone, Nova, Heat and MySQL are all installed on your controller, make sure you use the **controller's IP** for all required IP addresses (instead of localhost or 127.0.0.1).
    2. Make sure your "region_name" values conform to your existing Overcloud configuration (we found the conf file to have "RegionOne" instead of "regionOne" by default -- case matters?).
    3. Make sure all "project_name" values are "admin".
    4. In the [nfvo_vim] section, add/set this line:
         default_vim = VIM0
    5. In the [database] section, add this line:
         connection = mysql://tacker:<tacker password>@<controller IP>:3306/tacker
24. /usr/bin/tacker-db-manage --config-file /etc/tacker/tacker.conf upgrade head
25. cd ~/
26. git clone -b stable/mitaka https://github.com/openstack/python-tackerclient
27. cd python-tackerclient
28. python setup.py install
29. cd ~/
30. git clone -b stable/mitaka https://github.com/openstack/tacker-horizon
31. cd tacker-horizon
32. python setup.py install
33. cp openstack_dashboard_extensions/* /usr/share/openstack-dashboard/openstack_dashboard/enabled/
34. pcs resource restart httpd
35. Create a systemd service for Tacker:
    
        cat << EOF > /usr/lib/systemd/system/tacker-server.service
        [Unit]
        Description=Tacker server
        [Service]
        Type=simple
        ExecStart=/usr/bin/python /usr/bin/tacker-server --config-file /etc/tacker/tacker.conf --log-file /var/log/tacker/tacker.log
        [Install]
        WantedBy=multi-user.target
        EOF
36. systemctl daemon-reload
37. systemctl enable tacker-server.service
38. systemctl start tacker-server.service
39. The Tacker database doesn't cooperate with the long overcloud passwords, so do this:

        mysql
        USE tacker;
        ALTER TABLE vimauths MODIFY password VARCHAR(255) NOT NULL;
        exit;
40. Finally, register the default VIM:

        tacker vim-register --config-file <your vim_config.yaml file location, from earlier step> --name VIM0 --description <pick a VIM description>


Let's talk about `<html>`!