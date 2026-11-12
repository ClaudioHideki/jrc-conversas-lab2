module JrcCrm
  class ContractPdfService
    def initialize(record, revision: nil, signers: nil)
      @record = record
      @revision = revision
      @signers = signers
    end

    def call
      options = { kind: :contract, record: @record, revision: @revision }
      options[:signers] = @signers if @signers
      CommercialDocumentService.new(**options).call
    end
  end
end
