Rails.application.routes.draw do
  draw :jrc_operations
  get '/flows/portal(/:public_id)', to: 'jrc_flows/portal#show'
  post '/jrc_flows/events/:public_id', to: 'jrc_flows/events#create'
  # AUTH STARTS
  mount_devise_token_auth_for 'User', at: 'auth', controllers: {
    confirmations: 'devise_overrides/confirmations',
    passwords: 'devise_overrides/passwords',
    sessions: 'devise_overrides/sessions',
    token_validations: 'devise_overrides/token_validations',
    omniauth_callbacks: 'devise_overrides/omniauth_callbacks'
  }, via: [:get, :post]

  post 'resend_confirmation', to: 'auth/resend_confirmations#create'

  ## renders the frontend paths only if its not an api only server
  if ActiveModel::Type::Boolean.new.cast(ENV.fetch('CW_API_ONLY_SERVER', false))
    root to: 'api#index'
  else
    root to: 'dashboard#index'

    get '/app', to: 'dashboard#index'
    get '/app/*params', to: 'dashboard#index'
    get '/app/accounts/:account_id/settings/inboxes/new/twitter', to: 'dashboard#index', as: 'app_new_twitter_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/microsoft', to: 'dashboard#index', as: 'app_new_microsoft_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/instagram', to: 'dashboard#index', as: 'app_new_instagram_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/tiktok', to: 'dashboard#index', as: 'app_new_tiktok_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_twitter_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_email_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_instagram_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_tiktok_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_instagram_inbox_settings'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_tiktok_inbox_settings'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_email_inbox_settings'
    get '/app/accounts/:account_id/onboarding/inbox-setup', to: 'dashboard#index', as: 'app_onboarding_inbox_setup'

    resource :widget, only: [:show]
    namespace :survey do
      resources :responses, only: [:show]
    end
    resource :slack_uploads, only: [:show]
  end

  get '/health', to: 'health#show'
  get '/api', to: 'api#index'
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      # ----------------------------------
      # start of account scoped api routes
      resources :accounts, only: [:create, :show, :update] do
        member do
          post :update_active_at
          get :cache_keys
        end

        scope module: :accounts do
          # JRC Service Desk CP4: all endpoints inherit the native Account authentication.
          namespace :jrc_service_desk do
            # CP6-D01: structural authority is separate from ticket access.
            get 'structure/context', to: 'structure#context'
            get 'structure/members', to: 'structure#members'
            %w[operator_companies units unit_memberships].each do |structural_resource|
              scope "structure/#{structural_resource}", defaults: { resource: structural_resource } do
                get '/', to: 'structure#index'
                post '/', to: 'structure#create'
                get ':id/receipts/:audit_id', to: 'structure#receipt'
                get ':id', to: 'structure#show'
                patch ':id', to: 'structure#update'
              end
            end
            # CP6: finite, authorized administrative catalogue. No structural bootstrap or deletion.
            scope 'configuration/:resource', constraints: { resource: /queues|categories|priorities|statuses|services/ } do
              get '/', to: 'configuration#index'
              post '/', to: 'configuration#create'
              get '/:id/receipts/:audit_id', to: 'configuration#receipt'
              get '/:id', to: 'configuration#show'
              patch '/:id', to: 'configuration#update'
            end
            resources :lifecycle_policies, only: [:index, :show, :create]
            resources :service_definitions, only: [:index, :show, :create]
            get 'ui_context', to: 'ui_context#show'
            get 'dashboard', to: 'dashboard#show'
            %w[queues priorities categories statuses units operator_companies assignees requesters teams].each do |resource|
              get resource, to: 'lookups#index', defaults: { resource: resource }
            end
            resources :tickets, only: [:index, :show, :create, :update] do
              member do
                get 'lifecycle', to: 'lifecycle#show'
                post 'lifecycle', to: 'lifecycle#create'
                get 'lifecycle/transitions/:transition_id', to: 'lifecycle#transition'
                post :assign
                post 'transfer', to: 'tickets#transfer'
                get 'customer_context', to: 'native_context#customer'
                get 'conversations/:record_id/navigation', to: 'native_context#conversation_navigation'
                post :work_status
                post 'notes', to: 'tickets#add_note'
                post 'conversations', to: 'tickets#link_conversation'
                get 'notes/:record_id', to: 'tickets#related_item', defaults: { kind: 'notes' }
                get 'conversations/:record_id', to: 'tickets#related_item', defaults: { kind: 'conversations' }
                %w[notes events sla conversations status_options].each do |kind|
                  get kind, to: 'tickets#related', defaults: { kind: kind }
                end
              end
            end
          end
          namespace :actions do
            resource :contact_merge, only: [:create]
          end
          resource :bulk_actions, only: [:create]
          resource :onboarding, only: [:update] do
            get :help_center_generation
          end
          resources :agents, only: [:index, :create, :update, :destroy] do
            post :bulk_create, on: :collection
          end
          resources :sip_credentials, only: [:index, :update, :destroy], param: :user_id do
            get :me, on: :collection
          end
          resources :video_conference_settings, only: [:index, :update, :destroy], param: :user_id do
            get :me, on: :collection
          end
          resource :call_history, only: :show, controller: :call_history
          resources :call_quality_analyses, only: [:index, :create]
          namespace :captain do
            resource :preferences, only: [:show, :update]
            resources :assistants do
              member do
                post :playground
                get :metrics
                get :faq_stats
                get :summary
                get :drilldown
              end
              collection do
                get :tools
              end
              resources :inboxes, only: [:index, :create, :destroy], param: :inbox_id
              resources :scenarios
            end
            resources :agent_sessions, only: [:show]
            resources :assistant_responses
            resources :faq_suggestions, only: [:index, :show, :update] do
              post :approve, on: :member
              post :dismiss, on: :member
            end
            resources :message_reports, only: [:create]
            resources :bulk_actions, only: [:create]
            resources :copilot_threads, only: [:index, :create] do
              resources :copilot_messages, only: [:index, :create]
            end
            resources :custom_tools do
              post :test, on: :collection
            end
            resources :documents, only: [:index, :show, :create, :destroy] do
              post :sync, on: :member
            end
            resource :tasks, only: [], controller: 'tasks' do
              post :rewrite
              post :summarize
              post :reply_suggestion
              post :label_suggestion
              post :follow_up
            end
          end
          resource :saml_settings, only: [:show, :create, :update, :destroy]
          resources :agent_bots, only: [:index, :create, :show, :update, :destroy] do
            delete :avatar, on: :member
            post :reset_access_token, on: :member
            post :reset_secret, on: :member
          end
          resources :contact_inboxes, only: [] do
            collection do
              post :filter
            end
          end
          resources :assignable_agents, only: [:index]
          resource :audit_logs, only: [:show]
          resources :callbacks, only: [] do
            collection do
              post :register_facebook_page
              get :register_facebook_page
              post :facebook_pages
              post :reauthorize_page
            end
          end
          resources :canned_responses, only: [:index, :create, :update, :destroy]
          resources :automation_rules, only: [:index, :create, :show, :update, :destroy] do
            post :clone
          end
          resources :macros, only: [:index, :create, :show, :update, :destroy] do
            post :execute, on: :member
          end
          resources :sla_policies, only: [:index, :create, :show, :update, :destroy]
          resources :custom_roles, only: [:index, :create, :show, :update, :destroy]
          resources :agent_capacity_policies, only: [:index, :create, :show, :update, :destroy] do
            scope module: :agent_capacity_policies do
              resources :users, only: [:index, :create, :destroy]
              resources :inbox_limits, only: [:create, :update, :destroy]
            end
          end
          resources :campaigns, only: [:index, :create, :show, :update, :destroy]
          resources :dashboard_apps, only: [:index, :show, :create, :update, :destroy]
          resource :jrc_broker, only: [:show, :update], controller: 'jrc_broker' do
            get :resources
            post :adopt
            get :onboarding, action: :onboardings
            post :onboarding, action: :create_onboarding
            get 'onboarding/:operation_id', action: :onboarding
            post 'onboarding/:operation_id/recover', action: :recover_onboarding
            get 'inboxes/:inbox_id/status', action: :status
            post 'inboxes/:inbox_id/pair', action: :pair
            get 'inboxes/:inbox_id/pair-operations/:operation_id', action: :pair_operation
            post 'inboxes/:inbox_id/disconnect', action: :disconnect
            post 'inboxes/:inbox_id/confirm_identity', action: :confirm_identity
            get 'inboxes/:inbox_id/grants', action: :grants
              put 'inboxes/:inbox_id/grants', action: :update_grants
              put 'inboxes/:inbox_id/agents', action: :assign_agents
          end
          namespace :channels do
            resource :twilio_channel, only: [:create]
          end
          resources :conversations, only: [:index, :create, :show, :update, :destroy] do
            collection do
              get :meta
              get :search
              get :unread_counts, to: 'conversations/unread_counts#index'
              post :filter
            end
            scope module: :conversations do
              resources :messages, only: [:index, :create, :destroy, :update] do
                member do
                  post :translate
                  post :retry
                end
              end
              resources :assignments, only: [:create]
              resources :labels, only: [:create, :index]
              resource :participants, only: [:show, :create, :update, :destroy]
              resource :direct_uploads, only: [:create]
              resource :draft_messages, only: [:show, :update, :destroy]
            end
            member do
              post :mute
              post :unmute
              post :transcript
              post :toggle_status
              post :toggle_priority
              post :toggle_typing_status
              post :update_last_seen
              post :unread
              post :custom_attributes
              get :attachments
              get :inbox_assistant
              get :reporting_events if ChatwootApp.enterprise?
            end
          end

          resources :search, only: [:index] do
            collection do
              get :conversations
              get :messages
              get :contacts
              get :articles
            end
          end

          namespace :customers do
            get :metadata, to: 'directory#metadata'
            get :identity, to: 'directory#identity'
            post 'imports/preview', to: 'imports#preview'
            post 'imports/apply', to: 'imports#apply'
            resources :companies, only: [:index, :show, :create, :update] do
              get :duplicates, on: :collection
              member do
                get :overview
                get :timeline
                get :records
              end
              resources :addresses, only: [:create, :update, :destroy]
            end
            resources :contacts, only: [:index, :show, :create, :update] do
              member do
                get :duplicates
                get :timeline
                post :merge
              end
              resources :contact_points, only: [:create, :update, :destroy]
            end
          end

          resources :companies, only: [:index, :show, :create, :update, :destroy] do
            collection do
              get :search
            end
            member do
              post :destroy_custom_attributes
              delete :avatar
            end
            scope module: :companies do
              resources :contacts, only: [:index, :create, :destroy] do
                collection do
                  get :search
                end
              end
              resources :conversations, only: [:index]
              resources :notes, only: [:index]
            end
          end
          resources :contacts, only: [:index, :show, :update, :create, :destroy] do
            collection do
              get :active
              get :search
              post :filter
              post :import
              post :export
            end
            member do
              get :contactable_inboxes
              post :destroy_custom_attributes
              delete :avatar
            end
            scope module: :contacts do
              resources :conversations, only: [:index]
              resources :contact_inboxes, only: [:create]
              resources :labels, only: [:create, :index]
              resources :notes
              get :attachments, to: 'attachments#index'
              post :call, on: :member, to: 'calls#create' if ChatwootApp.enterprise?
            end
          end
          namespace :sales do
            resource :pipeline, only: :show, controller: :pipeline
            resource :summary, only: :show, controller: :summary
            resource :metadata, only: :show, controller: :metadata
            resources :opportunities, only: [:index, :show, :create, :update] do
              member do
                patch :move
                patch :archive
              end
              resources :activities, only: :create
            end
            resources :activities, only: :update
          end
          resources :jrc_flow_connections, only: [:index, :show, :create, :update] do
            member do
              post :verify
              post :install
              post :disconnect
            end
            resources :flows, controller: 'jrc_remote_flows' do
              get :metadata, on: :collection
              post :import_preview, on: :collection
              post :import_definition, on: :collection
              member do
                get :export_definition
                get :runs
                post :activate
                post :pause
                post :duplicate
                post :stop_run
                post :validate_definition
                post :simulate
              end
            end
          end
          resources :jrc_flows do
            get :metadata, on: :collection
            post :import_preview, on: :collection
            post :import_definition, on: :collection
            member do
              get :export_definition
              post :activate
              post :pause
              post :duplicate
              post :stop_run
              post :validate_definition
              post :simulate
              post :start
              get :runs
            end
          end
          namespace :jrc_campaigns do
            resources :consents, only: [:index, :create, :destroy]
            resource :metadata, only: :show, controller: :metadata
            resources :blacklists, only: [:index, :create, :destroy]
            resources :sanitized_lists, only: [:index, :show, :create, :destroy]
            resources :media_assets, only: :create
            resources :campaigns do
              collection do
                post :audience_preview
                get :analytics
                post :test_message
              end
              member do
                post :launch
                post :request_review
                post :approve
                post :pause
                post :resume
                post :cancel
                post :duplicate
                get :preview
                get :report
                get :export
              end
            end
          end
          namespace :crm do
            resource :dashboard, only: :show, controller: :dashboards
            resources :reports, only: :index
            resources :leads, only: [:index, :show, :create, :update, :destroy] do
              get :for_contact, on: :collection
              post :from_contact, on: :collection
              post :from_conversation, on: :collection
              member do
                post :convert
                post :lose
              end
            end
            resources :deals, only: [:index, :show, :create, :update] do
              resources :products, controller: :deal_products, only: [:index, :create, :update, :destroy]
              member do
                post :move_stage
                post :win
                post :lose
              end
            end
            resources :management, only: [:index]
            resources :pipelines
            resources :stages do
              post :reorder, on: :collection
            end
            resources :activities do
              post :complete, on: :member
            end
            resources :follow_ups do
              post :complete, on: :member
            end
            resources :products do
              patch :toggle_active, on: :member
            end
            resources :proposals do
              resources :items, controller: :proposal_items, only: [:create, :update, :destroy]
              member do
                get :pdf
                post :send_proposal
                post :duplicate
                post :request_approval
                post :approve
                post :accept
                post :reject
                post :cancel
                post :convert_to_order
              end
            end
            resources :sales_orders, only: [:index, :show, :create, :update] do
              post :preview, on: :collection
              member do
                get :pdf
                post :attachments, action: :upload_attachments
                get 'attachments/:attachment_id', action: :download_attachment, as: :attachment
              end
            end
            resources :contracts, only: [:index, :show, :create, :update] do
              member do
                get :pdf
                get :history
                post :documents, action: :upload_documents
                get 'documents/:attachment_id', action: :download_document, as: :document
                get :signed_document, action: :download_signed_document
                post :prepare_signature
                post :send_for_signature
                post :register_manual_signature
                post :renew
                post :addendum
              end
            end
            resources :commissions, only: [:index, :create, :update] do
              get :summary, on: :collection
              get :history, on: :collection
            end
            resources :commission_programs, only: [:index, :show, :create, :update] do
              post :simulate, on: :collection
            end
            resources :backoffice_requests, only: [:index, :show, :create, :update] do
              get :summary, on: :collection
              member do
                post :advance
                post :documents, action: :upload_documents
                get 'documents/:attachment_id', action: :download_document, as: :document
                post :document_status
                post :issues, action: :add_issue
                post :resolve_issue
                post :confirm_provisioning
                post :reopen
              end
            end
            resources :invoices, only: [:index, :show, :create, :update]
            resources :payments, only: [:index, :create]
            resources :contract_templates, only: [:index, :show, :create, :update, :destroy]
            resources :goals, only: [:index, :create, :update] do
              get :dashboard, on: :collection
            end
            resources :customers, only: [:show]
            resources :lost_reasons
            resource :wallet, only: :show
            resources :timeline, only: :index
            get 'public/proposals/:token', to: 'public_proposals#show'
            post 'public/proposals/:token/view', to: 'public_proposals#record_view'
            post 'public/proposals/:token/accept', to: 'public_proposals#accept'
            post 'public/proposals/:token/reject', to: 'public_proposals#reject'
          end
          post 'jrc_copilot/ask', to: 'jrc_copilot#ask'
          namespace :jrc_nico do
            resource :operations, only: [:show], controller: :operations do
              get :notices
              post 'notices/:id/read', action: :read_notice
              post 'notices/:id/retry', action: :retry_notice
              get :conversations
              post :ask
              post :transcribe
              post :prepare
              post :takeover
              post 'commands/:id/confirm', action: :confirm
              post 'commands/:id/cancel', action: :cancel
              post 'commands/:id/claim', action: :claim
              post 'commands/:id/receipt', action: :receipt
            end
            resource :assistance, only: [:show], controller: :assistance do
              post :authorize
              post :dismiss
            end
            resource :erp, only: [:show, :update], controller: :erp do
              post :bind
              post :revoke
            end
            resources :agents, only: [:index]
            resources :proposals, only: [:create] do
              post :approve, on: :member
            end
            resources :knowledge_documents, only: [:index, :create, :update] do
              post :approve, on: :member
            end
            resources :runs, only: [:index, :show, :create] do
              post :cancel, on: :member
            end
          end
          get 'jrc_copilot/context', to: 'jrc_copilot#context'
          namespace :jrc_ai do
            resource :cockpit, only: :show, controller: :cockpit
            resources :agents, only: :index
            resources :providers do
              post :validate_configuration, on: :member
              post :make_default, on: :member
            end
            get :usage, to: 'usage#index'
          end

          resources :data_imports, only: [:index, :show, :create] do
            collection do
              post :validate_source
            end
            member do
              post :start
              post :retry, action: :retry_import
              post :abandon
              get :error_logs
              get :skip_logs
            end
          end
          resources :csat_survey_responses, only: [:index] do
            collection do
              get :metrics
              get :download
            end
            member do
              patch :update if ChatwootApp.enterprise?
            end
          end
          resources :applied_slas, only: [:index] do
            collection do
              get :metrics
              get :download
            end
          end
          resources :reporting_events, only: [:index] if ChatwootApp.enterprise?

          if ChatwootApp.enterprise?
            resources :calls, only: [:index]
            resource :whatsapp_calling_configuration, only: [:show]
            resources :whatsapp_calls, only: [:show] do
              member do
                post :accept
                post :reject
                post :terminate
                post :upload_recording
              end
              collection do
                post :initiate
                get :permission
                post :request_permission
              end
            end
          end

          resources :custom_attribute_definitions, only: [:index, :show, :create, :update, :destroy]
          resources :custom_filters, only: [:index, :show, :create, :update, :destroy]
          resource :branded_email_layout, only: [:show, :update]
          resources :inboxes, only: [:index, :show, :create, :update, :destroy] do
            get :assignable_agents, on: :member
            get :campaigns, on: :member
            get :agent_bot, on: :member
            post :set_agent_bot, on: :member
            delete :avatar, on: :member
            post :sync_templates, on: :member
            get :health, on: :member
            post :register_webhook, on: :member
            post :reset_secret, on: :member
            if ChatwootApp.enterprise?
              resource :conference, only: %i[create destroy], controller: 'conference' do
                get :token, on: :member
              end
              post :enable_whatsapp_calling, on: :member
              post :disable_whatsapp_calling, on: :member
              post :set_inbound_calls, on: :member
            end

            resource :csat_template, only: [:show, :create], controller: 'inbox_csat_templates' do
              post :analyze, on: :collection
            end
          end

          resources :inbox_members, only: [:create, :show], param: :inbox_id do
            collection do
              delete :destroy
              patch :update
            end
          end
          resources :labels, only: [:index, :show, :create, :update, :destroy]

          resources :notifications, only: [:index, :update, :destroy] do
            collection do
              post :read_all
              get :unread_count
              post :destroy_all
            end
            member do
              post :snooze
              post :unread
            end
          end
          resource :notification_settings, only: [:show, :update]

          resources :teams do
            resources :team_members, only: [:index, :create] do
              collection do
                delete :destroy
                patch :update
              end
            end
          end

          # Assignment V2 Routes
          resources :assignment_policies do
            resources :inboxes, only: [:index, :create, :destroy], module: :assignment_policies
          end

          resources :inboxes, only: [] do
            resource :assignment_policy, only: [:show, :create, :destroy], module: :inboxes
          end

          namespace :twitter do
            resource :authorization, only: [:create]
          end

          namespace :microsoft do
            resource :authorization, only: [:create]
          end

          namespace :google do
            resource :authorization, only: [:create]
          end

          namespace :instagram do
            resource :authorization, only: [:create]
          end

          namespace :tiktok do
            resource :authorization, only: [:create]
          end

          namespace :notion do
            resource :authorization, only: [:create]
          end

          namespace :whatsapp do
            resource :authorization, only: [:create]
          end

          resources :webhooks, only: [:index, :create, :update, :destroy]
          namespace :integrations do
            resources :apps, only: [:index, :show]
            resources :hooks, only: [:show, :create, :update, :destroy] do
              member do
                post :process_event
              end
            end
            resource :slack, only: [:create, :update, :destroy], controller: 'slack' do
              member do
                get :list_all_channels
              end
            end
            resource :dyte, controller: 'dyte', only: [] do
              collection do
                post :create_a_meeting
                post :add_participant_to_meeting
              end
            end
            resource :shopify, controller: 'shopify', only: [:destroy] do
              collection do
                post :auth
                get :orders
              end
            end
            resource :linear, controller: 'linear', only: [] do
              collection do
                delete :destroy
                get :teams
                get :team_entities
                post :create_issue
                post :link_issue
                post :unlink_issue
                get :search_issue
                get :linked_issues
              end
            end
            resource :notion, controller: 'notion', only: [] do
              collection do
                delete :destroy
              end
            end
          end
          resources :portals do
            member do
              patch :archive
              delete :logo
              post :send_instructions
              get :ssl_status
            end
            resources :categories do
              post :reorder, on: :collection
            end
            namespace :articles do
              resource :bulk_actions, only: [] do
                post :translate
                patch :update_status
                patch :update_category
                delete :delete_articles
              end
            end
            resources :articles do
              post :reorder, on: :collection
            end
          end

          resources :upload, only: [:create]
        end
      end
      # end of account scoped api routes
      # ----------------------------------

      namespace :integrations do
        resources :webhooks, only: [:create]
      end

      # Frontend API endpoint to trigger SAML authentication flow
      post 'auth/saml_login', to: 'auth#saml_login'

      resource :profile, only: [:show, :update] do
        delete :avatar, on: :collection
        member do
          post :availability
          post :auto_offline
          put :set_active_account
          post :resend_confirmation
          post :reset_access_token
        end

        # MFA routes
        scope module: 'profile' do
          resource :mfa, controller: 'mfa', only: [:show, :create, :destroy] do
            post :verify
            post :backup_codes
          end
          resources :sessions, only: [:index, :destroy]
        end
      end

      resource :notification_subscriptions, only: [:create, :destroy]

      namespace :widget do
        resource :direct_uploads, only: [:create]
        resource :config, only: [:create]
        resources :campaigns, only: [:index]
        resources :events, only: [:create]
        resources :messages, only: [:index, :create, :update]
        resources :conversations, only: [:index, :create] do
          collection do
            post :destroy_custom_attributes
            post :set_custom_attributes
            post :update_last_seen
            post :toggle_typing
            post :transcript
            get  :toggle_status
          end
        end
        resource :contact, only: [:show, :update] do
          collection do
            post :destroy_custom_attributes
            patch :set_user
          end
        end
        resources :inbox_members, only: [:index]
        resources :labels, only: [:create, :destroy]
        namespace :integrations do
          resource :dyte, controller: 'dyte', only: [] do
            collection do
              post :add_participant_to_meeting
            end
          end
        end
      end
    end

    namespace :v2 do
      resources :accounts, only: [:create] do
        scope module: :accounts do
          resources :summary_reports, only: [] do
            collection do
              get :agent
              get :team
              get :inbox
              get :label
              get :channel
            end
          end
          resources :reports, only: [:index] do
            collection do
              get :summary
              get :bot_summary
              get :agents
              get :inboxes
              get :labels
              get :teams
              get :conversations
              get :conversations_summary
              get :conversation_traffic
              get :drilldown
              get :bot_metrics
              get :inbox_label_matrix
              get :first_response_time_distribution
              get :outgoing_messages_count
              get :performance
            end
          end
          resource :year_in_review, only: [:show]
          resources :live_reports, only: [] do
            collection do
              get :conversation_metrics
              get :grouped_conversation_metrics
            end
          end
        end
      end
    end
  end

  if ChatwootApp.enterprise?
    namespace :enterprise, defaults: { format: 'json' } do
      namespace :api do
        namespace :v1 do
          resources :accounts do
            member do
              post :checkout
              post :subscription
              post :select_billing_currency
              get :limits
              post :toggle_deletion
              post :topup_checkout
              get :topup_options
            end
          end
        end
      end

      post 'webhooks/stripe', to: 'webhooks/stripe#process_payload'
      post 'webhooks/firecrawl', to: 'webhooks/firecrawl#process_payload'
    end
  end

  # ----------------------------------------------------------------------
  # Routes for platform APIs
  namespace :platform, defaults: { format: 'json' } do
    namespace :api do
      namespace :v1 do
        resources :users, only: [:create, :show, :update, :destroy] do
          member do
            get :login
            post :token
          end
        end
        resources :agent_bots, only: [:index, :create, :show, :update, :destroy] do
          delete :avatar, on: :member
        end
        resources :accounts, only: [:index, :create, :show, :update, :destroy] do
          resources :account_users, only: [:index, :create] do
            collection do
              delete :destroy
            end
          end
          resources :email_channel_migrations, only: [:create]
        end
      end
    end
  end

  # ----------------------------------------------------------------------
  # Routes for inbox APIs Exposed to contacts
  namespace :public, defaults: { format: 'json' } do
    namespace :api do
      namespace :v1 do
        resources :inboxes do
          scope module: :inboxes do
            resources :contacts, only: [:create, :show, :update] do
              resources :conversations, only: [:index, :create, :show] do
                member do
                  post :toggle_status
                  post :toggle_typing
                  post :update_last_seen
                end

                resources :messages, only: [:index, :create, :update]
              end
            end
          end
        end

        resources :csat_survey, only: [:show, :update]
      end
    end
  end

  get 'hc/:slug', to: 'public/api/v1/portals#show'
  get 'hc/:slug/sitemap.xml', to: 'public/api/v1/portals#sitemap'
  get 'hc/:slug/:locale', to: 'public/api/v1/portals#show', as: :public_portal_locale
  get 'hc/:slug/:locale/search', to: 'public/api/v1/portals/search#index', as: :portal_search
  get 'hc/:slug/:locale/articles', to: 'public/api/v1/portals/articles#index'
  get 'hc/:slug/:locale/categories', to: 'public/api/v1/portals/categories#index'
  get 'hc/:slug/:locale/categories/:category_slug', to: 'public/api/v1/portals/categories#show', as: :public_portal_category
  get 'hc/:slug/:locale/categories/:category_slug/articles', to: 'public/api/v1/portals/articles#index'
  get 'hc/:slug/articles/:article_slug.png', to: 'public/api/v1/portals/articles#tracking_pixel'
  get 'hc/:slug/articles/:article_slug.md', to: 'public/api/v1/portals/articles#show_markdown', as: :public_portal_article_markdown,
                                            defaults: { format: :md }
  get 'hc/:slug/articles/:article_slug', to: 'public/api/v1/portals/articles#show', as: :public_portal_article

  # ----------------------------------------------------------------------
  # Used in mailer templates
  resource :app, only: [:index] do
    resources :accounts do
      resources :conversations, only: [:show]
    end
  end

  # ----------------------------------------------------------------------
  # Routes for channel integrations
  mount Facebook::Messenger::Server, at: 'bot'
  get 'webhooks/twitter', to: 'api/v1/webhooks#twitter_crc'
  post 'webhooks/twitter', to: 'api/v1/webhooks#twitter_events'
  post 'webhooks/line/:line_channel_id', to: 'webhooks/line#process_payload'
  post 'webhooks/telegram/:bot_token', to: 'webhooks/telegram#process_payload'
  post 'webhooks/sms/:phone_number', to: 'webhooks/sms#process_payload'
  get 'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#verify'
  post 'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#process_payload'
  get 'webhooks/instagram', to: 'webhooks/instagram#verify'
  post 'webhooks/instagram', to: 'webhooks/instagram#events'
  post 'webhooks/tiktok', to: 'webhooks/tiktok#events'
  post 'webhooks/shopify', to: 'webhooks/shopify#events'

  namespace :twitter do
    resource :callback, only: [:show]
  end

  namespace :linear do
    resource :callback, only: [:show]
  end

  namespace :shopify do
    resource :callback, only: [:show]
  end

  namespace :twilio do
    resources :callback, only: [:create]
    resources :delivery_status, only: [:create]

    if ChatwootApp.enterprise?
      post 'voice/call/:phone', to: 'voice#call_twiml', as: :voice_call
      post 'voice/status/:phone', to: 'voice#status', as: :voice_status
      post 'voice/conference_status/:phone', to: 'voice#conference_status', as: :voice_conference_status
      post 'voice/recording_status/:phone', to: 'voice#recording_status', as: :voice_recording_status
    end
  end

  get 'microsoft/callback', to: 'microsoft/callbacks#show'
  get 'google/callback', to: 'google/callbacks#show'
  get 'instagram/callback', to: 'instagram/callbacks#show'
  get 'tiktok/callback', to: 'tiktok/callbacks#show'
  get 'notion/callback', to: 'notion/callbacks#show'
  # ----------------------------------------------------------------------
  # Routes for external service verifications
  get '.well-known/assetlinks.json' => 'android_app#assetlinks'
  get '.well-known/apple-app-site-association' => 'apple_app#site_association'
  get '.well-known/microsoft-identity-association.json' => 'microsoft#identity_association'
  get '.well-known/cf-custom-hostname-challenge/:id', to: 'custom_domains#verify'

  # ----------------------------------------------------------------------
  # Internal Monitoring Routes
  require 'sidekiq/web'
  require 'sidekiq/cron/web'

  devise_for :super_admins, path: 'super_admin', controllers: { sessions: 'super_admin/devise/sessions' }
  devise_scope :super_admin do
    get 'super_admin/logout', to: 'super_admin/devise/sessions#destroy'
    namespace :super_admin do
      root to: 'dashboard#index'

      resource :app_config, only: [:show, :create]
      resource :push_diagnostics, only: [:show, :create] do
        post :destroy_subscriptions, on: :collection
      end

      # order of resources affect the order of sidebar navigation in super admin
      resources :accounts, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        get 'service-desk-initialization', to: 'service_desk_initializations#show', as: :service_desk_initialization
        post 'service-desk-initialization', to: 'service_desk_initializations#create'
        get 'service-desk-initialization/receipts/:audit_id', to: 'service_desk_initializations#receipt', as: :service_desk_initialization_receipt
        post :seed, on: :member
        post :reset_cache, on: :member
        post :toggle_feature, on: :member
        get :impersonate, to: 'account_impersonations#show'
        get 'settings/inboxes', to: 'account_inboxes#index'
        get 'settings/inboxes/*path', to: 'account_inboxes#index'
        get 'settings', to: 'account_settings#show', defaults: { section: 'general' }
        get 'settings/:section', to: 'account_settings#show'
        post 'settings/:section/:resource', to: 'account_settings#create'
        patch 'settings/:section/:resource/:id', to: 'account_settings#update'
        delete 'settings/:section/:resource/:id', to: 'account_settings#destroy'
      end

      namespace :api, defaults: { format: 'json' } do
        resources :accounts, only: [] do
          resources :assignment_policies do
            resources :inboxes, only: [:index], module: :assignment_policies
          end

          resources :inboxes, only: [:index, :show, :create, :update, :destroy] do
            get :assignable_agents, on: :member
            get :campaigns, on: :member
            get :agent_bot, on: :member
            post :set_agent_bot, on: :member
            delete :avatar, on: :member
            post :sync_templates, on: :member
            get :health, on: :member
            post :register_webhook, on: :member
            post :reset_secret, on: :member

            resource :csat_template, only: [:show, :create], controller: 'inbox_csat_templates' do
              post :analyze, on: :collection
            end
            resource :assignment_policy, only: [:show, :create, :destroy], module: :inboxes
          end

          resources :inbox_members, only: [:create, :show], param: :inbox_id do
            collection do
              delete :destroy
              patch :update
            end
          end
          resources :agents, only: [:index]
          resources :teams, only: [:index]
          resources :labels, only: [:index]
          resources :portals, only: [:index]

          resources :callbacks, only: [] do
            collection do
              post :register_facebook_page
              get :register_facebook_page
              post :facebook_pages
              post :reauthorize_page
            end
          end

          namespace :channels do
            resource :twilio_channel, only: [:create]
          end

          namespace :twitter do
            resource :authorization, only: [:create]
          end

          namespace :microsoft do
            resource :authorization, only: [:create]
          end

          namespace :google do
            resource :authorization, only: [:create]
          end

          namespace :instagram do
            resource :authorization, only: [:create]
          end

          namespace :tiktok do
            resource :authorization, only: [:create]
          end

          namespace :whatsapp do
            resource :authorization, only: [:create]
          end
        end
      end
      resources :users, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        delete :avatar, on: :member, action: :destroy_avatar
      end

      resources :access_tokens, only: [:index, :show]
      resources :installation_configs, only: [:index, :new, :create, :show, :edit, :update]
      resources :agent_bots, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        delete :avatar, on: :member, action: :destroy_avatar
      end
      resources :platform_apps, only: [:index, :new, :create, :show, :edit, :update, :destroy]
      resources :platform_banners
      resource :instance_status, only: [:show]

      resource :settings, only: [:show] do
        get :refresh, on: :collection
      end
      resources :sip_credentials, only: [:index, :update, :destroy], param: :user_id
      resources :video_conference_settings, only: [:index, :update, :destroy], param: :user_id
      resource :telephony_integration, only: :update do
        post :test_connection, on: :collection
      end
      resource :whatsapp_calling_configuration, only: %i[show update] do
        post :test_configuration, on: :collection
        post :enable_inbox_calling, on: :collection
        post :disable_inbox_calling, on: :collection
      end

      # resources that doesn't appear in primary navigation in super admin
      resources :account_users, only: [:new, :create, :show, :destroy]
    end
    authenticated :super_admin do
      mount Sidekiq::Web => '/monitoring/sidekiq'
    end
  end

  namespace :installation do
    get 'onboarding', to: 'onboarding#index'
    post 'onboarding', to: 'onboarding#create'
  end

  # ---------------------------------------------------------------------
  # JRC CRM public commercial proposals (no Chatwoot session required)
  get '/jrc/propostas/:account_id/:token', to: 'jrc_crm/public_proposals#show', as: :jrc_crm_public_proposal
  get '/jrc/propostas/:account_id/:token/pdf', to: 'jrc_crm/public_proposals#pdf', as: :jrc_crm_public_proposal_pdf
  post '/jrc/propostas/:account_id/:token/accept', to: 'jrc_crm/public_proposals#accept', as: :jrc_crm_public_proposal_accept
  post '/jrc/propostas/:account_id/:token/reject', to: 'jrc_crm/public_proposals#reject', as: :jrc_crm_public_proposal_reject

  # ---------------------------------------------------------------------
  # Routes for swagger docs
  get '/swagger/*path', to: 'swagger#respond'
  get '/swagger', to: 'swagger#respond'

  # ----------------------------------------------------------------------
  # Routes for testing
  resources :widget_tests, only: [:index] unless Rails.env.production?
end
