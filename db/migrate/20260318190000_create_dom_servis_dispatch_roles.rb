# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class CreateDomServisDispatchRoles < ActiveRecord::Migration[7.2]
  SYSTEM_USER_ID = 1

  ROLE_DEFINITIONS = {
    'Dom-Servis Admin' => {
      note:       'Assign together with Admin. Grants the Dom-Servis administrative workspace and dispatch policy controls.',
      permission: 'dom_servis.admin',
    },
    'Dom-Servis Dispatcher' => {
      note:       'Assign together with Agent. Grants the Dom-Servis dispatcher workspace and dispatcher actions.',
      permission: 'dom_servis.dispatcher',
    },
    'Dom-Servis Master' => {
      note:       'Assign together with Agent. Grants the Dom-Servis master workspace and master actions.',
      permission: 'dom_servis.master',
    },
  }.freeze

  def up
    ROLE_DEFINITIONS.each do |name, definition|
      role = Role.find_or_initialize_by(name: name)
      role.active        = true
      role.note          = definition[:note]
      role.created_by_id ||= SYSTEM_USER_ID
      role.updated_by_id = SYSTEM_USER_ID

      role.permission_grant(definition[:permission])
      role.save! if role.changed?
    end
  end

  def down
    Role.where(name: ROLE_DEFINITIONS.keys).find_each(&:destroy!)
  end
end
