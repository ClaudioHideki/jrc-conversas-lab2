# frozen_string_literal: true

class JrcServiceDesk::RequesterService < JrcServiceDesk::BaseService
  def create(unit_id:, company_id:, attributes:, request_key:, confirm_distinct: false)
    raise ArgumentError, 'Boolean confirmation required' unless [true, false].include?(confirm_distinct)
    with_unit(unit_id) do
      authorize_directory!
      authorize!(Contact, :create?)
      company = JrcServiceDesk::RequesterDirectory.new(context).company!(company_id)
      contact = writer.create!(company: company, attributes: attributes, request_key: JrcServiceDesk::Input.request_key(request_key),
                               confirm_distinct: confirm_distinct)
      JrcServiceDesk::RequesterDirectory.new(context).validate!(contact, company_id: company.id)
      contact
    end
  end

  def link(unit_id:, company_id:, contact_id:, confirm:)
    raise ArgumentError, 'Explicit confirmation required' unless confirm == true

    with_unit(unit_id) do
      authorize_directory!
      directory = JrcServiceDesk::RequesterDirectory.new(context)
      company = directory.company!(company_id)
      contact = directory.visible_contacts.find(JrcServiceDesk::Input.id(contact_id))
      authorize!(contact, :show?)
      authorize!(contact, :update?)
      writer.link!(contact: contact, company: company)
    end
  end

  private

  def authorize_directory!
    raise Pundit::NotAuthorizedError unless context.capability?(:tickets_create) && context.capability?(:customers_view)

    Pundit.authorize(context.to_h, :directory, :access?, policy_class: JrcCustomers::DirectoryPolicy)
  end

  def writer
    JrcCustomers::RequesterWriter.new(account: context.account, actor: context.user)
  end
end
