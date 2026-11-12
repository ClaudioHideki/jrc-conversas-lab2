# Project the native document workspace; never create a portfolio or a parallel document registry.
class JrcCustomers::CompanyDocumentsContext
  def initialize(member:, company:)
    @member = member
    @company = company
  end

  def call(assignment)
    return unless @company && assignment && assignment.company_id == @company.id

    context = JrcRelationship::Context.new(@member)
    return unless context.policy.documents_view?

    record = context.assignment(assignment.id)
    { assignment_id: record.id, can_manage_documents: context.policy.documents_manage?, formatting: context.formatting }
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    nil
  end
end
