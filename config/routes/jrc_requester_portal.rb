# Native login/MFA/recovery remain /auth. The bridge never accepts passwords.
get '/portal/login', to: 'requester_portal/shell#show'
get '/portal', to: 'requester_portal/shell#show'
get '/portal/chamados', to: 'requester_portal/shell#show'
get '/portal/chamados/novo', to: 'requester_portal/shell#show'
get '/portal/chamados/:id', to: 'requester_portal/shell#show'
get '/portal/conhecimento', to: 'requester_portal/shell#show'
get '/portal/perfil', to: 'requester_portal/shell#show'
scope '/portal', module: :requester_portal do
  resource :session, only: %i[create show update], controller: :sessions
  devise_scope :user do
    delete '/session', to: 'logout#destroy'
  end
  scope '/api' do
    get '/catalogo', to: 'tickets#services'
    get '/conhecimento', to: 'tickets#knowledge'
    get '/chamados', to: 'tickets#index'
    post '/chamados', to: 'tickets#create'
    get '/chamados/:id', to: 'tickets#show'
    post '/chamados/:id/mensagens', to: 'tickets#reply'
    get '/chamados/:id/notas/:note_id/anexos/:attachment_id', to: 'tickets#attachment'
    get '/chamados/:id/mensagens/:message_id/anexos/:attachment_id', to: 'tickets#customer_attachment'
    get '/chamados/:id/respostas/:message_id/anexos/:attachment_id', to: 'tickets#public_attachment'
  end
end

scope '/api/v1/accounts/:account_id/jrc_service_desk', module: 'api/v1/accounts/jrc_service_desk' do
  get '/requester_portal', to: 'requester_portal#show'
  patch '/requester_portal', to: 'requester_portal#update'
  post '/requester_portal/grants', to: 'requester_portal#create'
  patch '/requester_portal/grants/:id', to: 'requester_portal#change_grant'
end
