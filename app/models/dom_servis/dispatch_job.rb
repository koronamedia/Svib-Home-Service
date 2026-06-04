# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class DomServis::DispatchJob < ApplicationModel
  include ApplicationModel::HasAttachments

  self.table_name = 'dom_servis_dispatch_jobs'

  STATUSES   = %w[pool taken in_progress done cancelled transferred_to_partner].freeze
  PRIORITIES = %w[low medium high critical].freeze
  SOURCES    = %w[manual form email webhook ai].freeze
  VISIT_DAYS = %w[mon tue wed thu fri sat sun].freeze
  ATTACHMENT_KINDS = %w[intake_attachment route_info completion_act diagnostic_photo other].freeze

  VISIT_DAY_LABELS = {
    'mon' => 'Пн',
    'tue' => 'Вт',
    'wed' => 'Ср',
    'thu' => 'Чт',
    'fri' => 'Пт',
    'sat' => 'Сб',
    'sun' => 'Вс',
  }.freeze

  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :ticket, optional: true
  belongs_to :organization, optional: true
  belongs_to :request_source, class_name: 'DomServis::RequestSource', optional: true

  has_many :events,
           class_name: 'DomServis::DispatchEvent',
           foreign_key: :dispatch_job_id,
           inverse_of: :dispatch_job,
           dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: PRIORITIES }
  validates :source, inclusion: { in: SOURCES }
  validates :visit_day, inclusion: { in: VISIT_DAYS }
  validates :service_type, presence: true
  validates :address, presence: true

  attachments_cleanup!

  before_validation :apply_defaults
  before_validation :assign_job_code
  before_validation :normalize_work_tags
  before_validation :normalize_intake_metadata
  before_validation :sync_lifecycle_timestamps
  after_commit :notify_dispatch_board_created, on: :create
  after_commit :notify_dispatch_board_updated, on: :update
  after_commit :notify_dispatch_board_destroyed, on: :destroy

  scope :ordered_recent, -> { order(created_at: :desc, id: :desc) }
  scope :pool_visible, -> { where(status: 'pool', assignee_id: nil) }

  def self.search(query:, limit: 50, offset: 0, **)
    scoped = ordered_recent
    if query.present?
      like_query = "%#{query}%"
      scoped = scoped.where(
        'service_type ILIKE :query OR address ILIKE :query OR client_name ILIKE :query OR client_phone ILIKE :query',
        query: like_query
      )
    end

    {
      objects:     scoped.offset(offset).limit(limit),
      total_count: scoped.count,
    }
  end

  def ui_url
    "#manage/dom_servis_dispatch/id:#{id}"
  end

  def attributes_with_association_ids
    super.merge(
      request_source_label: request_source&.display_name,
      request_source_partner_key: request_source&.partner_key,
      request_source_transport_kind: request_source&.transport_kind,
    ).compact
  end

  private

  def notify_dispatch_board_created
    notify_dispatch_board_clients(:create)
  end

  def notify_dispatch_board_updated
    notify_dispatch_board_clients(:update)
  end

  def notify_dispatch_board_destroyed
    notify_dispatch_board_clients(:destroy)
  end

  def notify_dispatch_board_clients(event)
    PushMessages.send(
      message: {
        event: "#{self.class.name.gsub('::', '')}:#{event}",
        data:  {
          id:         id,
          updated_at: updated_at,
        },
      },
      type: 'authenticated',
    )
  end

  def apply_defaults
    self.status = 'pool' if status.blank?
    self.priority = 'medium' if priority.blank?
    self.source = 'manual' if source.blank?
    self.visit_day = infer_visit_day if visit_day.blank?
    self.organization_id ||= self.class.private_organization_id
    self.published_at ||= Time.zone.now if status == 'pool'
  end

  def assign_job_code
    return if job_code.present?

    timestamp = created_at || Time.zone.now

    loop do
      candidate = "#{timestamp.strftime('%Y%m%d')}-#{format('%04d', SecureRandom.random_number(10_000))}"
      next if self.class.exists?(job_code: candidate)

      self.job_code = candidate
      return
    end
  end

  def normalize_work_tags
    tags =
      case work_tags
      when Array
        work_tags
      when String
        work_tags.split(',')
      else
        []
      end

    self.work_tags = tags.filter_map do |value|
      normalized = value.to_s.strip
      normalized.presence
    end.uniq.first(10)
  end

  def normalize_intake_metadata
    self.source_reference = source_reference.presence
    self.intake_channel_key = intake_channel_key.presence
    self.intake_payload = intake_payload.presence || {}
  end

  def sync_lifecycle_timestamps
    self.taken_at = nil if status == 'pool'
    self.completed_at = nil if status != 'done'
    self.cancelled_at = nil if status != 'cancelled'

    self.taken_at ||= Time.zone.now if %w[taken in_progress done].include?(status) && assignee_id.present?
    self.completed_at ||= Time.zone.now if status == 'done'
    self.cancelled_at ||= Time.zone.now if status == 'cancelled'
  end

  def infer_visit_day
    return weekday_key_from_date(visit_date) if visit_date.present?

    case (created_at || Time.zone.now).wday
    when 1 then 'mon'
    when 2 then 'tue'
    when 3 then 'wed'
    when 4 then 'thu'
    when 5 then 'fri'
    when 6 then 'sat'
    else 'sun'
    end
  end

  def weekday_key_from_date(value)
    parsed_date = Date.parse(value.to_s)

    case parsed_date.wday
    when 1 then 'mon'
    when 2 then 'tue'
    when 3 then 'wed'
    when 4 then 'thu'
    when 5 then 'fri'
    when 6 then 'sat'
    else 'sun'
    end
  rescue ArgumentError
    'mon'
  end

  class << self
    def private_organization
      Organization.find_by(name: 'Частный заказ') || create_private_organization
    end

    def private_organization_id
      private_organization&.id
    end

    private

    def create_private_organization
      system_user = User.order(:id).first
      return nil if !system_user

      Organization.create_with(
        active:        true,
        shared:        false,
        note:          'System organization for direct Dom-Servis retail jobs.',
        created_by_id: system_user.id,
        updated_by_id: system_user.id,
      ).find_or_create_by!(name: 'Частный заказ')
    end
  end
end
