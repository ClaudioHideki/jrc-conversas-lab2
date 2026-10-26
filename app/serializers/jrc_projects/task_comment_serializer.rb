class JrcProjects::TaskCommentSerializer
  def initialize(record)
    @record = record
  end

  def as_json(_options = {})
    @record.attributes.slice('id', 'body', 'account_id', 'task_id', 'user_id', 'created_at', 'updated_at').merge(
      'content_format' => @record.content_format,
      'user' => @record.user.as_json(only: %i[id name]),
      'inline_images' => @record.inline_images.attachments.map do |attachment|
        { id: attachment.id, key: attachment.blob.metadata['comment_image_key'], name: attachment.filename.to_s,
          byte_size: attachment.byte_size, content_type: attachment.content_type }
      end
    )
  end
end
