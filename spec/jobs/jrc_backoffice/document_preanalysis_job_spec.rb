require 'rails_helper'

RSpec.describe JrcBackoffice::DocumentPreanalysisJob, type: :job do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved') }
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, owner: actor, requested_by: actor, contact: contact,
                                                title: 'TESTE SINTÉTICO — Job documental', metadata: { required_documents: ['powers'] })
  end
  let(:file) { fixture_file_upload(Rails.root.join('spec/fixtures/files/sample.pdf'), 'application/pdf') }
  let(:version) do
    JrcBackoffice::Documents.new(request: operation, actor: actor).upload!(key: 'powers', file: file, idempotency_key: SecureRandom.uuid)
  end

  before { account.enable_features!('jrc_crm') }

  it 'preserves an unavailable observation before retrying and never invokes OCR' do
    version
    expect(JrcBackoffice::TextExtraction).not_to receive(:call)
    with_modified_env(JRC_BO_CLAMAV_SOCKET: nil) do
      expect { described_class.perform_now(version.id) }.to have_enqueued_job(described_class).with(version.id)
    end
    expect(JrcBackoffice::DocumentSafety.new(version).current&.state).to eq('unavailable')
    expect(version.reload.analysis).to be_nil
    expect(version.decisions).to be_empty
  end

  it 'persists an infected observation without parsing or automatically retrying it' do
    scanner = instance_double(JrcServiceDesk::AttachmentScanner)
    allow(JrcServiceDesk::AttachmentScanner).to receive(:new).and_return(scanner)
    allow(scanner).to receive(:scan).with(version.file.blob, socket_path: anything).and_return(
      'service_desk_scan_state' => 'infected', 'service_desk_scan_sha256' => version.sha256
    )
    expect(JrcBackoffice::TextExtraction).not_to receive(:call)
    expect { described_class.perform_now(version.id) }.not_to have_enqueued_job(described_class)
    expect(JrcBackoffice::DocumentSafety.new(version).current&.state).to eq('infected')
    expect(version.reload.analysis).to be_nil
  end

  it 'parses clean bytes once and still requires a separate human decision' do
    # The daemon reply is simulated; Poppler and the native analysis persistence are real.
    scanner = instance_double(JrcServiceDesk::AttachmentScanner)
    allow(JrcServiceDesk::AttachmentScanner).to receive(:new).and_return(scanner)
    allow(scanner).to receive(:scan).with(version.file.blob, socket_path: anything).and_return(
      'service_desk_scan_state' => 'clean', 'service_desk_scan_sha256' => version.sha256
    )
    described_class.perform_now(version.id)
    expect(version.reload.analysis.state).to eq('review_required')
    expect(version.decisions).to be_empty
    event = JrcCrm::AuditEvent.find_by!(account: account, event_type: 'backoffice_document_analyzed')
    expect(event.actor_type).to eq('System')
    expect(event.actor_id).to be_nil
    expect { described_class.perform_now(version.id) }.not_to change(JrcBackoffice::DocumentAnalysis, :count)
    expect(JrcBackoffice::DocumentScan.where(document_version: version).count).to eq(1)
  end

  it 'does not turn interactive document authority into a system analysis command' do
    expect do
      JrcBackoffice::Documents.new(request: operation, actor: actor).reflect_analysis!(version)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(version.reload.analysis).to be_nil
    expect(version.decisions).to be_empty
  end

  it 'retains technical scan evidence but does not parse or rewrite a canceled operational request' do
    version
    operation.update!(status: 'canceled')
    before = operation.reload.attributes
    scanner = instance_double(JrcServiceDesk::AttachmentScanner)
    allow(JrcServiceDesk::AttachmentScanner).to receive(:new).and_return(scanner)
    allow(scanner).to receive(:scan).with(version.file.blob, socket_path: anything).and_return(
      'service_desk_scan_state' => 'clean', 'service_desk_scan_sha256' => version.sha256
    )
    expect(JrcBackoffice::TextExtraction).not_to receive(:call)
    described_class.perform_now(version.id)
    expect(operation.reload.attributes).to eq(before)
    expect(version.reload.analysis).to be_nil
    expect(version.decisions).to be_empty
    expect(JrcBackoffice::DocumentSafety.new(version).current.state).to eq('clean')
  end

  it 'does not inspect or parse a document from a suspended account' do
    version
    account.update!(status: 'suspended')
    expect(JrcServiceDesk::AttachmentScanner).not_to receive(:new)
    expect(JrcBackoffice::TextExtraction).not_to receive(:call)
    expect { described_class.perform_now(version.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcBackoffice::DocumentScan.where(document_version: version)).to be_empty
  end
end
