# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_09_29_140200) do
  # These extensions should be enabled to support this database
  enable_extension "pg_stat_statements"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "plpgsql"
  enable_extension "vector"

  create_table "access_tokens", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "token"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["owner_type", "owner_id"], name: "index_access_tokens_on_owner_type_and_owner_id"
    t.index ["token"], name: "index_access_tokens_on_token", unique: true
  end

  create_table "account_saml_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "sso_url"
    t.text "certificate"
    t.string "sp_entity_id"
    t.string "idp_entity_id"
    t.json "role_mappings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_account_saml_settings_on_account_id"
  end

  create_table "account_users", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "user_id"
    t.integer "role", default: 0
    t.bigint "inviter_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "active_at", precision: nil
    t.integer "availability", default: 0, null: false
    t.boolean "auto_offline", default: true, null: false
    t.bigint "custom_role_id"
    t.bigint "agent_capacity_policy_id"
    t.boolean "crm_enabled", default: false, null: false
    t.boolean "jrc_projects_enabled", default: false, null: false
    t.index ["account_id", "id"], name: "jrc_sd_ref_account_users", unique: true
    t.index ["account_id", "user_id"], name: "uniq_user_id_per_account_id", unique: true
    t.index ["account_id"], name: "index_account_users_on_account_id"
    t.index ["agent_capacity_policy_id"], name: "index_account_users_on_agent_capacity_policy_id"
    t.index ["custom_role_id"], name: "index_account_users_on_custom_role_id"
    t.index ["user_id"], name: "index_account_users_on_user_id"
  end

  create_table "accounts", id: :serial, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "locale", default: 0
    t.string "domain", limit: 100
    t.string "support_email", limit: 100
    t.bigint "feature_flags", default: 0, null: false
    t.integer "auto_resolve_duration"
    t.jsonb "limits", default: {}
    t.jsonb "custom_attributes", default: {}
    t.integer "status", default: 0
    t.jsonb "internal_attributes", default: {}, null: false
    t.jsonb "settings", default: {}
    t.bigint "feature_flags_ext_1", default: 0, null: false
    t.index ["status"], name: "index_accounts_on_status"
  end

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", precision: nil, null: false
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_bot_inboxes", force: :cascade do |t|
    t.integer "inbox_id"
    t.integer "agent_bot_id"
    t.integer "status", default: 0
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "account_id"
  end

  create_table "agent_bots", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.string "outgoing_url"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "account_id"
    t.integer "bot_type", default: 0
    t.jsonb "bot_config", default: {}
    t.string "secret"
    t.index ["account_id"], name: "index_agent_bots_on_account_id"
  end

  create_table "agent_capacity_policies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.jsonb "exclusion_rules", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_agent_capacity_policies_on_account_id"
  end

  create_table "agent_sessions", force: :cascade do |t|
    t.integer "session_type", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.string "result_type"
    t.bigint "result_id"
    t.bigint "account_id", null: false
    t.bigint "assistant_id", null: false
    t.bigint "user_id"
    t.string "llm_model"
    t.float "credits_consumed"
    t.jsonb "faq_ids", default: []
    t.jsonb "document_ids", default: []
    t.jsonb "scenario_ids", default: []
    t.jsonb "run_context", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "result_type", "result_id"], name: "idx_on_account_id_result_type_result_id_ca66c00cd7"
    t.index ["account_id", "session_type", "created_at"], name: "idx_on_account_id_session_type_created_at_c20a14bd4e"
    t.index ["account_id", "subject_type", "subject_id"], name: "idx_on_account_id_subject_type_subject_id_6d60963b3d"
    t.index ["account_id"], name: "index_agent_sessions_on_account_id"
    t.index ["assistant_id"], name: "index_agent_sessions_on_assistant_id"
    t.index ["user_id"], name: "index_agent_sessions_on_user_id"
  end

  create_table "applied_slas", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "sla_policy_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sla_status", default: 0
    t.index ["account_id", "sla_policy_id", "conversation_id"], name: "index_applied_slas_on_account_sla_policy_conversation", unique: true
    t.index ["account_id"], name: "index_applied_slas_on_account_id"
    t.index ["conversation_id"], name: "index_applied_slas_on_conversation_id"
    t.index ["sla_policy_id"], name: "index_applied_slas_on_sla_policy_id"
  end

  create_table "article_embeddings", force: :cascade do |t|
    t.bigint "article_id", null: false
    t.text "term", null: false
    t.vector "embedding", limit: 1536
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_article_embeddings_on_embedding", using: :ivfflat
  end

  create_table "articles", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "portal_id", null: false
    t.integer "category_id"
    t.integer "folder_id"
    t.string "title"
    t.text "description"
    t.text "content"
    t.integer "status"
    t.integer "views"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "author_id"
    t.bigint "associated_article_id"
    t.jsonb "meta", default: {}
    t.string "slug", null: false
    t.integer "position"
    t.string "locale", default: "en", null: false
    t.string "draft_title"
    t.text "draft_content"
    t.index ["account_id"], name: "index_articles_on_account_id"
    t.index ["associated_article_id"], name: "index_articles_on_associated_article_id"
    t.index ["author_id"], name: "index_articles_on_author_id"
    t.index ["portal_id"], name: "index_articles_on_portal_id"
    t.index ["slug"], name: "index_articles_on_slug", unique: true
    t.index ["status"], name: "index_articles_on_status"
    t.index ["views"], name: "index_articles_on_views"
  end

  create_table "assignment_policies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.integer "assignment_order", default: 0, null: false
    t.integer "conversation_priority", default: 0, null: false
    t.integer "fair_distribution_limit", default: 100, null: false
    t.integer "fair_distribution_window", default: 3600, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "exclude_older_than_hours", default: 168
    t.index ["account_id", "name"], name: "index_assignment_policies_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_assignment_policies_on_account_id"
    t.index ["enabled"], name: "index_assignment_policies_on_enabled"
  end

  create_table "attachments", id: :serial, force: :cascade do |t|
    t.integer "file_type", default: 0
    t.string "external_url"
    t.float "coordinates_lat", default: 0.0
    t.float "coordinates_long", default: 0.0
    t.integer "message_id", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "fallback_title"
    t.string "extension"
    t.jsonb "meta", default: {}
    t.index ["account_id"], name: "index_attachments_on_account_id"
    t.index ["message_id"], name: "index_attachments_on_message_id"
  end

  create_table "audits", force: :cascade do |t|
    t.bigint "auditable_id"
    t.string "auditable_type"
    t.bigint "associated_id"
    t.string "associated_type"
    t.bigint "user_id"
    t.string "user_type"
    t.string "username"
    t.string "action"
    t.jsonb "audited_changes"
    t.integer "version", default: 0
    t.string "comment"
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "created_at", precision: nil
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "automation_rules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "event_name", null: false
    t.jsonb "conditions", default: "{}", null: false
    t.jsonb "actions", default: "{}", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "active", default: true, null: false
    t.index ["account_id"], name: "index_automation_rules_on_account_id"
  end

  create_table "calls", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "message_id"
    t.bigint "accepted_by_agent_id"
    t.string "provider_call_id", null: false
    t.integer "provider", default: 0, null: false
    t.integer "direction", null: false
    t.string "status", default: "ringing", null: false
    t.datetime "started_at"
    t.integer "duration_seconds"
    t.string "end_reason"
    t.jsonb "meta", default: {}
    t.text "transcript"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "contact_id"], name: "index_calls_on_account_id_and_contact_id"
    t.index ["account_id", "conversation_id"], name: "index_calls_on_account_id_and_conversation_id"
    t.index ["account_id", "created_at"], name: "index_calls_on_account_id_and_created_at"
    t.index ["message_id"], name: "index_calls_on_message_id"
    t.index ["provider", "provider_call_id"], name: "index_calls_on_provider_and_provider_call_id", unique: true
  end

  create_table "campaigns", force: :cascade do |t|
    t.integer "display_id", null: false
    t.string "title", null: false
    t.text "description"
    t.text "message", null: false
    t.integer "sender_id"
    t.boolean "enabled", default: true
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.jsonb "trigger_rules", default: {}
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "campaign_type", default: 0, null: false
    t.integer "campaign_status", default: 0, null: false
    t.jsonb "audience", default: []
    t.datetime "scheduled_at", precision: nil
    t.boolean "trigger_only_during_business_hours", default: false
    t.jsonb "template_params"
    t.index ["account_id"], name: "index_campaigns_on_account_id"
    t.index ["campaign_status"], name: "index_campaigns_on_campaign_status"
    t.index ["campaign_type"], name: "index_campaigns_on_campaign_type"
    t.index ["inbox_id"], name: "index_campaigns_on_inbox_id"
    t.index ["scheduled_at"], name: "index_campaigns_on_scheduled_at"
  end

  create_table "canned_responses", id: :serial, force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "short_code"
    t.text "content"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "captain_assistant_responses", force: :cascade do |t|
    t.string "question", null: false
    t.text "answer", null: false
    t.vector "embedding", limit: 1536
    t.bigint "assistant_id", null: false
    t.bigint "documentable_id"
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 1, null: false
    t.string "documentable_type"
    t.boolean "edited", default: false, null: false
    t.index ["account_id"], name: "index_captain_assistant_responses_on_account_id"
    t.index ["assistant_id"], name: "index_captain_assistant_responses_on_assistant_id"
    t.index ["documentable_id", "documentable_type"], name: "idx_cap_asst_resp_on_documentable"
    t.index ["embedding"], name: "vector_idx_knowledge_entries_embedding", using: :ivfflat
    t.index ["status"], name: "index_captain_assistant_responses_on_status"
  end

  create_table "captain_assistants", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "account_id", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "config", default: {}, null: false
    t.jsonb "response_guidelines", default: []
    t.jsonb "guardrails", default: []
    t.index ["account_id"], name: "index_captain_assistants_on_account_id"
  end

  create_table "captain_custom_tools", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.text "description"
    t.string "http_method", default: "GET", null: false
    t.text "endpoint_url", null: false
    t.text "request_template"
    t.text "response_template"
    t.string "auth_type", default: "none"
    t.jsonb "auth_config", default: {}
    t.jsonb "param_schema", default: []
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "slug"], name: "index_captain_custom_tools_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_captain_custom_tools_on_account_id"
  end

  create_table "captain_documents", force: :cascade do |t|
    t.string "name"
    t.text "external_link", null: false
    t.text "content"
    t.bigint "assistant_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "metadata", default: {}
    t.integer "sync_status"
    t.datetime "last_synced_at"
    t.datetime "last_sync_attempted_at"
    t.index "assistant_id, md5(external_link)", name: "idx_captain_documents_on_assistant_id_and_external_link_md5", unique: true
    t.index ["account_id", "assistant_id", "sync_status", "last_synced_at"], name: "idx_captain_documents_on_account_assistant_sync_stats"
    t.index ["account_id", "sync_status"], name: "index_captain_documents_on_account_id_and_sync_status"
    t.index ["account_id"], name: "index_captain_documents_on_account_id"
    t.index ["assistant_id"], name: "index_captain_documents_on_assistant_id"
    t.index ["status"], name: "index_captain_documents_on_status"
  end

  create_table "captain_faq_observations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "faq_suggestion_id"
    t.string "generated_question", null: false
    t.text "generated_answer", null: false
    t.string "language", default: "en", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_captain_faq_observations_on_account_id"
    t.index ["conversation_id", "faq_suggestion_id"], name: "idx_captain_faq_observations_on_conversation_and_suggestion", unique: true, where: "(faq_suggestion_id IS NOT NULL)"
    t.index ["conversation_id"], name: "index_captain_faq_observations_on_conversation_id"
    t.index ["faq_suggestion_id"], name: "index_captain_faq_observations_on_faq_suggestion_id"
  end

  create_table "captain_faq_suggestions", force: :cascade do |t|
    t.string "question", null: false
    t.text "answer", null: false
    t.vector "embedding", limit: 1536
    t.bigint "assistant_id", null: false
    t.bigint "account_id", null: false
    t.string "language", default: "en", null: false
    t.integer "source_count", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "assistant_id", "status", "language"], name: "idx_cap_faq_suggestions_on_account_assistant_status_language"
    t.index ["account_id"], name: "index_captain_faq_suggestions_on_account_id"
    t.index ["assistant_id"], name: "index_captain_faq_suggestions_on_assistant_id"
    t.index ["embedding"], name: "vector_idx_captain_faq_suggestions_embedding", opclass: :vector_cosine_ops, using: :ivfflat
  end

  create_table "captain_inboxes", force: :cascade do |t|
    t.bigint "captain_assistant_id", null: false
    t.bigint "inbox_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["captain_assistant_id", "inbox_id"], name: "index_captain_inboxes_on_captain_assistant_id_and_inbox_id", unique: true
    t.index ["captain_assistant_id"], name: "index_captain_inboxes_on_captain_assistant_id"
    t.index ["inbox_id"], name: "index_captain_inboxes_on_inbox_id"
  end

  create_table "captain_message_reports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "message_id", null: false
    t.bigint "user_id", null: false
    t.string "report_reason", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_captain_message_reports_on_account_id"
    t.index ["conversation_id"], name: "index_captain_message_reports_on_conversation_id"
    t.index ["message_id"], name: "index_captain_message_reports_on_message_id"
    t.index ["user_id"], name: "index_captain_message_reports_on_user_id"
  end

  create_table "captain_scenarios", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.text "instruction"
    t.jsonb "tools", default: []
    t.boolean "enabled", default: true, null: false
    t.bigint "assistant_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_captain_scenarios_on_account_id"
    t.index ["assistant_id", "enabled"], name: "index_captain_scenarios_on_assistant_id_and_enabled"
    t.index ["assistant_id"], name: "index_captain_scenarios_on_assistant_id"
    t.index ["enabled"], name: "index_captain_scenarios_on_enabled"
  end

  create_table "categories", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "portal_id", null: false
    t.string "name"
    t.text "description"
    t.integer "position"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "locale", default: "en"
    t.string "slug", null: false
    t.bigint "parent_category_id"
    t.bigint "associated_category_id"
    t.string "icon", default: ""
    t.string "icon_color", default: ""
    t.index ["associated_category_id"], name: "index_categories_on_associated_category_id"
    t.index ["locale", "account_id"], name: "index_categories_on_locale_and_account_id"
    t.index ["locale"], name: "index_categories_on_locale"
    t.index ["parent_category_id"], name: "index_categories_on_parent_category_id"
    t.index ["slug", "locale", "portal_id"], name: "index_categories_on_slug_and_locale_and_portal_id", unique: true
  end

  create_table "channel_api", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "webhook_url"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "identifier"
    t.string "hmac_token"
    t.boolean "hmac_mandatory", default: false
    t.jsonb "additional_attributes", default: {}
    t.string "secret"
    t.index ["hmac_token"], name: "index_channel_api_on_hmac_token", unique: true
    t.index ["identifier"], name: "index_channel_api_on_identifier", unique: true
  end

  create_table "channel_email", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "email", null: false
    t.string "forward_to_email", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "imap_enabled", default: false
    t.string "imap_address", default: ""
    t.integer "imap_port", default: 0
    t.string "imap_login", default: ""
    t.string "imap_password", default: ""
    t.boolean "imap_enable_ssl", default: true
    t.boolean "smtp_enabled", default: false
    t.string "smtp_address", default: ""
    t.integer "smtp_port", default: 0
    t.string "smtp_login", default: ""
    t.string "smtp_password", default: ""
    t.string "smtp_domain", default: ""
    t.boolean "smtp_enable_starttls_auto", default: true
    t.string "smtp_authentication", default: "login"
    t.string "smtp_openssl_verify_mode", default: "none"
    t.boolean "smtp_enable_ssl_tls", default: false
    t.jsonb "provider_config", default: {}
    t.string "provider"
    t.boolean "verified_for_sending", default: false, null: false
    t.string "imap_authentication", default: "plain"
    t.index ["email"], name: "index_channel_email_on_email", unique: true
    t.index ["forward_to_email"], name: "index_channel_email_on_forward_to_email", unique: true
  end

  create_table "channel_facebook_pages", id: :serial, force: :cascade do |t|
    t.string "page_id", null: false
    t.string "user_access_token", null: false
    t.string "page_access_token", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "instagram_id"
    t.index ["page_id", "account_id"], name: "index_channel_facebook_pages_on_page_id_and_account_id", unique: true
    t.index ["page_id"], name: "index_channel_facebook_pages_on_page_id"
  end

  create_table "channel_instagram", force: :cascade do |t|
    t.string "access_token", null: false
    t.datetime "expires_at", null: false
    t.integer "account_id", null: false
    t.string "instagram_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instagram_id"], name: "index_channel_instagram_on_instagram_id", unique: true
  end

  create_table "channel_line", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "line_channel_id", null: false
    t.string "line_channel_secret", null: false
    t.string "line_channel_token", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["line_channel_id"], name: "index_channel_line_on_line_channel_id", unique: true
  end

  create_table "channel_sms", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "phone_number", null: false
    t.string "provider", default: "default"
    t.jsonb "provider_config", default: {}
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["phone_number"], name: "index_channel_sms_on_phone_number", unique: true
  end

  create_table "channel_telegram", force: :cascade do |t|
    t.string "bot_name"
    t.integer "account_id", null: false
    t.string "bot_token", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["bot_token"], name: "index_channel_telegram_on_bot_token", unique: true
  end

  create_table "channel_tiktok", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "business_id", null: false
    t.string "access_token", null: false
    t.datetime "expires_at", null: false
    t.string "refresh_token", null: false
    t.datetime "refresh_token_expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_channel_tiktok_on_business_id", unique: true
  end

  create_table "channel_twilio_sms", force: :cascade do |t|
    t.string "phone_number"
    t.string "auth_token", null: false
    t.string "account_sid", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "medium", default: 0
    t.string "messaging_service_sid"
    t.string "api_key_sid"
    t.jsonb "content_templates", default: {}
    t.datetime "content_templates_last_updated"
    t.boolean "voice_enabled", default: false, null: false
    t.string "twiml_app_sid"
    t.string "api_key_secret"
    t.jsonb "provider_config", default: {}
    t.index ["account_sid", "phone_number"], name: "index_channel_twilio_sms_on_account_sid_and_phone_number", unique: true
    t.index ["messaging_service_sid"], name: "index_channel_twilio_sms_on_messaging_service_sid", unique: true
    t.index ["phone_number"], name: "index_channel_twilio_sms_on_phone_number", unique: true
  end

  create_table "channel_twitter_profiles", force: :cascade do |t|
    t.string "profile_id", null: false
    t.string "twitter_access_token", null: false
    t.string "twitter_access_token_secret", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "tweets_enabled", default: true
    t.index ["account_id", "profile_id"], name: "index_channel_twitter_profiles_on_account_id_and_profile_id", unique: true
  end

  create_table "channel_web_widgets", id: :serial, force: :cascade do |t|
    t.string "website_url"
    t.integer "account_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "website_token"
    t.string "widget_color", default: "#1f93ff"
    t.string "welcome_title"
    t.string "welcome_tagline"
    t.integer "feature_flags", default: 7, null: false
    t.integer "reply_time", default: 0
    t.string "hmac_token"
    t.boolean "pre_chat_form_enabled", default: false
    t.jsonb "pre_chat_form_options", default: {}
    t.boolean "hmac_mandatory", default: false
    t.boolean "continuity_via_email", default: true, null: false
    t.text "allowed_domains", default: ""
    t.index ["hmac_token"], name: "index_channel_web_widgets_on_hmac_token", unique: true
    t.index ["website_token"], name: "index_channel_web_widgets_on_website_token", unique: true
  end

  create_table "channel_whatsapp", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "phone_number", null: false
    t.string "provider", default: "default"
    t.jsonb "provider_config", default: {}
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.jsonb "message_templates", default: {}
    t.datetime "message_templates_last_updated", precision: nil
    t.jsonb "phone_number_health", default: {}, null: false
    t.datetime "phone_number_health_checked_at"
    t.string "phone_number_health_error", limit: 500
    t.index ["phone_number"], name: "index_channel_whatsapp_on_phone_number", unique: true
    t.index ["phone_number_health_checked_at"], name: "index_channel_whatsapp_on_phone_number_health_checked_at"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "domain"
    t.text "description"
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "contacts_count", default: 0, null: false
    t.jsonb "additional_attributes", default: {}
    t.jsonb "custom_attributes", default: {}
    t.datetime "last_activity_at", precision: nil
    t.index ["account_id", "domain"], name: "index_companies_on_account_and_domain", unique: true, where: "(domain IS NOT NULL)"
    t.index ["account_id"], name: "index_companies_on_account_id"
    t.index ["name", "account_id"], name: "index_companies_on_name_and_account_id"
  end

  create_table "contact_inboxes", force: :cascade do |t|
    t.bigint "contact_id"
    t.bigint "inbox_id"
    t.text "source_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "hmac_verified", default: false
    t.string "pubsub_token"
    t.index ["contact_id"], name: "index_contact_inboxes_on_contact_id"
    t.index ["inbox_id", "source_id"], name: "index_contact_inboxes_on_inbox_id_and_source_id", unique: true
    t.index ["inbox_id"], name: "index_contact_inboxes_on_inbox_id"
    t.index ["pubsub_token"], name: "index_contact_inboxes_on_pubsub_token", unique: true
    t.index ["source_id"], name: "index_contact_inboxes_on_source_id"
  end

  create_table "contacts", id: :serial, force: :cascade do |t|
    t.string "name", default: ""
    t.string "email"
    t.string "phone_number"
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.jsonb "additional_attributes", default: {}
    t.string "identifier"
    t.jsonb "custom_attributes", default: {}
    t.datetime "last_activity_at", precision: nil
    t.integer "contact_type", default: 0
    t.string "middle_name", default: ""
    t.string "last_name", default: ""
    t.string "location", default: ""
    t.string "country_code", default: ""
    t.boolean "blocked", default: false, null: false
    t.bigint "company_id"
    t.index "lower((email)::text), account_id", name: "index_contacts_on_lower_email_account_id"
    t.index ["account_id", "contact_type"], name: "index_contacts_on_account_id_and_contact_type"
    t.index ["account_id", "email", "phone_number", "identifier"], name: "index_contacts_on_nonempty_fields", where: "(((email)::text <> ''::text) OR ((phone_number)::text <> ''::text) OR ((identifier)::text <> ''::text))"
    t.index ["account_id", "id"], name: "jrc_sd_ref_contacts", unique: true
    t.index ["account_id", "last_activity_at"], name: "index_contacts_on_account_id_and_last_activity_at", order: { last_activity_at: "DESC NULLS LAST" }
    t.index ["account_id"], name: "index_contacts_on_account_id"
    t.index ["account_id"], name: "index_resolved_contact_account_id", where: "(((email)::text <> ''::text) OR ((phone_number)::text <> ''::text) OR ((identifier)::text <> ''::text))"
    t.index ["blocked"], name: "index_contacts_on_blocked"
    t.index ["company_id"], name: "index_contacts_on_company_id"
    t.index ["email", "account_id"], name: "uniq_email_per_account_contact", unique: true
    t.index ["identifier", "account_id"], name: "uniq_identifier_per_account_contact", unique: true
    t.index ["name", "email", "phone_number", "identifier"], name: "index_contacts_on_name_email_phone_number_identifier", opclass: :gin_trgm_ops, using: :gin
    t.index ["phone_number", "account_id"], name: "index_contacts_on_phone_number_and_account_id"
  end

  create_table "conversation_participants", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["account_id"], name: "index_conversation_participants_on_account_id"
    t.index ["conversation_id"], name: "index_conversation_participants_on_conversation_id"
    t.index ["user_id", "conversation_id"], name: "index_conversation_participants_on_user_id_and_conversation_id", unique: true
    t.index ["user_id"], name: "index_conversation_participants_on_user_id"
  end

  create_table "conversations", id: :serial, force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "inbox_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "assignee_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "contact_id"
    t.integer "display_id", null: false
    t.datetime "contact_last_seen_at", precision: nil
    t.datetime "agent_last_seen_at", precision: nil
    t.jsonb "additional_attributes", default: {}
    t.bigint "contact_inbox_id"
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.string "identifier"
    t.datetime "last_activity_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "team_id"
    t.bigint "campaign_id"
    t.datetime "snoozed_until", precision: nil
    t.jsonb "custom_attributes", default: {}
    t.datetime "assignee_last_seen_at", precision: nil
    t.datetime "first_reply_created_at", precision: nil
    t.integer "priority"
    t.bigint "sla_policy_id"
    t.datetime "waiting_since"
    t.text "cached_label_list"
    t.bigint "assignee_agent_bot_id"
    t.index ["account_id", "display_id"], name: "index_conversations_on_account_id_and_display_id", unique: true
    t.index ["account_id", "id"], name: "index_conversations_on_id_and_account_id"
    t.index ["account_id", "id"], name: "jrc_sd_ref_conversations", unique: true
    t.index ["account_id", "inbox_id", "status", "assignee_id"], name: "conv_acid_inbid_stat_asgnid_idx"
    t.index ["account_id"], name: "index_conversations_on_account_id"
    t.index ["assignee_id", "account_id"], name: "index_conversations_on_assignee_id_and_account_id"
    t.index ["campaign_id"], name: "index_conversations_on_campaign_id"
    t.index ["contact_id"], name: "index_conversations_on_contact_id"
    t.index ["contact_inbox_id"], name: "index_conversations_on_contact_inbox_id"
    t.index ["first_reply_created_at"], name: "index_conversations_on_first_reply_created_at"
    t.index ["identifier", "account_id"], name: "index_conversations_on_identifier_and_account_id"
    t.index ["inbox_id"], name: "index_conversations_on_inbox_id"
    t.index ["priority"], name: "index_conversations_on_priority"
    t.index ["status", "account_id"], name: "index_conversations_on_status_and_account_id"
    t.index ["status", "priority"], name: "index_conversations_on_status_and_priority"
    t.index ["team_id"], name: "index_conversations_on_team_id"
    t.index ["uuid"], name: "index_conversations_on_uuid", unique: true
    t.index ["waiting_since"], name: "index_conversations_on_waiting_since"
  end

  create_table "copilot_messages", force: :cascade do |t|
    t.bigint "copilot_thread_id", null: false
    t.bigint "account_id", null: false
    t.jsonb "message", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "message_type", default: 0
    t.index ["account_id"], name: "index_copilot_messages_on_account_id"
    t.index ["copilot_thread_id"], name: "index_copilot_messages_on_copilot_thread_id"
  end

  create_table "copilot_threads", force: :cascade do |t|
    t.string "title", null: false
    t.bigint "user_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "assistant_id"
    t.index ["account_id"], name: "index_copilot_threads_on_account_id"
    t.index ["assistant_id"], name: "index_copilot_threads_on_assistant_id"
    t.index ["user_id"], name: "index_copilot_threads_on_user_id"
  end

  create_table "csat_survey_responses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "message_id", null: false
    t.integer "rating", null: false
    t.text "feedback_message"
    t.bigint "contact_id", null: false
    t.bigint "assigned_agent_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "csat_review_notes"
    t.datetime "review_notes_updated_at"
    t.bigint "review_notes_updated_by_id"
    t.index ["account_id"], name: "index_csat_survey_responses_on_account_id"
    t.index ["assigned_agent_id"], name: "index_csat_survey_responses_on_assigned_agent_id"
    t.index ["contact_id"], name: "index_csat_survey_responses_on_contact_id"
    t.index ["conversation_id"], name: "index_csat_survey_responses_on_conversation_id"
    t.index ["message_id"], name: "index_csat_survey_responses_on_message_id", unique: true
    t.index ["review_notes_updated_by_id"], name: "index_csat_survey_responses_on_review_notes_updated_by_id"
  end

  create_table "custom_attribute_definitions", force: :cascade do |t|
    t.string "attribute_display_name"
    t.string "attribute_key"
    t.integer "attribute_display_type", default: 0
    t.integer "default_value"
    t.integer "attribute_model", default: 0
    t.bigint "account_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "attribute_description"
    t.jsonb "attribute_values", default: []
    t.string "regex_pattern"
    t.string "regex_cue"
    t.index ["account_id"], name: "index_custom_attribute_definitions_on_account_id"
    t.index ["attribute_key", "attribute_model", "account_id"], name: "attribute_key_model_index", unique: true
  end

  create_table "custom_filters", force: :cascade do |t|
    t.string "name", null: false
    t.integer "filter_type", default: 0, null: false
    t.jsonb "query", default: "{}", null: false
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["account_id"], name: "index_custom_filters_on_account_id"
    t.index ["user_id"], name: "index_custom_filters_on_user_id"
  end

  create_table "custom_roles", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.bigint "account_id", null: false
    t.text "permissions", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_custom_roles_on_account_id"
  end

  create_table "dashboard_apps", force: :cascade do |t|
    t.string "title", null: false
    t.jsonb "content", default: []
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["account_id"], name: "index_dashboard_apps_on_account_id"
    t.index ["user_id"], name: "index_dashboard_apps_on_user_id"
  end

  create_table "data_import_errors", force: :cascade do |t|
    t.bigint "data_import_id", null: false
    t.bigint "data_import_item_id"
    t.string "source_object_type"
    t.string "source_object_id"
    t.string "error_code", null: false
    t.text "message"
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["data_import_id"], name: "index_data_import_errors_on_data_import_id"
    t.index ["data_import_item_id"], name: "index_data_import_errors_on_data_import_item_id"
    t.index ["source_object_type", "source_object_id"], name: "idx_data_import_errors_on_source"
  end

  create_table "data_import_items", force: :cascade do |t|
    t.bigint "data_import_id", null: false
    t.string "source_provider", null: false
    t.string "source_object_type", null: false
    t.string "source_object_id", null: false
    t.integer "status", default: 0, null: false
    t.string "chatwoot_record_type"
    t.bigint "chatwoot_record_id"
    t.integer "attempt_count", default: 0, null: false
    t.string "last_error_code"
    t.text "last_error_message"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chatwoot_record_type", "chatwoot_record_id"], name: "idx_data_import_items_on_record"
    t.index ["data_import_id", "source_object_type", "source_object_id"], name: "idx_data_import_items_on_import_and_source", unique: true
    t.index ["data_import_id"], name: "index_data_import_items_on_data_import_id"
    t.index ["source_provider", "source_object_type", "source_object_id"], name: "idx_data_import_items_on_source"
  end

  create_table "data_import_mappings", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "data_import_id", null: false
    t.string "source_provider", null: false
    t.string "source_object_type", null: false
    t.string "source_object_id", null: false
    t.string "chatwoot_record_type", null: false
    t.bigint "chatwoot_record_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "source_provider", "source_object_type", "source_object_id"], name: "idx_data_import_mappings_on_account_and_source", unique: true
    t.index ["chatwoot_record_type", "chatwoot_record_id"], name: "idx_data_import_mappings_on_record"
    t.index ["data_import_id"], name: "index_data_import_mappings_on_data_import_id"
  end

  create_table "data_imports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "data_type", null: false
    t.integer "status", default: 0, null: false
    t.text "processing_errors"
    t.integer "total_records"
    t.integer "processed_records"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "name"
    t.string "source_type"
    t.string "source_provider"
    t.jsonb "import_types", default: [], null: false
    t.integer "initiated_by_id"
    t.text "access_token"
    t.jsonb "source_metadata", default: {}, null: false
    t.jsonb "stats", default: {}, null: false
    t.jsonb "cursor", default: {}, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "abandoned_at"
    t.datetime "last_error_at"
    t.index ["account_id"], name: "index_data_imports_on_account_id"
    t.index ["initiated_by_id"], name: "index_data_imports_on_initiated_by_id"
    t.index ["source_provider"], name: "index_data_imports_on_source_provider"
  end

  create_table "email_templates", force: :cascade do |t|
    t.string "name", null: false
    t.text "body", null: false
    t.integer "account_id"
    t.integer "template_type", default: 1
    t.integer "locale", default: 0, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "inbox_id"
    t.index ["account_id", "name", "template_type", "locale"], name: "index_email_templates_on_account_scope", unique: true, where: "((account_id IS NOT NULL) AND (inbox_id IS NULL))"
    t.index ["inbox_id", "name", "template_type", "locale"], name: "index_email_templates_on_inbox_scope", unique: true, where: "(inbox_id IS NOT NULL)"
    t.index ["inbox_id"], name: "index_email_templates_on_inbox_id"
    t.index ["name", "template_type", "locale"], name: "index_email_templates_on_installation_scope", unique: true, where: "((account_id IS NULL) AND (inbox_id IS NULL))"
  end

  create_table "folders", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "category_id", null: false
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "inbox_assignment_policies", force: :cascade do |t|
    t.bigint "inbox_id", null: false
    t.bigint "assignment_policy_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assignment_policy_id"], name: "index_inbox_assignment_policies_on_assignment_policy_id"
    t.index ["inbox_id"], name: "index_inbox_assignment_policies_on_inbox_id", unique: true
  end

  create_table "inbox_capacity_limits", force: :cascade do |t|
    t.bigint "agent_capacity_policy_id", null: false
    t.bigint "inbox_id", null: false
    t.integer "conversation_limit", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_capacity_policy_id", "inbox_id"], name: "idx_on_agent_capacity_policy_id_inbox_id_71c7ec4caf", unique: true
    t.index ["agent_capacity_policy_id"], name: "index_inbox_capacity_limits_on_agent_capacity_policy_id"
    t.index ["inbox_id"], name: "index_inbox_capacity_limits_on_inbox_id"
  end

  create_table "inbox_members", id: :serial, force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "inbox_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["inbox_id", "user_id"], name: "index_inbox_members_on_inbox_id_and_user_id", unique: true
    t.index ["inbox_id"], name: "index_inbox_members_on_inbox_id"
  end

  create_table "inboxes", id: :serial, force: :cascade do |t|
    t.integer "channel_id", null: false
    t.integer "account_id", null: false
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "channel_type"
    t.boolean "enable_auto_assignment", default: true
    t.boolean "greeting_enabled", default: false
    t.string "greeting_message"
    t.string "email_address"
    t.boolean "working_hours_enabled", default: false
    t.string "out_of_office_message"
    t.string "timezone", default: "UTC"
    t.boolean "enable_email_collect", default: true
    t.boolean "csat_survey_enabled", default: false
    t.boolean "allow_messages_after_resolved", default: true
    t.jsonb "auto_assignment_config", default: {}
    t.boolean "lock_to_single_conversation", default: false, null: false
    t.bigint "portal_id"
    t.integer "sender_name_type", default: 0, null: false
    t.string "business_name"
    t.jsonb "csat_config", default: {}, null: false
    t.index ["account_id", "id"], name: "jrc_broker_inbox_tenant_unique", unique: true
    t.index ["account_id"], name: "index_inboxes_on_account_id"
    t.index ["channel_id", "channel_type"], name: "index_inboxes_on_channel_id_and_channel_type"
    t.index ["portal_id"], name: "index_inboxes_on_portal_id"
  end

  create_table "installation_configs", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "serialized_value", default: {}, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "locked", default: true, null: false
    t.index ["name", "created_at"], name: "index_installation_configs_on_name_and_created_at", unique: true
    t.index ["name"], name: "index_installation_configs_on_name", unique: true
  end

  create_table "integrations_hooks", force: :cascade do |t|
    t.integer "status", default: 1
    t.integer "inbox_id"
    t.integer "account_id"
    t.string "app_id"
    t.integer "hook_type", default: 0
    t.string "reference_id"
    t.string "access_token"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.jsonb "settings", default: {}
  end

  create_table "jrc_ai_providers", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "created_by_id"
    t.string "provider_type", null: false
    t.string "name", null: false
    t.text "api_key"
    t.string "base_url"
    t.string "default_model"
    t.string "fast_model"
    t.string "advanced_model"
    t.bigint "monthly_token_limit"
    t.bigint "monthly_budget_cents"
    t.boolean "active", default: true, null: false
    t.boolean "default_provider", default: false, null: false
    t.string "status", default: "not_validated", null: false
    t.datetime "last_validated_at"
    t.text "last_error"
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_jrc_ai_providers_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "idx_jrc_ai_one_default_provider_per_account", unique: true, where: "(default_provider = true)"
    t.index ["account_id"], name: "index_jrc_ai_providers_on_account_id"
    t.index ["created_by_id"], name: "index_jrc_ai_providers_on_created_by_id"
  end

  create_table "jrc_ai_usage_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "provider_id"
    t.bigint "user_id"
    t.string "agent_key", default: "copilot", null: false
    t.string "feature", default: "assistant", null: false
    t.string "model"
    t.bigint "input_tokens", default: 0, null: false
    t.bigint "output_tokens", default: 0, null: false
    t.bigint "total_tokens", default: 0, null: false
    t.bigint "estimated_cost_cents", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "agent_key", "created_at"], name: "idx_jrc_ai_usage_by_agent"
    t.index ["account_id", "created_at"], name: "index_jrc_ai_usage_events_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_jrc_ai_usage_events_on_account_id"
    t.index ["provider_id"], name: "index_jrc_ai_usage_events_on_provider_id"
    t.index ["user_id"], name: "index_jrc_ai_usage_events_on_user_id"
  end

  create_table "jrc_broker_inbox_bindings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.uuid "integration_id", null: false
    t.uuid "instance_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "inbox_id"], name: "jrc_broker_binding_tenant_unique", unique: true
    t.index ["account_id", "integration_id"], name: "jrc_broker_connection_unique", unique: true
    t.index ["inbox_id"], name: "index_jrc_broker_inbox_bindings_on_inbox_id", unique: true
  end

  create_table "jrc_broker_inbox_grants", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.bigint "user_id", null: false
    t.boolean "can_pair", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "inbox_id", "user_id"], name: "jrc_broker_grant_unique", unique: true
  end

  create_table "jrc_broker_integrations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "broker_origin", null: false
    t.uuid "organization_id", null: false
    t.integer "destination_revision", null: false
    t.text "encrypted_control_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_broker_integrations_on_account_id", unique: true
    t.index ["broker_origin", "organization_id"], name: "jrc_broker_remote_org_unique", unique: true
    t.check_constraint "destination_revision > 0", name: "jrc_broker_revision_positive"
  end

  create_table "jrc_campaign_blacklists", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "created_by_id"
    t.string "phone_number", null: false
    t.string "reason"
    t.string "source", default: "manual", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "phone_number"], name: "index_jrc_campaign_blacklists_on_account_id_and_phone_number", unique: true
    t.index ["account_id"], name: "index_jrc_campaign_blacklists_on_account_id"
    t.index ["created_by_id"], name: "index_jrc_campaign_blacklists_on_created_by_id"
  end

  create_table "jrc_campaign_consents", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "recorded_by_id", null: false
    t.string "phone_number", null: false
    t.text "evidence", null: false
    t.datetime "granted_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "phone_number"], name: "index_jrc_campaign_consents_active_phone", unique: true, where: "(revoked_at IS NULL)"
    t.index ["account_id"], name: "index_jrc_campaign_consents_on_account_id"
    t.index ["recorded_by_id"], name: "index_jrc_campaign_consents_on_recorded_by_id"
  end

  create_table "jrc_campaign_deliveries", force: :cascade do |t|
    t.bigint "recipient_id", null: false
    t.bigint "step_id", null: false
    t.integer "inbox_id", null: false
    t.string "external_id"
    t.string "status", default: "queued", null: false
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "read_at"
    t.datetime "failed_at"
    t.text "error_message"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_jrc_campaign_deliveries_on_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["inbox_id"], name: "index_jrc_campaign_deliveries_on_inbox_id"
    t.index ["recipient_id", "step_id"], name: "index_jrc_campaign_deliveries_on_recipient_id_and_step_id", unique: true
    t.index ["recipient_id"], name: "index_jrc_campaign_deliveries_on_recipient_id"
    t.index ["step_id"], name: "index_jrc_campaign_deliveries_on_step_id"
  end

  create_table "jrc_campaign_events", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "execution_id"
    t.bigint "recipient_id"
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "event_type"], name: "index_jrc_campaign_events_on_campaign_id_and_event_type"
    t.index ["campaign_id"], name: "index_jrc_campaign_events_on_campaign_id"
    t.index ["execution_id"], name: "index_jrc_campaign_events_on_execution_id"
    t.index ["recipient_id"], name: "index_jrc_campaign_events_on_recipient_id"
  end

  create_table "jrc_campaign_executions", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.integer "run_number", default: 1, null: false
    t.string "status", default: "queued", null: false
    t.integer "total_count", default: 0, null: false
    t.integer "sent_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.integer "delivered_count", default: 0, null: false
    t.integer "read_count", default: 0, null: false
    t.integer "replied_count", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "run_number"], name: "index_jrc_campaign_executions_on_campaign_id_and_run_number", unique: true
    t.index ["campaign_id"], name: "index_jrc_campaign_executions_on_campaign_id"
  end

  create_table "jrc_campaign_inboxes", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.integer "inbox_id", null: false
    t.integer "position", default: 0, null: false
    t.integer "weight", default: 1, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "inbox_id"], name: "index_jrc_campaign_inboxes_on_campaign_id_and_inbox_id", unique: true
    t.index ["campaign_id"], name: "index_jrc_campaign_inboxes_on_campaign_id"
    t.index ["inbox_id"], name: "index_jrc_campaign_inboxes_on_inbox_id"
  end

  create_table "jrc_campaign_media_assets", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "created_by_id"
    t.string "kind"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_campaign_media_assets_on_account_id"
    t.index ["created_by_id"], name: "index_jrc_campaign_media_assets_on_created_by_id"
  end

  create_table "jrc_campaign_recipients", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "execution_id", null: false
    t.integer "contact_id"
    t.integer "inbox_id"
    t.integer "conversation_id"
    t.string "name"
    t.string "phone_number", null: false
    t.string "source", default: "contact", null: false
    t.string "status", default: "queued", null: false
    t.datetime "scheduled_at"
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "read_at"
    t.datetime "replied_at"
    t.datetime "failed_at"
    t.text "error_message"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "phone_number"], name: "index_jrc_campaign_recipients_on_campaign_id_and_phone_number"
    t.index ["campaign_id"], name: "index_jrc_campaign_recipients_on_campaign_id"
    t.index ["contact_id"], name: "index_jrc_campaign_recipients_on_contact_id"
    t.index ["conversation_id"], name: "index_jrc_campaign_recipients_on_conversation_id"
    t.index ["execution_id", "phone_number"], name: "index_jrc_campaign_recipients_on_execution_id_and_phone_number", unique: true
    t.index ["execution_id", "status"], name: "index_jrc_campaign_recipients_on_execution_id_and_status"
    t.index ["execution_id"], name: "index_jrc_campaign_recipients_on_execution_id"
    t.index ["inbox_id"], name: "index_jrc_campaign_recipients_on_inbox_id"
  end

  create_table "jrc_campaign_sanitized_entries", force: :cascade do |t|
    t.bigint "sanitized_list_id", null: false
    t.string "name"
    t.string "phone_number"
    t.string "normalized_phone"
    t.string "status", default: "valid", null: false
    t.string "reason"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sanitized_list_id", "normalized_phone"], name: "idx_on_sanitized_list_id_normalized_phone_b94ac446e9"
    t.index ["sanitized_list_id", "status"], name: "idx_on_sanitized_list_id_status_b19511a848"
    t.index ["sanitized_list_id"], name: "index_jrc_campaign_sanitized_entries_on_sanitized_list_id"
  end

  create_table "jrc_campaign_sanitized_lists", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "created_by_id"
    t.string "name", null: false
    t.jsonb "stats", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_campaign_sanitized_lists_on_account_id"
    t.index ["created_by_id"], name: "index_jrc_campaign_sanitized_lists_on_created_by_id"
  end

  create_table "jrc_campaign_steps", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.integer "position", default: 0, null: false
    t.string "kind", default: "text", null: false
    t.text "body", default: "", null: false
    t.string "media_url"
    t.string "file_name"
    t.string "template_name"
    t.string "template_namespace"
    t.string "template_language"
    t.jsonb "template_params", default: {}, null: false
    t.jsonb "inbox_overrides", default: {}, null: false
    t.integer "delay_after_seconds", default: 0, null: false
    t.boolean "only_if_no_reply", default: false, null: false
    t.integer "follow_up_after_hours"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "position"], name: "index_jrc_campaign_steps_on_campaign_id_and_position"
    t.index ["campaign_id"], name: "index_jrc_campaign_steps_on_campaign_id"
  end

  create_table "jrc_campaigns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id"
    t.bigint "created_by_id"
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.string "trigger_type", default: "manual", null: false
    t.datetime "scheduled_at"
    t.string "audience_type", default: "all_contacts", null: false
    t.jsonb "audience_config", default: {}, null: false
    t.text "message_body", default: "", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "started_at"
    t.datetime "paused_at"
    t.datetime "completed_at"
    t.integer "estimated_recipients", default: 0, null: false
    t.integer "sent_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.integer "replied_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "rotation_mode", default: "round_robin", null: false
    t.integer "delay_min_seconds", default: 5, null: false
    t.integer "delay_max_seconds", default: 20, null: false
    t.jsonb "sending_window", default: {"end" => "18:00", "days" => [1, 2, 3, 4, 5], "start" => "08:00"}, null: false
    t.string "conversation_mode", default: "reply_only", null: false
    t.jsonb "recurrence_config", default: {}, null: false
    t.jsonb "follow_up_config", default: {}, null: false
    t.integer "delivered_count", default: 0, null: false
    t.integer "read_count", default: 0, null: false
    t.integer "clicked_count", default: 0, null: false
    t.datetime "last_execution_at"
    t.text "last_error"
    t.jsonb "review_snapshot"
    t.string "review_digest"
    t.string "approved_digest"
    t.datetime "approved_at"
    t.datetime "approval_expires_at"
    t.bigint "approved_by_id"
    t.index ["account_id", "scheduled_at"], name: "index_jrc_campaigns_on_account_id_and_scheduled_at"
    t.index ["account_id", "status"], name: "index_jrc_campaigns_on_account_id_and_status"
    t.index ["account_id"], name: "index_jrc_campaigns_on_account_id"
    t.index ["approved_by_id"], name: "index_jrc_campaigns_on_approved_by_id"
    t.index ["created_by_id"], name: "index_jrc_campaigns_on_created_by_id"
    t.index ["inbox_id"], name: "index_jrc_campaigns_on_inbox_id"
  end

  create_table "jrc_crm_activities", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "deal_id"
    t.bigint "lead_id"
    t.integer "contact_id"
    t.bigint "company_id"
    t.bigint "organization_id"
    t.integer "conversation_id"
    t.integer "user_id"
    t.string "activity_type"
    t.string "title"
    t.text "description"
    t.datetime "due_at"
    t.datetime "completed_at"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "legacy_sales_activity_id"
    t.string "status", default: "scheduled", null: false
    t.index ["account_id", "legacy_sales_activity_id"], name: "idx_jrc_crm_activities_legacy_sales", unique: true, where: "(legacy_sales_activity_id IS NOT NULL)"
    t.index ["account_id"], name: "index_jrc_crm_activities_on_account_id"
    t.index ["activity_type"], name: "index_jrc_crm_activities_on_activity_type"
    t.index ["deal_id"], name: "index_jrc_crm_activities_on_deal_id"
    t.index ["due_at"], name: "index_jrc_crm_activities_on_due_at"
    t.index ["organization_id"], name: "index_jrc_crm_activities_on_organization_id"
    t.index ["user_id"], name: "index_jrc_crm_activities_on_user_id"
  end

  create_table "jrc_crm_audit_events", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "event_type"
    t.string "actor_type"
    t.integer "actor_id"
    t.string "resource_type"
    t.bigint "resource_id"
    t.jsonb "from_value"
    t.jsonb "to_value"
    t.jsonb "metadata"
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.bigint "legacy_sales_stage_history_id"
    t.index ["account_id", "legacy_sales_stage_history_id"], name: "idx_jrc_crm_audits_legacy_sales", unique: true, where: "(legacy_sales_stage_history_id IS NOT NULL)"
    t.index ["account_id"], name: "index_jrc_crm_audit_events_on_account_id"
    t.index ["actor_id"], name: "index_jrc_crm_audit_events_on_actor_id"
    t.index ["created_at"], name: "index_jrc_crm_audit_events_on_created_at"
    t.index ["event_type"], name: "index_jrc_crm_audit_events_on_event_type"
    t.index ["resource_type", "resource_id"], name: "index_jrc_crm_audit_events_on_resource_type_and_resource_id"
  end

  create_table "jrc_crm_automation_executions", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "automation_rule_id", null: false
    t.string "execution_id", null: false
    t.string "correlation_id", null: false
    t.string "event_type", null: false
    t.integer "depth", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "correlation_id", "automation_rule_id"], name: "idx_jrc_crm_auto_exec_idempotency"
    t.index ["account_id"], name: "index_jrc_crm_automation_executions_on_account_id"
    t.index ["automation_rule_id"], name: "index_jrc_crm_automation_executions_on_automation_rule_id"
    t.index ["execution_id"], name: "index_jrc_crm_automation_executions_on_execution_id", unique: true
    t.index ["status"], name: "index_jrc_crm_automation_executions_on_status"
  end

  create_table "jrc_crm_automation_rules", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "trigger_type", null: false
    t.jsonb "conditions", default: []
    t.jsonb "actions", default: []
    t.boolean "active", default: true, null: false
    t.integer "execution_count", default: 0, null: false
    t.datetime "last_executed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_crm_automation_rules_on_account_id"
    t.index ["active"], name: "index_jrc_crm_automation_rules_on_active"
    t.index ["trigger_type"], name: "index_jrc_crm_automation_rules_on_trigger_type"
  end

  create_table "jrc_crm_campaigns", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name"
    t.text "description"
    t.string "status", default: "active"
    t.bigint "pipeline_id"
    t.jsonb "settings"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_crm_campaigns_on_account_id"
    t.index ["status"], name: "index_jrc_crm_campaigns_on_status"
  end

  create_table "jrc_crm_custom_attribute_definitions", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "entity_type"
    t.string "name"
    t.string "key"
    t.string "attribute_type"
    t.jsonb "options"
    t.boolean "required", default: false
    t.boolean "active", default: true
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "entity_type"], name: "idx_jrc_crm_custom_attrs_account_entity"
    t.index ["account_id"], name: "index_jrc_crm_custom_attribute_definitions_on_account_id"
  end

  create_table "jrc_crm_deal_contacts", force: :cascade do |t|
    t.bigint "deal_id", null: false
    t.integer "contact_id", null: false
    t.string "role", default: "primary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deal_id", "contact_id"], name: "index_jrc_crm_deal_contacts_on_deal_id_and_contact_id", unique: true
  end

  create_table "jrc_crm_deal_conversations", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "deal_id", null: false
    t.integer "conversation_id", null: false
    t.integer "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_crm_deal_conversations_on_account_id"
    t.index ["conversation_id"], name: "index_jrc_crm_deal_conversations_on_conversation_id"
    t.index ["deal_id", "conversation_id"], name: "idx_jrc_crm_deal_conversations_uniq", unique: true
    t.index ["deal_id"], name: "index_jrc_crm_deal_conversations_on_deal_id"
  end

  create_table "jrc_crm_deal_products", force: :cascade do |t|
    t.bigint "deal_id"
    t.bigint "product_id"
    t.text "description_snapshot"
    t.integer "quantity", default: 1
    t.bigint "unit_price_cents"
    t.bigint "discount_cents", default: 0
    t.bigint "total_cents"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deal_id"], name: "index_jrc_crm_deal_products_on_deal_id"
    t.index ["product_id"], name: "index_jrc_crm_deal_products_on_product_id"
  end

  create_table "jrc_crm_deals", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "pipeline_id", null: false
    t.bigint "stage_id", null: false
    t.integer "contact_id"
    t.bigint "organization_id"
    t.bigint "company_id"
    t.integer "owner_id", null: false
    t.bigint "team_id"
    t.string "title", null: false
    t.text "description"
    t.bigint "value_cents", default: 0, null: false
    t.string "currency", default: "BRL", null: false
    t.string "source"
    t.string "status", default: "open", null: false
    t.decimal "probability", precision: 5, scale: 2
    t.datetime "expected_close_at"
    t.datetime "won_at"
    t.datetime "lost_at"
    t.bigint "lost_reason_id"
    t.text "lost_reason_note"
    t.bigint "lead_id"
    t.jsonb "custom_attributes", default: {}
    t.jsonb "metadata", default: {}
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "legacy_sales_opportunity_id"
    t.string "product_name"
    t.string "temperature", default: "warm", null: false
    t.string "conversion_key"
    t.index ["account_id", "conversion_key"], name: "idx_jrc_crm_deals_account_conversion", unique: true, where: "(conversion_key IS NOT NULL)"
    t.index ["account_id", "legacy_sales_opportunity_id"], name: "idx_jrc_crm_deals_legacy_sales", unique: true, where: "(legacy_sales_opportunity_id IS NOT NULL)"
    t.index ["account_id"], name: "index_jrc_crm_deals_on_account_id"
    t.index ["company_id"], name: "index_jrc_crm_deals_on_company_id"
    t.index ["expected_close_at"], name: "index_jrc_crm_deals_on_expected_close_at"
    t.index ["lead_id"], name: "index_jrc_crm_deals_on_lead_id"
    t.index ["organization_id"], name: "index_jrc_crm_deals_on_organization_id"
    t.index ["owner_id"], name: "index_jrc_crm_deals_on_owner_id"
    t.index ["pipeline_id"], name: "index_jrc_crm_deals_on_pipeline_id"
    t.index ["stage_id"], name: "index_jrc_crm_deals_on_stage_id"
    t.index ["status"], name: "index_jrc_crm_deals_on_status"
    t.index ["team_id"], name: "index_jrc_crm_deals_on_team_id"
  end

  create_table "jrc_crm_follow_ups", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "deal_id"
    t.bigint "lead_id"
    t.integer "user_id"
    t.string "title"
    t.text "description"
    t.datetime "due_at"
    t.boolean "is_completed", default: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_crm_follow_ups_on_account_id"
    t.index ["deal_id"], name: "index_jrc_crm_follow_ups_on_deal_id"
    t.index ["user_id"], name: "index_jrc_crm_follow_ups_on_user_id"
  end

  create_table "jrc_crm_import_batches", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "user_id"
    t.string "file_name"
    t.string "import_type", default: "leads"
    t.integer "row_count"
    t.integer "success_count", default: 0
    t.integer "error_count", default: 0
    t.integer "duplicate_count", default: 0
    t.string "status", default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_crm_import_batches_on_account_id"
    t.index ["status"], name: "index_jrc_crm_import_batches_on_status"
    t.index ["user_id"], name: "index_jrc_crm_import_batches_on_user_id"
  end

  create_table "jrc_crm_import_row_errors", force: :cascade do |t|
    t.bigint "batch_id"
    t.integer "row_number"
    t.jsonb "row_data"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.index ["batch_id"], name: "index_jrc_crm_import_row_errors_on_batch_id"
  end

  create_table "jrc_crm_leads", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "owner_id", null: false
    t.integer "contact_id"
    t.integer "conversation_id"
    t.bigint "team_id"
    t.string "name", null: false
    t.string "company_name"
    t.string "email"
    t.string "phone"
    t.string "source"
    t.string "temperature", default: "warm", null: false
    t.string "status", default: "new"
    t.integer "score", default: 0
    t.text "notes"
    t.jsonb "custom_attributes"
    t.datetime "converted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "idempotency_key"
    t.datetime "classified_at"
    t.index ["account_id", "idempotency_key"], name: "idx_jrc_crm_leads_account_idempotency", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["account_id"], name: "index_jrc_crm_leads_on_account_id"
    t.index ["contact_id"], name: "index_jrc_crm_leads_on_contact_id"
    t.index ["conversation_id"], name: "index_jrc_crm_leads_on_conversation_id"
    t.index ["email"], name: "index_jrc_crm_leads_on_email"
    t.index ["owner_id"], name: "index_jrc_crm_leads_on_owner_id"
    t.index ["phone"], name: "index_jrc_crm_leads_on_phone"
    t.index ["status"], name: "index_jrc_crm_leads_on_status"
    t.index ["team_id"], name: "index_jrc_crm_leads_on_team_id"
  end

  create_table "jrc_crm_lost_reasons", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "legacy_sales_loss_reason_id"
    t.index ["account_id", "legacy_sales_loss_reason_id"], name: "idx_jrc_crm_reasons_legacy_sales", unique: true, where: "(legacy_sales_loss_reason_id IS NOT NULL)"
    t.index ["account_id", "name"], name: "index_jrc_crm_lost_reasons_on_account_id_and_name", unique: true
  end

  create_table "jrc_crm_organizations", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "owner_id"
    t.string "name", null: false
    t.string "domain"
    t.string "phone"
    t.string "website"
    t.text "description"
    t.boolean "active", default: true, null: false
    t.jsonb "custom_attributes", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_crm_organizations_on_account_id"
    t.index ["active"], name: "index_jrc_crm_organizations_on_active"
    t.index ["name"], name: "index_jrc_crm_organizations_on_name"
    t.index ["owner_id"], name: "index_jrc_crm_organizations_on_owner_id"
  end

  create_table "jrc_crm_pipelines", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name", null: false
    t.string "key", null: false
    t.boolean "active", default: true, null: false
    t.integer "position", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "legacy_sales_pipeline_id"
    t.index ["account_id", "key"], name: "index_jrc_crm_pipelines_on_account_id_and_key", unique: true
    t.index ["account_id", "legacy_sales_pipeline_id"], name: "idx_jrc_crm_pipelines_legacy_sales", unique: true, where: "(legacy_sales_pipeline_id IS NOT NULL)"
  end

  create_table "jrc_crm_products", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name", null: false
    t.string "sku"
    t.string "category"
    t.text "description"
    t.bigint "unit_price_cents", default: 0
    t.string "currency", default: "BRL"
    t.boolean "active", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "custom_attributes", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "product_type", default: "service", null: false
    t.string "subcategory"
    t.jsonb "tags", default: [], null: false
    t.string "sales_unit", default: "unidade", null: false
    t.string "billing_model", default: "one_time", null: false
    t.bigint "cost_cents", default: 0, null: false
    t.bigint "setup_fee_cents", default: 0, null: false
    t.bigint "minimum_price_cents", default: 0, null: false
    t.decimal "tax_rate", precision: 6, scale: 2, default: "0.0", null: false
    t.decimal "commission_rate", precision: 6, scale: 2, default: "0.0", null: false
    t.decimal "included_quantity", precision: 14, scale: 2, default: "0.0", null: false
    t.string "included_unit"
    t.bigint "overage_unit_price_cents", default: 0, null: false
    t.integer "minimum_quantity", default: 1, null: false
    t.boolean "allow_variable_quantity", default: true, null: false
    t.integer "activation_days", default: 0, null: false
    t.integer "validation_period_days", default: 0, null: false
    t.boolean "rollover_allowance", default: false, null: false
    t.integer "contract_term_months", default: 12, null: false
    t.decimal "maximum_discount_percent", precision: 6, scale: 2, default: "20.0", null: false
    t.decimal "discount_approval_percent", precision: 6, scale: 2, default: "10.0", null: false
    t.string "renewal_type", default: "automatic", null: false
    t.string "adjustment_index", default: "IPCA", null: false
    t.integer "adjustment_period_months", default: 12, null: false
    t.decimal "cancellation_penalty_percent", precision: 6, scale: 2, default: "0.0", null: false
    t.boolean "allow_standalone_sale", default: true, null: false
    t.boolean "requires_contract", default: false, null: false
    t.string "fiscal_service_code"
    t.jsonb "available_for", default: [], null: false
    t.jsonb "integrations", default: [], null: false
    t.string "proposal_template_name"
    t.string "contract_template_name"
    t.text "sales_notes"
    t.text "technical_requirements"
    t.text "scope_included"
    t.text "scope_excluded"
    t.index ["account_id", "billing_model"], name: "idx_jrc_crm_products_account_billing"
    t.index ["account_id", "product_type"], name: "idx_jrc_crm_products_account_type"
    t.index ["account_id", "sku"], name: "idx_jrc_crm_products_account_sku"
    t.index ["account_id"], name: "index_jrc_crm_products_on_account_id"
  end

  create_table "jrc_crm_proposal_events", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "proposal_id", null: false
    t.integer "user_id"
    t.string "event_type", null: false
    t.text "description"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.index ["account_id"], name: "index_jrc_crm_proposal_events_on_account_id"
    t.index ["event_type"], name: "index_jrc_crm_proposal_events_on_event_type"
    t.index ["proposal_id"], name: "index_jrc_crm_proposal_events_on_proposal_id"
  end

  create_table "jrc_crm_proposal_items", force: :cascade do |t|
    t.bigint "proposal_id", null: false
    t.bigint "product_id"
    t.string "name_snapshot", null: false
    t.text "description_snapshot"
    t.integer "quantity", default: 1, null: false
    t.bigint "unit_price_cents", default: 0, null: false
    t.bigint "discount_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "billing_model", default: "one_time", null: false
    t.string "unit_name", default: "unidade", null: false
    t.bigint "setup_fee_cents", default: 0, null: false
    t.bigint "recurring_total_cents", default: 0, null: false
    t.bigint "initial_total_cents", default: 0, null: false
    t.decimal "included_quantity", precision: 14, scale: 2, default: "0.0", null: false
    t.string "included_unit"
    t.bigint "overage_unit_price_cents", default: 0, null: false
    t.integer "activation_days", default: 0, null: false
    t.integer "validation_period_days", default: 0, null: false
    t.index ["product_id"], name: "index_jrc_crm_proposal_items_on_product_id"
    t.index ["proposal_id"], name: "index_jrc_crm_proposal_items_on_proposal_id"
  end

  create_table "jrc_crm_proposals", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "deal_id", null: false
    t.integer "owner_id", null: false
    t.string "title", null: false
    t.string "status", default: "draft", null: false
    t.bigint "subtotal_cents", default: 0, null: false
    t.bigint "discount_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.text "solution_description"
    t.bigint "implementation_cents", default: 0, null: false
    t.bigint "monthly_cents", default: 0, null: false
    t.date "valid_until"
    t.integer "term_months", default: 12, null: false
    t.text "commercial_notes"
    t.text "next_steps"
    t.string "last_sent_channel"
    t.bigint "last_sent_message_id"
    t.integer "last_sent_conversation_id"
    t.string "public_token_digest", null: false
    t.datetime "public_token_expires_at"
    t.datetime "public_token_revoked_at"
    t.text "notes"
    t.text "customer_notes"
    t.datetime "sent_at"
    t.datetime "viewed_at"
    t.datetime "accepted_at"
    t.datetime "rejected_at"
    t.datetime "canceled_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "proposal_number", null: false
    t.integer "version_number", default: 1, null: false
    t.string "issuer_company_name", default: "Grupo JRC", null: false
    t.string "issuer_tax_id"
    t.string "issuer_unit"
    t.string "payment_method"
    t.integer "billing_day"
    t.integer "first_billing_days", default: 0, null: false
    t.boolean "taxes_included", default: true, null: false
    t.string "annual_adjustment_index", default: "IPCA", null: false
    t.string "renewal_type", default: "automatic", null: false
    t.decimal "cancellation_penalty_percent", precision: 6, scale: 2, default: "0.0", null: false
    t.string "approval_status", default: "not_required", null: false
    t.string "commercial_approval_status", default: "not_required", null: false
    t.string "financial_approval_status", default: "not_required", null: false
    t.string "technical_approval_status", default: "not_required", null: false
    t.integer "viewed_count", default: 0, null: false
    t.datetime "last_viewed_at"
    t.string "accepted_by_name"
    t.string "accepted_by_document"
    t.string "accepted_from_ip"
    t.string "accepted_user_agent"
    t.datetime "locked_at"
    t.boolean "follow_up_enabled", default: true, null: false
    t.integer "follow_up_days", default: 3, null: false
    t.index ["account_id", "proposal_number"], name: "idx_jrc_crm_proposals_account_number", unique: true
    t.index ["account_id"], name: "index_jrc_crm_proposals_on_account_id"
    t.index ["deal_id"], name: "index_jrc_crm_proposals_on_deal_id"
    t.index ["last_sent_conversation_id"], name: "index_jrc_crm_proposals_on_last_sent_conversation_id"
    t.index ["last_sent_message_id"], name: "index_jrc_crm_proposals_on_last_sent_message_id"
    t.index ["public_token_digest"], name: "index_jrc_crm_proposals_on_public_token_digest", unique: true
    t.index ["status"], name: "index_jrc_crm_proposals_on_status"
  end

  create_table "jrc_crm_stages", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "pipeline_id", null: false
    t.string "name", null: false
    t.string "key", null: false
    t.integer "position", null: false
    t.string "color"
    t.decimal "probability", precision: 5, scale: 2
    t.boolean "is_terminal", default: false, null: false
    t.boolean "is_won", default: false, null: false
    t.boolean "is_lost", default: false, null: false
    t.boolean "requires_handoff", default: false, null: false
    t.boolean "active", default: true, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "legacy_sales_stage_id"
    t.index ["account_id", "legacy_sales_stage_id"], name: "idx_jrc_crm_stages_legacy_sales", unique: true, where: "(legacy_sales_stage_id IS NOT NULL)"
    t.index ["account_id"], name: "index_jrc_crm_stages_on_account_id"
    t.index ["pipeline_id", "key"], name: "index_jrc_crm_stages_on_pipeline_id_and_key", unique: true
  end

  create_table "jrc_flow_connections", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "public_id", null: false
    t.string "name", null: false
    t.string "base_url", null: false
    t.bigint "remote_account_id", null: false
    t.bigint "bot_id"
    t.bigint "dashboard_app_id"
    t.boolean "enabled", default: false, null: false
    t.jsonb "inbox_ids", default: [], null: false
    t.jsonb "catalog", default: {}, null: false
    t.text "credential_ciphertext"
    t.datetime "verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "base_url", "remote_account_id"], name: "idx_jrc_connection_destination", unique: true
    t.index ["account_id"], name: "index_jrc_flow_connections_on_account_id"
    t.index ["public_id"], name: "index_jrc_flow_connections_on_public_id", unique: true
  end

  create_table "jrc_flow_remote_events", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.string "event_key", null: false
    t.text "payload_ciphertext", null: false
    t.string "status", default: "queued", null: false
    t.datetime "claimed_at"
    t.string "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "event_key"], name: "idx_jrc_remote_event_dedup", unique: true
    t.index ["connection_id"], name: "index_jrc_flow_remote_events_on_connection_id"
    t.index ["status", "created_at"], name: "index_jrc_flow_remote_events_on_status_and_created_at"
  end

  create_table "jrc_flow_remote_sessions", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.bigint "flow_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "inbox_id", null: false
    t.integer "flow_version", null: false
    t.string "status", default: "ready", null: false
    t.string "node_id"
    t.jsonb "variables", default: {}, null: false
    t.jsonb "trace", default: [], null: false
    t.integer "steps", default: 0, null: false
    t.bigint "last_message_id", default: 0, null: false
    t.datetime "wake_at"
    t.datetime "claimed_at"
    t.datetime "finished_at"
    t.string "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "conversation_id"], name: "idx_jrc_remote_session_identity", unique: true
    t.index ["connection_id"], name: "index_jrc_flow_remote_sessions_on_connection_id"
    t.index ["flow_id"], name: "index_jrc_flow_remote_sessions_on_flow_id"
  end

  create_table "jrc_flow_runs", force: :cascade do |t|
    t.bigint "flow_id", null: false
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.string "event_key", null: false
    t.string "status", default: "running", null: false
    t.string "node_id"
    t.jsonb "graph", default: {}, null: false
    t.jsonb "settings", default: {}, null: false
    t.jsonb "variables", default: {}, null: false
    t.jsonb "trace", default: [], null: false
    t.bigint "last_message_id", default: 0, null: false
    t.integer "steps", default: 0, null: false
    t.integer "wake_version", default: 0, null: false
    t.datetime "wake_at"
    t.datetime "finished_at"
    t.datetime "reset_at"
    t.string "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_jrc_flow_runs_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_jrc_flow_runs_on_account_id"
    t.index ["conversation_id"], name: "idx_jrc_one_live_flow_per_conversation", unique: true, where: "((status)::text = ANY (ARRAY[('running'::character varying)::text, ('waiting'::character varying)::text, ('delayed'::character varying)::text]))"
    t.index ["conversation_id"], name: "index_jrc_flow_runs_on_conversation_id"
    t.index ["flow_id", "event_key"], name: "index_jrc_flow_runs_on_flow_id_and_event_key", unique: true
    t.index ["flow_id"], name: "index_jrc_flow_runs_on_flow_id"
    t.index ["status", "wake_at"], name: "index_jrc_flow_runs_on_status_and_wake_at"
  end

  create_table "jrc_flows", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "created_by_id"
    t.string "name", null: false
    t.text "description"
    t.string "kind", default: "chatbot", null: false
    t.string "status", default: "draft", null: false
    t.datetime "next_run_at"
    t.jsonb "graph", default: {}, null: false
    t.jsonb "settings", default: {}, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "engine", default: "native", null: false
    t.text "source_ciphertext"
    t.text "credential_ciphertext"
    t.bigint "connection_id"
    t.index ["account_id", "status"], name: "index_jrc_flows_on_account_id_and_status"
    t.index ["account_id"], name: "index_jrc_flows_on_account_id"
    t.index ["connection_id"], name: "index_jrc_flows_on_connection_id"
    t.index ["created_by_id"], name: "index_jrc_flows_on_created_by_id"
  end

  create_table "jrc_nico_commands", force: :cascade do |t|
    t.bigint "session_id", null: false
    t.uuid "request_id", null: false
    t.text "message", null: false
    t.string "status", default: "planning", null: false
    t.string "tool"
    t.jsonb "arguments", default: {}, null: false
    t.jsonb "result", default: {}, null: false
    t.text "reply"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "source_notice_id"
    t.jsonb "execution_context", default: {}, null: false
    t.index ["session_id", "request_id"], name: "index_jrc_nico_commands_on_session_id_and_request_id", unique: true
    t.index ["session_id"], name: "index_jrc_nico_commands_on_session_id"
    t.index ["source_notice_id"], name: "index_jrc_nico_commands_on_source_notice_id"
  end

  create_table "jrc_nico_delegations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "agent_bot_id", null: false
    t.string "status", default: "active", null: false
    t.text "objective", null: false
    t.text "summary"
    t.string "reason"
    t.integer "version", default: 1, null: false
    t.boolean "allow_crm", default: false, null: false
    t.datetime "expires_at", null: false
    t.bigint "last_message_id", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "allowed_actions", default: [], null: false
    t.index ["account_id"], name: "index_jrc_nico_delegations_on_account_id"
    t.index ["agent_bot_id"], name: "index_jrc_nico_delegations_on_agent_bot_id"
    t.index ["conversation_id"], name: "index_jrc_nico_delegations_on_conversation_id", unique: true
    t.index ["user_id"], name: "index_jrc_nico_delegations_on_user_id"
  end

  create_table "jrc_nico_erp_bindings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "contact_id", null: false
    t.string "cnpj", null: false
    t.string "customer_name", null: false
    t.string "bemtevi_customer_id", null: false
    t.string "helpdesk_company_id", null: false
    t.string "mode", null: false
    t.string "version", null: false
    t.boolean "enabled", default: true, null: false
    t.bigint "verified_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "contact_id"], name: "nico_erp_contact_unique", unique: true
    t.index ["account_id"], name: "index_jrc_nico_erp_bindings_on_account_id"
    t.index ["contact_id"], name: "index_jrc_nico_erp_bindings_on_contact_id"
    t.index ["verified_by_id"], name: "index_jrc_nico_erp_bindings_on_verified_by_id"
  end

  create_table "jrc_nico_erp_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "mode", default: "off", null: false
    t.string "operator_company_id"
    t.string "requester_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_nico_erp_settings_on_account_id", unique: true
  end

  create_table "jrc_nico_inferences", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "status", default: "running", null: false
    t.integer "reserved_tokens", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_jrc_nico_inferences_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_jrc_nico_inferences_on_account_id"
    t.index ["user_id"], name: "index_jrc_nico_inferences_on_user_id"
  end

  create_table "jrc_nico_knowledge_documents", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "author_id", null: false
    t.bigint "approved_by_id"
    t.string "title", null: false
    t.text "body", null: false
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "customer_visible", default: false, null: false
    t.index ["account_id", "approved_at"], name: "idx_nico_approved_knowledge"
    t.index ["account_id"], name: "index_jrc_nico_knowledge_documents_on_account_id"
    t.index ["approved_by_id"], name: "index_jrc_nico_knowledge_documents_on_approved_by_id"
    t.index ["author_id"], name: "index_jrc_nico_knowledge_documents_on_author_id"
  end

  create_table "jrc_nico_notices", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "conversation_id"
    t.string "event_key", null: false
    t.string "kind", null: false
    t.string "status", default: "new", null: false
    t.text "body", null: false
    t.text "request"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id", "event_key"], name: "nico_notice_event_once", unique: true
    t.index ["account_id"], name: "index_jrc_nico_notices_on_account_id"
    t.index ["conversation_id"], name: "index_jrc_nico_notices_on_conversation_id"
    t.index ["user_id"], name: "index_jrc_nico_notices_on_user_id"
  end

  create_table "jrc_nico_proposals", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "run_id", null: false
    t.bigint "activity_id"
    t.uuid "request_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "digest", null: false
    t.string "status", default: "pending", null: false
    t.datetime "expires_at", null: false
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id", "request_id"], name: "nico_proposal_idempotency", unique: true
    t.index ["account_id"], name: "index_jrc_nico_proposals_on_account_id"
    t.index ["activity_id"], name: "index_jrc_nico_proposals_on_activity_id"
    t.index ["run_id"], name: "index_jrc_nico_proposals_on_run_id"
    t.index ["user_id"], name: "index_jrc_nico_proposals_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'executed'::character varying::text])", name: "nico_proposal_status"
  end

  create_table "jrc_nico_runs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.uuid "request_id", null: false
    t.string "status", default: "queued", null: false
    t.text "message", null: false
    t.string "fingerprint", null: false
    t.jsonb "result", default: {}, null: false
    t.string "error_code"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "reserved_tokens", default: 0, null: false
    t.jsonb "source_manifest"
    t.string "agent_key", default: "nico", null: false
    t.index ["account_id", "agent_key", "created_at"], name: "nico_agent_history"
    t.index ["account_id", "created_at"], name: "index_jrc_nico_runs_on_account_id_and_created_at"
    t.index ["account_id", "user_id", "request_id"], name: "idx_nico_run_request", unique: true
    t.index ["account_id"], name: "index_jrc_nico_runs_on_account_id"
    t.index ["conversation_id"], name: "index_jrc_nico_runs_on_conversation_id"
    t.index ["user_id"], name: "index_jrc_nico_runs_on_user_id"
    t.check_constraint "reserved_tokens >= 0", name: "nico_nonnegative_reservation"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "nico_run_status"
  end

  create_table "jrc_nico_sessions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.jsonb "messages", default: [], null: false
    t.jsonb "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "index_jrc_nico_sessions_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_jrc_nico_sessions_on_account_id"
    t.index ["user_id"], name: "index_jrc_nico_sessions_on_user_id"
  end

  create_table "jrc_nico_turns", force: :cascade do |t|
    t.bigint "delegation_id", null: false
    t.bigint "message_id", null: false
    t.integer "version", null: false
    t.string "status", default: "running", null: false
    t.bigint "outgoing_message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["delegation_id", "version", "message_id"], name: "nico_turn_once", unique: true
    t.index ["delegation_id"], name: "index_jrc_nico_turns_on_delegation_id"
  end

  create_table "jrc_operations_links", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "created_by_id", null: false
    t.bigint "ticket_id"
    t.bigint "project_id", null: false
    t.bigint "task_id"
    t.bigint "conversation_id"
    t.bigint "crm_deal_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "ticket_unit_id"
    t.index ["account_id", "project_id", "conversation_id"], name: "idx_jrc_ops_project_conversation", unique: true
    t.index ["account_id", "project_id", "crm_deal_id"], name: "idx_jrc_ops_project_deal", unique: true
    t.index ["account_id", "project_id", "ticket_id", "task_id"], name: "idx_jrc_ops_project_ticket_task", unique: true, where: "(task_id IS NOT NULL)"
    t.index ["account_id", "project_id", "ticket_id"], name: "idx_jrc_ops_project_ticket", unique: true, where: "(task_id IS NULL)"
    t.index ["account_id"], name: "index_jrc_operations_links_on_account_id"
    t.index ["conversation_id"], name: "index_jrc_operations_links_on_conversation_id"
    t.index ["created_by_id"], name: "index_jrc_operations_links_on_created_by_id"
    t.index ["crm_deal_id"], name: "index_jrc_operations_links_on_crm_deal_id"
    t.index ["project_id"], name: "index_jrc_operations_links_on_project_id"
    t.index ["task_id"], name: "index_jrc_operations_links_on_task_id"
    t.index ["ticket_id"], name: "index_jrc_operations_links_on_ticket_id"
    t.check_constraint "num_nonnulls(ticket_id, conversation_id, crm_deal_id) = 1 AND (task_id IS NULL OR ticket_id IS NOT NULL) AND (ticket_id IS NULL) = (ticket_unit_id IS NULL)", name: "jrc_project_link_shape"
  end

  create_table "jrc_projects_audit_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "actor_id"
    t.string "action", null: false
    t.string "auditable_type", null: false
    t.bigint "auditable_id", null: false
    t.jsonb "before_data", default: {}, null: false
    t.jsonb "after_data", default: {}, null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_audit_events_on_account_id"
    t.index ["actor_id"], name: "index_jrc_projects_audit_events_on_actor_id"
    t.index ["auditable_type", "auditable_id"], name: "idx_on_auditable_type_auditable_id_99c282993f"
  end

  create_table "jrc_projects_automation_rules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id"
    t.string "name", null: false
    t.string "event_name", null: false
    t.jsonb "conditions", default: {}, null: false
    t.jsonb "actions", default: [], null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_automation_rules_on_account_id"
    t.index ["project_id"], name: "index_jrc_projects_automation_rules_on_project_id"
  end

  create_table "jrc_projects_board_columns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "board_id", null: false
    t.string "name", null: false
    t.string "status_key", null: false
    t.integer "position", default: 0, null: false
    t.integer "wip_limit"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_board_columns_on_account_id"
    t.index ["board_id"], name: "index_jrc_projects_board_columns_on_board_id"
  end

  create_table "jrc_projects_boards", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_boards_on_account_id"
    t.index ["project_id"], name: "index_jrc_projects_boards_on_project_id"
  end

  create_table "jrc_projects_budgets", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.bigint "planned_cents", default: 0, null: false
    t.bigint "committed_cents", default: 0, null: false
    t.bigint "actual_cents", default: 0, null: false
    t.string "currency", default: "BRL", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_budgets_on_account_id"
    t.index ["project_id"], name: "index_jrc_projects_budgets_on_project_id", unique: true
  end

  create_table "jrc_projects_capacities", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.integer "minutes_per_day", default: 480, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_capacities_on_account_id"
    t.index ["user_id"], name: "index_jrc_projects_capacities_on_user_id"
  end

  create_table "jrc_projects_checklist_items", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "task_id", null: false
    t.string "text", null: false
    t.boolean "completed", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_checklist_items_on_account_id"
    t.index ["task_id"], name: "index_jrc_projects_checklist_items_on_task_id"
  end

  create_table "jrc_projects_custom_field_definitions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id"
    t.string "name", null: false
    t.string "field_type", null: false
    t.boolean "required", default: false, null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_custom_field_definitions_on_account_id"
    t.index ["project_id"], name: "index_jrc_projects_custom_field_definitions_on_project_id"
  end

  create_table "jrc_projects_decisions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "status", default: "open", null: false
    t.string "severity"
    t.bigint "owner_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_decisions_on_account_id"
    t.index ["owner_id"], name: "index_jrc_projects_decisions_on_owner_id"
    t.index ["project_id"], name: "index_jrc_projects_decisions_on_project_id"
  end

  create_table "jrc_projects_issues", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "status", default: "open", null: false
    t.string "severity"
    t.bigint "owner_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_issues_on_account_id"
    t.index ["owner_id"], name: "index_jrc_projects_issues_on_owner_id"
    t.index ["project_id"], name: "index_jrc_projects_issues_on_project_id"
  end

  create_table "jrc_projects_milestones", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.bigint "phase_id"
    t.string "name", null: false
    t.date "due_on"
    t.string "status", default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_milestones_on_account_id"
    t.index ["phase_id"], name: "index_jrc_projects_milestones_on_phase_id"
    t.index ["project_id"], name: "index_jrc_projects_milestones_on_project_id"
  end

  create_table "jrc_projects_outbox_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "event_name", null: false
    t.string "aggregate_type", null: false
    t.bigint "aggregate_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "available_at", null: false
    t.datetime "delivered_at"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_outbox_events_on_account_id"
    t.index ["status", "available_at"], name: "index_jrc_projects_outbox_events_on_status_and_available_at"
  end

  create_table "jrc_projects_phases", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.date "starts_on"
    t.date "ends_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_phases_on_account_id"
    t.index ["project_id"], name: "index_jrc_projects_phases_on_project_id"
  end

  create_table "jrc_projects_project_members", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "member", null: false
    t.integer "allocation_percent", default: 100, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_project_members_on_account_id"
    t.index ["project_id", "user_id"], name: "index_jrc_projects_project_members_on_project_id_and_user_id", unique: true
    t.index ["project_id"], name: "index_jrc_projects_project_members_on_project_id"
    t.index ["user_id"], name: "index_jrc_projects_project_members_on_user_id"
  end

  create_table "jrc_projects_project_templates", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.integer "version", default: 1, null: false
    t.jsonb "definition", default: {}, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_project_templates_on_account_id"
  end

  create_table "jrc_projects_projects", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.string "status", default: "planned", null: false
    t.string "visibility", default: "members", null: false
    t.bigint "owner_id", null: false
    t.date "starts_on"
    t.date "due_on"
    t.jsonb "settings", default: {}, null: false
    t.jsonb "template_snapshot", default: {}, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "contact_id"
    t.string "idempotency_key"
    t.string "request_fingerprint"
    t.integer "lock_version", default: 0, null: false
    t.text "acceptance_notes"
    t.datetime "completed_at"
    t.bigint "accepted_by_id"
    t.index ["accepted_by_id"], name: "index_jrc_projects_projects_on_accepted_by_id"
    t.index ["account_id", "id"], name: "idx_projects_account_identity", unique: true
    t.index ["account_id", "idempotency_key"], name: "idx_jrc_project_request", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["account_id", "key"], name: "index_jrc_projects_projects_on_account_id_and_key", unique: true
    t.index ["account_id"], name: "index_jrc_projects_projects_on_account_id"
    t.index ["contact_id"], name: "index_jrc_projects_projects_on_contact_id"
    t.index ["owner_id"], name: "index_jrc_projects_projects_on_owner_id"
  end

  create_table "jrc_projects_recurrences", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.string "frequency", null: false
    t.integer "interval", default: 1, null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "next_run_at", null: false
    t.string "last_occurrence_key"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_recurrences_on_account_id"
    t.index ["project_id"], name: "index_jrc_projects_recurrences_on_project_id"
  end

  create_table "jrc_projects_risks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "status", default: "open", null: false
    t.string "severity"
    t.bigint "owner_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_risks_on_account_id"
    t.index ["owner_id"], name: "index_jrc_projects_risks_on_owner_id"
    t.index ["project_id"], name: "index_jrc_projects_risks_on_project_id"
  end

  create_table "jrc_projects_sprints", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.string "name", null: false
    t.string "status", default: "planned", null: false
    t.date "starts_on"
    t.date "ends_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_sprints_on_account_id"
    t.index ["project_id"], name: "index_jrc_projects_sprints_on_project_id"
  end

  create_table "jrc_projects_task_comments", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "task_id", null: false
    t.bigint "user_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_task_comments_on_account_id"
    t.index ["task_id"], name: "index_jrc_projects_task_comments_on_task_id"
    t.index ["user_id"], name: "index_jrc_projects_task_comments_on_user_id"
  end

  create_table "jrc_projects_task_dependencies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "predecessor_id", null: false
    t.bigint "successor_id", null: false
    t.string "kind", default: "finish_to_start", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_task_dependencies_on_account_id"
    t.index ["predecessor_id", "successor_id"], name: "idx_jrc_projects_unique_dependency", unique: true
    t.index ["predecessor_id"], name: "index_jrc_projects_task_dependencies_on_predecessor_id"
    t.index ["successor_id"], name: "index_jrc_projects_task_dependencies_on_successor_id"
  end

  create_table "jrc_projects_tasks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.bigint "board_column_id"
    t.bigint "parent_id"
    t.bigint "assignee_id"
    t.bigint "created_by_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "status", default: "backlog", null: false
    t.string "priority", default: "medium", null: false
    t.decimal "position", precision: 20, scale: 10, default: "0.0", null: false
    t.integer "estimated_minutes", default: 0, null: false
    t.date "starts_on"
    t.date "due_on"
    t.jsonb "custom_fields", default: {}, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "project_id", "id"], name: "idx_project_tasks_scope_identity", unique: true
    t.index ["account_id"], name: "index_jrc_projects_tasks_on_account_id"
    t.index ["assignee_id"], name: "index_jrc_projects_tasks_on_assignee_id"
    t.index ["board_column_id"], name: "index_jrc_projects_tasks_on_board_column_id"
    t.index ["created_by_id"], name: "index_jrc_projects_tasks_on_created_by_id"
    t.index ["parent_id"], name: "index_jrc_projects_tasks_on_parent_id"
    t.index ["project_id", "board_column_id", "position"], name: "idx_jrc_projects_task_order"
    t.index ["project_id"], name: "index_jrc_projects_tasks_on_project_id"
  end

  create_table "jrc_projects_time_entries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.bigint "task_id"
    t.bigint "user_id", null: false
    t.integer "minutes", null: false
    t.date "worked_on", null: false
    t.string "status", default: "submitted", null: false
    t.integer "hourly_cost_cents"
    t.string "currency", default: "BRL", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_jrc_projects_time_entries_on_account_id"
    t.index ["project_id"], name: "index_jrc_projects_time_entries_on_project_id"
    t.index ["task_id"], name: "index_jrc_projects_time_entries_on_task_id"
    t.index ["user_id"], name: "index_jrc_projects_time_entries_on_user_id"
  end

  create_table "jrc_service_desk_categories", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "unit_id", null: false
    t.string "code", limit: 80, null: false
    t.string "name", limit: 255, null: false
    t.boolean "active", default: true, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "unit_id", "active"], name: "jrc_sd_categories_active"
    t.index ["account_id", "unit_id", "code"], name: "jrc_sd_categories_code", unique: true
    t.index ["account_id", "unit_id", "id"], name: "jrc_sd_categories_scope_ref", unique: true
    t.check_constraint "btrim(code::text) <> ''::text AND btrim(name::text) <> ''::text", name: "jrc_sd_categories_names"
  end

  create_table "jrc_service_desk_lifecycle_pauses", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "unit_id", null: false
    t.bigint "ticket_id", null: false
    t.bigint "lifecycle_policy_version_id", null: false
    t.bigint "sla_cycle_id"
    t.bigint "started_by_membership_id", null: false
    t.bigint "ended_by_membership_id"
    t.string "reason_code", limit: 80, null: false
    t.jsonb "clocks", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "unit_id", "ticket_id", "id"], name: "jrc_sd_lc_lifecycle_pauses_ref", unique: true
    t.index ["account_id", "unit_id", "ticket_id"], name: "jrc_sd_lc_one_pause", unique: true, where: "(ended_at IS NULL)"
    t.check_constraint "jsonb_typeof(clocks) = 'array'::text AND clocks <@ '[\"first_response\", \"resolution\"]'::jsonb AND (ended_at IS NULL) = (ended_by_membership_id IS NULL) AND (ended_at IS NULL OR ended_at >= started_at)", name: "jrc_sd_lc_pause_period"
  end

  create_table "jrc_service_desk_lifecycle_policies", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "unit_id", null: false
    t.bigint "service_id"
    t.string "name", limit: 255, null: false
    t.boolean "enabled", default: false, null: false
    t.bigint "current_version_id"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "unit_id", "id"], name: "jrc_sd_lc_lifecycle_policies_ref", unique: true
    t.index ["account_id", "unit_id", "service_id"], name: "jrc_sd_lc_service_policy", unique: true, where: "(service_id IS NOT NULL)"
    t.index ["account_id", "unit_id"], name: "jrc_sd_lc_unit_policy", unique: true, where: "(service_id IS NULL)"
  end

  create_table "jrc_service_desk_lifecycle_policy_versions", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "unit_id", null: false
    t.bigint "lifecycle_policy_id", null: false
    t.bigint "actor_membership_id", null: false
    t.integer "version", null: false
    t.jsonb "definition", null: false
    t.jsonb "status_phases", null: false
    t.jsonb "publication", null: false
    t.string "digest", limit: 64, null: false
    t.datetime "created_at", null: false
    t.index ["account_id", "unit_id", "id"], name: "jrc_sd_lc_lifecycle_policy_versions_ref", unique: true
    t.index ["account_id", "unit_id", "lifecycle_policy_id", "id"], name: "jrc_sd_lc_version_parent_ref", unique: true
    t.index ["lifecycle_policy_id", "version"], name: "jrc_sd_lc_version_number", unique: true
    t.check_constraint "version > 0 AND jsonb_typeof(definition) = 'object'::text AND digest::text ~ '^[a-f0-9]{64}$'::text", name: "jrc_sd_lc_version_valid"
  end

  create_table "jrc_service_desk_lifecycle_transitions", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "unit_id", null: false
    t.bigint "ticket_id", null: false
    t.bigint "lifecycle_policy_version_id", null: false
    t.bigint "actor_membership_id", null: false
    t.bigint "from_status_id", null: false
    t.bigint "to_status_id", null: false
    t.string "action", limit: 32, null: false
    t.string "rule_key", limit: 80, null: false
    t.string "request_key", limit: 120, null: false
    t.string "fingerprint", limit: 64, null: false
    t.datetime "occurred_at", null: false
    t.jsonb "payload", null: false
    t.datetime "created_at", null: false
    t.index ["account_id", "unit_id", "ticket_id", "actor_membership_id", "request_key"], name: "jrc_sd_lc_transition_key", unique: true
    t.index ["account_id", "unit_id", "ticket_id", "id"], name: "jrc_sd_lc_lifecycle_transitions_ref", unique: true
    t.index ["account_id", "unit_id", "ticket_id", "occurred_at", "id"], name: "jrc_sd_lc_transition_timeline"
    t.check_constraint "(action::text = ANY (ARRAY['pause'::character varying::text, 'resume'::character varying::text, 'resolve'::character varying::text, 'close'::character varying::text, 'cancel'::character varying::text, 'reopen'::character varying::text, 'work_status'::character varying::text])) AND jsonb_typeof(payload) = 'object'::text AND fingerprint::text ~ '^[a-f0-9]{64}$'::text AND btrim(request_key::text) <> ''::text", name: "jrc_sd_lc_transition_valid"
  end

  create_table "jrc_service_desk_operator_companies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "code", limit: 80, null: false
    t.string "name", limit: 255, null: false
    t.boolean "active", default: true, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "code"], name: "jrc_sd_operator_code", unique: true
    t.index ["account_id", "id"], name: "jrc_sd_operator_ref", unique: true
    t.check_constraint "btrim(code::text) <> ''::text AND btrim(name::text) <> ''::text", name: "jrc_sd_operator_companies_names"
  end

  create_table "jrc_service_desk_priorities", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "unit_id", null: false
    t.string "code", limit: 80, null: false
    t.string "name", limit: 255, null: false
    t.boolean "active", default: true, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "position", null: false
    t.index ["account_id", "unit_id", "active"], name: "jrc_sd_priorities_active"
    t.index ["account_id", "unit_id", "code"], name: "jrc_sd_priorities_code", unique: true
    t.index ["account_id", "unit_id", "id"], name: "jrc_sd_priorities_scope_ref", unique: true
    t.check_constraint "\"position\" >= 0", name: "jrc_sd_priority_position"
    t.check_constraint "btrim(code::text) <> ''::text AND btrim(name::text) <> ''::text", name: "jrc_sd_priorities_names"
  end

  create_table "jrc_service_desk_queues", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "unit_id", null: false
    t.string "code", limit: 80, null: false
    t.string "name", limit: 255, null: false
    t.boolean "active", default: true, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "team_id"
    t.index ["account_id", "team_id"], name: "jrc_sd_queue_team"
    t.index ["account_id", "unit_id", "active"], name: "jrc_sd_queues_active"
    t.index ["account_id", "unit_id", "code"], name: "jrc_sd_queues_code", unique: true
    t.index ["account_id", "unit_id", "id"], name: "jrc_sd_queues_scope_ref", unique: true
    t.check_constraint "btrim(code::text) <> ''::text AND btrim(name::text) <> ''::text", name: "jrc_sd_queues_names"
  end

  create_table "jrc_service_desk_services", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "unit_id", null: false
    t.string "name", limit: 255, null: false
    t.string "code", limit: 80, null: false
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "unit_id", "code"], name: "jrc_sd_lc_service_code", unique: true
    t.index ["account_id", "unit_id", "id"], name: "jrc_sd_lc_services_ref", unique: true
    t.check_constraint "btrim(name::text) <> ''::text AND btrim(code::text) <> ''::text", name: "jrc_sd_lc_service_names"
  end

  create_table "jrc_service_desk_sla_clocks", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "unit_id", null: false
    t.bigint "ticket_id", null: false
    t.bigint "sla_cycle_id", null: false
    t.string "kind", limit: 24, null: false
    t.string "state", limit: 24, null: false
    t.bigint "budget_seconds", null: false
    t.decimal "elapsed_seconds", precision: 20, scale: 6, null: false
    t.datetime "anchor_at", null: false
    t.datetime "due_at", null: false
    t.datetime "achieved_at"
    t.string "calculator_version", limit: 100, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "unit_id", "ticket_id", "id"], name: "jrc_sd_lc_sla_clocks_ref", unique: true
    t.index ["account_id", "unit_id", "ticket_id", "sla_cycle_id", "kind"], name: "jrc_sd_lc_clock_kind", unique: true
    t.check_constraint "(kind::text = ANY (ARRAY['first_response'::character varying::text, 'resolution'::character varying::text])) AND (state::text = ANY (ARRAY['running'::character varying::text, 'paused'::character varying::text, 'completed'::character varying::text, 'stopped'::character varying::text])) AND budget_seconds > 0 AND elapsed_seconds >= 0::numeric", name: "jrc_sd_lc_clock_values"
    t.check_constraint "(state::text = 'completed'::text) = (achieved_at IS NOT NULL)", name: "jrc_sd_lc_clock_completion"
  end

  create_table "jrc_service_desk_sla_cycles", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "unit_id", null: false
    t.bigint "ticket_id", null: false
    t.bigint "lifecycle_policy_version_id", null: false
    t.bigint "sla_snapshot_id", null: false
    t.integer "number", null: false
    t.datetime "started_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "unit_id", "ticket_id", "id"], name: "jrc_sd_lc_sla_cycles_ref", unique: true
    t.index ["account_id", "unit_id", "ticket_id", "number"], name: "jrc_sd_lc_cycle_number", unique: true
    t.check_constraint "number > 0", name: "jrc_sd_lc_cycle_number_valid"
  end

  create_table "jrc_service_desk_sla_milestones", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "unit_id", null: false
    t.bigint "ticket_id", null: false
    t.bigint "sla_snapshot_id", null: false
    t.string "kind", limit: 24, null: false
    t.datetime "due_at"
    t.datetime "calculated_at"
    t.string "calculator_version", limit: 100
    t.datetime "achieved_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "unit_id", "due_at"], name: "jrc_sd_milestone_due"
    t.index ["account_id", "unit_id", "sla_snapshot_id", "kind"], name: "jrc_sd_milestone_unique", unique: true
    t.index ["account_id", "unit_id", "ticket_id"], name: "jrc_sd_milestone_ticket"
    t.check_constraint "due_at IS NULL AND calculated_at IS NULL AND calculator_version IS NULL OR due_at IS NOT NULL AND calculated_at IS NOT NULL AND calculator_version IS NOT NULL AND btrim(calculator_version::text) <> ''::text", name: "jrc_sd_milestone_calculation"
    t.check_constraint "kind::text = ANY (ARRAY['first_response'::character varying::text, 'resolution'::character varying::text])", name: "jrc_sd_milestone_kind"
  end

  create_table "jrc_service_desk_sla_snapshots", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "unit_id", null: false
    t.bigint "ticket_id", null: false
    t.integer "version", null: false
    t.string "source_system", limit: 255, null: false
    t.string "source_reference", limit: 255, null: false
    t.string "source_version", limit: 255, null: false
    t.string "policy_key", limit: 255, null: false
    t.string "policy_version", limit: 255, null: false
    t.string "calendar_key", limit: 255, null: false
    t.string "calendar_version", limit: 255, null: false
    t.string "calendar_scope", limit: 24, null: false
    t.string "timezone", limit: 100, null: false
    t.jsonb "contract_conditions", null: false
    t.jsonb "policy_conditions", null: false
    t.jsonb "calendar_conditions", null: false
    t.datetime "captured_at", null: false
    t.datetime "applied_at", null: false
    t.string "payload_digest", limit: 64, null: false
    t.datetime "created_at", null: false
    t.index ["account_id", "unit_id", "ticket_id", "id"], name: "jrc_sd_snapshot_ref", unique: true
    t.index ["account_id", "unit_id", "ticket_id", "payload_digest"], name: "jrc_sd_snapshot_deduplicate", unique: true
    t.index ["account_id", "unit_id", "ticket_id", "version"], name: "jrc_sd_snapshot_version", unique: true
    t.check_constraint "calendar_scope::text = ANY (ARRAY['account'::character varying::text, 'operator_company'::character varying::text, 'unit'::character varying::text])", name: "jrc_sd_snapshot_scope"
    t.check_constraint "jsonb_typeof(calendar_conditions) = 'object'::text", name: "jrc_sd_snapshot_calendar_conditions"
    t.check_constraint "jsonb_typeof(contract_conditions) = 'object'::text", name: "jrc_sd_snapshot_contract_conditions"
    t.check_constraint "jsonb_typeof(policy_conditions) = 'object'::text", name: "jrc_sd_snapshot_policy_conditions"
    t.check_constraint "payload_digest::text ~ '^[a-f0-9]{64}$'::text", name: "jrc_sd_snapshot_digest"
    t.check_constraint "version > 0", name: "jrc_sd_snapshot_version_positive"
  end

  create_table "jrc_service_desk_ticket_conversations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "unit_id", null: false
    t.bigint "ticket_id", null: false
    t.integer "conversation_id", null: false
    t.bigint "linked_by_membership_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "conversation_id"], name: "jrc_sd_conversation_reverse"
    t.index ["account_id", "unit_id", "linked_by_membership_id"], name: "jrc_sd_conversation_actor"
    t.index ["account_id", "unit_id", "ticket_id", "conversation_id"], name: "jrc_sd_conversation_link_unique", unique: true
  end

  create_table "jrc_service_desk_ticket_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "unit_id", null: false
    t.bigint "ticket_id", null: false
    t.bigint "actor_membership_id", null: false
    t.string "event_type", limit: 80, null: false
    t.jsonb "data", default: {}, null: false
    t.string "correlation_id", limit: 120
    t.datetime "created_at", null: false
    t.index ["account_id", "event_type", "created_at"], name: "jrc_sd_event_type"
    t.index ["account_id", "unit_id", "actor_membership_id"], name: "jrc_sd_event_actor"
    t.index ["account_id", "unit_id", "ticket_id", "created_at", "id"], name: "jrc_sd_events_timeline"
    t.check_constraint "jsonb_typeof(data) = 'object'::text AND btrim(event_type::text) <> ''::text", name: "jrc_sd_event_payload"
  end

  create_table "jrc_service_desk_ticket_notes", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "unit_id", null: false
    t.bigint "ticket_id", null: false
    t.bigint "author_membership_id", null: false
    t.text "body", null: false
    t.string "visibility", limit: 16, default: "internal", null: false
    t.string "idempotency_key", limit: 120, null: false
    t.string "request_fingerprint", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "unit_id", "author_membership_id"], name: "jrc_sd_note_author"
    t.index ["account_id", "unit_id", "ticket_id", "author_membership_id", "idempotency_key"], name: "jrc_sd_note_idempotency", unique: true
    t.index ["account_id", "unit_id", "ticket_id", "created_at", "id"], name: "jrc_sd_notes_timeline"
    t.check_constraint "btrim(idempotency_key::text) <> ''::text AND request_fingerprint::text ~ '^[a-f0-9]{64}$'::text", name: "jrc_sd_note_fingerprint"
    t.check_constraint "visibility::text = 'internal'::text AND btrim(body) <> ''::text", name: "jrc_sd_note_internal"
  end

  create_table "jrc_service_desk_ticket_statuses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "unit_id", null: false
    t.string "code", limit: 80, null: false
    t.string "name", limit: 255, null: false
    t.boolean "active", default: true, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "phase", limit: 24, null: false
    t.integer "position", default: 0, null: false
    t.boolean "initial", default: false, null: false
    t.index ["account_id", "unit_id", "active"], name: "jrc_sd_ticket_statuses_active"
    t.index ["account_id", "unit_id", "code"], name: "jrc_sd_ticket_statuses_code", unique: true
    t.index ["account_id", "unit_id", "id"], name: "jrc_sd_ticket_statuses_scope_ref", unique: true
    t.index ["account_id", "unit_id"], name: "jrc_sd_status_initial", unique: true, where: "(initial AND active)"
    t.check_constraint "NOT initial OR phase::text = 'open'::text", name: "jrc_sd_status_initial_phase"
    t.check_constraint "\"position\" >= 0", name: "jrc_sd_status_position"
    t.check_constraint "btrim(code::text) <> ''::text AND btrim(name::text) <> ''::text", name: "jrc_sd_ticket_statuses_names"
    t.check_constraint "phase::text = ANY (ARRAY['open'::character varying::text, 'waiting'::character varying::text, 'resolved'::character varying::text, 'closed'::character varying::text, 'cancelled'::character varying::text])", name: "jrc_sd_status_phase"
  end

  create_table "jrc_service_desk_tickets", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "unit_id", null: false
    t.string "title", limit: 255, null: false
    t.text "description"
    t.integer "requester_id", null: false
    t.bigint "status_id", null: false
    t.bigint "priority_id", null: false
    t.bigint "category_id"
    t.bigint "queue_id"
    t.bigint "team_id"
    t.bigint "assignee_membership_id"
    t.bigint "created_by_membership_id", null: false
    t.string "origin_channel", limit: 80, null: false
    t.datetime "opened_at", null: false
    t.string "idempotency_key", limit: 120, null: false
    t.string "request_fingerprint", limit: 64, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "service_id"
    t.bigint "lifecycle_policy_version_id"
    t.index ["account_id", "requester_id"], name: "jrc_sd_ticket_requester"
    t.index ["account_id", "unit_id", "assignee_membership_id", "created_at"], name: "jrc_sd_ticket_assignee_membership_id"
    t.index ["account_id", "unit_id", "category_id", "created_at"], name: "jrc_sd_ticket_category_id"
    t.index ["account_id", "unit_id", "created_at", "id"], name: "jrc_sd_ticket_recent"
    t.index ["account_id", "unit_id", "created_by_membership_id", "idempotency_key"], name: "jrc_sd_ticket_idempotency", unique: true
    t.index ["account_id", "unit_id", "id"], name: "jrc_sd_tickets_scope_ref", unique: true
    t.index ["account_id", "unit_id", "lifecycle_policy_version_id"], name: "jrc_sd_ticket_lc_version"
    t.index ["account_id", "unit_id", "priority_id", "created_at"], name: "jrc_sd_ticket_priority_id"
    t.index ["account_id", "unit_id", "queue_id", "created_at"], name: "jrc_sd_ticket_queue_id"
    t.index ["account_id", "unit_id", "service_id"], name: "jrc_sd_ticket_service"
    t.index ["account_id", "unit_id", "status_id", "created_at"], name: "jrc_sd_ticket_status_id"
    t.index ["account_id", "unit_id", "team_id", "created_at"], name: "jrc_sd_ticket_team_id"
    t.check_constraint "btrim(title::text) <> ''::text AND btrim(origin_channel::text) <> ''::text AND btrim(idempotency_key::text) <> ''::text", name: "jrc_sd_ticket_required_text"
    t.check_constraint "request_fingerprint::text ~ '^[a-f0-9]{64}$'::text", name: "jrc_sd_ticket_fingerprint"
  end

  create_table "jrc_service_desk_unit_memberships", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "unit_id", null: false
    t.bigint "account_user_id", null: false
    t.boolean "active", default: false, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "account_user_id", "active", "unit_id"], name: "jrc_sd_membership_access"
    t.index ["account_id", "unit_id", "account_user_id"], name: "jrc_sd_membership_unique", unique: true
    t.index ["account_id", "unit_id", "id"], name: "jrc_sd_unit_memberships_scope_ref", unique: true
  end

  create_table "jrc_service_desk_units", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "operator_company_id", null: false
    t.string "code", limit: 80, null: false
    t.string "name", limit: 255, null: false
    t.boolean "active", default: true, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "id"], name: "jrc_sd_unit_ref", unique: true
    t.index ["account_id", "operator_company_id", "code"], name: "jrc_sd_unit_code", unique: true
    t.check_constraint "btrim(code::text) <> ''::text AND btrim(name::text) <> ''::text", name: "jrc_sd_units_names"
  end

  create_table "labels", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "color", default: "#1f93ff", null: false
    t.boolean "show_on_sidebar"
    t.bigint "account_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["account_id"], name: "index_labels_on_account_id"
    t.index ["title", "account_id"], name: "index_labels_on_title_and_account_id", unique: true
  end

  create_table "leaves", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.integer "leave_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.text "reason"
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_leaves_on_account_id_and_status"
    t.index ["account_id"], name: "index_leaves_on_account_id"
    t.index ["approved_by_id"], name: "index_leaves_on_approved_by_id"
    t.index ["user_id"], name: "index_leaves_on_user_id"
  end

  create_table "macros", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.integer "visibility", default: 0
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.jsonb "actions", default: {}, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["account_id"], name: "index_macros_on_account_id"
  end

  create_table "mentions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "account_id", null: false
    t.datetime "mentioned_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["account_id"], name: "index_mentions_on_account_id"
    t.index ["conversation_id"], name: "index_mentions_on_conversation_id"
    t.index ["user_id", "conversation_id"], name: "index_mentions_on_user_id_and_conversation_id", unique: true
    t.index ["user_id"], name: "index_mentions_on_user_id"
  end

  create_table "messages", id: :serial, force: :cascade do |t|
    t.text "content"
    t.integer "account_id", null: false
    t.integer "inbox_id", null: false
    t.integer "conversation_id", null: false
    t.integer "message_type", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "private", default: false, null: false
    t.integer "status", default: 0
    t.text "source_id"
    t.integer "content_type", default: 0, null: false
    t.json "content_attributes", default: {}
    t.string "sender_type"
    t.bigint "sender_id"
    t.jsonb "external_source_ids", default: {}
    t.jsonb "additional_attributes", default: {}
    t.text "processed_message_content"
    t.jsonb "sentiment", default: {}
    t.index "((additional_attributes -> 'campaign_id'::text))", name: "index_messages_on_additional_attributes_campaign_id", using: :gin
    t.index ["account_id", "content_type", "created_at"], name: "idx_messages_account_content_created"
    t.index ["account_id", "created_at", "message_type"], name: "index_messages_on_account_created_type"
    t.index ["account_id", "inbox_id"], name: "index_messages_on_account_id_and_inbox_id"
    t.index ["account_id"], name: "index_messages_on_account_id"
    t.index ["content"], name: "index_messages_on_content", opclass: :gin_trgm_ops, using: :gin
    t.index ["conversation_id", "account_id", "message_type", "created_at"], name: "index_messages_on_conversation_account_type_created"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["inbox_id"], name: "index_messages_on_inbox_id"
    t.index ["sender_type", "sender_id", "created_at"], name: "index_messages_on_sender_and_created"
    t.index ["sender_type", "sender_id"], name: "index_messages_on_sender_type_and_sender_id"
    t.index ["source_id"], name: "index_messages_on_source_id"
  end

  create_table "notes", force: :cascade do |t|
    t.text "content", null: false
    t.bigint "account_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["account_id"], name: "index_notes_on_account_id"
    t.index ["contact_id"], name: "index_notes_on_contact_id"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "notification_settings", force: :cascade do |t|
    t.integer "account_id"
    t.integer "user_id"
    t.integer "email_flags", default: 0, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "push_flags", default: 0, null: false
    t.index ["account_id", "user_id"], name: "by_account_user", unique: true
  end

  create_table "notification_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "subscription_type", null: false
    t.jsonb "subscription_attributes", default: {}, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "identifier"
    t.index ["identifier"], name: "index_notification_subscriptions_on_identifier", unique: true
    t.index ["user_id"], name: "index_notification_subscriptions_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.integer "notification_type", null: false
    t.string "primary_actor_type", null: false
    t.bigint "primary_actor_id", null: false
    t.string "secondary_actor_type"
    t.bigint "secondary_actor_id"
    t.datetime "read_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "snoozed_until"
    t.datetime "last_activity_at", default: -> { "CURRENT_TIMESTAMP" }
    t.jsonb "meta", default: {}
    t.index ["account_id"], name: "index_notifications_on_account_id"
    t.index ["last_activity_at"], name: "index_notifications_on_last_activity_at"
    t.index ["primary_actor_type", "primary_actor_id"], name: "uniq_primary_actor_per_account_notifications"
    t.index ["secondary_actor_type", "secondary_actor_id"], name: "uniq_secondary_actor_per_account_notifications"
    t.index ["user_id", "account_id", "snoozed_until", "read_at"], name: "idx_notifications_performance"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "platform_app_permissibles", force: :cascade do |t|
    t.bigint "platform_app_id", null: false
    t.string "permissible_type", null: false
    t.bigint "permissible_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["permissible_type", "permissible_id"], name: "index_platform_app_permissibles_on_permissibles"
    t.index ["platform_app_id", "permissible_id", "permissible_type"], name: "unique_permissibles_index", unique: true
    t.index ["platform_app_id"], name: "index_platform_app_permissibles_on_platform_app_id"
  end

  create_table "platform_apps", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "platform_banners", force: :cascade do |t|
    t.text "banner_message", null: false
    t.integer "banner_type", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "portals", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "custom_domain"
    t.string "color"
    t.string "homepage_link"
    t.string "page_title"
    t.text "header_text"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.jsonb "config", default: {"allowed_locales" => ["en"]}
    t.boolean "archived", default: false
    t.bigint "channel_web_widget_id"
    t.jsonb "ssl_settings", default: {}, null: false
    t.index ["channel_web_widget_id"], name: "index_portals_on_channel_web_widget_id"
    t.index ["custom_domain"], name: "index_portals_on_custom_domain", unique: true
    t.index ["slug"], name: "index_portals_on_slug", unique: true
  end

  create_table "portals_members", id: false, force: :cascade do |t|
    t.bigint "portal_id", null: false
    t.bigint "user_id", null: false
    t.index ["portal_id", "user_id"], name: "index_portals_members_on_portal_id_and_user_id", unique: true
    t.index ["portal_id"], name: "index_portals_members_on_portal_id"
    t.index ["user_id"], name: "index_portals_members_on_user_id"
  end

  create_table "related_categories", force: :cascade do |t|
    t.bigint "category_id"
    t.bigint "related_category_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["category_id", "related_category_id"], name: "index_related_categories_on_category_id_and_related_category_id", unique: true
    t.index ["related_category_id", "category_id"], name: "index_related_categories_on_related_category_id_and_category_id", unique: true
  end

  create_table "reporting_events", force: :cascade do |t|
    t.string "name"
    t.float "value"
    t.integer "account_id"
    t.integer "inbox_id"
    t.integer "user_id"
    t.integer "conversation_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.float "value_in_business_hours"
    t.datetime "event_start_time", precision: nil
    t.datetime "event_end_time", precision: nil
    t.index ["account_id", "name", "created_at"], name: "reporting_events__account_id__name__created_at"
    t.index ["account_id", "name", "inbox_id", "created_at"], name: "index_reporting_events_for_response_distribution"
    t.index ["account_id"], name: "index_reporting_events_on_account_id"
    t.index ["conversation_id"], name: "index_reporting_events_on_conversation_id"
    t.index ["created_at"], name: "index_reporting_events_on_created_at"
    t.index ["inbox_id"], name: "index_reporting_events_on_inbox_id"
    t.index ["name"], name: "index_reporting_events_on_name"
    t.index ["user_id"], name: "index_reporting_events_on_user_id"
  end

  create_table "reporting_events_rollups", force: :cascade do |t|
    t.integer "account_id", null: false
    t.date "date", null: false
    t.string "dimension_type", null: false
    t.bigint "dimension_id", null: false
    t.string "metric", null: false
    t.bigint "count", default: 0, null: false
    t.float "sum_value", default: 0.0, null: false
    t.float "sum_value_business_hours", default: 0.0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "date", "dimension_type", "dimension_id", "metric"], name: "index_rollup_unique_key", unique: true
    t.index ["account_id", "dimension_type", "date"], name: "index_rollup_summary"
    t.index ["account_id", "metric", "date"], name: "index_rollup_timeseries"
  end

  create_table "sales_activities", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "sales_opportunity_id", null: false
    t.integer "contact_id", null: false
    t.integer "owner_id", null: false
    t.string "activity_type", null: false
    t.string "title", null: false
    t.datetime "scheduled_at", null: false
    t.string "status", default: "scheduled", null: false
    t.text "notes"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "owner_id"], name: "index_sales_activities_on_account_id_and_owner_id"
    t.index ["account_id", "scheduled_at"], name: "index_sales_activities_on_account_id_and_scheduled_at"
    t.index ["account_id", "status"], name: "index_sales_activities_on_account_id_and_status"
    t.index ["account_id"], name: "index_sales_activities_on_account_id"
    t.index ["contact_id"], name: "index_sales_activities_on_contact_id"
    t.index ["owner_id"], name: "index_sales_activities_on_owner_id"
    t.index ["sales_opportunity_id"], name: "index_sales_activities_on_sales_opportunity_id"
  end

  create_table "sales_loss_reasons", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_sales_loss_reasons_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_sales_loss_reasons_on_account_id"
  end

  create_table "sales_opportunities", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "sales_pipeline_id", null: false
    t.bigint "sales_stage_id", null: false
    t.integer "contact_id", null: false
    t.integer "conversation_id"
    t.integer "inbox_id"
    t.bigint "team_id"
    t.integer "owner_id", null: false
    t.bigint "loss_reason_id"
    t.string "title", null: false
    t.string "product_name"
    t.decimal "value", precision: 15, scale: 2
    t.string "temperature", default: "warm", null: false
    t.string "source_channel"
    t.string "status", default: "open", null: false
    t.text "notes"
    t.text "loss_notes"
    t.datetime "won_at"
    t.datetime "lost_at"
    t.datetime "archived_at"
    t.string "idempotency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "contact_id"], name: "index_sales_opportunities_on_account_id_and_contact_id"
    t.index ["account_id", "conversation_id"], name: "index_sales_opportunities_on_account_id_and_conversation_id"
    t.index ["account_id", "idempotency_key"], name: "index_sales_opportunities_on_account_id_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["account_id", "owner_id"], name: "index_sales_opportunities_on_account_id_and_owner_id"
    t.index ["account_id", "sales_stage_id"], name: "index_sales_opportunities_on_account_id_and_sales_stage_id"
    t.index ["account_id", "status"], name: "index_sales_opportunities_on_account_id_and_status"
    t.index ["account_id"], name: "index_sales_opportunities_on_account_id"
    t.index ["contact_id"], name: "index_sales_opportunities_on_contact_id"
    t.index ["conversation_id"], name: "index_sales_opportunities_on_conversation_id"
    t.index ["inbox_id"], name: "index_sales_opportunities_on_inbox_id"
    t.index ["loss_reason_id"], name: "index_sales_opportunities_on_loss_reason_id"
    t.index ["owner_id"], name: "index_sales_opportunities_on_owner_id"
    t.index ["sales_pipeline_id"], name: "index_sales_opportunities_on_sales_pipeline_id"
    t.index ["sales_stage_id"], name: "index_sales_opportunities_on_sales_stage_id"
    t.index ["team_id"], name: "index_sales_opportunities_on_team_id"
  end

  create_table "sales_pipelines", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_sales_pipelines_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_sales_pipelines_on_account_id"
  end

  create_table "sales_stage_histories", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "sales_opportunity_id", null: false
    t.bigint "from_stage_id"
    t.bigint "to_stage_id", null: false
    t.integer "user_id", null: false
    t.datetime "changed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "sales_opportunity_id"], name: "index_sales_stage_histories_on_account_and_opportunity"
    t.index ["account_id"], name: "index_sales_stage_histories_on_account_id"
    t.index ["from_stage_id"], name: "index_sales_stage_histories_on_from_stage_id"
    t.index ["sales_opportunity_id"], name: "index_sales_stage_histories_on_sales_opportunity_id"
    t.index ["to_stage_id"], name: "index_sales_stage_histories_on_to_stage_id"
    t.index ["user_id"], name: "index_sales_stage_histories_on_user_id"
  end

  create_table "sales_stages", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "sales_pipeline_id", null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.string "color", null: false
    t.string "stage_type", default: "open", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_sales_stages_on_account_id"
    t.index ["sales_pipeline_id", "name"], name: "index_sales_stages_on_sales_pipeline_id_and_name", unique: true
    t.index ["sales_pipeline_id", "position"], name: "index_sales_stages_on_sales_pipeline_id_and_position", unique: true
    t.index ["sales_pipeline_id"], name: "index_sales_stages_on_sales_pipeline_id"
  end

  create_table "sip_credentials", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "wss_server", null: false
    t.string "sip_domain", null: false
    t.string "extension", null: false
    t.string "username", null: false
    t.text "password", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "call_history_extension"
    t.index ["account_id", "user_id"], name: "index_sip_credentials_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_sip_credentials_on_account_id"
    t.index ["user_id"], name: "index_sip_credentials_on_user_id"
  end

  create_table "sla_events", force: :cascade do |t|
    t.bigint "applied_sla_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "account_id", null: false
    t.bigint "sla_policy_id", null: false
    t.bigint "inbox_id", null: false
    t.integer "event_type"
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_sla_events_on_account_id"
    t.index ["applied_sla_id"], name: "index_sla_events_on_applied_sla_id"
    t.index ["conversation_id"], name: "index_sla_events_on_conversation_id"
    t.index ["inbox_id"], name: "index_sla_events_on_inbox_id"
    t.index ["sla_policy_id"], name: "index_sla_events_on_sla_policy_id"
  end

  create_table "sla_policies", force: :cascade do |t|
    t.string "name", null: false
    t.float "first_response_time_threshold"
    t.float "next_response_time_threshold"
    t.boolean "only_during_business_hours", default: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.float "resolution_time_threshold"
    t.index ["account_id"], name: "index_sla_policies_on_account_id"
  end

  create_table "taggings", id: :serial, force: :cascade do |t|
    t.integer "tag_id"
    t.string "taggable_type"
    t.integer "taggable_id"
    t.string "tagger_type"
    t.integer "tagger_id"
    t.string "context", limit: 128
    t.datetime "created_at", precision: nil
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "index_taggings_on_taggable_id_and_taggable_type_and_context"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
  end

  create_table "tags", id: :serial, force: :cascade do |t|
    t.string "name"
    t.integer "taggings_count", default: 0
    t.index "lower((name)::text) gin_trgm_ops", name: "tags_name_trgm_idx", using: :gin
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "team_members", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["team_id", "user_id"], name: "index_team_members_on_team_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_team_members_on_team_id"
    t.index ["user_id"], name: "index_team_members_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "allow_auto_assign", default: true
    t.bigint "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "icon", default: ""
    t.string "icon_color", default: ""
    t.index ["account_id", "id"], name: "jrc_sd_ref_teams", unique: true
    t.index ["account_id"], name: "index_teams_on_account_id"
    t.index ["name", "account_id"], name: "index_teams_on_name_and_account_id", unique: true
  end

  create_table "telephony_integrations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "provider", default: "hodupbx", null: false
    t.boolean "history_enabled", default: false, null: false
    t.string "cdr_base_url", default: "https://portal-cloud.jrcpabx.com.br", null: false
    t.string "cdr_api_version", default: "v1.4", null: false
    t.text "cdr_token"
    t.string "tenant_type", default: "TENANT", null: false
    t.integer "default_period_days", default: 7, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_telephony_integrations_on_account_id", unique: true
  end

  create_table "user_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "client_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.string "browser_name"
    t.string "browser_version"
    t.string "device_name"
    t.string "platform_name"
    t.string "platform_version"
    t.string "city"
    t.string "country"
    t.string "country_code"
    t.datetime "last_activity_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "client_id"], name: "index_user_sessions_on_user_id_and_client_id", unique: true
    t.index ["user_id"], name: "index_user_sessions_on_user_id"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.string "provider", default: "email", null: false
    t.string "uid", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at", precision: nil
    t.datetime "confirmation_sent_at", precision: nil
    t.string "unconfirmed_email"
    t.string "name", null: false
    t.string "display_name"
    t.string "email"
    t.json "tokens"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "pubsub_token"
    t.integer "availability", default: 0
    t.jsonb "ui_settings", default: {}
    t.jsonb "custom_attributes", default: {}
    t.string "type"
    t.text "message_signature"
    t.string "otp_secret"
    t.integer "consumed_timestep"
    t.boolean "otp_required_for_login", default: false, null: false
    t.text "otp_backup_codes"
    t.index ["email"], name: "index_users_on_email"
    t.index ["otp_required_for_login"], name: "index_users_on_otp_required_for_login"
    t.index ["otp_secret"], name: "index_users_on_otp_secret", unique: true
    t.index ["pubsub_token"], name: "index_users_on_pubsub_token", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["uid", "provider"], name: "index_users_on_uid_and_provider", unique: true
  end

  create_table "video_conference_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.text "moderator_url"
    t.text "spectator_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "moderator_password"
    t.text "spectator_password"
    t.index ["account_id", "user_id"], name: "index_video_conference_settings_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_video_conference_settings_on_account_id"
    t.index ["user_id"], name: "index_video_conference_settings_on_user_id"
  end

  create_table "webhooks", force: :cascade do |t|
    t.integer "account_id"
    t.integer "inbox_id"
    t.text "url"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "webhook_type", default: 0
    t.jsonb "subscriptions", default: ["conversation_status_changed", "conversation_updated", "conversation_created", "contact_created", "contact_updated", "message_created", "message_updated", "webwidget_triggered"]
    t.string "name"
    t.string "secret"
    t.index ["account_id", "url"], name: "index_webhooks_on_account_id_and_url", unique: true
  end

  create_table "whatsapp_calling_configurations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "enabled", default: false, null: false
    t.string "waba_id"
    t.string "phone_number_id"
    t.text "access_token"
    t.string "configuration_status", default: "not_configured", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_whatsapp_calling_configurations_on_account_id", unique: true
  end

  create_table "working_hours", force: :cascade do |t|
    t.bigint "inbox_id"
    t.bigint "account_id"
    t.integer "day_of_week", null: false
    t.boolean "closed_all_day", default: false
    t.integer "open_hour"
    t.integer "open_minutes"
    t.integer "close_hour"
    t.integer "close_minutes"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "open_all_day", default: false
    t.index ["account_id"], name: "index_working_hours_on_account_id"
    t.index ["inbox_id"], name: "index_working_hours_on_inbox_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "inboxes", "portals"
  add_foreign_key "jrc_ai_providers", "accounts"
  add_foreign_key "jrc_ai_providers", "users", column: "created_by_id"
  add_foreign_key "jrc_ai_usage_events", "accounts"
  add_foreign_key "jrc_ai_usage_events", "jrc_ai_providers", column: "provider_id"
  add_foreign_key "jrc_ai_usage_events", "users"
  add_foreign_key "jrc_broker_inbox_bindings", "inboxes", column: ["account_id", "inbox_id"], primary_key: ["account_id", "id"], on_delete: :cascade
  add_foreign_key "jrc_broker_inbox_bindings", "jrc_broker_integrations", column: "account_id", primary_key: "account_id", on_delete: :cascade
  add_foreign_key "jrc_broker_inbox_grants", "account_users", column: ["account_id", "user_id"], primary_key: ["account_id", "user_id"], on_delete: :cascade
  add_foreign_key "jrc_broker_inbox_grants", "inbox_members", column: ["inbox_id", "user_id"], primary_key: ["inbox_id", "user_id"], on_delete: :cascade
  add_foreign_key "jrc_broker_inbox_grants", "jrc_broker_inbox_bindings", column: ["account_id", "inbox_id"], primary_key: ["account_id", "inbox_id"], on_delete: :cascade
  add_foreign_key "jrc_broker_integrations", "accounts", on_delete: :cascade
  add_foreign_key "jrc_campaign_blacklists", "accounts"
  add_foreign_key "jrc_campaign_blacklists", "users", column: "created_by_id"
  add_foreign_key "jrc_campaign_consents", "accounts"
  add_foreign_key "jrc_campaign_consents", "users", column: "recorded_by_id"
  add_foreign_key "jrc_campaign_deliveries", "inboxes"
  add_foreign_key "jrc_campaign_deliveries", "jrc_campaign_recipients", column: "recipient_id"
  add_foreign_key "jrc_campaign_deliveries", "jrc_campaign_steps", column: "step_id"
  add_foreign_key "jrc_campaign_events", "jrc_campaign_executions", column: "execution_id"
  add_foreign_key "jrc_campaign_events", "jrc_campaign_recipients", column: "recipient_id"
  add_foreign_key "jrc_campaign_events", "jrc_campaigns", column: "campaign_id"
  add_foreign_key "jrc_campaign_executions", "jrc_campaigns", column: "campaign_id"
  add_foreign_key "jrc_campaign_inboxes", "inboxes"
  add_foreign_key "jrc_campaign_inboxes", "jrc_campaigns", column: "campaign_id"
  add_foreign_key "jrc_campaign_media_assets", "accounts"
  add_foreign_key "jrc_campaign_media_assets", "users", column: "created_by_id"
  add_foreign_key "jrc_campaign_recipients", "contacts"
  add_foreign_key "jrc_campaign_recipients", "conversations"
  add_foreign_key "jrc_campaign_recipients", "inboxes"
  add_foreign_key "jrc_campaign_recipients", "jrc_campaign_executions", column: "execution_id"
  add_foreign_key "jrc_campaign_recipients", "jrc_campaigns", column: "campaign_id"
  add_foreign_key "jrc_campaign_sanitized_entries", "jrc_campaign_sanitized_lists", column: "sanitized_list_id"
  add_foreign_key "jrc_campaign_sanitized_lists", "accounts"
  add_foreign_key "jrc_campaign_sanitized_lists", "users", column: "created_by_id"
  add_foreign_key "jrc_campaign_steps", "jrc_campaigns", column: "campaign_id"
  add_foreign_key "jrc_campaigns", "accounts"
  add_foreign_key "jrc_campaigns", "inboxes"
  add_foreign_key "jrc_campaigns", "users", column: "approved_by_id"
  add_foreign_key "jrc_campaigns", "users", column: "created_by_id"
  add_foreign_key "jrc_crm_activities", "accounts"
  add_foreign_key "jrc_crm_activities", "contacts"
  add_foreign_key "jrc_crm_activities", "conversations"
  add_foreign_key "jrc_crm_activities", "jrc_crm_deals", column: "deal_id"
  add_foreign_key "jrc_crm_activities", "jrc_crm_leads", column: "lead_id"
  add_foreign_key "jrc_crm_activities", "jrc_crm_organizations", column: "organization_id"
  add_foreign_key "jrc_crm_activities", "users"
  add_foreign_key "jrc_crm_audit_events", "accounts"
  add_foreign_key "jrc_crm_deal_contacts", "contacts"
  add_foreign_key "jrc_crm_deal_contacts", "jrc_crm_deals", column: "deal_id"
  add_foreign_key "jrc_crm_deal_conversations", "accounts"
  add_foreign_key "jrc_crm_deal_conversations", "conversations"
  add_foreign_key "jrc_crm_deal_conversations", "jrc_crm_deals", column: "deal_id"
  add_foreign_key "jrc_crm_deal_conversations", "users", column: "created_by_id"
  add_foreign_key "jrc_crm_deal_products", "jrc_crm_deals", column: "deal_id"
  add_foreign_key "jrc_crm_deal_products", "jrc_crm_products", column: "product_id"
  add_foreign_key "jrc_crm_deals", "accounts"
  add_foreign_key "jrc_crm_deals", "contacts"
  add_foreign_key "jrc_crm_deals", "jrc_crm_leads", column: "lead_id"
  add_foreign_key "jrc_crm_deals", "jrc_crm_lost_reasons", column: "lost_reason_id"
  add_foreign_key "jrc_crm_deals", "jrc_crm_organizations", column: "organization_id"
  add_foreign_key "jrc_crm_deals", "jrc_crm_pipelines", column: "pipeline_id"
  add_foreign_key "jrc_crm_deals", "jrc_crm_stages", column: "stage_id"
  add_foreign_key "jrc_crm_deals", "teams"
  add_foreign_key "jrc_crm_deals", "users", column: "owner_id"
  add_foreign_key "jrc_crm_follow_ups", "accounts"
  add_foreign_key "jrc_crm_follow_ups", "jrc_crm_deals", column: "deal_id"
  add_foreign_key "jrc_crm_follow_ups", "jrc_crm_leads", column: "lead_id"
  add_foreign_key "jrc_crm_follow_ups", "users"
  add_foreign_key "jrc_crm_leads", "accounts"
  add_foreign_key "jrc_crm_leads", "contacts"
  add_foreign_key "jrc_crm_leads", "conversations"
  add_foreign_key "jrc_crm_leads", "teams"
  add_foreign_key "jrc_crm_leads", "users", column: "owner_id"
  add_foreign_key "jrc_crm_lost_reasons", "accounts"
  add_foreign_key "jrc_crm_organizations", "accounts"
  add_foreign_key "jrc_crm_organizations", "users", column: "owner_id"
  add_foreign_key "jrc_crm_pipelines", "accounts"
  add_foreign_key "jrc_crm_products", "accounts"
  add_foreign_key "jrc_crm_proposal_events", "accounts"
  add_foreign_key "jrc_crm_proposal_events", "jrc_crm_proposals", column: "proposal_id"
  add_foreign_key "jrc_crm_proposal_events", "users"
  add_foreign_key "jrc_crm_proposal_items", "jrc_crm_products", column: "product_id"
  add_foreign_key "jrc_crm_proposal_items", "jrc_crm_proposals", column: "proposal_id"
  add_foreign_key "jrc_crm_proposals", "accounts"
  add_foreign_key "jrc_crm_proposals", "jrc_crm_deals", column: "deal_id"
  add_foreign_key "jrc_crm_proposals", "users", column: "owner_id"
  add_foreign_key "jrc_crm_stages", "accounts"
  add_foreign_key "jrc_crm_stages", "jrc_crm_pipelines", column: "pipeline_id"
  add_foreign_key "jrc_flow_connections", "accounts"
  add_foreign_key "jrc_flow_remote_events", "jrc_flow_connections", column: "connection_id"
  add_foreign_key "jrc_flow_remote_sessions", "jrc_flow_connections", column: "connection_id"
  add_foreign_key "jrc_flow_remote_sessions", "jrc_flows", column: "flow_id"
  add_foreign_key "jrc_flow_runs", "accounts"
  add_foreign_key "jrc_flow_runs", "conversations", on_delete: :cascade
  add_foreign_key "jrc_flow_runs", "jrc_flows", column: "flow_id"
  add_foreign_key "jrc_flows", "accounts"
  add_foreign_key "jrc_flows", "jrc_flow_connections", column: "connection_id"
  add_foreign_key "jrc_flows", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "jrc_nico_commands", "jrc_nico_notices", column: "source_notice_id", on_delete: :nullify
  add_foreign_key "jrc_nico_commands", "jrc_nico_sessions", column: "session_id", on_delete: :cascade
  add_foreign_key "jrc_nico_delegations", "accounts", on_delete: :cascade
  add_foreign_key "jrc_nico_delegations", "agent_bots"
  add_foreign_key "jrc_nico_delegations", "conversations", on_delete: :cascade
  add_foreign_key "jrc_nico_delegations", "users", on_delete: :cascade
  add_foreign_key "jrc_nico_erp_bindings", "accounts"
  add_foreign_key "jrc_nico_erp_bindings", "contacts"
  add_foreign_key "jrc_nico_erp_bindings", "users", column: "verified_by_id"
  add_foreign_key "jrc_nico_erp_settings", "accounts"
  add_foreign_key "jrc_nico_inferences", "accounts", on_delete: :cascade
  add_foreign_key "jrc_nico_inferences", "users", on_delete: :cascade
  add_foreign_key "jrc_nico_knowledge_documents", "accounts", on_delete: :cascade
  add_foreign_key "jrc_nico_knowledge_documents", "users", column: "approved_by_id", on_delete: :cascade
  add_foreign_key "jrc_nico_knowledge_documents", "users", column: "author_id", on_delete: :cascade
  add_foreign_key "jrc_nico_notices", "accounts", on_delete: :cascade
  add_foreign_key "jrc_nico_notices", "conversations", on_delete: :cascade
  add_foreign_key "jrc_nico_notices", "users", on_delete: :cascade
  add_foreign_key "jrc_nico_proposals", "accounts", on_delete: :cascade
  add_foreign_key "jrc_nico_proposals", "jrc_crm_activities", column: "activity_id", on_delete: :nullify
  add_foreign_key "jrc_nico_proposals", "jrc_nico_runs", column: "run_id", on_delete: :cascade
  add_foreign_key "jrc_nico_proposals", "users", on_delete: :cascade
  add_foreign_key "jrc_nico_runs", "accounts", on_delete: :cascade
  add_foreign_key "jrc_nico_runs", "conversations", on_delete: :cascade
  add_foreign_key "jrc_nico_runs", "users", on_delete: :cascade
  add_foreign_key "jrc_nico_sessions", "accounts", on_delete: :cascade
  add_foreign_key "jrc_nico_sessions", "users", on_delete: :cascade
  add_foreign_key "jrc_nico_turns", "jrc_nico_delegations", column: "delegation_id", on_delete: :cascade
  add_foreign_key "jrc_operations_links", "accounts"
  add_foreign_key "jrc_operations_links", "conversations"
  add_foreign_key "jrc_operations_links", "jrc_crm_deals", column: "crm_deal_id"
  add_foreign_key "jrc_operations_links", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_operations_links", "jrc_projects_projects", column: ["account_id", "project_id"], primary_key: ["account_id", "id"], name: "fk_project_links_account"
  add_foreign_key "jrc_operations_links", "jrc_projects_tasks", column: "task_id"
  add_foreign_key "jrc_operations_links", "jrc_projects_tasks", column: ["account_id", "project_id", "task_id"], primary_key: ["account_id", "project_id", "id"], name: "fk_project_links_task_scope"
  add_foreign_key "jrc_operations_links", "jrc_service_desk_tickets", column: "ticket_id"
  add_foreign_key "jrc_operations_links", "jrc_service_desk_tickets", column: ["account_id", "ticket_unit_id", "ticket_id"], primary_key: ["account_id", "unit_id", "id"], name: "fk_project_links_r2_unit"
  add_foreign_key "jrc_operations_links", "users", column: "created_by_id"
  add_foreign_key "jrc_projects_audit_events", "accounts"
  add_foreign_key "jrc_projects_audit_events", "users", column: "actor_id"
  add_foreign_key "jrc_projects_automation_rules", "accounts"
  add_foreign_key "jrc_projects_automation_rules", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_board_columns", "accounts"
  add_foreign_key "jrc_projects_board_columns", "jrc_projects_boards", column: "board_id"
  add_foreign_key "jrc_projects_boards", "accounts"
  add_foreign_key "jrc_projects_boards", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_budgets", "accounts"
  add_foreign_key "jrc_projects_budgets", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_capacities", "accounts"
  add_foreign_key "jrc_projects_capacities", "users"
  add_foreign_key "jrc_projects_checklist_items", "accounts"
  add_foreign_key "jrc_projects_checklist_items", "jrc_projects_tasks", column: "task_id"
  add_foreign_key "jrc_projects_custom_field_definitions", "accounts"
  add_foreign_key "jrc_projects_custom_field_definitions", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_decisions", "accounts"
  add_foreign_key "jrc_projects_decisions", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_decisions", "users", column: "owner_id"
  add_foreign_key "jrc_projects_issues", "accounts"
  add_foreign_key "jrc_projects_issues", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_issues", "users", column: "owner_id"
  add_foreign_key "jrc_projects_milestones", "accounts"
  add_foreign_key "jrc_projects_milestones", "jrc_projects_phases", column: "phase_id"
  add_foreign_key "jrc_projects_milestones", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_outbox_events", "accounts"
  add_foreign_key "jrc_projects_phases", "accounts"
  add_foreign_key "jrc_projects_phases", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_project_members", "accounts"
  add_foreign_key "jrc_projects_project_members", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_project_members", "users"
  add_foreign_key "jrc_projects_project_templates", "accounts"
  add_foreign_key "jrc_projects_projects", "accounts"
  add_foreign_key "jrc_projects_projects", "contacts"
  add_foreign_key "jrc_projects_projects", "users", column: "accepted_by_id"
  add_foreign_key "jrc_projects_projects", "users", column: "owner_id"
  add_foreign_key "jrc_projects_recurrences", "accounts"
  add_foreign_key "jrc_projects_recurrences", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_risks", "accounts"
  add_foreign_key "jrc_projects_risks", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_risks", "users", column: "owner_id"
  add_foreign_key "jrc_projects_sprints", "accounts"
  add_foreign_key "jrc_projects_sprints", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_task_comments", "accounts"
  add_foreign_key "jrc_projects_task_comments", "jrc_projects_tasks", column: "task_id"
  add_foreign_key "jrc_projects_task_comments", "users"
  add_foreign_key "jrc_projects_task_dependencies", "accounts"
  add_foreign_key "jrc_projects_task_dependencies", "jrc_projects_tasks", column: "predecessor_id"
  add_foreign_key "jrc_projects_task_dependencies", "jrc_projects_tasks", column: "successor_id"
  add_foreign_key "jrc_projects_tasks", "accounts"
  add_foreign_key "jrc_projects_tasks", "jrc_projects_board_columns", column: "board_column_id"
  add_foreign_key "jrc_projects_tasks", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_tasks", "jrc_projects_tasks", column: "parent_id"
  add_foreign_key "jrc_projects_tasks", "users", column: "assignee_id"
  add_foreign_key "jrc_projects_tasks", "users", column: "created_by_id"
  add_foreign_key "jrc_projects_time_entries", "accounts"
  add_foreign_key "jrc_projects_time_entries", "jrc_projects_projects", column: "project_id"
  add_foreign_key "jrc_projects_time_entries", "jrc_projects_tasks", column: "task_id"
  add_foreign_key "jrc_projects_time_entries", "users"
  add_foreign_key "jrc_service_desk_categories", "accounts", name: "jrc_sd_categories_account_fk"
  add_foreign_key "jrc_service_desk_categories", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_categories_unit_fk"
  add_foreign_key "jrc_service_desk_lifecycle_pauses", "accounts"
  add_foreign_key "jrc_service_desk_lifecycle_pauses", "jrc_service_desk_lifecycle_policy_versions", column: ["account_id", "unit_id", "lifecycle_policy_version_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_ff94180ace6ba8957c3c_fk"
  add_foreign_key "jrc_service_desk_lifecycle_pauses", "jrc_service_desk_sla_cycles", column: ["account_id", "unit_id", "ticket_id", "sla_cycle_id"], primary_key: ["account_id", "unit_id", "ticket_id", "id"], name: "jrc_sd_lc_2eed46e90db61ccb1a49_fk"
  add_foreign_key "jrc_service_desk_lifecycle_pauses", "jrc_service_desk_tickets", column: ["account_id", "unit_id", "ticket_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_244ef841e81d2d71d0c1_fk"
  add_foreign_key "jrc_service_desk_lifecycle_pauses", "jrc_service_desk_unit_memberships", column: ["account_id", "unit_id", "ended_by_membership_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_a0322dd34d8501041c7e_fk"
  add_foreign_key "jrc_service_desk_lifecycle_pauses", "jrc_service_desk_unit_memberships", column: ["account_id", "unit_id", "started_by_membership_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_4abfeb5e9c1e55ad9272_fk"
  add_foreign_key "jrc_service_desk_lifecycle_pauses", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_lc_e5cde32ed282f4f277d6_fk"
  add_foreign_key "jrc_service_desk_lifecycle_policies", "accounts"
  add_foreign_key "jrc_service_desk_lifecycle_policies", "jrc_service_desk_lifecycle_policy_versions", column: ["account_id", "unit_id", "id", "current_version_id"], primary_key: ["account_id", "unit_id", "lifecycle_policy_id", "id"], name: "jrc_sd_lc_current_version_fk"
  add_foreign_key "jrc_service_desk_lifecycle_policies", "jrc_service_desk_services", column: ["account_id", "unit_id", "service_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_9583cbc86336d1b68f5e_fk"
  add_foreign_key "jrc_service_desk_lifecycle_policies", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_lc_5d4b2ae138d6dcd2d563_fk"
  add_foreign_key "jrc_service_desk_lifecycle_policy_versions", "accounts"
  add_foreign_key "jrc_service_desk_lifecycle_policy_versions", "jrc_service_desk_lifecycle_policies", column: ["account_id", "unit_id", "lifecycle_policy_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_82a0f9e91538d7ad5e44_fk"
  add_foreign_key "jrc_service_desk_lifecycle_policy_versions", "jrc_service_desk_unit_memberships", column: ["account_id", "unit_id", "actor_membership_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_783f21fc0d62b0dcda5d_fk"
  add_foreign_key "jrc_service_desk_lifecycle_policy_versions", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_lc_6700244cad9d84f9270b_fk"
  add_foreign_key "jrc_service_desk_lifecycle_transitions", "accounts"
  add_foreign_key "jrc_service_desk_lifecycle_transitions", "jrc_service_desk_lifecycle_policy_versions", column: ["account_id", "unit_id", "lifecycle_policy_version_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_1cb64e7b5fdba16b37ef_fk"
  add_foreign_key "jrc_service_desk_lifecycle_transitions", "jrc_service_desk_ticket_statuses", column: ["account_id", "unit_id", "from_status_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_6d97861e11981c6a6095_fk"
  add_foreign_key "jrc_service_desk_lifecycle_transitions", "jrc_service_desk_ticket_statuses", column: ["account_id", "unit_id", "to_status_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_d0b7f293ace9b0865991_fk"
  add_foreign_key "jrc_service_desk_lifecycle_transitions", "jrc_service_desk_tickets", column: ["account_id", "unit_id", "ticket_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_cf77431d460edbc54836_fk"
  add_foreign_key "jrc_service_desk_lifecycle_transitions", "jrc_service_desk_unit_memberships", column: ["account_id", "unit_id", "actor_membership_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_2975db347397ce297cec_fk"
  add_foreign_key "jrc_service_desk_lifecycle_transitions", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_lc_93886a9d959a412d8ee6_fk"
  add_foreign_key "jrc_service_desk_operator_companies", "accounts", name: "jrc_sd_operator_companies_account_fk"
  add_foreign_key "jrc_service_desk_priorities", "accounts", name: "jrc_sd_priorities_account_fk"
  add_foreign_key "jrc_service_desk_priorities", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_priorities_unit_fk"
  add_foreign_key "jrc_service_desk_queues", "accounts", name: "jrc_sd_queues_account_fk"
  add_foreign_key "jrc_service_desk_queues", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_queues_unit_fk"
  add_foreign_key "jrc_service_desk_queues", "teams", column: ["account_id", "team_id"], primary_key: ["account_id", "id"], name: "jrc_sd_queue_team_fk"
  add_foreign_key "jrc_service_desk_services", "accounts"
  add_foreign_key "jrc_service_desk_services", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_lc_8c1eac17a78786f3d5fd_fk"
  add_foreign_key "jrc_service_desk_sla_clocks", "accounts"
  add_foreign_key "jrc_service_desk_sla_clocks", "jrc_service_desk_sla_cycles", column: ["account_id", "unit_id", "ticket_id", "sla_cycle_id"], primary_key: ["account_id", "unit_id", "ticket_id", "id"], name: "jrc_sd_lc_6785476a9d1ed7010fcd_fk"
  add_foreign_key "jrc_service_desk_sla_clocks", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_lc_53e89155e366e94dc6ea_fk"
  add_foreign_key "jrc_service_desk_sla_cycles", "accounts"
  add_foreign_key "jrc_service_desk_sla_cycles", "jrc_service_desk_lifecycle_policy_versions", column: ["account_id", "unit_id", "lifecycle_policy_version_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_be09fbe5e539aae7890e_fk"
  add_foreign_key "jrc_service_desk_sla_cycles", "jrc_service_desk_sla_snapshots", column: ["account_id", "unit_id", "ticket_id", "sla_snapshot_id"], primary_key: ["account_id", "unit_id", "ticket_id", "id"], name: "jrc_sd_lc_57795d1c18d31cc851cc_fk"
  add_foreign_key "jrc_service_desk_sla_cycles", "jrc_service_desk_tickets", column: ["account_id", "unit_id", "ticket_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_ece94b547cf313d03248_fk"
  add_foreign_key "jrc_service_desk_sla_cycles", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_lc_86dbb9b833bafac0ff2c_fk"
  add_foreign_key "jrc_service_desk_sla_milestones", "accounts", name: "jrc_sd_sla_milestones_account_fk"
  add_foreign_key "jrc_service_desk_sla_milestones", "jrc_service_desk_sla_snapshots", column: ["account_id", "unit_id", "ticket_id", "sla_snapshot_id"], primary_key: ["account_id", "unit_id", "ticket_id", "id"], name: "jrc_sd_milestone_snapshot_fk"
  add_foreign_key "jrc_service_desk_sla_milestones", "jrc_service_desk_tickets", column: ["account_id", "unit_id", "ticket_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_sla_milestones_ticket_fk"
  add_foreign_key "jrc_service_desk_sla_milestones", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_sla_milestones_unit_fk"
  add_foreign_key "jrc_service_desk_sla_snapshots", "accounts", name: "jrc_sd_sla_snapshots_account_fk"
  add_foreign_key "jrc_service_desk_sla_snapshots", "jrc_service_desk_tickets", column: ["account_id", "unit_id", "ticket_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_sla_snapshots_ticket_fk"
  add_foreign_key "jrc_service_desk_sla_snapshots", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_sla_snapshots_unit_fk"
  add_foreign_key "jrc_service_desk_ticket_conversations", "accounts", name: "jrc_sd_ticket_conversations_account_fk"
  add_foreign_key "jrc_service_desk_ticket_conversations", "conversations", column: ["account_id", "conversation_id"], primary_key: ["account_id", "id"], name: "jrc_sd_link_conversation_fk"
  add_foreign_key "jrc_service_desk_ticket_conversations", "jrc_service_desk_tickets", column: ["account_id", "unit_id", "ticket_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_ticket_conversations_ticket_fk"
  add_foreign_key "jrc_service_desk_ticket_conversations", "jrc_service_desk_unit_memberships", column: ["account_id", "unit_id", "linked_by_membership_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_conversation_actor_fk"
  add_foreign_key "jrc_service_desk_ticket_conversations", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_ticket_conversations_unit_fk"
  add_foreign_key "jrc_service_desk_ticket_events", "accounts", name: "jrc_sd_ticket_events_account_fk"
  add_foreign_key "jrc_service_desk_ticket_events", "jrc_service_desk_tickets", column: ["account_id", "unit_id", "ticket_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_ticket_events_ticket_fk"
  add_foreign_key "jrc_service_desk_ticket_events", "jrc_service_desk_unit_memberships", column: ["account_id", "unit_id", "actor_membership_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_event_actor_fk"
  add_foreign_key "jrc_service_desk_ticket_events", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_ticket_events_unit_fk"
  add_foreign_key "jrc_service_desk_ticket_notes", "accounts", name: "jrc_sd_ticket_notes_account_fk"
  add_foreign_key "jrc_service_desk_ticket_notes", "jrc_service_desk_tickets", column: ["account_id", "unit_id", "ticket_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_ticket_notes_ticket_fk"
  add_foreign_key "jrc_service_desk_ticket_notes", "jrc_service_desk_unit_memberships", column: ["account_id", "unit_id", "author_membership_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_note_author_fk"
  add_foreign_key "jrc_service_desk_ticket_notes", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_ticket_notes_unit_fk"
  add_foreign_key "jrc_service_desk_ticket_statuses", "accounts", name: "jrc_sd_ticket_statuses_account_fk"
  add_foreign_key "jrc_service_desk_ticket_statuses", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_ticket_statuses_unit_fk"
  add_foreign_key "jrc_service_desk_tickets", "accounts", name: "jrc_sd_tickets_account_fk"
  add_foreign_key "jrc_service_desk_tickets", "contacts", column: ["account_id", "requester_id"], primary_key: ["account_id", "id"], name: "jrc_sd_ticket_requester_fk"
  add_foreign_key "jrc_service_desk_tickets", "jrc_service_desk_categories", column: ["account_id", "unit_id", "category_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_ticket_category_id_fk"
  add_foreign_key "jrc_service_desk_tickets", "jrc_service_desk_lifecycle_policy_versions", column: ["account_id", "unit_id", "lifecycle_policy_version_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_8474edf85fdbbeae3b72_fk"
  add_foreign_key "jrc_service_desk_tickets", "jrc_service_desk_priorities", column: ["account_id", "unit_id", "priority_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_ticket_priority_id_fk"
  add_foreign_key "jrc_service_desk_tickets", "jrc_service_desk_queues", column: ["account_id", "unit_id", "queue_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_ticket_queue_id_fk"
  add_foreign_key "jrc_service_desk_tickets", "jrc_service_desk_services", column: ["account_id", "unit_id", "service_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_lc_494d58616d7e06366570_fk"
  add_foreign_key "jrc_service_desk_tickets", "jrc_service_desk_ticket_statuses", column: ["account_id", "unit_id", "status_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_ticket_status_id_fk"
  add_foreign_key "jrc_service_desk_tickets", "jrc_service_desk_unit_memberships", column: ["account_id", "unit_id", "assignee_membership_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_ticket_assignee_fk"
  add_foreign_key "jrc_service_desk_tickets", "jrc_service_desk_unit_memberships", column: ["account_id", "unit_id", "created_by_membership_id"], primary_key: ["account_id", "unit_id", "id"], name: "jrc_sd_ticket_creator_fk"
  add_foreign_key "jrc_service_desk_tickets", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_tickets_unit_fk"
  add_foreign_key "jrc_service_desk_tickets", "teams", column: ["account_id", "team_id"], primary_key: ["account_id", "id"], name: "jrc_sd_ticket_team_fk"
  add_foreign_key "jrc_service_desk_unit_memberships", "account_users", column: ["account_id", "account_user_id"], primary_key: ["account_id", "id"], name: "jrc_sd_membership_account_user_fk"
  add_foreign_key "jrc_service_desk_unit_memberships", "accounts", name: "jrc_sd_unit_memberships_account_fk"
  add_foreign_key "jrc_service_desk_unit_memberships", "jrc_service_desk_units", column: ["account_id", "unit_id"], primary_key: ["account_id", "id"], name: "jrc_sd_unit_memberships_unit_fk"
  add_foreign_key "jrc_service_desk_units", "accounts", name: "jrc_sd_units_account_fk"
  add_foreign_key "jrc_service_desk_units", "jrc_service_desk_operator_companies", column: ["account_id", "operator_company_id"], primary_key: ["account_id", "id"], name: "jrc_sd_unit_operator_fk"
  add_foreign_key "sales_activities", "accounts"
  add_foreign_key "sales_activities", "contacts"
  add_foreign_key "sales_activities", "sales_opportunities"
  add_foreign_key "sales_activities", "users", column: "owner_id"
  add_foreign_key "sales_loss_reasons", "accounts"
  add_foreign_key "sales_opportunities", "accounts"
  add_foreign_key "sales_opportunities", "contacts"
  add_foreign_key "sales_opportunities", "conversations"
  add_foreign_key "sales_opportunities", "inboxes"
  add_foreign_key "sales_opportunities", "sales_loss_reasons", column: "loss_reason_id"
  add_foreign_key "sales_opportunities", "sales_pipelines"
  add_foreign_key "sales_opportunities", "sales_stages"
  add_foreign_key "sales_opportunities", "teams"
  add_foreign_key "sales_opportunities", "users", column: "owner_id"
  add_foreign_key "sales_pipelines", "accounts"
  add_foreign_key "sales_stage_histories", "accounts"
  add_foreign_key "sales_stage_histories", "sales_opportunities"
  add_foreign_key "sales_stage_histories", "sales_stages", column: "from_stage_id"
  add_foreign_key "sales_stage_histories", "sales_stages", column: "to_stage_id"
  add_foreign_key "sales_stage_histories", "users"
  add_foreign_key "sales_stages", "accounts"
  add_foreign_key "sales_stages", "sales_pipelines"
  add_foreign_key "sip_credentials", "accounts"
  add_foreign_key "sip_credentials", "users"
  add_foreign_key "telephony_integrations", "accounts"
  add_foreign_key "user_sessions", "users"
  add_foreign_key "video_conference_settings", "accounts"
  add_foreign_key "video_conference_settings", "users"
  add_foreign_key "whatsapp_calling_configurations", "accounts"
  create_trigger("accounts_after_insert_row_tr", :generated => true, :compatibility => 1).
      on("accounts").
      after(:insert).
      for_each(:row) do
    "execute format('create sequence IF NOT EXISTS conv_dpid_seq_%s', NEW.id);"
  end

  create_trigger("conversations_before_insert_row_tr", :generated => true, :compatibility => 1).
      on("conversations").
      before(:insert).
      for_each(:row) do
    "NEW.display_id := nextval('conv_dpid_seq_' || NEW.account_id);"
  end

  create_trigger("camp_dpid_before_insert", :generated => true, :compatibility => 1).
      on("accounts").
      name("camp_dpid_before_insert").
      after(:insert).
      for_each(:row) do
    "execute format('create sequence IF NOT EXISTS camp_dpid_seq_%s', NEW.id);"
  end

  create_trigger("campaigns_before_insert_row_tr", :generated => true, :compatibility => 1).
      on("campaigns").
      before(:insert).
      for_each(:row) do
    "NEW.display_id := nextval('camp_dpid_seq_' || NEW.account_id);"
  end

end
