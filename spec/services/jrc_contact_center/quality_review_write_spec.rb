# frozen_string_literal: true

require 'rails_helper'
require 'stringio'

RSpec.describe JrcContactCenter::QualityReviewWrite, :pabx do
  include_context 'with native authorized quality review source'

  let(:service) { described_class.new(account: account, member: member) }
  let(:snapshot) { JrcContactCenter::QualityAnalysisSnapshot.new(analysis: analysis, authorized_call_id: record.external_unique_id) }
  let(:values) do
    { 'classification' => 'negative', 'adjusted_summary' => 'SYNTHETIC human correction', 'adjusted_themes' => ['SYNTHETIC service'],
      'recommendation_ids' => snapshot.recommendations.pluck('id'), 'justification' => 'SYNTHETIC reviewed reason',
      'expected_revision' => 0, 'expected_source_sha256' => snapshot.sha256, 'request_id' => SecureRandom.uuid }
  end
  let(:rows) { JrcContactCenter::QualityReviewRevision.where(account: account) }

  it 'persists the explicit human revision without changing the original classification, zero score, recording or transcript' do
    original_record = record.attributes
    original_analysis = analysis.deep_dup
    row = service.call(record.id, values).reload
    expect(row.reviewed_values).to include('classification' => 'negative', 'justification' => values.fetch('justification'))
    expect(row.original_analysis).to include('sentimento_cliente' => 'positivo', 'classificacao_ligacao' => 'excelente', 'nota_final' => 0)
    expect(row.original_analysis).to include('model' => nil, 'sentiment_confidence' => nil)
    expect(row.original_analysis).not_to have_key('texto_transcrito')
    expect(row).to have_attributes(revision: 1, actor_user_id: actor.id, actor_account_user_id: member.id)
    expect(row.scope_snapshot.fetch('business_unit_id')).to eq(business.id.to_s)
    expect(record.reload.attributes).to eq(original_record)
    expect(analysis).to eq(original_analysis)
    expect(Audited.audit_class.where(auditable: row, action: 'create').count).to eq(1)
  end

  it 'returns the exact existing revision for a retry without duplicating the revision or its audit' do
    first = service.call(record.id, values)
    repeated = service.call(record.id, values.to_a.reverse.to_h)
    expect(repeated.id).to eq(first.id)
    expect(rows.count).to eq(1)
    expect(Audited.audit_class.where(auditable: first, action: 'create').count).to eq(1)
  end

  it 'refuses reuse of a request identity with changed text and preserves the first immutable revision' do
    first = service.call(record.id, values)
    expect do
      service.call(record.id, values.merge('adjusted_summary' => 'SYNTHETIC different correction'))
    end.to raise_error(JrcContactCenter::OperationError, 'quality_review_request_conflict')
    expect(rows.sole.attributes).to eq(first.reload.attributes)
  end

  it 'rejects a stale competing revision and appends only after the user explicitly reviews the new counter' do
    first = service.call(record.id, values)
    competing = values.merge('request_id' => SecureRandom.uuid, 'classification' => 'neutral')
    expect { service.call(record.id, competing) }.to raise_error(JrcContactCenter::OperationError, 'quality_review_revision_changed')
    second = service.call(record.id, competing.merge('expected_revision' => 1))
    expect(second.revision).to eq(2)
    expect(first.reload.reviewed_values.fetch('classification')).to eq('negative')
    expect(rows.order(:revision).pluck(:revision)).to eq([1, 2])
  end

  it 'refuses an absent justification and an invented suggestion without creating a partial revision or action' do
    invalid = [values.merge('justification' => ''), values.merge('recommendation_ids' => ['e' * 64])]
    invalid.each do |input|
      expect { service.call(record.id, input) }.to raise_error(JrcContactCenter::OperationError)
    end
    expect(rows).to be_empty
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'revalidates the explicit review permission after source I/O and never creates a revision for a revoked agent' do
    values
    allow(provider).to receive(:find_analysis) do
      role.update!(permissions: recording_rights)
      analysis
    end
    expect { service.call(record.id, values) }.to raise_error(Pundit::NotAuthorizedError)
    expect(rows).to be_empty
  end

  it 'rolls back the actual revision when its native audit is rejected by PostgreSQL' do
    values
    name = "cc_synthetic_quality_audit_#{Integer(account.id)}"
    condition = "auditable_type <> 'JrcContactCenter::QualityReviewRevision' OR associated_id <> #{Integer(account.id)}"
    ApplicationRecord.connection.add_check_constraint(:audits, condition, name: name)
    expect do
      ApplicationRecord.transaction(requires_new: true) { service.call(record.id, values) }
    end.to raise_error(ActiveRecord::StatementInvalid, /cc_synthetic_quality_audit_/)
    expect(rows).to be_empty
  end

  it 'keeps ordinary logs and the native audit metadata free of original transcript and reviewed private text' do
    previous = ActiveRecord::Base.logger
    output = StringIO.new
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(output)
    row = service.call(record.id, values)
    ApplicationRecord.connection.execute('SELECT 1 AS synthetic_quality_unrelated_probe')
    audit = Audited.audit_class.where(auditable: row, action: 'create').sole
    expect(audit.audited_changes).to include('operation' => 'quality_review', 'revision' => 1)
    private_values = [values.fetch('adjusted_summary'), values.fetch('justification'), 'SYNTHETIC original transcript']
    expect(audit.audited_changes.to_json).not_to include(*private_values)
    expect(output.string).to include('jrc_contact_center_quality_review_revisions', '[FILTERED]', 'synthetic_quality_unrelated_probe')
    expect(output.string).not_to include(*private_values, 'SYNTHETIC original summary')
    expect(row.inspect).not_to include(values.fetch('adjusted_summary'), values.fetch('justification'), 'SYNTHETIC original summary')
    expect(ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter('quality_review' => values))
      .to eq('quality_review' => '[FILTERED]')
  ensure
    ActiveRecord::Base.logger = previous
  end
end
