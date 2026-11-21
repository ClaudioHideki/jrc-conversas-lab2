namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      namespace :jrc_contact_center, module: 'accounts/jrc_contact_center' do
        resources :administration, only: %i[index show]
        get 'context', to: 'context#show'
        get 'customer_context', to: 'customer_context#show'
        resource :agent_state, only: %i[show update], controller: 'agent_states'
        resource :acw_policy, only: %i[show update], controller: 'acw_policies'
        resources :qualifications, only: %i[index create update]
        get 'supervisor', to: 'supervisor#show'
        resources :commands, only: %i[index show create]
        resources :events, only: [:index] do
          post :reprocess, on: :member
        end
        resources :units, only: %i[index show create update]
        resources :queues, only: %i[index show create update]
        resources :queue_memberships, only: %i[index show create update]
        resources :call_sessions, only: %i[index show] do
          patch :observations, on: :member
          get :observations, on: :member, to: 'call_observations#index'
        end
        resources :cases, only: %i[index show create update]
        resources :callbacks, only: %i[index create update]
        resources :routing_rules, only: %i[index show create update]
        get 'reports/summary', to: 'reports#summary'
        get 'integrations/capabilities', to: 'integrations#capabilities'
        get 'integrations/health', to: 'integrations#health'
      end
    end
  end
end

# Separate additive scope preserves the existing operational routes unchanged.
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      namespace :jrc_contact_center, module: 'accounts/jrc_contact_center' do
        resource :pause_catalog, only: %i[show update], controller: 'pause_catalogs'
        resource :deferred_pause_request, only: %i[create destroy], controller: 'deferred_pause_requests'
        resources :qualifications, only: [] do
          patch :draft, on: :member
          get :form_context, on: :member
        end
        resources :access_authorizations, path: 'access_authorizations/:subject_type', only: %i[index show update]
        resources :team_supervisions, only: %i[show update] do
          get :candidates, on: :member
        end
        resources :ivr_drafts, only: %i[index show create update] do
          post :preview, on: :collection
          get :versions, on: :member
          get 'versions/:revision', on: :member, action: :version, as: :version
          get :export, on: :member
          post :simulate, on: :member
        end
        resources :acw_forms, only: %i[index show create update] do
          get :versions, on: :member
          get 'versions/:revision', on: :member, action: :version, as: :version
        end
        resources :configuration_audits, only: %i[index show] do
          get :export, on: :collection
        end
      end
    end
  end
end

# Additive operational history and institutional organization; established routes remain unchanged.
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      namespace :jrc_contact_center, module: 'accounts/jrc_contact_center' do
        resources :agent_state_histories, only: [:index]
        resources :audio_folders, only: %i[index show create update]
        resources :audio_assets, only: %i[index show create update] do
          resource :usages, only: [:show], controller: 'audio_usages'
          resources :versions, only: %i[index show create], controller: 'audio_versions' do
            resource :bytes, only: [:show], controller: 'audio_bytes'
            resources :inspections, only: %i[index create], controller: 'audio_inspections'
          end
        end
      end
    end
  end
end
