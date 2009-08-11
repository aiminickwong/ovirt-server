#!/usr/bin/ruby

$: << File.join(File.dirname(__FILE__), "./dutils")

require "rubygems"
require "qpid"
require "dutils"

get_credentials('qpidd')

server, port = get_srv('qpidd', 'tcp')
raise "Unable to determine qpid server from DNS SRV record" if not server

srv = "amqp://#{server}:#{port}"
puts "Connecting to #{srv}.."
s = Qpid::Qmf::Session.new()
b = s.add_broker(srv, :mechanism => 'GSSAPI')

nodes = s.objects(:class => "node")
nodes.each do |node|
    puts "node: #{node.hostname}"
    for (key, val) in node.properties
        puts "  property: #{key}, #{val}"
    end

    # Find any domains that on the current node.
    domains = s.objects(:class => "domain", 'node' => node.object_id)
    domains.each do |domain|
        r = domain.getXMLDesc()
        puts "getXMLDesc() status: #{r.status}"
        puts "getXMLDesc() status: #{r.text}"
        if r.status == 0
            puts "xml length: #{r.description.length}"
        end

        puts "  domain: #{domain.name}, state: #{domain.state}, id: #{domain.id}"
        for (key, val) in domain.properties
            puts "    property: #{key}, #{val}"
        end
    end

    pools = s.objects(:class => "pool", 'node' => node.object_id)
    pools.each do |pool|
        puts "  pool: #{pool.name}"
        for (key, val) in pool.properties
            puts "    property: #{key}, #{val}"
        end

        r = pool.getXMLDesc()
        puts "getXMLDesc() status: #{r.status}"
        puts "getXMLDesc() text: #{r.text}"
        if r.status == 0
            puts "xml length: #{r.description.length}"
        end

        # Find volumes that are part of the pool.
        volumes = s.objects(:class => "volume", 'pool' => pool.object_id)
        volumes.each do |volume|
            puts "    volume: #{volume.name}"
            for (key, val) in volume.properties
                puts "      property: #{key}, #{val}"
            end
        end
    end
end
