# No source call or destination is created by this history fixture.
RSpec.shared_context 'with native private ending action definitions' do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:catalogue) { JrcContactCenter::EndingActions::Catalogue.new(account: account) }
  let(:definition) { { 'version' => 1, 'entries' => [] } }
  let(:versions) { JrcContactCenter::EndingActionVersion.where(account: account).order(:revision) }

  def record_private_ending_definition(document = definition)
    account.with_lock(requires_new: true) do
      member
      before = JrcContactCenter::AcwPolicyAudit.capture(account)
      update_private_ending_head(document)
      Current.set(user: actor, account: account, account_user: member) do
        audit = JrcContactCenter::AcwPolicyAudit.write!(account: account, before: before,
                                                    after: JrcContactCenter::AcwPolicyAudit.capture(account))
        JrcContactCenter::EndingActionVersion.record_change!(account: account, definition: document, audit: audit)
      end
    end
  end

  def update_private_ending_head(document)
    head = catalogue.head_for(document)
    settings = account.settings.fetch(JrcContactCenter::AcwPolicy::KEY, {}).merge(catalogue.class::KEY => head)
    account.update!(settings: account.settings.merge(JrcContactCenter::AcwPolicy::KEY => settings))
  end

  def guarded_ending_version_sql(statement)
    ApplicationRecord.transaction(requires_new: true) { ApplicationRecord.connection.execute(statement) }
  end
end
