# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class DomServis::Intake::TicketAdapter
  DEFAULT_CHANNEL_KEY = 'zammad_form'.freeze

  def initialize(ticket:, organization_id:, source: 'form', channel_key: DEFAULT_CHANNEL_KEY, source_reference: nil)
    @ticket = ticket
    @organization_id = organization_id
    @source = source.to_s
    @channel_key = channel_key.to_s
    @source_reference = source_reference
  end

  attr_reader :ticket, :organization_id, :source, :channel_key, :source_reference

  def payload
    {
      source:            source,
      source_reference:  source_reference.presence || ticket.number,
      partner_org_id:    organization.id,
      channel_key:       channel_key.presence || DEFAULT_CHANNEL_KEY,
      raw_payload:       raw_payload,
      dispatch:          dispatch_attributes,
    }
  end

  private

  def dispatch_attributes
    {
      source:          source,
      organization_id: organization.id,
      service_type:    ticket_value(:dom_servis_service_type).presence || ticket.title,
      address:         required_ticket_value(:dom_servis_address),
      client_name:     ticket_value(:dom_servis_client_name).presence || ticket.customer&.fullname || ticket.customer&.login || ticket.customer&.email,
      client_phone:    ticket_value(:dom_servis_client_phone).presence || ticket.customer&.phone,
      visit_day:       ticket_value(:dom_servis_visit_day).presence,
      visit_date:      ticket_value(:dom_servis_visit_date).presence,
      visit_time:      ticket_value(:dom_servis_visit_time).presence,
      priority:        ticket_value(:dom_servis_dispatch_priority).presence || 'medium',
      description:     ticket_value(:dom_servis_description).presence || ticket_body,
      comment:         ticket_value(:dom_servis_comment).presence,
      work_tags:       normalize_work_tags(ticket_value(:dom_servis_work_tags)),
    }.compact
  end

  def raw_payload
    {
      ticket_id:      ticket.id,
      ticket_number:  ticket.number,
      ticket_title:   ticket.title,
      ticket_body:    ticket_body,
      customer_id:    ticket.customer_id,
      organization_id: organization_id,
      form_fields:    {
        dom_servis_service_type:    ticket_value(:dom_servis_service_type),
        dom_servis_address:         ticket_value(:dom_servis_address),
        dom_servis_client_name:     ticket_value(:dom_servis_client_name),
        dom_servis_client_phone:    ticket_value(:dom_servis_client_phone),
        dom_servis_visit_day:       ticket_value(:dom_servis_visit_day),
        dom_servis_visit_date:      ticket_value(:dom_servis_visit_date),
        dom_servis_visit_time:      ticket_value(:dom_servis_visit_time),
        dom_servis_dispatch_priority: ticket_value(:dom_servis_dispatch_priority),
        dom_servis_description:     ticket_value(:dom_servis_description),
        dom_servis_comment:         ticket_value(:dom_servis_comment),
        dom_servis_work_tags:       ticket_value(:dom_servis_work_tags),
      },
    }
  end

  def ticket_body
    ticket.articles.reorder(:created_at, :id).last&.body.presence
  end

  def organization
    @organization ||= Organization.find_by(id: organization_id) || raise(Exceptions::UnprocessableEntity, 'Dom-Servis intake requires a configured partner organization.')
  end

  def required_ticket_value(field_name)
    value = ticket_value(field_name).presence
    return value if value.present?

    raise Exceptions::UnprocessableEntity, "Dom-Servis intake requires the '#{field_name}' field."
  end

  def ticket_value(field_name)
    return nil if !ticket.respond_to?(field_name)

    ticket.public_send(field_name)
  end

  def normalize_work_tags(value)
    tags =
      case value
      when Array
        value
      when String
        value.split(',')
      else
        []
      end

    tags.filter_map do |tag_name|
      normalized = tag_name.to_s.strip
      normalized.presence
    end.uniq.first(10)
  end
end
