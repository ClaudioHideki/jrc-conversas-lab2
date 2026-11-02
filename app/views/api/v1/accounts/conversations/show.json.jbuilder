json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: @conversation
json.contact_inbox @conversation.contact_inbox&.as_json(only: [:id, :contact_id, :inbox_id, :source_id])
