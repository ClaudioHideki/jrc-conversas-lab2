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
    new_images = @images.reject { |key, _file| existing_images.key?(key) }
    return false if @record.persisted? && @record.body == @body && @record.content_format == @format && new_images.empty?

    @record.assign_attributes(body: @body, content_format: @format)
    new_images.each do |key, file|
      @record.inline_images.attach(io: file.tempfile, filename: file.original_filename, content_type: file.content_type,
                                   metadata: { comment_image_key: key })
    end
    @record.save!
    true
  end

  def validate!
    raise ArgumentError, 'Formato de comentário inválido.' unless %w[plain_text markdown].include?(@format)
    own_keys = existing_images.keys
    invalid_upload = @images.any? do |key, file|
         !IMAGE_KEY.match?(key) || !file.is_a?(ActionDispatch::Http::UploadedFile) ||
           file.size > 10.megabytes || file.size.zero? || !IMAGE_TYPES.include?(Marcel::MimeType.for(file.tempfile)) ||
           !IMAGE_TYPES.include?(file.content_type) || (existing_images.key?(key) && !matching_image?(existing_images[key], file))
    end
    if (own_keys | @images.keys).length > 10 || invalid_upload
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

  private

  def existing_images
    @existing_images ||= @record.inline_images.attachments.includes(:blob).index_by { |image| image.blob.metadata['comment_image_key'] }
  end

  def matching_image?(image, file)
    return false unless image.blob[:filename] == file.original_filename && image.content_type == file.content_type && image.byte_size == file.size

    image.blob.open do |stored|
      Digest::SHA256.file(stored.path).hexdigest == Digest::SHA256.file(file.tempfile.path).hexdigest
    end
  end
end
