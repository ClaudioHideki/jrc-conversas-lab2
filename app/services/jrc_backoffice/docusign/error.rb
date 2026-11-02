class JrcBackoffice::Docusign::Error < StandardError
  attr_reader :code, :http_status

  def initialize(code:, http_status: nil, uncertain: false)
    @code = code
    @http_status = http_status
    @uncertain = uncertain
    super(code)
  end

  def uncertain?
    @uncertain
  end
end
