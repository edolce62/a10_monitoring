#! /usr/bin/env ruby

# Copyright 2016 Yahoo Inc.
# Licensed under the terms of the New-BSD license. Please see LICENSE file in
# the project root for terms.

$LOAD_PATH.unshift File.expand_path('../../../src', __FILE__)
require 'a10_monitoring'

# Server status code 1 means up, 0 means down. See API docs page 226.
SERVER_STATUS_UP = 1

#===============================================================================
# Application usage and options
#===============================================================================

DESCRIPTION = <<-STR
Check A10 load balancer vserver health, which is defined as the percent of servers
that are up. Returns:

CRITICAL if % up < critical-threshold
WARNING  if % up < warning-threshold
OK       otherwise
STR

EXAMPLES = <<-STR
__APPNAME__ [options]
STR

cli = CommandLine.new(:description => DESCRIPTION, :examples => EXAMPLES)

cli.option(:slb, '-s', '--slb HOST[:PORT]', "SLB host and port. Assumes port 80 if not specified.") do |v|
  v
end
cli.option(:warning_threshold, '-w', '--warning PCT', 'Warning threshold, as percent (0-100)', 80) do |v|
  Float(v)
end
cli.option(:critical_threshold, '-c', '--critical PCT', 'Critical threshold, as percent (0-100)', 20) do |v|
  Float(v)
end
cli.option(:vserver, '-V', '--vserver NAME', "A10 vserver name.") do |v|
  v
end
cli.option(:verbose, '-v', '--verbose', "Enable verbose output, including backtraces.") do
  true
end
cli.option(:version, nil, '--version', "Print the version string and exit.") do
  puts A10_MONITORING_VERSION_MESSAGE
  exit
end

#===============================================================================
# Functions
#===============================================================================

# Convert virtual server status to string (p. 255 in API docs)
def vserver_status_to_string(code)
  case code
  when 0 then :DISABLED
  when 1 then :ALL_UP
  when 2 then :PARTIAL_UP
  when 3 then :FUNC_UP
  when 4 then :DOWN
  else        :UNKNOWN
  end
end

#===============================================================================
# Main
#===============================================================================

slb = nil

begin
  # Parse command-line arguments
  cli.parse
  raise ArgumentError, 'please specify the SLB host:port'  unless cli.slb
  raise ArgumentError, 'please specify warning threshold'  unless cli.warning_threshold
  raise ArgumentError, 'please specify critical threshold' unless cli.critical_threshold
  raise ArgumentError, 'please specify vserver name'       unless cli.vserver

  # Fetch vserver data
  slb = A10LoadBalancer.new(cli.slb)
  vserver = slb.virtual_server_configs[cli.vserver]
  Icinga::quit(Icinga::UNKNOWN, "virtual server '#{cli.vserver}' not found") unless vserver

  # Don't query service groups more than once
  service_group_percent_up = {}
  ports_percent_up = {}
  all_servers_down = []

  # Examine each port and check the status
  vserver[:vport_list].each do |port,data|
    group       = data[:service_group]
    status_code = data[:status]
    status_name = vserver_status_to_string(status_code)

    # If not up, quit
    unless [:ALL_UP, :PARTIAL_UP, :FUNC_UP].include? status_name
      Icinga.quit(Icinga::CRITICAL, "vserver #{cli.vserver} port #{port} status is #{status_name}")
    end

    # If we already checked this service group, we can skip it
    if service_group_percent_up[group]
      ports_percent_up[port] = service_group_percent_up[group]
      next
    end

    # Fetch the service group and grab the hosts
    servers = slb.service_group_configs[group][:member_list]

    # Calculate the percent of servers that are up.
    servers_down = servers.select { |s| s[:status] != SERVER_STATUS_UP }.map { |s| s[:server] }
    up_flags     = servers.map { |s| s[:status] == SERVER_STATUS_UP ? 1 : 0 }
    num_up       = up_flags.inject(&:+)
    num_hosts    = up_flags.size
    pct_up       = 100.0 * num_up.to_f / num_hosts

    # Save the percent up for this service group and port
    service_group_percent_up[group] = pct_up
    ports_percent_up[port] = pct_up

    # Return warning or critical if bad
    message = "vserver %s port %d is %0.1f%% up (hosts down: %s)" %
      [cli.vserver, port, pct_up, servers_down.join(', ')]
    Icinga.quit(Icinga::CRITICAL, message) if pct_up < cli.critical_threshold
    Icinga.quit(Icinga::WARNING,  message) if pct_up < cli.warning_threshold

    # Otherwise save the hosts that are down
    all_servers_down += servers_down
  end

  # Write the final status message, then quit
  ports = ports_percent_up.keys.sort.map { |x| "%d=%0.0f%%" % [x, ports_percent_up[x]] }.join(', ')
  message = "vserver #{cli.vserver} is up (ports: #{ports})"
  message += " (hosts down: #{all_servers_down.uniq.join(', ')})" unless all_servers_down.empty?
  Icinga.quit(Icinga::OK, message)

rescue => e
  Utils.print_backtrace(e) if cli.verbose
  Icinga::quit(Icinga::CRITICAL, "#{e.class.name}: #{e.message}")
ensure
  slb.close_session if slb
end
