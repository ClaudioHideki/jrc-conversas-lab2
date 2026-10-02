require 'set'

class JrcCampaigns::AudienceResolver
  Entry = Data.define(:contact, :name, :phone_number, :source, :metadata)

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
    @preview ||= begin
      resolved = resolved_entries
      without_whatsapp = 0
      blacklisted = 0
      blocked = 0
      without_consent = 0
      eligible = resolved.filter_map do |entry|
        phone = JrcCampaigns::PhoneNormalizer.call(entry.phone_number)
        if phone.blank?
          without_whatsapp += 1
          next
        end
        if blacklisted_phones.include?(phone)
          blacklisted += 1
          next
        end
        if blocked_phones.include?(phone)
          blocked += 1
          next
        end
        unless consented_phones.include?(phone)
          without_consent += 1
          next
        end

        Entry.new(
          contact: entry.contact,
          name: entry.name,
          phone_number: phone,
          source: entry.source,
          metadata: entry.metadata || {}
        )
      end
      unique_entries = eligible.uniq { |entry| entry.phone_number }

      {
        found_count: resolved.size,
        estimated_recipients: unique_entries.size,
        without_whatsapp_count: without_whatsapp,
        blacklisted_count: blacklisted,
        blocked_count: blocked,
        without_consent_count: without_consent,
        duplicate_count: eligible.size - unique_entries.size,
        entries: unique_entries
      }
    end
  end

  private

  attr_reader :campaign, :account

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
      Entry.new(contact: contact, name: contact.name, phone_number: contact.phone_number, source: source, metadata: {})
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
    values = campaign.audience_config['customer_filters'] || {}
    raise JrcCustomers::CampaignFilter::InvalidFilter, 'Customer filters must be an object' unless values.is_a?(Hash)
    if values.values.any?(&:present?)
      raise JrcCustomers::CampaignFilter::InvalidFilter, 'Company filters require native contacts; sanitized phone lists have no reliable company identity'
    end
    list_id = campaign.audience_config['sanitized_list_id']
    list = account.jrc_campaign_sanitized_lists.find_by(id: list_id)
    return [] unless list

    list.entries.where(status: 'valid').find_each.map do |entry|
      Entry.new(
        contact: nil,
        name: entry.name,
        phone_number: entry.normalized_phone,
        source: 'sanitized_list',
        metadata: { sanitized_entry_id: entry.id, sanitized_list_id: list.id }
      )
    end
  end

  def blacklisted_phones
    @blacklisted_phones ||= account.jrc_campaign_blacklists.pluck(:phone_number).to_set
  end

  def consented_phones
    @consented_phones ||= JrcCampaigns::Consent.active.where(account: account).pluck(:phone_number).to_set
  end

  def blocked_phones
    @blocked_phones ||= account.contacts.where(blocked: true).where.not(phone_number: [nil, '']).pluck(:phone_number).filter_map do |phone|
      normalized = JrcCampaigns::PhoneNormalizer.call(phone)
      normalized.presence
    end.to_set
  end
end
