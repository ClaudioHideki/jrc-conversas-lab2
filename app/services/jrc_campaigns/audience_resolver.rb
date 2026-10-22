class JrcCampaigns::AudienceResolver
  Entry = Data.define(:contact, :name, :phone_number, :email, :source, :metadata) do
    def destination(channel)
      channel == 'email' ? email : phone_number
    end

    def selection_key
      return "contact:#{contact.id}" if contact

      sanitized_entry_id = metadata.to_h.with_indifferent_access[:sanitized_entry_id]
      "sanitized_entry:#{sanitized_entry_id}"
    end
  end

  def initialize(campaign)
    @campaign = campaign
    @account = campaign.account
  end

  def entries
    preview[:entries]
  end

  def estimated_count
    entries.size
  end

  def preview
    @preview ||= build_preview
  end

  private

  attr_reader :campaign, :account

  def build_preview
    resolved = resolved_entries
    counters = Hash.new(0)
    rejections = []
    evolution = campaign.whatsapp? && (campaign.evolution_connectors.any? || campaign.broker_connectors.any?)
    list_preview = evolution || (campaign.new_record? && campaign.inbox_id.nil? && campaign.campaign_inboxes.empty?)
    eligible = resolved.filter_map do |entry|
      normalized = normalized_entry(entry)
      destination = normalized.destination(campaign.delivery_channel)
      if destination.blank?
        counters[:without_destination_count] += 1
        rejections << rejection_json(entry, normalized, campaign.email? ? 'E-mail inválido.' : 'Telefone inválido.')
        next
      end
      if campaign.whatsapp? && blacklisted_phones.include?(destination)
        counters[:blacklisted_count] += 1
        rejections << rejection_json(entry, normalized, 'Destinatário na blacklist.')
        next
      end
      if entry.contact&.blocked?
        counters[:blocked_count] += 1
        rejections << rejection_json(entry, normalized, 'Contato bloqueado.')
        next
      end

      if campaign.whatsapp?
        policy = JrcCampaigns::EligibilityPolicy.new(account: account, phone_number: destination, contact: entry.contact,
                                                      purpose: evolution ? 'whatsapp_campaigns' : nil)
        reason = list_preview ? policy.list_rejection_reason : policy.rejection_reason
        if reason
          counters[reason == 'Telefone inválido.' ? :without_destination_count : :without_consent_count] += 1
          rejections << rejection_json(entry, normalized, reason)
          next
        end
      end

      normalized
    end
    selectable_entries = eligible.uniq { |entry| entry.destination(campaign.delivery_channel) }
    selected_entries = selectable_entries.select { |entry| selected_by_user?(entry) }

    {
      found_count: resolved.size,
      available_recipients: selectable_entries.size,
      estimated_recipients: selected_entries.size,
      manually_excluded_count: selectable_entries.size - selected_entries.size,
      without_destination_count: counters[:without_destination_count],
      without_whatsapp_count: campaign.whatsapp? ? counters[:without_destination_count] : 0,
      without_email_count: campaign.email? ? counters[:without_destination_count] : 0,
      blacklisted_count: counters[:blacklisted_count],
      blocked_count: counters[:blocked_count],
      without_consent_count: counters[:without_consent_count],
      duplicate_count: eligible.size - selectable_entries.size,
      rejections: rejections,
      selectable_entries: selectable_entries,
      entries: selected_entries
    }
  end

  def rejection_json(entry, normalized, reason)
    { selection_key: entry.selection_key, name: entry.name, phone_number: normalized.phone_number, email: normalized.email, reason: reason }
  end

  def selected_by_user?(entry)
    selected = recipient_selection_keys.include?(entry.selection_key)
    recipient_selection_mode == 'include' ? selected : !selected
  end

  def recipient_selection_mode
    @recipient_selection_mode ||= campaign.audience_config['recipient_selection_mode'] == 'include' ? 'include' : 'exclude'
  end

  def recipient_selection_keys
    @recipient_selection_keys ||= Array(campaign.audience_config['recipient_selection_keys']).compact_blank.map(&:to_s).to_set
  end

  def normalized_entry(entry)
    Entry.new(
      contact: entry.contact,
      name: entry.name,
      phone_number: JrcCampaigns::PhoneNormalizer.call(entry.phone_number),
      email: JrcCampaigns::EmailNormalizer.call(entry.email),
      source: entry.source,
      metadata: entry.metadata || {}
    )
  end

  def resolved_entries
    case campaign.audience_type
    when 'label' then contact_entries(label_contacts, 'label')
    when 'inbox' then contact_entries(inbox_contacts, 'inbox')
    when 'crm_stage' then contact_entries(crm_contacts, 'crm_stage')
    when 'sanitized_list' then sanitized_entries
    else contact_entries(account.contacts, 'all_contacts')
    end
  end

  def contact_entries(scope, source)
    scope = JrcCustomers::CampaignFilter.apply(scope: scope, account: account, filters: campaign.audience_config['customer_filters'] || {})
    scope.distinct.find_each.map do |contact|
      Entry.new(
        contact: contact,
        name: contact.name,
        phone_number: contact.phone_number,
        email: contact.email,
        source: source,
        metadata: {}
      )
    end
  end

  def label_contacts
    ids = Array(campaign.audience_config['label_ids']).compact_blank.map(&:to_i)
    titles = ids.any? ? account.labels.where(id: ids).pluck(:title) : [campaign.audience_config['label'].to_s].compact_blank
    return account.contacts.none if titles.empty?

    account.contacts.tagged_with(titles, any: true)
  end

  def inbox_contacts
    ids = Array(campaign.audience_config['inbox_ids']).compact_blank.map(&:to_i)
    legacy_inbox_id = campaign.audience_config['inbox_id']
    ids << legacy_inbox_id.to_i if ids.empty? && legacy_inbox_id.present?
    ids << campaign.inbox_id if ids.empty? && campaign.inbox_id.present?
    return account.contacts.none if ids.empty?

    account.contacts.joins(:contact_inboxes).where(contact_inboxes: { inbox_id: ids })
  end

  def crm_contacts
    stage_ids = Array(campaign.audience_config['stage_ids']).compact_blank.map(&:to_i)
    return account.contacts.none if stage_ids.empty?

    deals = account.jrc_crm_deals.where(stage_id: stage_ids)
    primary_ids = deals.where.not(contact_id: nil).pluck(:contact_id)
    linked_ids = JrcCrm::DealContact.where(deal_id: deals.select(:id)).pluck(:contact_id)
    account.contacts.where(id: primary_ids + linked_ids)
  end

  def sanitized_entries
    list_id = campaign.audience_config['sanitized_list_id']
    list = account.jrc_campaign_sanitized_lists.find_by(id: list_id)
    return [] unless list

    list.entries.find_each.map do |entry|
      Entry.new(
        contact: nil,
        name: entry.name,
        phone_number: entry.normalized_phone.presence || entry.phone_number,
        email: entry.normalized_email.presence || entry.email,
        source: 'sanitized_list',
        metadata: { sanitized_entry_id: entry.id, sanitized_list_id: list.id }
      )
    end
  end

  def blacklisted_phones
    @blacklisted_phones ||= account.jrc_campaign_blacklists.pluck(:phone_number).to_set
  end
end
