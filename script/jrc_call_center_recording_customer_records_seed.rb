# frozen_string_literal: true

# Data and explicit rights belong only to the original owned browser fixture.
# No provider, customer environment, user profile or operational policy is configured.
class JrcContactCenter::SyntheticRecordingCustomerRecordsSeed
  def self.call(account:, operator:, viewer:, record:)
    owned!(account, operator, viewer, record)
    account.enable_features!('jrc_crm')
    rights = %w[jrc_crm jrc_service_desk_history_view]
    operator.custom_role.update!(permissions: (operator.custom_role.permissions + rights).uniq)
    call = JrcContactCenter::CallSession.find_by!(account: account, external_session_id: record.external_unique_id)
    contact = account.contacts.find(call.contact_id)
    stage = stage!(account)
    records = 26.times.map { |index| deal!(account, operator.user, contact, stage, "SYNTHETIC context opportunity #{index + 1}") }
    private_record = deal!(account, viewer.user, contact, stage, 'SYNTHETIC PRIVATE other-owner opportunity')
    { contact_id: contact.id.to_s, deal_ids: records.map { |row| row.id.to_s },
      private_deal_id: private_record.id.to_s, private_title: private_record.title }.merge(projects!(account, operator, contact))
  end

  def self.projects!(account, operator, contact)
    owner = account.account_users.where(role: :administrator).where.not(id: operator.id).sole
    JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: owner, user: owner.user) do
      attributes = { name: 'SYNTHETIC context permitted project', visibility: 'private', contact_id: contact.id }
      allowed = JrcProjects::Projects::Create.call(account: account, actor: owner.user, attributes: attributes, idempotency_key: SecureRandom.uuid)
      attributes = attributes.merge(name: 'SYNTHETIC context PRIVATE excluded project')
      hidden = JrcProjects::Projects::Create.call(account: account, actor: owner.user, attributes: attributes, idempotency_key: SecureRandom.uuid)
      JrcProjects::ProjectMember.create!(account: account, project: allowed, user: operator.user, role: 'member')
      { project_id: allowed.id.to_s, project_title: allowed.name, private_project_id: hidden.id.to_s, private_project_title: hidden.name }
    end
  end

  def self.stage!(account)
    pipeline = JrcCrm::Pipeline.create!(account: account, name: 'SYNTHETIC recording context', key: 'synthetic-recording-context', active: true)
    JrcCrm::Stage.create!(account: account, pipeline: pipeline, name: 'SYNTHETIC context stage', key: 'synthetic-context',
                         position: 0, active: true, probability: 0, is_terminal: false, is_won: false, is_lost: false)
  end

  def self.deal!(account, owner, contact, stage, title)
    JrcCrm::Deal.create!(account: account, owner: owner, contact: contact, company_id: contact.company_id,
                        pipeline: stage.pipeline, stage: stage, title: title, status: 'open', value_cents: 0, currency: 'BRL')
  end

  def self.owned_runtime?(config)
    [Rails.env.test?, ENV['GITHUB_ACTIONS'] == 'true', ENV['RUNNER_ENVIRONMENT'] == 'github-hosted',
     ENV['GITHUB_REF_NAME'] == 'codex/call-center-control-desk-20261116',
     config.configuration_hash[:host] == '127.0.0.1', ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15',
     JrcContactCenter::SyntheticRecordingsSeed.owned_database?(config)].all?
  end

  def self.owned!(account, operator, viewer, record)
    config = ApplicationRecord.connection_db_config
    raise 'Owned recording customer context runner required' unless owned_runtime?(config)

    marker = account.reload.settings.fetch(JrcContactCenter::SyntheticRecordingsSeed::MARKER)
    account_id = account.id
    account_name = account.name
    ids = marker.fetch('record_ids')
    identities = [account_name.start_with?('SYNTHETIC pause '), account_name.end_with?('-recordings'),
                  marker.fetch('source_sha') == ENV.fetch('GITHUB_SHA'), ids.uniq.length == 24,
                  operator.account_id == account_id, viewer.account_id == account_id,
                  record.account_id == account_id, ids.include?(record.id), operator.agent?]
    raise 'Exact owned recording customer context identities required' unless identities.all?
  end
  private_class_method :owned!, :owned_runtime?, :stage!, :deal!, :projects!
end
