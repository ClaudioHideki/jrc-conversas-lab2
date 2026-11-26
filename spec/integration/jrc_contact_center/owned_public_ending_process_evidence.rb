# frozen_string_literal: true

# Test witness only: no job execution, ACK creation, provider command or business mutation.
class SyntheticPublicEndingProcessEvidence
  THREAD_KEY = :jrc_cc_owned_public_worker_job
  IDENTITY = %w[jid job_class account_id record_id].freeze

  def self.with_job(job, arguments, name)
    previous = Thread.current[THREAD_KEY]
    Thread.current[THREAD_KEY] = { 'jid' => job.fetch('jid'), 'job_class' => name,
                                   'account_id' => arguments.first, 'record_id' => arguments.last }.freeze
    yield
  ensure
    Thread.current[THREAD_KEY] = previous
  end

  def self.parent_job
    Thread.current[THREAD_KEY]&.dup
  end

  def self.verify!(input, output, produced:, acks:, expected_qualification_id:)
    ids = [input.fetch('producer_pid'), output.fetch('worker_pid'), output.fetch('postgres_backend_pid')]
    raise 'Native isolated PostgreSQL/Redis worker evidence missing' unless ids.all? { |value| value.is_a?(Integer) && value.positive? }

    parent = input['parent_job']
    if parent.nil?
      raise 'Independent HTTP producer and worker required' if input.fetch('producer_pid') == output.fetch('worker_pid')

      return true
    end

    verify_parent!(parent, input, produced: produced, acks: acks, qualification_id: expected_qualification_id)
  end

  def self.verify_parent!(parent, input, produced:, acks:, qualification_id:)
    valid = parent.is_a?(Hash) && parent.keys.sort == IDENTITY.sort && parent['jid'] != input.fetch('jid')
    valid &&= parent['job_class'] == 'JrcContactCenter::EndingActionsJob'
    valid &&= input.fetch('job_class') == 'JrcContactCenter::EndingDestinationJob'
    raise 'Native chained job parent identity required' unless valid

    original = produced.fetch(parent.fetch('jid'))
    completed = acks.fetch(parent.fetch('jid'))
    verify_parent_identity!(parent, original, completed)
    verify_parent_scope!(parent, input, original, completed, qualification_id)
    verify_parent_processes!(input, original, completed)

    true
  end

  def self.verify_parent_identity!(parent, original, completed)
    valid = original.slice(*IDENTITY) == parent && completed.slice(*IDENTITY) == parent && original['parent_job'].nil?
    raise 'Native chained job source or process mismatch' unless valid
  end

  def self.verify_parent_scope!(parent, input, original, completed, qualification_id)
    valid = parent.fetch('account_id') == input.fetch('account_id') && parent.fetch('record_id') == qualification_id
    valid &&= %w[source_sha queue].all? { |key| original.fetch(key) == input.fetch(key) && completed.fetch(key) == input.fetch(key) }
    raise 'Native chained job source or process mismatch' unless valid
  end

  def self.verify_parent_processes!(input, original, completed)
    valid = original.fetch('producer_pid').positive? && original.fetch('producer_pid') != completed.fetch('worker_pid')
    valid &&= input.fetch('producer_pid') == completed.fetch('worker_pid')
    raise 'Native chained job source or process mismatch' unless valid
  end
  private_class_method :verify_parent!, :verify_parent_identity!, :verify_parent_scope!, :verify_parent_processes!
end
