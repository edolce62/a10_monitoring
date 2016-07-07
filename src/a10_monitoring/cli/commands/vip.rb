# Copyright 2016 Yahoo Inc.
# Licensed under the terms of the New-BSD license. Please see LICENSE file in
# the project root for terms.

#===============================================================================
# 'group' command class. Shows service group info. For raw API output, use:
#
#     sudo ./bin/query_a10_api.rb -s $SLB -m slb.service_group.getAll
#     sudo ./bin/query_a10_api.rb -s $SLB -m slb.virtual_server.getAll
#     sudo ./bin/query_a10_api.rb -s $SLB -m slb.virtual_server.fetchAllStatistics
#
#===============================================================================

module A10CLI
module Commands

class VIP
  # Run the 'vip' command
  def self.run(cli)
    begin
      slb = A10LoadBalancer.new(cli.slb, sleep_sec: 1)
      arg = cli.positional.first

      if cli.full
        results = get_full_results(slb)
        raise RuntimeError, "vip not found: #{arg}" if arg && !results[arg]
        results = results[arg] if arg
        puts results.to_yaml
      else
        if arg
          get_hosts_behind_vip(slb, arg).each do |host, ports|
            puts "%s %s" % [host, ports.sort.join(',')]
          end
        else
          puts slb.virtual_server_names.sort.join("\n")
        end
      end
    rescue RuntimeError => e
      abort "a10cli: " + e.message
    end
  end

  # Get full results, as a hash
  def self.get_full_results(slb)
    results = {}
    conf = slb.virtual_server_configs
    groups = slb.service_group_configs

    slb.virtual_server_stats.each do |name,data|
      # Grab per-port data
      ports = []
      data[:vport_stat_list].each do |port,pdata|
        service_group = conf[name][:vport_list][port][:service_group]

        # Fetch service group members
        members = []
        groups[service_group][:member_list].each do |m|
          members << '%s:%d' % [m[:server], m[:port]]
        end

        # Construct port data
        ports << {
          'port'          => port,
          'curr_conns'    => pdata[:cur_conns],
          'conn_rate'     => '%d conns/s' % pdata[:tot_conn_rate],
          'req_rate'      => Utils.pretty_rate(pdata[:req_bit_rate], :bits),
          'resp_rate'     => Utils.pretty_rate(pdata[:resp_bit_rate], :bits),
          'service_group' => {
            'name'        => service_group,
            'members'     => members,
          }
        }
      end

      # Add to results hash
      results[name] = {
        'name'       => name,
        'address'    => data[:address],
        'curr_conns' => data[:cur_conns],
        'conn_rate'  => '%d conns/s' % data[:tot_conn_rate],
        'req_rate'   => Utils.pretty_rate(data[:req_bit_rate], :bits),
        'resp_rate'  => Utils.pretty_rate(data[:resp_bit_rate], :bits),
        'ports'      => ports,
      }
    end
    results
  end

  # Get the list of hosts behind a given vip. Returns a hash from hostname to
  # array of VIP ports.
  def self.get_hosts_behind_vip(slb, name)
    results = Hash.new { |h,k| h[k] = [] }
    vips = slb.virtual_server_configs
    groups = slb.service_group_configs

    raise RuntimeError, "vip not found: #{name}" unless vips[name]

    # For each port that the VIP serves, get the service group, extract the hosts
    # behind the group, and add each host along with the VIP's port.
    vips[name][:vport_list].each do |port,data|
      service_group = data[:service_group]
      groups[service_group][:member_list].each do |m|
        results[m[:server]] << port
      end
    end
    results
  end
end

end
end
