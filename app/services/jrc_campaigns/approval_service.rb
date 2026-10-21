require 'digest'

class JrcCampaigns::ApprovalService
  CONFIGURATION_FIELDS = %w[delivery_channel name inbox_id trigger_type scheduled_at audience_type audience_config message_body rotation_mode delay_min_seconds
                            delay_max_seconds sending_window conversation_mode recurrence_config follow_up_config].freeze

  def initialize(campaign)
    @campaign = campaign
  end

  def request_review!
    campaign.with_lock do
      reject!('A revisão exige campanha em rascunho ou agendada.') unless campaign.editable?
      campaign.ensure_sender_compatibility!
      snapshot = {
        'configuration' => configuration,
        'recipients' => JrcCampaigns::AudienceResolver.new(campaign).entries.map do |entry|
          { 'contact_id' => entry.contact&.id, 'name' => entry.name, 'phone_number' => entry.phone_number,
            'email' => entry.email, 'destination' => entry.destination(campaign.delivery_channel),
            'source' => entry.source, 'metadata' => entry.metadata }
        end
      }
      campaign.update!(review_snapshot: snapshot, review_digest: digest(snapshot), approved_digest: nil, approved_by: nil,
                       approved_at: nil, approval_expires_at: nil)
    end
  end

  def approve!(user, expected_digest)
    campaign.with_lock do
      reject!('Somente administradores podem aprovar campanhas.') unless campaign.account.account_users.exists?(user_id: user.id,
                                                                                                                role: :administrator)
      reject!('A aprovação exige campanha em rascunho ou agendada.') unless campaign.editable?
      unless expected_digest.present? && expected_digest == campaign.review_digest && current_review?
        reject!('A revisão está desatualizada. Revise novamente antes de aprovar.')
      end

      campaign.update!(approved_by: user, approved_at: Time.current, approval_expires_at: 48.hours.from_now, approved_digest: campaign.review_digest)
    end
  end

  def valid?
    campaign.approved_by_id.present? && campaign.approved_at.present? && campaign.approval_expires_at&.future? &&
      campaign.approved_digest.present? && campaign.approved_digest == campaign.review_digest && current_review?
  end

  def ensure_valid!
    campaign.ensure_sender_compatibility!
    reject!('A campanha exige aprovação humana válida. Revise e aprove novamente; a validade é de 48 horas.') unless valid?
  end

  private

  attr_reader :campaign

  def current_review?
    snapshot = campaign.review_snapshot
    snapshot.present? && snapshot['configuration'] == configuration && digest(snapshot) == campaign.review_digest
  end

  def configuration
    result = campaign.as_json(only: CONFIGURATION_FIELDS).merge(
      'steps' => campaign.steps.order(:position, :id).map { |step| step.as_json.except('created_at', 'updated_at') },
      'inboxes' => campaign.campaign_inboxes.order(:position, :id).map { |link| link.as_json.except('created_at', 'updated_at') }
    )
    connectors = campaign.evolution_connectors
    result['evolution_connectors'] = connectors.map(&:public_configuration) if connectors.any?
    brokers = campaign.broker_connectors
    if brokers.any?
      result['broker_connectors'] = brokers.map do |connector|
        connector.public_configuration.merge('identity_revision' => connector.transport(campaign.created_by).fetch('identityRevision'))
      end
    end
    result
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
