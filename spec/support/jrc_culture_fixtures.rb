# frozen_string_literal: true

RSpec.shared_context 'Manual de Cultura fixtures' do
  let(:account) { create(:account) }
  let(:company) { account.master_companies.create!(name: 'Empresa sintética', relationship_type: 'internal') }
  let(:unit) { account.jrc_crm_business_units.create!(name: 'Unidade A', code: 'culture-a', operating_company: company) }
  let(:admin_member) { create(:account_user, account: account, role: :administrator) }
  let(:employee) { create(:account_user, account: account) }
  let(:admin_grant) { culture_access(admin_member, unit, 'administrator') }
  let(:grant) { culture_access(employee, unit, 'employee') }
  let(:admin_headers) { admin_grant.account_user.user.create_new_auth_token }
  let(:employee_headers) { grant.account_user.user.create_new_auth_token }
  let(:api) { "/portal/manual-de-cultura/api/accounts/#{account.id}" }

  def culture_access(member, target, role)
    JrcCrm::UserBusinessUnit.find_or_create_by!(account: member.account, user: member.user, scope: 'BUSINESS_UNIT',
                                              business_unit: target, active: true, structure_managed: true)
    JrcCulture::Grant.create!(account: member.account, account_user: member, unit: target, role: role)
  end

  def culture_version(target = unit)
    manual = JrcCulture::Manual.create!(account: account, name: 'Manual de Cultura JRC')
    version = manual.versions.create!(title: 'Manual inicial', number: 1, state: 'published', published_at: Time.current)
    version.audiences.create!(unit: target)
    version
  end
end
