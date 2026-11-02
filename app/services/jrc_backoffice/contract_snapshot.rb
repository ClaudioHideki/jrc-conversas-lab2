# A bounded legal/commercial source. Operational statuses and timestamps are
# deliberately not legal revisions; the stored PDF remains the document sent.
require 'openssl'

class JrcBackoffice::ContractSnapshot
  CONTRACT_FIELDS = %w[id contract_number sales_order_id contract_template_id business_unit_id contract_type starts_on ends_on term_months
                       renewal_type adjustment_index monthly_cents one_time_cents payment_condition due_day auto_renew
                       renewal_notice_days renewal_term_months content_override notes].freeze
  COMPANY_FIELDS = %w[id name legal_name trade_name tax_id person_kind domain].freeze

  def self.capture(contract, signer_roster: nil)
    data = {
      contract: contract.attributes.slice(*CONTRACT_FIELDS), financials: contract.financial_summary,
      addenda: Array(contract.lifecycle_metadata['addenda']),
      items: item_snapshots(contract),
      template: contract.contract_template&.attributes&.slice('id', 'name', 'body'), renderer: 'native-commercial-document/1'
    }.merge(parties(contract))
    data[:signer_roster] = signer_roster.version_snapshot if signer_roster
    JrcServiceDesk::CanonicalJson.normalize(data.as_json)
  end

  def self.parties(contract)
    company = contract.account.master_companies.find_by(id: contract.contact&.company_id)
    {
      customer: company_snapshot(company),
      issuer_company: company_snapshot(contract.business_unit&.operating_company),
      contact: contract.contact&.attributes&.slice('id', 'name', 'email', 'phone_number', 'company_id')
    }.merge(commercial_origin(contract))
  end

  def self.company_snapshot(company)
    company&.attributes&.slice(*COMPANY_FIELDS)
  end

  def self.commercial_origin(contract)
    {
      commercial_owner: { id: contract.owner_id, name: contract.owner.name },
      issuer: JrcCrm::CorporateIssuer.document_name(contract, contract.sales_order, (contract.sales_order.snapshot || {}).with_indifferent_access),
      order_number: contract.sales_order.order_number, proposal_number: contract.sales_order.proposal&.proposal_number
    }
  end

  def self.digest(contract, signer_roster: nil)
    digest_data(capture(contract, signer_roster: signer_roster))
  end

  def self.digest_data(data)
    personal = %w[customer issuer_company].any? { |key| JrcCustomers::TaxIdentifier.normalize(data.dig(key, 'tax_id'))&.length == 11 }
    return JrcApprovals::Ledger.digest(data) unless data.key?('signer_roster') || personal

    key = Rails.application.key_generator.generate_key('jrc-contract-source-with-signers-v2', 32)
    OpenSSL::HMAC.hexdigest('SHA256', key, JrcServiceDesk::CanonicalJson.dump(data))
  end

  def self.presentation(data)
    public_data = data.deep_dup
    roster = public_data.dig('signer_roster', 'source')
    Array(roster&.fetch('signers')).each do |person|
      person.except!('personal_tax_identifier', 'identity_id', 'anchor')
    end
    [public_data['customer'], public_data['issuer_company'], roster&.fetch('customer'), roster&.fetch('issuer')].compact.each do |company|
      value = JrcCustomers::TaxIdentifier.normalize(company['tax_id'])
      company['tax_id'] = "***.***.***-#{value[-2, 2]}" if value&.length == 11
    end
    public_data
  end

  def self.item_snapshots(contract)
    items = contract.contract_items.order(:id).to_a
    items = contract.sales_order.order_items.order(:id).to_a if items.empty?
    items.map { |item| item.attributes.except('created_at', 'updated_at', 'status', 'starts_on', 'operational_identifier') }
  end

  def self.differences(before, after, prefix = '')
    if before.is_a?(Hash) && after.is_a?(Hash)
      return (before.keys | after.keys).sort.flat_map do |key|
        differences(before[key], after[key], [prefix, key].reject(&:empty?).join('.'))
      end
    end
    before == after ? [] : [{ path: prefix, before: before, after: after }]
  end
end
