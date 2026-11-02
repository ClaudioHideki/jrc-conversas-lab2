# frozen_string_literal: true

# Associations only: official Projects, Articles and Approval engines retain
# ownership of task execution, knowledge publication and approval decisions.
class LinkServiceDeskCasesToNativeResources < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_service_desk_incidents, :approval_issuer_company_id, :bigint
    add_column :jrc_service_desk_incidents, :approval_business_unit_id, :bigint
    add_foreign_key :jrc_service_desk_incidents, :companies, column: [:account_id, :approval_issuer_company_id], primary_key: [:account_id, :id],
                                                             name: 'jrc_sd_problem_issuer_fk'
    add_foreign_key :jrc_service_desk_incidents, :jrc_crm_business_units,
                    column: [:account_id, :approval_issuer_company_id, :approval_business_unit_id], primary_key: [:account_id, :company_id, :id], name: 'jrc_sd_problem_business_unit_fk'
    add_index :articles, [:account_id, :id], unique: true, name: 'jrc_sd_article_account_ref'
    create_table :jrc_service_desk_case_resource_links do |t|
      t.bigint :account_id, null: false
      t.bigint :unit_id, null: false
      t.bigint :incident_id, null: false
      t.bigint :created_by_membership_id, null: false
      t.bigint :project_id
      t.bigint :task_id
      t.bigint :article_id
      t.bigint :approval_request_id
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_check_constraint :jrc_service_desk_case_resource_links,
                         '(CASE WHEN task_id IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN article_id IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN approval_request_id IS NOT NULL THEN 1 ELSE 0 END) = 1', name: 'jrc_sd_case_resource_one_target'
    add_check_constraint :jrc_service_desk_case_resource_links, '(task_id IS NULL) = (project_id IS NULL)', name: 'jrc_sd_case_resource_project_task'
    add_foreign_key :jrc_service_desk_case_resource_links, :jrc_service_desk_incidents, column: [:account_id, :unit_id, :incident_id],
                                                                                        primary_key: [:account_id, :unit_id, :id], name: 'jrc_sd_case_resource_case'
    add_foreign_key :jrc_service_desk_case_resource_links, :jrc_service_desk_unit_memberships,
                    column: [:account_id, :unit_id, :created_by_membership_id], primary_key: [:account_id, :unit_id, :id], name: 'jrc_sd_case_resource_actor'
    add_foreign_key :jrc_service_desk_case_resource_links, :jrc_projects_tasks, column: [:account_id, :project_id, :task_id],
                                                                                primary_key: [:account_id, :project_id, :id], name: 'jrc_sd_case_resource_task'
    add_foreign_key :jrc_service_desk_case_resource_links, :articles, column: [:account_id, :article_id], primary_key: [:account_id, :id],
                                                                      name: 'jrc_sd_case_resource_article'
    add_foreign_key :jrc_service_desk_case_resource_links, :jrc_approvals_requests, column: [:account_id, :approval_request_id],
                                                                                    primary_key: [:account_id, :id], name: 'jrc_sd_case_resource_approval'
    %i[task_id article_id approval_request_id].each do |field|
      add_index :jrc_service_desk_case_resource_links, [:incident_id, field], unique: true, where: "#{field} IS NOT NULL",
                                                                              name: "jrc_sd_case_resource_#{field}_unique"
    end
  end
end
