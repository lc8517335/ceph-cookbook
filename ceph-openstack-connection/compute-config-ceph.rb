# encoding: UTF-8
#
# Cookbook Name:: openstack-compute
# Recipe:: libvirt_rbd
#
# Copyright 2014, x-ion GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'ceph::_common'
include_recipe 'ceph::mon_install'
include_recipe 'ceph::conf'
cluster = 'ceph'

class ::Chef::Recipe # rubocop:disable Documentation
  include ::Openstack
end

platform_options = node['openstack']['compute']['platform']

platform_options['libvirt_ceph_packages'].each do |pkg|
  package pkg do
    options platform_options['package_overrides']
    action :upgrade
  end
end

execute "rpm -Uvh --force #{node['ceph']['rhel']['extras']['repository']}/qemu-kvm-0.12.1.2-2.415.el6.3ceph.x86_64.rpm #{node['ceph']['rhel']['extras']['repository']}/qemu-img-0.12.1.2-2.415.el6.3ceph.x86_64.rpm" do
  not_if "rpm -qa | grep qemu | grep ceph"
end

# TODO(srenatus) there might be multiple secrets, cinder will tell nova-compute
# which one should be used for each single volume mount request
Chef::Log.info("rbd_secret_name: #{node['openstack']['compute']['libvirt']['rbd']['rbd_secret_name']}")
secret_uuid = node['openstack']['block-storage']['rbd_secret_uuid']
#secret_uuid = 'f7c4b7af-f0b2-459c-bae8-5d3b8668ea07'
puts "******************secret_uuid:#{secret_uuid}"

if mon_nodes.nil?
  ceph_key = ""
  LOG.info("ceph storage cluster is not working,rbd key is empty#{ceph_key}")
  puts "**********************mon_nodes_is_not_ok,rbd key is empty:#{ceph_key}"
else
  ceph_key = mon_nodes[0]['ceph']['cinder-secret']
  puts "**********************ceph_key:#{ceph_key}"
end

require 'securerandom'
filename = SecureRandom.hex

template "/tmp/#{filename}.xml" do
  source 'secret.xml.erb'
  user 'root'
  group 'root'
  mode '700'
  variables(
    uuid: secret_uuid,
    client_name: node['openstack']['compute']['libvirt']['rbd']['rbd_user']
  )
  not_if "virsh secret-list | grep #{secret_uuid}"
end

execute "virsh secret-define --file /tmp/#{filename}.xml" do
  not_if "virsh secret-list | grep #{secret_uuid}"
end

# this will update the key if necessary
execute "virsh secret-set-value --secret #{secret_uuid} --base64 #{ceph_key}" do
  #not_if "virsh secret-get-value #{secret_uuid} | grep '#{ceph_key}'"
  notifies :restart, 'service[nova-compute-ceph]', :immediately
end

file "/tmp/#{filename}.xml" do
  action :delete
end

service 'nova-compute-ceph' do
  service_name platform_options['compute_compute_service']
  supports status: true, restart: true
  subscribes :restart, resources('template[/etc/nova/nova.conf]')

  action :restart
end
