namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      namespace :approvals, module: 'accounts/approvals' do
        get 'context', to: 'context#show'
        resources :options, only: :index
        resources :resources, only: :index
        resources :catalogs, only: :index
        get 'gates', to: 'gates#show'
        resources :policies, only: %i[index show create update] do
          member { post :validate; post :publish; post :retire; get :versions }
        end
        resources :requests, only: %i[index show create] do
          collection { post :simulate }
          member { post :decide; post :transition; get :audit }
        end
        resources :delegations, only: %i[index create destroy]
      end
    end
  end
end
