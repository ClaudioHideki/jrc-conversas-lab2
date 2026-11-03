# A campaign's audience and review snapshot can retain imported contact IDs.
class JrcNico::MigrationCampaignEvidence
  def initialize(campaign, account:)
    @campaign = campaign
    @account = account
  end

  def call
    pending = ActiveRecord::Base.uncached do
      JrcMigrations::Mapping.exists?(account: @account, domain: %w[contacts companies], accepted_at: nil)
    end
    return @campaign unless pending

    preview = JrcCampaigns::AudienceResolver.new(@campaign).preview
    ids = (Array(preview[:entries]) + Array(preview[:selectable_entries])).filter_map { |entry| entry.contact&.id }
    ids += @campaign.recipients.where.not(contact_id: nil).distinct.pluck(:contact_id)
    collect_ids(preview[:rejections], ids)
    collect_ids(@campaign.review_snapshot, ids)
    validate_ids!(ids.uniq)
    @campaign
  end

  private

  def collect_ids(value, ids)
    case value
    when Hash
      value.each do |key, item|
        collect_reference(key, item, ids)
        collect_ids(item, ids)
      end
    when Array then value.each { |item| collect_ids(item, ids) }
    end
  end

  def collect_reference(key, item, ids)
    case key.to_s
    when 'contact_id' then ids << item.to_i if item.present?
    when 'selection_key'
      ids << item.delete_prefix('contact:').to_i if item.is_a?(String) && item.start_with?('contact:')
    end
  end

  def validate_ids!(ids)
    allowed = JrcNico::MigrationVisibility.contacts(@account).where(id: ids)
    raise ActiveRecord::RecordNotFound unless allowed.count == ids.length

    company_ids = allowed.where.not(company_id: nil).distinct.pluck(:company_id)
    raise ActiveRecord::RecordNotFound unless JrcNico::MigrationVisibility.companies(@account).where(id: company_ids).count == company_ids.length
  end
end
