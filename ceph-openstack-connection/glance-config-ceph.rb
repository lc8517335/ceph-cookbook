# attention:
# this recipe should run after the openstack and ceph are working correctly!
#

include_recipe 'ceph::_common'
include_recipe 'ceph::mon_install'
include_recipe 'ceph::conf'
platform_options = node['openstack']['image']['platform']
cluster = 'ceph'

class ::Chef::Recipe # rubocop:disable Documentation
  include ::Openstack
end


rbd_user = node['openstack']['image']['api']['rbd']['rbd_store_user']
puts "**********************rbd_user:#{rbd_user}"
if mon_nodes.nil?
  rbd_key = ""
  LOG.info("ceph storage cluster is not working,rbd key is empty#{rbd_key}")
  puts "**********************mon_nodes_is_not_ok,rbd key is empty:#{rbd_key}"
else
  rbd_key = mon_nodes[0]['ceph']['glance-secret']
  puts "**********************rbd_key:#{rbd_key}"
end

template "/etc/ceph/ceph.client.#{rbd_user}.keyring" do
  source 'ceph.client.keyring.erb'
  cookbook 'openstack-common'
  owner node['openstack']['image']['user']
  group node['openstack']['image']['group']
  mode 00600
  variables(
      name: rbd_user,
      key: rbd_key
  )
end

execute "modify the glance-api.conf" do
  command "sed -i 's/default_store = file/default_store = rbd/g' /etc/glance/glance-api.conf"
  ignore_failure true
  notifies :restart, 'service[glance-api-ceph]', :immediately
end

service 'glance-api-ceph' do
  service_name platform_options['image_api_service']
  supports status: true, restart: true
  action :enable
end

