class JrcRelationship::ExpansionAttributes
  def initialize(context, assignment)
    @context = context
    @assignment = assignment
  end

  def call(data:, key:, revenue_growth:, usage_growth:, base:)
    usage = data[:usage_growth]
    source_product = if usage_growth
                       @context.account.jrc_crm_products.active.where(id: Array(data[:products]).pluck(:id))
                               .find_by(id: usage[:product_id])
                     end
    { account: @context.account, assignment: @assignment, owner: @assignment.owner,
      title: expansion_title(revenue_growth),
      source_product: source_product, potential_cents: 0,
      evidence: expansion_evidence(data, revenue_growth, base),
      metadata: { source_key: key, automatic: true, kind: 'upsell',
                  qualification_status: 'product_selection_pending',
                  observed_contract_ids: data[:active_contract_ids],
                  observed_product_ids: Array(data[:products]).pluck(:id),
                  _source_ids: data[:_source_ids] } }
  end

  private

  def expansion_title(revenue_growth)
    revenue_growth ? 'Expansão: crescimento observado da receita recorrente' : 'Expansão: crescimento observado de uso'
  end

  def expansion_evidence(data, revenue_growth, base)
    usage = data[:usage_growth]
    observed = if revenue_growth
                 "MRR observado: #{base} → #{data[:mrr_cents]} centavos."
               else
                 "Uso observado: #{usage[:baseline]} → #{usage[:current]}; #{usage[:evidence]}"
               end
    "#{observed} Potencial ainda depende de qualificação comercial."
  end
end
