# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class DomServis::Dispatch::JobsController < DomServis::Dispatch::BaseController
  def index
    model_index_render(dispatch_job_scope.ordered_recent, params)
  end

  def show
    model_show_render(dispatch_job_scope, params)
  end

  def create
    job = DomServis::DispatchJob.new(job_create_params)
    authorize job, :create?
    ensure_action_allowed!('create_job')
    ensure_action_allowed!('publish_to_pool') if job.status == 'pool'
    job.save!

    create_event!(job, 'created', source: job.source)
    create_event!(job, 'published') if job.status == 'pool'

    model_item_render(job, status: :created)
  end

  def update
    job = dispatch_job_scope.find(params[:id])
    authorize job, :update?
    ensure_action_allowed!('edit_all_fields')
    ensure_fields_editable!(job_update_params.keys)
    ensure_update_actions_allowed!(job, job_update_params)

    tracked_changes = collect_tracked_changes(job, job_update_params)
    job.update!(job_update_params)

    tracked_changes.each do |event_type, meta|
      create_event!(job, event_type, meta)
    end

    create_event!(job, 'updated') if tracked_changes.blank?

    model_item_render(job)
  end

  def destroy
    job = dispatch_job_scope.find(params[:id])
    authorize job, :destroy?
    ensure_action_allowed!('delete_job')
    job.destroy!

    model_destroy_render_item
  end

  def take
    job = dispatch_job_scope.find(params[:id])
    authorize job, :take?
    ensure_action_allowed!('take_job')

    conflict = nil

    job.with_lock do
      if job.assignee_id.present? && job.assignee_id != current_user.id
        conflict = job
        next
      end

      job.update!(
        assignee_id: current_user.id,
        status:      job.status == 'pool' ? 'taken' : job.status,
        taken_at:    job.taken_at || Time.zone.now,
      )
      create_event!(job, 'taken')
    end

    if conflict
      render json: conflict.attributes_with_association_ids, status: :conflict
      return
    end

    model_item_render(job)
  end

  def release
    job = dispatch_job_scope.find(params[:id])
    authorize job, :release?
    ensure_action_allowed!('release_to_pool')

    job.with_lock do
      job.update!(
        assignee_id: nil,
        status:      'pool',
        taken_at:    nil,
      )
      create_event!(job, 'released')
    end

    model_item_render(job)
  end

  def update_status
    job = dispatch_job_scope.find(params[:id])
    authorize job, :update_status?

    status = params.require(:status).to_s
    raise Exceptions::UnprocessableEntity, 'Invalid dispatch job status.' if !DomServis::DispatchJob::STATUSES.include?(status)
    ensure_status_allowed!(status)
    ensure_action_allowed!('cancel_job') if status == 'cancelled'
    ensure_action_allowed!('set_status_in_progress') if status == 'in_progress'
    ensure_action_allowed!('set_status_done') if status == 'done'
    ensure_action_allowed!('reopen_job') if %w[pool taken].include?(status) && job.status.in?(%w[done cancelled])

    job.with_lock do
      job.update!(status: status)
      create_event!(job, 'status_changed', to: status)
    end

    model_item_render(job)
  end

  def move_day
    job = dispatch_job_scope.find(params[:id])
    authorize job, :update?
    ensure_action_allowed!('move_job_day')
    ensure_field_editable!('visit_day')

    visit_day = params.require(:visit_day).to_s
    raise Exceptions::UnprocessableEntity, 'Invalid dispatch visit day.' if !DomServis::DispatchJob::VISIT_DAYS.include?(visit_day)

    updates = {
      visit_day:,
      visit_date: params[:visit_date].presence || job.visit_date,
    }

    job.with_lock do
      job.update!(updates)
      create_event!(job, 'moved_weekday', from: job.visit_day_before_last_save, to: job.visit_day)
    end

    model_item_render(job)
  end

  def change_priority
    job = dispatch_job_scope.find(params[:id])
    authorize job, :update?
    ensure_action_allowed!('change_priority')
    ensure_field_editable!('priority')

    priority = params.require(:priority).to_s
    raise Exceptions::UnprocessableEntity, 'Invalid dispatch job priority.' if !DomServis::DispatchJob::PRIORITIES.include?(priority)

    job.with_lock do
      job.update!(priority:)
      create_event!(job, 'priority_changed', from: job.priority_before_last_save, to: job.priority)
    end

    model_item_render(job)
  end

  def parse_input
    input = params.require(:input).to_s.strip
    raise Exceptions::UnprocessableEntity, 'No input submitted.' if input.blank?
    ensure_action_allowed!('create_job')

    render json: {
      draft: {
        service_type: infer_service_type(input),
        address:      'Address to be confirmed',
        description:  input,
        priority:     infer_priority(input),
        status:       'pool',
        source:       'ai',
      }
    }, status: :ok
  end

  private

  def job_create_params
    permitted_job_params.merge(
      status:       permitted_job_params[:status].presence || 'pool',
      source:       permitted_job_params[:source].presence || 'manual',
      published_at: permitted_job_params[:published_at].presence || Time.zone.now,
    )
  end

  def job_update_params
    permitted_job_params
  end

  def permitted_job_params
    params.permit(
      :assignee_id,
      :organization_id,
      :ticket_id,
      :status,
      :priority,
      :visit_day,
      :service_type,
      :client_name,
      :client_phone,
      :address,
      :visit_date,
      :visit_time,
      :description,
      :comment,
      :source,
      :published_at,
      :taken_at,
      :completed_at,
      :cancelled_at,
      work_tags: []
    )
  end

  def collect_tracked_changes(job, updates)
    {}.tap do |changes|
      if updates[:priority].present? && updates[:priority] != job.priority
        changes['priority_changed'] = { from: job.priority, to: updates[:priority] }
      end

      if updates[:status].present? && updates[:status] != job.status
        changes['status_changed'] = { from: job.status, to: updates[:status] }
      end

      if updates[:visit_day].present? && updates[:visit_day] != job.visit_day
        changes['moved_weekday'] = { from: job.visit_day, to: updates[:visit_day] }
      end

      if updates[:comment].present? && updates[:comment] != job.comment
        changes['comment_added'] = { comment: updates[:comment] }
      end

      if updates.key?(:organization_id) && normalized_assignee_id(updates[:organization_id]) != normalized_assignee_id(job.organization_id)
        changes['organization_changed'] = { from: job.organization_id, to: updates[:organization_id] }
      end

      if updates[:work_tags].present? && updates[:work_tags] != job.work_tags
        changes['tags_changed'] = { to: updates[:work_tags] }
      end
    end
  end

  def create_event!(job, event_type, meta = {})
    DomServis::DispatchEvent.create!(
      dispatch_job: job,
      actor_user:   current_user,
      event_type:,
      meta:         meta,
    )
  end

  def infer_priority(input)
    lowered = input.downcase
    return 'critical' if lowered.match?(/авар|сроч|горит|замерз|затоп|ошибк/i)

    'medium'
  end

  def infer_service_type(input)
    lowered = input.downcase
    return 'Plumbing' if lowered.match?(/кран|смесител|вода|сантех/i)
    return 'Boiler' if lowered.match?(/кот[её]л|отоплен|газ/i)
    return 'Electrical' if lowered.match?(/розет|свет|элект|люстр/i)

    'General Service'
  end

  def master_access?
    current_user.permissions?('dom_servis.master') && !dispatcher_access?
  end

  def dispatcher_access?
    current_user.permissions?('dom_servis.admin') || current_user.permissions?('dom_servis.dispatcher')
  end

  def ensure_action_allowed!(action_key)
    return true if DomServis::DispatchPolicy.action_allowed?(current_user, action_key)

    raise Exceptions::Forbidden, "Dispatch action '#{action_key}' is not allowed for the current role."
  end

  def ensure_status_allowed!(status_key)
    return true if DomServis::DispatchPolicy.status_allowed?(current_user, status_key)

    raise Exceptions::Forbidden, "Dispatch status '#{status_key}' is not allowed for the current role."
  end

  def ensure_fields_editable!(field_names)
    Array(field_names).each do |field_name|
      ensure_field_editable!(field_name)
    end
  end

  def ensure_field_editable!(field_name)
    return true if DomServis::DispatchPolicy.editable_field?(current_user, field_name)

    raise Exceptions::Forbidden, "Dispatch field '#{field_name}' is not editable for the current role."
  end

  def ensure_update_actions_allowed!(job, updates)
    updates = updates.to_h.deep_symbolize_keys
    return if updates.blank?

    if updates[:status].present? && updates[:status] != job.status
      status = updates[:status].to_s

      raise Exceptions::UnprocessableEntity, 'Invalid dispatch job status.' if !DomServis::DispatchJob::STATUSES.include?(status)

      ensure_status_allowed!(status)
      ensure_action_allowed!('cancel_job') if status == 'cancelled'
      ensure_action_allowed!('set_status_in_progress') if status == 'in_progress'
      ensure_action_allowed!('set_status_done') if status == 'done'
      ensure_action_allowed!('reopen_job') if %w[pool taken].include?(status) && job.status.in?(%w[done cancelled])
    end

    if updates[:priority].present? && updates[:priority] != job.priority
      ensure_action_allowed!('change_priority')
    end

    if updates.key?(:assignee_id) && normalized_assignee_id(updates[:assignee_id]) != normalized_assignee_id(job.assignee_id)
      ensure_action_allowed!('change_assignee')
    end

    if updates.key?(:comment) && updates[:comment].to_s != job.comment.to_s
      ensure_action_allowed!('add_comment')
    end

    ensure_schedule_update_allowed!(job, updates)
  end

  def ensure_schedule_update_allowed!(job, updates)
    visit_day_changed  = updates.key?(:visit_day) && updates[:visit_day].to_s != job.visit_day.to_s
    visit_date_changed = updates.key?(:visit_date) && updates[:visit_date].to_s != job.visit_date.to_s
    return if !visit_day_changed && !visit_date_changed

    old_date = parse_dispatch_date(job.visit_date)
    new_date = parse_dispatch_date(updates[:visit_date].presence || job.visit_date)

    if visit_date_changed && (!old_date || !new_date || week_start_for(old_date) != week_start_for(new_date))
      ensure_action_allowed!('move_job_week')
      return
    end

    ensure_action_allowed!('move_job_day')
  end

  def normalized_assignee_id(value)
    return nil if value.blank?

    value.to_i
  end

  def parse_dispatch_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def week_start_for(date)
    date.beginning_of_week(:monday)
  end
end
