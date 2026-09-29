scope '/api/v1/accounts/:account_id', defaults: { format: 'json' } do
  scope 'operations', module: 'jrc_operations', as: 'jrc_operations' do
    resource :settings, only: %i[show update]
    get 'status', to: 'settings#show'
    get 'options', to: 'options#index'
    get 'contacts', to: 'options#contacts'
    get 'deals', to: 'options#deals'
    get 'tickets', to: 'options#tickets'
    resources :links, only: %i[index create destroy]
    get 'overview', to: 'overview#show'
    get 'agenda', to: 'overview#agenda'
  end
  scope 'projects', module: 'jrc_projects/api/v1', as: 'jrc_projects' do
    resource :settings, only: %i[show update]
    resource :portfolio, only: :show, controller: :portfolio
    resources :project_templates, only: %i[index show create update destroy]
    resources :projects, only: %i[index show create update] do
      resources :members, :milestones, :sprints, :risks, :issues, :decisions, only: %i[index show create update destroy]
      resources :boards, only: :index do
        resources :columns, only: %i[index create update destroy]
      end
      resources :tasks do
        member { post :move }
        resources :comments, only: %i[index create]
        resources :checklist_items, only: %i[create update destroy]
        resources :files, only: %i[index create destroy]
      end
      resources :files, only: %i[index create destroy]
      resource :budget, only: %i[show update]
      resources :time_entries, only: %i[index create update]
      get 'reports/export', to: 'reports#export'
      resources :reports, only: :index
      get :critical_path, to: 'planning#critical_path'
      get :dependencies, to: 'planning#dependencies'
      post :dependencies, to: 'planning#dependency'
      delete 'dependencies/:id', to: 'planning#remove_dependency'
    end
  end
end
