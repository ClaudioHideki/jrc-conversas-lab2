# frozen_string_literal: true

require_relative '../spec/integration/jrc_contact_center/owned_public_ending_queue'

configuration = SyntheticPublicEndingQueue.configuration!
raise 'One owned account identifier required' unless ARGV.length == 1 && ARGV.first.match?(/\A[1-9][0-9]{0,18}\z/)

account_id = Integer(ARGV.first)
raise 'Unknown synthetic account' unless configuration.fetch('account_ids').include?(account_id)

redis = Redis.new(url: ENV.fetch('REDIS_URL'))
receipts = %w[produced acks].index_with do |kind|
  redis.hgetall("jrc_cc_public:#{configuration.fetch('nonce')}:#{kind}").transform_values { |raw| JSON.parse(raw) }
       .select { |_jid, value| value.fetch('account_id') == account_id }
end
produced, acks = receipts.values_at('produced', 'acks')
producer_sha = Digest::SHA256.file(Rails.root.join('spec/integration/jrc_contact_center/owned_public_ending_adapter.rb')).hexdigest
worker_sha = Digest::SHA256.file(Rails.root.join('spec/integration/jrc_contact_center/owned_public_ending_worker_boot.rb')).hexdigest
raise 'Actual worker receipts missing' if produced.empty? || produced.keys.sort != acks.keys.sort

produced.each do |jid, source|
  result = acks.fetch(jid)
  fields = %w[jid job_class account_id record_id source_sha queue]
  unless source.fetch('witness_sha256') == producer_sha && result.fetch('witness_sha256') == worker_sha
    raise 'Witness source hashes differ from the pinned native checkout'
  end
  raise 'Produced job identity differs from actual dequeue' unless source.slice(*fields) == result.slice(*fields)
  unless result.fetch('database') == SyntheticPublicEndingQueue::DATABASE && result.fetch('postgres_backend_pid').positive? &&
         result.fetch('redis_database') == 15 && result.fetch('worker_pid').positive?
    raise 'Actual native PostgreSQL/Redis worker identity missing'
  end
end
unless produced.any? { |jid, row| row.fetch('producer_pid') != acks.fetch(jid).fetch('worker_pid') }
  raise 'At least one actual HTTP producer and separate native worker process required'
end
raise 'Both native job classes must have run' unless acks.values.map { |row| row.fetch('job_class') }.uniq.sort ==
                                                     SyntheticPublicEndingQueue::JOB_CLASSES.sort

origin = JrcContactCenter::EndingActionOrigin.find_by!(account_id: account_id)
attempts = JrcContactCenter::EndingDestinationAttempt.where(account_id: account_id, origin: origin).includes(:outcome, :execution).order(:id)
raise 'Independent failed root, retry and automatic destination required' unless attempts.length == 3
raise 'Exactly two native effects required' unless JrcProjects::Task.where(account_id: account_id).count == 2 &&
                                                   attempts.count { |row| row.outcome&.outcome == 'succeeded' } == 2
raise 'Failed root must remain immutable and unexecuted' unless attempts.first.outcome.outcome == 'failed' && attempts.first.execution.nil?
raise 'Selected retry must refer to the failed root' unless attempts.second.retry_of_id == attempts.first.id

attempts.select { |row| row.outcome.outcome == 'succeeded' }.each do |attempt|
  execution = attempt.execution
  raise 'Actual native Project target required' unless execution.target_type == 'JrcProjects::Task'

  task = JrcProjects::Task.where(account_id: account_id).find(execution.target_id)
  raise 'Actual native Task creator must be the original operator' unless task.created_by_id == origin.actor_user_id

  JrcProjects::AuditEvent.find_by!(account_id: account_id, auditable_type: task.class.name, auditable_id: task.id,
                                   actor_id: origin.actor_user_id, action: 'projects.task.created', correlation_id: attempt.effect_key)
end

qualification = JrcContactCenter::Qualification.find(origin.source_qualification_id)
raise 'Independent ACW must have completed' unless qualification.completed_at

attempt_rows = attempts.map do |row|
  { id: row.id, retry_of_id: row.retry_of_id, rule_code: row.rule_code,
    outcome: row.outcome.outcome, result_code: row.outcome.result_code, execution_id: row.execution&.id }
end
puts({ source_sha: configuration.fetch('source_sha'), account_id: account_id,
       real_Sidekiq_produced: produced, real_Sidekiq_acknowledgements: acks,
       original_actor_id: origin.actor_account_user_id, original_user_id: origin.actor_user_id,
       attempts: attempt_rows,
       native_task_count: 2, original_operator_and_native_audits_verified: true,
       completed_ACW_independent: true, existing_data_deleted: false }.to_json)
