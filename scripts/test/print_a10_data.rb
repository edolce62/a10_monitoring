#! /usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path('../../../src', __FILE__)
require 'a10_monitoring'
require 'pp'

def print_output(slb, method)
  puts "---------------------------------------------------------------------------------"
  puts method
  puts "---------------------------------------------------------------------------------"
  puts
  pp slb.send(method)
  puts
end

fqdn = ARGV.shift or abort "Please specify SLB FQDN"
slb = A10LoadBalancer.new(fqdn)

print_output(slb, :virtual_server_names)
print_output(slb, :virtual_server_configs)
print_output(slb, :virtual_server_stats)
print_output(slb, :service_group_names)
print_output(slb, :service_group_configs)
print_output(slb, :service_group_stats)
print_output(slb, :network_interface_port_nums)
print_output(slb, :network_interface_configs)
print_output(slb, :network_interface_stats)
