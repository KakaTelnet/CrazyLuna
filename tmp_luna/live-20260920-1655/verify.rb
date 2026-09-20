#!/usr/bin/env ruby
# Verify the isolated Luna live-test artifact against a selected requirement version.
# Uses only Ruby standard libraries and never modifies the implementation or fixture.
require 'json'
require 'open3'
require 'rbconfig'
require 'digest'

unless ARGV.length == 3 && %w[P1 P2].include?(ARGV[2])
  warn 'Usage: ruby verify.rb <filter_orders.rb> <orders.json> <P1|P2>'
  exit 2
end

implementation, fixture, version = ARGV.map(&:dup)
implementation = File.expand_path(implementation)
fixture = File.expand_path(fixture)
unless File.file?(implementation) && File.file?(fixture)
  warn 'Implementation or fixture does not exist.'
  exit 2
end

fixture_before = Digest::SHA256.file(fixture).hexdigest
rows = JSON.parse(File.read(fixture))
by_id = rows.to_h { |row| [row.fetch('id'), row] }
expected_ids = {
  'P1' => { 'all' => %w[o3 o2 o4 o1], 'paid' => %w[o2 o4 o1], 'pending' => %w[o3], 'cancelled' => [] },
  'P2' => { 'all' => %w[o1 o4 o2 o3], 'paid' => %w[o1 o4 o2], 'pending' => %w[o3], 'cancelled' => [] }
}.fetch(version)

failures = []
expected_ids.each do |status, ids|
  stdout, stderr, process = Open3.capture3(RbConfig.ruby, implementation, fixture, status)
  begin
    actual = JSON.parse(stdout)
    expected = ids.map { |id| by_id.fetch(id) }
    accepted = process.success? && actual == expected
    failures << status unless accepted
    puts JSON.generate(version: version, case: status, result: accepted ? 'PASS' : 'FAIL',
                       exit_code: process.exitstatus, expected: expected, actual: actual, stderr: stderr)
  rescue JSON::ParserError
    failures << status
    puts JSON.generate(version: version, case: status, result: 'FAIL',
                       exit_code: process.exitstatus, stdout: stdout, stderr: stderr,
                       reason: 'stdout is not valid JSON')
  end
end

fixture_after = Digest::SHA256.file(fixture).hexdigest
if fixture_before != fixture_after
  failures << 'fixture_changed'
  warn 'FAIL: fixture changed during verification'
end
puts JSON.generate(version: version, passed: expected_ids.length - failures.count { |name| expected_ids.key?(name) },
                   cases: expected_ids.length, failures: failures,
                   implementation_sha256: Digest::SHA256.file(implementation).hexdigest,
                   fixture_sha256: fixture_after, fixture_unchanged: fixture_before == fixture_after)
exit(failures.empty? ? 0 : 1)
