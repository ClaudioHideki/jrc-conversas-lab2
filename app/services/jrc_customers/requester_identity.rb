# frozen_string_literal: true

# Classification uses official metadata/identifiers, never similarity of names.
# Unclassified native Contacts remain people; imported records need review.
class JrcCustomers::RequesterIdentity
  ORGANIZATION_IDENTIFIER = '^bemtevi:customer:'.freeze
  IMPORT_IDENTIFIER = '^(bemtevi|bentevi|helpdesk|helpedesk|veccio):'.freeze
  ENTITY = "COALESCE(contacts.additional_attributes->>'entity_type', '')".freeze

  def self.people(scope)
    scope.where("COALESCE(contacts.identifier, '') !~* ?", ORGANIZATION_IDENTIFIER)
      .where("#{ENTITY} = 'person' OR (#{ENTITY} = '' AND " \
             "COALESCE(contacts.additional_attributes->>'source_system', '') = '' AND " \
             "COALESCE(contacts.additional_attributes->>'source_id', '') = '' AND " \
             "COALESCE(contacts.identifier, '') !~* ?)", IMPORT_IDENTIFIER)
  end

  def self.reason(contact)
    attributes = contact.additional_attributes || {}
    entity = attributes['entity_type'].to_s
    return 'organization' if %w[company organization].include?(entity) || contact.identifier.to_s.match?(/\Abemtevi:customer:/i)
    return nil if entity == 'person'
    return 'import_review' if entity.present? || attributes['source_system'].present? || attributes['source_id'].present? ||
                              contact.identifier.to_s.match?(/\A(bemtevi|bentevi|helpdesk|helpedesk|veccio):/i)

    nil
  end
end
