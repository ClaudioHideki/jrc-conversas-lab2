require 'uri'

class JrcCampaigns::ProviderMessageProxy
  AttachmentProxy = Data.define(:file_type, :download_url, :meta, :file)

  class FileProxy
    attr_reader :filename

    def initialize(filename)
      @filename = filename.to_s
    end

    def attached?
      false
    end
  end

  attr_accessor :external_error, :status, :provider_response
  attr_reader :content_type, :content_attributes

  def initialize(kind:, body:, media_url: nil, file_name: nil)
    @kind = kind
    @body = body
    @media_url = media_url
    @file_name = file_name
    @content_type = 'text'
    @content_attributes = {}
  end

  def capture_provider_response(value)
    data = value.is_a?(Hash) ? value : {}
    @provider_response = Array(data['messages']).first.to_h.slice('message_status')
    error = data['error'].is_a?(Hash) ? data['error'] : {}
    safe_error = error.slice('code', 'error_subcode', 'type').transform_values(&:to_s)
                      .select { |_key, item| item.match?(/\A[a-zA-Z0-9_]{1,64}\z/) }
    @provider_response['error'] = safe_error if safe_error.present?
  end

  def attachments
    return [] unless %w[image document video audio].include?(@kind)

    [AttachmentProxy.new(
      file_type: @kind,
      download_url: @media_url,
      meta: {},
      file: FileProxy.new(@file_name.presence || fallback_file_name)
    )]
  end

  def outgoing_content
    @body.to_s
  end

  def save!
    true
  end

  private

  def fallback_file_name
    File.basename(URI.parse(@media_url.to_s).path)
  rescue URI::InvalidURIError
    'arquivo'
  end
end
