require 'digest'

class JrcCampaigns::ApprovalService
  def initialize(campaign)
    @campaign = campaign
  end

  def request_review!
    prepared = configuration.prepare
    campaign.with_lock do
      reject!('A revisão exige campanha em rascunho ou agendada.') unless campaign.editable?
      verify_configuration!(prepared)
      campaign.ensure_sender_compatibility!
      snapshot = {
        'configuration' => prepared.configuration,
        'recipients' => recipient_snapshot
      }
      campaign.update!(review_snapshot: snapshot, review_digest: digest(snapshot), approved_digest: nil, approved_by: nil,
                       approved_at: nil, approval_expires_at: nil)
    end
  end

  def approve!(user, expected_digest)
    ensure_approver!(user)
    prepared = configuration.prepare
    campaign.with_lock do
      verify_configuration!(prepared, actor: user)
      ensure_approver!(user)
      reject!('A aprovação exige campanha em rascunho ou agendada.') unless campaign.editable?
      unless expected_digest.present? && expected_digest == campaign.review_digest && current_review?(prepared.configuration)
        reject!('A revisão está desatualizada. Revise novamente antes de aprovar.')
      end

      campaign.update!(approved_by: user, approved_at: Time.current, approval_expires_at: 48.hours.from_now, approved_digest: campaign.review_digest)
    end
  end

  def valid?
    return false unless locally_valid?

    prepared = configuration.prepare
    configuration.matches?(prepared) && current_review?(prepared.configuration)
  end

  # Read-only presentation of the human approval; remote sender readiness is checked at execution.
  def locally_valid?
    approved? && current_review?(configuration.local_configuration, local: true)
  end

  def prepare_validation!
    campaign.reload
    campaign.ensure_sender_compatibility!
    reject_approval! unless locally_valid?
    configuration.prepare
  end

  def ensure_valid!(prepared: nil)
    prepared ||= prepare_validation!
    campaign.with_lock do
      verify_configuration!(prepared)
      campaign.ensure_sender_compatibility!
      reject_approval! unless approved? && current_review?(prepared.configuration)
    end
  end

  private

  attr_reader :campaign

  def recipient_snapshot
    JrcCampaigns::AudienceResolver.new(campaign).entries.map do |entry|
      { 'contact_id' => entry.contact&.id, 'name' => entry.name, 'phone_number' => entry.phone_number,
        'email' => entry.email, 'destination' => entry.destination(campaign.delivery_channel),
        'source' => entry.source, 'metadata' => entry.metadata }
    end
  end

  def current_review?(expected, local: false)
    snapshot = campaign.review_snapshot
    return false unless snapshot.present? && digest(snapshot) == campaign.review_digest

    actual = snapshot['configuration'].deep_dup
    actual['broker_connectors']&.each { |connector| connector.delete('identity_revision') } if local
    actual == expected
  end

  def configuration
    @configuration ||= JrcCampaigns::ReviewConfiguration.new(campaign)
  end

  def verify_configuration!(prepared, actor: nil)
    configuration.lock_sources!(actor: actor)
    reject!('A configuração mudou durante a consulta. Revise novamente antes de aprovar.') unless configuration.matches?(prepared)
  end

  def approved?
    campaign.approved_by_id.present? && campaign.approved_at.present? && campaign.approval_expires_at&.future? &&
      campaign.approved_digest.present? && campaign.approved_digest == campaign.review_digest
  end

  def ensure_approver!(user)
    return if campaign.account.account_users.exists?(user_id: user.id, role: :administrator)

    reject!('Somente administradores podem aprovar campanhas.')
  end

  def reject_approval!
    reject!('A campanha exige aprovação humana válida. Revise e aprove novamente; a validade é de 48 horas.')
  end

  def digest(value)
    Digest::SHA256.hexdigest(canonical(value).to_json)
  end

  def canonical(value)
    case value
    when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end

  def reject!(message)
    campaign.errors.add(:base, message)
    raise ActiveRecord::RecordInvalid, campaign
  end
end
