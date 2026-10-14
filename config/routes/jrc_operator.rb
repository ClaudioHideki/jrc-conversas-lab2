scope '/api/v1/accounts/:account_id/operator', defaults: { format: 'json' }, controller: 'api/v1/accounts/jrc_operator', as: 'jrc_operator' do
  get :context
  get :bindings
  scope 'bindings/:binding_id' do
    get :options
    get :customer
    get :plans
    get :charges
    get :availability
    get :operations
    post :reserve
    post :release
    post :reconcile
    post :prepare_boleto
    post :send_boleto
    get 'operations/:operation_id/pdf', action: :boleto
  end
end
