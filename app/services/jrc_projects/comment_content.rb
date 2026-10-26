require 'digest'

class JrcProjects::CommentContent
  IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  IMAGE_KEY = /\A[a-zA-Z0-9-]{16,80}\z/

  def initialize(record:, parameters:)
    @record = record
    @parameters = parameters
    @body = parameters.require(:body).to_s
    @format = parameters[:content_format].presence || record.content_format
    images = parameters[:images]
    raise ArgumentError, 'Imagens inválidas.' if images.present? && !images.is_a?(ActionController::Parameters)
    @images = images.present? ? images.to_unsafe_h : {}
  end

  def digest
    @digest ||= Digest::SHA256.hexdigest(JSON.generate([
      @body, @format, @images.sort.map { |key, file| [key, file.original_filename, Digest::SHA256.file(file.tempfile.path).hexdigest] }
    ]))
  end

  def apply!
    validate!
    @record.assign_attributes(body: @body, content_format: @format)
    @images.each do |key, file|
      @record.inline_images.attach(io: file.tempfile, filename: file.original_filename, content_type: file.content_type,
                                   metadata: { comment_image_key: key })
    end
    @record.save!
  end

  def validate!
    raise ArgumentError, 'Formato de comentário inválido.' unless %w[plain_text markdown].include?(@format)
    own_keys = @record.inline_images.attachments.map { |image| image.blob.metadata['comment_image_key'] }
    invalid_upload = @images.any? do |key, file|
         !IMAGE_KEY.match?(key) || own_keys.include?(key) || !file.is_a?(ActionDispatch::Http::UploadedFile) ||
           file.size > 10.megabytes || file.size.zero? || !IMAGE_TYPES.include?(Marcel::MimeType.for(file.tempfile)) ||
           !IMAGE_TYPES.include?(file.content_type)
    end
    if @images.length + own_keys.length > 10 || invalid_upload
      raise ArgumentError, 'Use até 10 imagens PNG, JPEG, GIF ou WebP de até 10 MB por comentário.'
    end
    return if @format == 'plain_text' && @images.empty?
    raise ArgumentError, 'Imagens exigem comentário rico.' unless @format == 'markdown'
    raise ArgumentError, 'Imagens Base64 não são permitidas.' if @body.match?(/data\s*:\s*image\//i)

    references = @body.scan(/!\[[^\]]*\]\(([^\s)]+)/).flatten
    available = own_keys + @images.keys
    unless references.all? { |url| url.start_with?('comment-image:') && available.include?(url.delete_prefix('comment-image:')) }
      raise ArgumentError, 'Cada imagem deve pertencer a este comentário.'
    end
  end
end
