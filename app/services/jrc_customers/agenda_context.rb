# Enrichment/filtering of JrcOperations::Agenda, not another calendar or table.
class JrcCustomers::AgendaContext
  def initialize(account_user:, filters:)
    @member = account_user
    @account = @member.account
    @user = @member.user
    @allowed = @account.feature_enabled?('jrc_customer_master') &&
               JrcCustomers::DirectoryPolicy.new(JrcOperations::Access.user_context(@member), :directory).access?
    @contexts = []
    %i[company_id contact_id].each do |key|
      next if filters[key].blank?
      raise Pundit::NotAuthorizedError unless @allowed
      record = key == :company_id ? @account.master_companies.find(filters[key]) : @account.contacts.find(filters[key])
      @contexts << JrcCustomers::Customer360.new(account: @account, user: @user, account_user: @member,
                                                **{ key == :company_id ? :company : :contact => record })
    end
    @companies = {}
    @contacts = {}
  end

  def projects(scope)
    @contexts.reduce(scope) { |result, context| result.where(id: context.projects.select(:id)) }
  end

  def crm(scope)
    source = scope.klass == JrcCrm::FollowUp ? :follow_ups : :activities
    result = @contexts.reduce(scope) { |rows, context| rows.where(id: context.public_send(source).select(:id)) }
    @allowed ? result.includes(:deal, :lead) : result
  end

  def attributes(record)
    return {} unless @allowed
    origin = record.is_a?(JrcProjects::Task) ? record.project : record
    company_id = origin.has_attribute?(:company_id) ? origin.company_id : nil
    contact_id = origin.has_attribute?(:contact_id) ? origin.contact_id : nil
    %i[deal lead].each do |key|
      next unless origin.respond_to?(key)
      related = origin.public_send(key)
      next unless related && related.account_id == @account.id
      company_id ||= related.company_id
      contact_id ||= related.contact_id
    end
    contact = @contacts.fetch(contact_id) { @contacts[contact_id] = @account.contacts.find_by(id: contact_id) } if contact_id
    company_id ||= contact&.company_id
    company = @companies.fetch(company_id) { @companies[company_id] = @account.master_companies.find_by(id: company_id) } if company_id
    { contact: contact && { id: contact.id, name: contact.name }, company: company && { id: company.id, name: company.name } }
  end
end
