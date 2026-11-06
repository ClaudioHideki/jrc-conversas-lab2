# Reference validation only; current actor authorization stays in Context.
class JrcRelationship::ConfigurationScope
  def self.validate(record)
    kind, id = record.scope_key.to_s.split(':')
    target = { 'segment' => JrcCustomers::Taxonomy, 'product' => JrcCrm::Product, 'company' => JrcCustomers::Company,
               'unit' => JrcCrm::BusinessUnit, 'team' => Team, 'portfolio' => JrcRelationship::PortfolioGroup }[kind]
    scope = target&.where(account_id: record.account_id, id: id)
    scope = scope.where(kind: 'segment') if kind == 'segment' && scope
    record.errors.add(:scope_key, 'scope must belong to this account and kind') if scope && !scope.exists?
  end
end
