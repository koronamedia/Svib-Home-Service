# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class AddDomServisAdminRole < ActiveRecord::Migration[7.2]
  SYSTEM_USER_ID = 1

  def up
    role = Role.find_or_initialize_by(name: 'Dom-Servis Admin')
    role.active        = true
    role.note          = 'Assign together with Admin. Grants the Dom-Servis administrative workspace and dispatch policy controls.'
    role.created_by_id ||= SYSTEM_USER_ID
    role.updated_by_id = SYSTEM_USER_ID
    role.permission_grant('dom_servis.admin')
    role.save! if role.changed?
  end

  def down
    Role.find_by(name: 'Dom-Servis Admin')&.destroy!
  end
end
