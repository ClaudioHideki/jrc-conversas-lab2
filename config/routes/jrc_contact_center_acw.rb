# Native namespace is retained by draw; paths, verbs, names and controllers are unchanged.
resource :acw_policy, only: %i[show update], controller: 'acw_policies'
get 'acw_policy/ending_rules/source_context', to: 'ending_rules#source_context'
get 'acw_policy/ending_rules', to: 'ending_rules#index'
post 'acw_policy/ending_rules', to: 'ending_rules#create'
post 'acw_policy/ending_rules/activate', to: 'ending_rules#activate'
get 'acw_policy/ending_rules/readiness', to: 'ending_rules#readiness'
