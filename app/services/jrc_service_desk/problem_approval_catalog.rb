# frozen_string_literal: true

# Registers only a read-only contract. Installs no policy, amount, approver,
# commercial authority, feature activation or operational callback.
class JrcServiceDesk::ProblemApprovalCatalog
  KEY = 'service_desk.problem_change'
  FIELDS = { 'severity' => 'string', 'status' => 'string', 'context_digest' => 'string' }.freeze

  def self.install!
    model = JrcServiceDesk::Incident
    existing = JrcApprovals::Catalog.instance_variable_get(:@entries)[KEY]
    return if existing&.model.equal?(model)

    JrcApprovals::Catalog.instance_variable_get(:@mutex).synchronize { JrcApprovals::Catalog.instance_variable_get(:@entries).delete(KEY) }
    JrcApprovals::Catalog.register(key: KEY, version: 1, model: model, fields: FIELDS,
                                   authorize: lambda { |user, row|
                                     member = row.account.account_users.find_by(user_id: user&.id)
                                     row.resource_kind == 'problem' && member && JrcServiceDesk::IncidentPolicy.new({ account: row.account, user: user, account_user: member }, row).update?
                                   },
                                   capture: lambda { |row|
                                     raise JrcApprovals::Error, 'EXPLICIT_APPROVAL_SCOPE_REQUIRED' unless row.approval_issuer_company_id

                                     { 'issuer_company_id' => row.approval_issuer_company_id, 'business_unit_id' => row.approval_business_unit_id,
                                       'values' => { 'severity' => row.severity, 'status' => row.status,
                                                     'context_digest' => JrcServiceDesk::CanonicalJson.digest(row.attributes.slice('unit_id', 'title', 'description', 'cause', 'resolution', 'details', 'severity', 'status')) } }
                                   })
  end
end
