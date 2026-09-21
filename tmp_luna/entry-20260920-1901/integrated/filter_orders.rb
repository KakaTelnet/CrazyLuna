#!/usr/bin/env ruby

require 'json'

unless ARGV.length == 2 && %w[all pending paid cancelled].include?(ARGV[1])
  warn 'Usage: ruby filter_orders.rb <orders.json> <all|pending|paid|cancelled>'
  exit 2
end

orders_path, requested_status = ARGV
orders = JSON.parse(File.read(orders_path))

filtered = if requested_status == 'all'
             orders
           else
             orders.select { |order| order['status'] == requested_status }
           end

result = filtered.sort_by { |order| order.fetch('updated_at') }.reverse
STDOUT.write(JSON.generate(result))
STDOUT.write("\n")
