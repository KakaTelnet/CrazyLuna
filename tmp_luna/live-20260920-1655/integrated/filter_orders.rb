#!/usr/bin/env ruby
# Filter orders by status and sort them by update time.
require 'json'

orders_path = ARGV.fetch(0)
status = ARGV.fetch(1)
orders = JSON.parse(File.read(orders_path))

filtered = if status == 'all'
             orders.dup
           else
             orders.select { |order| order.fetch('status') == status }
           end

filtered.sort_by! { |order| -order.fetch('updated_at').to_f }
puts JSON.generate(filtered)
