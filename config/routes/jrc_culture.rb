# frozen_string_literal: true

get '/portal/manual-de-cultura', to: 'jrc_culture/shell#show'
scope '/portal/manual-de-cultura', module: :jrc_culture, as: :jrc_culture do
  resource :session, only: %i[show create], controller: :sessions
  scope '/api/accounts/:account_id' do
    get '/manuals', to: 'manuals#index'
    post '/versions/:id/confirm', to: 'manuals#confirm'
    get '/versions/:id/files/:kind', to: 'manuals#file'
    scope '/admin' do
      get '/setup', to: 'administration#setup'
      get '/report', to: 'administration#report'
      get '/export', to: 'administration#export'
      post '/versions', to: 'administration#create_version'
      post '/versions/:id/transition', to: 'administration#transition'
      get '/versions/:id/files/:kind', to: 'administration#file'
      resources :roster, only: %i[index create destroy], controller: :roster do
        get :directory, on: :collection
      end
      resources :imports, only: %i[index show create] do
        post :apply, on: :member
        get :file, on: :member
      end
    end
  end
end
