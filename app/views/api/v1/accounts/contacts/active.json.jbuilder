json.meta do
  json.count @contacts_count
  json.current_page @current_page
  json.directory @directory_list.summary if @directory_list
end

directory_details = @directory_list&.details(@contacts)

json.payload do
  json.array! @contacts do |contact|
    json.partial! 'api/v1/models/contact', formats: [:json], resource: contact, with_contact_inboxes: @include_contact_inboxes
    json.directory directory_details.fetch(contact.id) if directory_details
  end
end
