module JrcCrm
  class ProposalPdfService
    def initialize(record)
      @record = record
    end

    def call
      CommercialDocumentService.new(kind: :proposal, record: @record).call
    end
  end
end
