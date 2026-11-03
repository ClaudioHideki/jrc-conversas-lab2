require 'rails_helper'

RSpec.describe DataImportJob do
  let(:data_import) { create(:data_import) }

  it 'preserves a queued legacy source and records the real review requirement without importing contacts' do
    source = data_import.import_file.blob
    data_import.account.enable_features!('jrc_customer_master')
    expect { described_class.perform_now(data_import) }.not_to change(Contact, :count)
    expect(data_import.reload).to be_failed
    expect(data_import.processing_errors).to start_with('REVIEW_REQUIRED:')
    expect(data_import.import_file.blob).to eq(source)
    expect(data_import.items.count).to eq(0)
  end

  it 'never passes a reviewed master run to the legacy parser or mutates its durable outcome' do
    account = data_import.account
    account.enable_features!('jrc_customer_master')
    actor = create(:user, account: account, role: :administrator)
    run = JrcCustomers::ImportRuns.new(account: account, actor: actor)
                                  .create!(kind: 'contacts', content: "name,email\nPerson,person@example.test\n", filename: 'source.csv')
    previous = run.reload.attributes
    expect { described_class.perform_now(run) }.not_to change(Contact, :count)
    expect(run.reload.attributes).to eq(previous)
  end
end
