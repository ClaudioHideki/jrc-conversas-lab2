require 'rails_helper'

RSpec.describe 'DataImports::ReconciliationReport' do
  let(:account) { create(:account) }
  let(:data_import) { create(:data_import, :intercom, account: account, import_types: ['contacts'], status: :completed) }

  it 'keeps a missing source total unknown rather than treating it as zero' do
    report = DataImports::ReconciliationReport.new(data_import: data_import).call

    expect(report).to include(status: 'incomplete', source_checked: false, acceptance: 'not_reviewed')
    expect(report[:entities].first).to include(type: 'contact', source_total: nil, difference: nil, comparison: 'unknown')
  end

  it 'accepts a recorded zero but does not certify the source or migration' do
    data_import.update!(stats: { 'contacts' => { 'total' => 0 } })

    report = DataImports::ReconciliationReport.new(data_import: data_import).call

    expect(report[:entities].first).to include(source_total: 0, difference: 0, comparison: 'equal')
    expect(report).to include(status: 'local_checks_passed', source_checked: false, acceptance: 'not_reviewed')
  end

  it 'counts missing and foreign-account targets without exposing their data', :aggregate_failures do
    contact = create(:contact, account: account)
    foreign = create(:contact, name: 'Foreign reconciliation fixture', email: 'foreign-reconciliation@example.test')
    [[contact.id, 'valid'], [foreign.id, 'foreign'], [9_999_999_999, 'missing']].each do |target_id, source_id|
      data_import.mappings.create!(account: account, source_provider: 'intercom', source_object_type: 'contact',
                                   source_object_id: source_id, chatwoot_record_type: 'Contact', chatwoot_record_id: target_id)
    end
    data_import.update!(stats: { 'contacts' => { 'total' => 3 } })

    report = DataImports::ReconciliationReport.new(data_import: data_import).call

    expect(report[:entities].first[:mappings]).to include(total: 3, valid: 1, missing: 1, cross_account: 1, unsupported: 0)
    expect(report[:entities].first).to include(difference: 2, comparison: 'different')
    expect(report[:status]).to eq('differences_found')
    expect(report.to_json).not_to include(foreign.email, foreign.name)
  end

  it 'uses a fixed target whitelist instead of resolving an arbitrary stored class name' do
    data_import.mappings.create!(account: account, source_provider: 'intercom', source_object_type: 'contact',
                                 source_object_id: 'unsafe-type', chatwoot_record_type: 'Kernel', chatwoot_record_id: 1)

    report = DataImports::ReconciliationReport.new(data_import: data_import).call

    expect(report[:entities].first[:mappings]).to include(valid: 0, unsupported: 1)
    expect(report[:status]).to eq('differences_found')
    expect(report.to_json).not_to include('Kernel')
  end

  it 'does not pass local checks when an imported item has lost its source mapping' do
    contact = create(:contact, account: account)
    data_import.items.create!(source_provider: 'intercom', source_object_type: 'contact', source_object_id: 'unmapped',
                             status: :imported, chatwoot_record_type: 'Contact', chatwoot_record_id: contact.id)
    data_import.update!(stats: { 'contacts' => { 'total' => 0 } })

    report = DataImports::ReconciliationReport.new(data_import: data_import).call

    expect(report[:entities].first[:mappings]).to include(unmapped_items: 1)
    expect(report[:status]).to eq('differences_found')
  end

  it 'recognizes an existing mapping from a previous run through the current item identity' do
    previous = create(:data_import, :intercom, account: account, status: :completed)
    contact = create(:contact, account: account)
    previous.mappings.create!(account: account, source_provider: 'intercom', source_object_type: 'contact',
                              source_object_id: 'already-imported', chatwoot_record_type: 'Contact', chatwoot_record_id: contact.id)
    data_import.items.create!(source_provider: 'intercom', source_object_type: 'contact', source_object_id: 'already-imported',
                             status: :skipped, chatwoot_record_type: 'Contact', chatwoot_record_id: contact.id)
    data_import.update!(stats: { 'contacts' => { 'total' => 1 } })

    report = DataImports::ReconciliationReport.new(data_import: data_import).call

    expect(report[:entities].first[:mappings]).to include(total: 1, valid: 1, missing: 0)
    expect(report[:entities].first[:items]).to include('skipped' => 1)
    expect(report[:entities].first).to include(difference: 0, comparison: 'equal')
  end

  it 'reports corrupt foreign-account mapping ownership without following its target' do
    foreign = create(:account)
    contact = create(:contact, account: foreign, name: 'Foreign ownership fixture', email: 'foreign-ownership@example.test')
    data_import.mappings.create!(account: foreign, source_provider: 'intercom', source_object_type: 'contact',
                                 source_object_id: 'foreign-binding', chatwoot_record_type: 'Contact', chatwoot_record_id: contact.id)

    report = DataImports::ReconciliationReport.new(data_import: data_import).call

    expect(report[:integrity]).to include(foreign_account_mappings: 1)
    expect(report[:entities].first[:mappings]).to include(valid: 0)
    expect(report[:status]).to eq('differences_found')
    expect(report.to_json).not_to include(contact.name, contact.email)
  end

  it 'keeps unsupported source entities explicit rather than silently omitting them' do
    contact = create(:contact, account: account)
    data_import.mappings.create!(account: account, source_provider: 'intercom', source_object_type: 'asset',
                                 source_object_id: 'asset-1', chatwoot_record_type: 'Contact', chatwoot_record_id: contact.id)

    report = DataImports::ReconciliationReport.new(data_import: data_import).call

    expect(report[:integrity]).to include(unsupported_source_types: 1)
    expect(report[:status]).to eq('differences_found')
  end

  it 'does not pass local checks when stored mappings contain an entity outside the selected import scope' do
    data_import.update!(stats: { 'contacts' => { 'total' => 0 } })
    conversation = create(:conversation, account: account)
    data_import.mappings.create!(account: account, source_provider: 'intercom', source_object_type: 'conversation',
                                 source_object_id: 'unexpected-conversation', chatwoot_record_type: 'Conversation', chatwoot_record_id: conversation.id)

    report = DataImports::ReconciliationReport.new(data_import: data_import).call

    expect(report[:integrity]).to include(unselected_mapping_types: 1)
    expect(report[:status]).to eq('differences_found')
  end

  it 'does not pass local checks when stored items contain an entity outside the selected import scope without a mapping' do
    data_import.update!(stats: { 'contacts' => { 'total' => 0 } })
    conversation = create(:conversation, account: account)
    data_import.items.create!(source_provider: 'intercom', source_object_type: 'conversation', source_object_id: 'unexpected-item',
                             status: :imported, chatwoot_record_type: 'Conversation', chatwoot_record_id: conversation.id)

    report = DataImports::ReconciliationReport.new(data_import: data_import).call

    expect(report[:integrity]).to include(unselected_item_types: 1)
    expect(report[:status]).to eq('differences_found')
  end

  it 'keeps legitimate skipped message mappings separate and does not certify attachment integrity', :aggregate_failures do
    data_import.update!(import_types: ['conversations'])
    conversation = create(:conversation, account: account)
    data_import.mappings.create!(account: account, source_provider: 'intercom', source_object_type: 'message',
                                 source_object_id: 'skipped-part', chatwoot_record_type: 'Conversation', chatwoot_record_id: conversation.id,
                                 metadata: { skipped: true, source: { attachments: [{ url: 'https://example.test/private-file' }] } })

    report = DataImports::ReconciliationReport.new(data_import: data_import).call

    message = report[:entities].find { |entity| entity[:type] == 'message' }
    expect(message[:mappings]).to include(total: 1, skipped: 1, unsupported: 0, valid: 0)
    expect(report[:attachments]).to include(coverage: 'not_supported', integrity_verified: false, referenced_messages: 1)
    expect(report[:status]).not_to eq('local_checks_passed')
    expect(report.to_json).not_to include('private-file')
  end
end
