#! /usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path('../../../src', __FILE__)
require 'a10_monitoring'

#===============================================================================
# Application usage and options
#===============================================================================

DESCRIPTION = <<-STR
Check A10 load balancer vserver bandwidth. Queries the SLB twice for bytes
transmitted and received. Returns:

CRITICAL if bandwidth > critical-threshold
WARNING  if bandwidth > warning-threshold
OK       otherwise
STR

EXAMPLES = <<-STR
__APPNAME__ [options]
STR

cli = CommandLine.new(:description => DESCRIPTION, :examples => EXAMPLES)

cli.option(:slb, '-s', '--slb HOST[:PORT]', "SLB host and port. Assumes port 80 if not specified.") do |v|
  v
end
cli.option(:warning_threshold, '-w', '--warning RATE', 'Warning threshold, in Mb/s', 400) do |v|
  Float(v)
end
cli.option(:critical_threshold, '-c', '--critical RATE', 'Critical threshold, in Mb/s', 600) do |v|
  Float(v)
end
cli.option(:vserver, '-V', '--vserver NAME', "A10 vserver name.") do |v|
  v
end
cli.option(:sleep_sec, '-S', '--sleep-sec SEC', "Number of seconds to sleep between queries.", 4) do |v|
  Integer(v)
end
cli.option(:verbose, '-v', '--verbose', "Enable verbose output, including backtraces.") do
  true
end
cli.option(:version, nil, '--version', "Print the version string and exit.") do
  puts A10_MONITORING_VERSION_MESSAGE
  exit
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

  warn = cli.warning_threshold
  crit = cli.critical_threshold

  # Fetch vserver data
  slb = A10LoadBalancer.new(cli.slb, :sleep_sec => cli.sleep_sec)
  stats = slb.virtual_server_stats[cli.vserver]
  Icinga::quit(Icinga::UNKNOWN, "virtual server '#{cli.vserver}' not found") unless stats

  # Compute IO rates
  rx_rate_mbps = stats[:req_bit_rate] / 1024 / 1024
  tx_rate_mbps = stats[:resp_bit_rate] / 1024 / 1024
  pretty_rx_rate = Utils.pretty_rate(stats[:req_bit_rate], :bits)
  pretty_tx_rate = Utils.pretty_rate(stats[:resp_bit_rate], :bits)

  # Return the proper status
  message = "#{cli.vserver} bandwidth: (tx: %s, rx: %s)" % [pretty_tx_rate, pretty_rx_rate]
  Icinga::quit(Icinga::CRITICAL, message) if tx_rate_mbps > crit || rx_rate_mbps > crit
  Icinga::quit(Icinga::WARNING,  message) if tx_rate_mbps > warn || rx_rate_mbps > warn
  Icinga::quit(Icinga::OK,       message)

rescue => e
  Utils.print_backtrace(e) if cli.verbose
  Icinga::quit(Icinga::CRITICAL, "#{e.class.name}: #{e.message}")
ensure
  slb.close_session if slb
end
