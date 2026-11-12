require 'digest'

# A persisted campaign keeps its trusted creator as the audience principal, including in jobs.
# The reviewed cohort is hashed without names, destinations or financial values.
class JrcCustomers::CampaignSegment
  def initialize(campaign)
    @campaign = campaign
  end

  def selected?
    filters = @campaign.audience_config['customer_filters']
    filters.is_a?(Hash) && filters['customer_segment_id'].present?
  end

  def apply(scope)
    return scope unless selected?

    if @campaign.audience_type == 'sanitized_list'
      raise JrcCustomers::CampaignFilter::InvalidFilter, 'Published segments require existing customer contacts'
    end

    account = Account.find(@campaign.account_id)
    member = account.account_users.find_by(user_id: @campaign.created_by_id)
    raise Pundit::NotAuthorizedError unless account.active? && account.feature_enabled?('jrc_campaigns') && member&.administrator?

    filter = JrcCustomers::ModuleSegmentFilter.new(account: account, actor: member.user, module_key: 'campaigns', segment_id: segment_id)
    filter.call(scope, contact_column: :id)
  end

  def review_evidence
    contacts = apply(@campaign.account.contacts)
    taxonomy = JrcCustomers::Taxonomy.where(account_id: @campaign.account_id, kind: 'segment').find(segment_id)
    definition = taxonomy.attributes.slice('id', 'selection_mode', 'criteria', 'modules', 'active', 'updated_at')
    digest = Digest::SHA256.new
    contacts.reselect(:id).find_each { |contact| digest << "#{contact.id}:" }
    { 'definition_sha256' => Digest::SHA256.hexdigest(definition.to_json), 'contact_ids_sha256' => digest.hexdigest }
  end

  def authorize_viewer!(actor)
    return unless selected?

    scope = apply(@campaign.account.contacts)
    filter = JrcCustomers::ModuleSegmentFilter.new(account: @campaign.account, actor: actor, module_key: 'campaigns', segment_id: segment_id)
    visible = filter.call(@campaign.account.contacts, contact_column: :id)
    raise Pundit::NotAuthorizedError if scope.where.not(id: visible.reselect(:id)).exists?
  end

  def reviewed_contacts_visible?(recipients)
    ids = recipients.pluck('contact_id')
    return false if ids.any?(&:blank?)

    scope = apply(@campaign.account.contacts)
    ids.uniq.each_slice(1000).all? { |batch| scope.where(id: batch).distinct.count == batch.size }
  end

  private

  def segment_id
    @campaign.audience_config.fetch('customer_filters').fetch('customer_segment_id')
  end
end
