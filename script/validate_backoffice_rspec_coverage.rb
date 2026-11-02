require 'json'

# The dry-run is only a collection plan, never evidence of tests passing.
# Committed Service Desk concurrency fixtures run separately from the main regression.
plan_path, *result_paths = ARGV
raise 'Provide a collection plan and both execution results' unless plan_path && result_paths.length == 2

plan = JSON.parse(File.read(plan_path)).fetch('examples').map { |example| example.fetch('id') }
raise 'Empty or duplicate collection plan' if plan.empty? || plan.uniq.length != plan.length

executed = result_paths.flat_map do |path|
  result = JSON.parse(File.read(path))
  summary = result.fetch('summary')
  %w[failure_count pending_count errors_outside_of_examples_count].each do |key|
    raise "Unapproved RSpec result: #{File.basename(path)} #{key}" unless summary.fetch(key).zero?
  end
  examples = result.fetch('examples')
  raise 'Empty or inconsistent execution results' unless examples.any? && summary.fetch('example_count') == examples.length
  raise 'Every planned example must pass' unless examples.all? { |example| example.fetch('status') == 'passed' }

  examples.map { |example| example.fetch('id') }
end
raise 'An example was executed in both partitions' unless executed.uniq.length == executed.length
raise 'Executed examples differ from the full collection plan' unless executed.sort == plan.sort

puts "Complete native RSpec plan verified: #{plan.length} examples, no omissions, duplicates, failures or pending examples."
