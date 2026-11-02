# A bounded legal/commercial source. Operational statuses and timestamps are
# deliberately not legal revisions; the stored PDF remains the document sent.
class JrcBackoffice::ContractSnapshot
  CONTRACT_FIELDS = %w[id contract_number sales_order_id contract_template_id contract_type starts_on ends_on term_months
                       renewal_type adjustment_index monthly_cents one_time_cents payment_condition due_day auto_renew
                       renewal_notice_days renewal_term_months content_override notes].freeze
  COMPANY_FIELDS = %w[id name legal_name trade_name tax_id domain].freeze

  def self.capture(contract)
    data = {
      contract: contract.attributes.slice(*CONTRACT_FIELDS), financials: contract.financial_summary,
      addenda: Array(contract.lifecycle_metadata['addenda']),
      items: item_snapshots(contract),
      template: contract.contract_template&.attributes&.slice('id', 'name', 'body'), renderer: 'native-commercial-document/1'
    }.merge(parties(contract))
    JrcServiceDesk::CanonicalJson.normalize(data.as_json)
  end

  def self.parties(contract)
    company = contract.account.master_companies.find_by(id: contract.contact&.company_id)
    {
      customer: company&.attributes&.slice(*COMPANY_FIELDS),
      contact: contract.contact&.attributes&.slice('id', 'name', 'email', 'phone_number', 'company_id'),
      commercial_owner: { id: contract.owner_id, name: contract.owner.name },
      issuer: JrcCrm::CorporateIssuer.document_name(contract, contract.sales_order, (contract.sales_order.snapshot || {}).with_indifferent_access),
      order_number: contract.sales_order.order_number
    }
  end

  def self.digest(contract)
    JrcApprovals::Ledger.digest(capture(contract))
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
