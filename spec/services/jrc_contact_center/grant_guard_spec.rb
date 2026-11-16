require 'rails_helper'

RSpec.describe JrcContactCenter::GrantGuard do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }

  before { account.enable_features!('jrc_contact_center') }

  it 'does not let a native administrator manufacture a newly introduced power' do
    expect { described_class.check!(actor: actor, account: account, proposed: ['jrc_contact_center_publish']) }
      .to raise_error(Pundit::NotAuthorizedError)
  end

  it 'preserves existing grants and permits removals without silently changing them' do
    expect { described_class.check!(actor: actor, account: account, proposed: [], previous: ['jrc_contact_center_publish']) }.not_to raise_error
    expect do
      described_class.check!(actor: actor, account: account, proposed: ['jrc_contact_center_publish'], previous: ['jrc_contact_center_publish'])
    end.not_to raise_error
  end

  it 'allows explicit authorized grantors but requires account-wide corporate coverage' do
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_publish])
    account.account_users.find_by!(user: actor).update!(custom_role: role)
    expect { described_class.check!(actor: actor, account: account, proposed: ['jrc_contact_center_publish']) }.not_to raise_error
    company = account.master_companies.create!(name: 'Synthetic issuer', relationship_type: 'internal')
    JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'Synthetic unit', code: 'SYNTHETIC')
    expect { described_class.check!(actor: actor, account: account, proposed: ['jrc_contact_center_publish']) }
      .to raise_error(Pundit::NotAuthorizedError)
  end
end
