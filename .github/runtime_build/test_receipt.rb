# frozen_string_literal: true
require_relative 'receipt'
source = 'a' * 40
nonce = 'b' * 32
cases = []
def check(cases, name)
  yield
  cases << name
end
def rejected
  begin
    yield
  rescue RuntimeError
    return
  end
  raise 'Invalid receipt was accepted'
end
[1, 42, Process.pid].uniq.each do |pid|
  check(cases, "accept_positive_pid_#{pid}") do
    data = RuntimeSmokeReceipt.build(product_sha: source, nonce: nonce, pid: pid)
    raise unless RuntimeSmokeReceipt.verify!(data: data, persisted: data.dup, product_sha: source, nonce: nonce)
  end
end
[0, -1, 1.0, '1', true, nil].each_with_index do |pid, i|
  check(cases, "reject_invalid_pid_#{i}") { rejected { RuntimeSmokeReceipt.build(product_sha: source, nonce: nonce, pid: pid) } }
end
valid = RuntimeSmokeReceipt.build(product_sha: source, nonce: nonce, pid: 1)
[
  [valid.merge('product_sha' => 'c' * 40), valid],
  [valid.merge('nonce' => 'd' * 32), valid],
  [valid.reject { |k, _v| k == 'nonce' }, valid],
  [valid, nil],
  [valid, valid.merge('pid' => 2)],
  [nil, valid]
].each_with_index do |(data, persisted), i|
  check(cases, "reject_wrong_identity_or_persistence_#{i}") do
    rejected { RuntimeSmokeReceipt.verify!(data: data, persisted: persisted, product_sha: source, nonce: nonce) }
  end
end
if ENV['EXPECT_PID_ONE'] == '1'
  raise 'Test Ruby process is not PID 1' unless Process.pid == 1
  cases << 'actual_container_pid_one'
end
report = { passed: true, examples: cases.size, failures: 0, pending: 0, pid: Process.pid, cases: cases }
File.write(ARGV.fetch(0), JSON.pretty_generate(report)) unless ARGV.empty?
puts JSON.generate(report)
