class JrcRelationship::SurveyRule < ApplicationRecord
  self.table_name = 'jrc_relationship_survey_rules'
  belongs_to :account
  belongs_to :definition, class_name: 'JrcRelationship::SurveyDefinition'
  belongs_to :execution_member, class_name: 'AccountUser', optional: true
  validates :name, presence: true, length: { maximum: 120 }
  validates :active, inclusion: { in: [true, false] }
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000 }
  DEFAULTS = { 'channel' => 'same', 'frequency_days' => 0, 'frequency_scope' => 'contact_type', 'delay_minutes' => 0,
               'expires_hours' => 168, 'max_attempts' => 1, 'resend_minutes' => 60, 'consent_required' => true, 'delivery_inbox_id' => nil,
               'whatsapp_template' => nil }.freeze
  REFERENCES = { 'company_id' => 'JrcCustomers::Company', 'unit_id' => 'JrcServiceDesk::Unit', 'team_id' => 'Team',
                 'inbox_id' => 'Inbox', 'product_id' => 'JrcCrm::Product', 'contract_id' => 'JrcCrm::Contract' }.freeze
  validate :valid_policy

  def effective_settings
    DEFAULTS.merge(settings)
  end

  def snapshot
    attributes.slice('id', 'name', 'version', 'priority', 'matchers', 'execution_member_id').merge('settings' => effective_settings)
  end

  def specificity
    scopes = { 5 => %w[source_type channel_type], 4 => %w[team_id inbox_id],
               3 => %w[product_id contract_id], 2 => %w[company_id unit_id] }
    scopes.find { |_level, keys| keys.any? { |key| matchers[key].present? } }&.first || 1
  end

  private

  def valid_policy
    validate_references
    unless matchers.is_a?(Hash) && (matchers.keys - (REFERENCES.keys + %w[source_type channel_type])).empty?
      errors.add(:matchers, 'unknown policy scope')
      return
    end
    validate_matchers
    unless settings.is_a?(Hash) && (settings.keys - DEFAULTS.keys).empty?
      errors.add(:settings, 'unknown dispatch setting')
      return
    end
    validate_delivery_settings
    validate_timing_settings
    validate_template_settings
  end

  def validate_template_settings
    JrcRelationship::SurveyRuleTemplate.new(self).validate!
  rescue ArgumentError, Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    errors.add(:settings, 'invalid or unavailable approved WhatsApp template configuration')
  end

  def validate_references
    errors.add(:definition, 'wrong account') if definition && definition.account_id != account_id
    errors.add(:execution_member, 'wrong account') if execution_member && execution_member.account_id != account_id
    validate_active_reference
  end

  def validate_active_reference
    return unless active && (!execution_member || definition&.status != 'active')

    errors.add(:active, 'requires an explicit execution member and active definition')
  end

  def validate_matchers
    REFERENCES.each do |key, type|
      errors.add(:matchers, "#{key} must belong to account") if matchers[key].present? && !type.constantize.exists?(account_id: account_id,
                                                                                                                    id: matchers[key])
    end
    return unless matchers['source_type'].present? && JrcRelationship::SurveySource::TYPES.exclude?(matchers['source_type'])

    errors.add(:matchers, 'unsupported source')
  end

  def validate_delivery_settings
    policy = effective_settings
    errors.add(:settings, 'invalid channel') unless %w[same whatsapp email public_link].include?(policy['channel'])
    errors.add(:settings, 'invalid frequency scope') unless %w[contact company contact_type].include?(policy['frequency_scope'])
    if %w[email whatsapp].include?(policy['channel']) && !Inbox.exists?(account_id: account_id, id: policy['delivery_inbox_id'])
      errors.add(:settings, 'alternate channel requires an explicit account inbox')
    end
    errors.add(:settings, 'consent_required must be boolean') unless [true, false].include?(policy['consent_required'])
  end

  def validate_timing_settings
    policy = effective_settings
    %w[frequency_days delay_minutes expires_hours max_attempts resend_minutes].each do |key|
      value = policy[key]
      minimum = %w[frequency_days delay_minutes].include?(key) ? 0 : 1
      errors.add(:settings, "invalid #{key}") unless value.is_a?(Integer) && value.between?(minimum, key == 'max_attempts' ? 3 : 52_560)
    end
  end
end
