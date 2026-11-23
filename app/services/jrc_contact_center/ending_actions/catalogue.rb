# frozen_string_literal: true

# The native account API serializes settings, so it may contain
# only a revision/nonce head. Private definitions and their hashes remain in the ledger.
class JrcContactCenter::EndingActions::Catalogue
  KEY = 'voice_ending_automations'

  def initialize(account:)
    @account = account
  end

  def call
    metadata = head
    return { 'version' => 0, 'entries' => [] } unless metadata

    version = synchronized_version!(metadata)
    JrcContactCenter::EndingActions::RuleDefinition.new.call(version.definition).deep_dup
  end

  def head
    settings = @account.settings.fetch(JrcContactCenter::AcwPolicy::KEY, {})
    return nil unless settings.key?(KEY)

    metadata = settings.fetch(KEY)
    valid = metadata.is_a?(Hash) && metadata.keys.sort == %w[nonce version]
    valid &&= metadata['version'].is_a?(Integer) && metadata['version'].between?(1, 2_147_483_647)
    valid &&= valid_nonce?(metadata['nonce'])
    unavailable! unless valid
    metadata.deep_dup
  end

  def head_for(document)
    JrcContactCenter::EndingActions::RuleDefinition.new.call(document)
    { 'version' => document.fetch('version'), 'nonce' => SecureRandom.uuid }
  end

  def signature(values)
    metadata = head
    metadata ? values + [[KEY, metadata.fetch('version'), metadata.fetch('nonce')]] : values
  end

  def verify_synchronized!
    metadata = head
    recorded = JrcContactCenter::EndingActionVersion.where(account: @account).order(revision: :desc).first
    matches = metadata ? recorded && synchronized_version!(metadata).id == recorded.id : recorded.nil?
    return if matches

    unavailable!
  end

  # A per-rule command preserves every unrelated/unseen entry. Its caller must
  # authorize both the old and new destination references under the account lock.
  def propose(rule:)
    verify_synchronized!
    current = call
    previous = current.fetch('entries').find { |entry| entry.fetch('code') == rule.fetch('code') }
    return current if previous == rule

    proposed = { 'version' => current.fetch('version') + 1, 'entries' => updated_entries(current, rule, previous) }
    JrcContactCenter::EndingActions::RuleDefinition.new.call(proposed)
  end

  private

  def valid_nonce?(value)
    value.is_a?(String) && value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
  end

  def updated_entries(current, rule, previous)
    entries = current.fetch('entries').map { |entry| entry.fetch('code') == rule.fetch('code') ? rule : entry }
    entries << rule unless previous
    entries
  end

  def synchronized_version!(metadata)
    row = JrcContactCenter::EndingActionVersion.find_by(account: @account, revision: metadata.fetch('version'),
                                                     head_nonce: metadata.fetch('nonce'))
    unavailable! unless row && row.definition['version'] == row.revision
    row
  end

  def unavailable!
    raise JrcContactCenter::OperationError, 'ending_automation_ledger_unavailable'
  end
end
