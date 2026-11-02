# Contextual selection from the existing CRM template registry and matcher.
# The selected order/issuer comes from the authorized request, never the picker.
class JrcBackoffice::ContractTemplates
  def initialize(account:, actor:, request_id:)
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
    @request_id = request_id
  end

  def options(query: nil, page: 1)
    contract = editable_contract!
    digest = JrcBackoffice::ContractSnapshot.digest(contract)
    payload = eligible_page(contract, query, page)
    raise JrcBackoffice::ContractVersions::Changed unless digest == JrcBackoffice::ContractSnapshot.digest(editable_contract!)

    payload
  end

  # Called under the native draft update transaction. SHARE prevents a template
  # administrator changing its active/rules/body halfway through the selection.
  def select!(id)
    contract = editable_contract!
    template = registry.find(id)
    template.lock!('FOR SHARE')
    raise ArgumentError, 'O modelo não atende aos critérios atuais deste pedido.' unless template.active? && matches?(template, contract)

    editable_contract!
    template
  end

  private

  def editable_contract!
    request = @access.writable!(@access.request(@request_id))
    contract = @access.contract!(request)
    JrcCrm::CorporateIssuer.authorize_resource!(contract, @access.actor)
    raise ArgumentError, 'O contrato enviado ou assinado foi preservado.' if contract.signature_status.in?(%w[sent signed])

    contract
  end

  def registry
    @access.account.jrc_crm_contract_templates
  end

  def matches?(template, contract)
    JrcCrm::ContractTemplateSelection.match?(template.selection_rules || {}, JrcCrm::ContractTemplateSelection.context(contract.sales_order))
  end

  def eligible_page(contract, query, page)
    rows = search(registry.where(active: true), query).select(:id, :name, :category, :selection_rules)
    ids = matching_ids(rows, contract)
    pages = [(ids.length / 10.0).ceil, 1].max
    selected_page = page.to_s.to_i.clamp(1, pages)
    selected = rows.where(id: ids).order(:name, :id).offset((selected_page - 1) * 10).limit(10)
    { data: selected.map { |row| row.slice('id', 'name', 'category') },
      meta: { page: selected_page, pages: pages, per_page: 10, total: ids.length } }
  end

  def matching_ids(rows, contract)
    context = JrcCrm::ContractTemplateSelection.context(contract.sales_order)
    # Iterate configuration in batches, without reading template bodies or
    # returning an unbounded registry to the browser.
    rows.find_each.filter_map { |row| row.id if JrcCrm::ContractTemplateSelection.match?(row.selection_rules || {}, context) }
  end

  def search(rows, query)
    raise ArgumentError, 'Use uma pesquisa de até 120 caracteres.' unless query.nil? || (query.is_a?(String) && query.length <= 120)

    term = query.to_s.strip
    term.empty? ? rows : rows.where('name ILIKE ?', "%#{JrcCrm::ContractTemplate.sanitize_sql_like(term)}%")
  end
end
