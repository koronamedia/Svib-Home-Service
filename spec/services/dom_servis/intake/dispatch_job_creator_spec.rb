# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe DomServis::Intake::DispatchJobCreator do
  let(:group)         { create(:group, name: '000 Intake Group') }
  let(:dispatcher)    { create(:agent, groups: [group]) }
  let(:partner_org)   { create(:organization, name: 'Partner Org') }
  let(:forged_org)    { create(:organization, name: 'Forged Org') }
  let(:customer)      { create(:customer) }
  let(:base_ticket) do
    Ticket.create!(
      group:               group,
      customer:            customer,
      organization:        forged_org,
      title:               'Boiler repair request',
      preferences:         { form: { remote_ip: '127.0.0.1', fingerprint_md5: 'abc123' } },
      dom_servis_service_type:    'Boiler repair',
      dom_servis_address:         'Lenina 10',
      dom_servis_client_name:     'Ivan Petrov',
      dom_servis_client_phone:    '+79001234567',
      dom_servis_visit_day:       'mon',
      dom_servis_visit_date:      '2026-03-23',
      dom_servis_visit_time:      '10:00-12:00',
      dom_servis_dispatch_priority: 'high',
      dom_servis_description:     'Initial intake description',
      dom_servis_comment:         'Call before arrival',
      dom_servis_work_tags:       'boiler,urgent',
    )
  end

  let(:payload) do
    DomServis::Intake::TicketAdapter.new(
      ticket:          base_ticket,
      organization_id: partner_org.id,
      source:          'form',
      channel_key:     'zammad_form',
      source_reference: base_ticket.number,
    ).payload
  end

  it 'creates a dispatch job from the canonical intake payload and syncs the ticket' do
    job = described_class.new(payload:, ticket: base_ticket, actor_user: dispatcher).execute

    expect(job).to be_persisted
    expect(job.ticket_id).to eq(base_ticket.id)
    expect(job.organization_id).to eq(partner_org.id)
    expect(job.source).to eq('form')
    expect(job.source_reference).to eq(base_ticket.number)
    expect(job.intake_channel_key).to eq('zammad_form')
    expect(job.intake_payload).to be_a(Hash)
    expect(job.intake_payload['ticket_number']).to eq(base_ticket.number)
    expect(job.service_type).to eq('Boiler repair')
    expect(job.address).to eq('Lenina 10')
    expect(job.client_name).to eq('Ivan Petrov')
    expect(job.client_phone).to eq('+79001234567')
    expect(job.priority).to eq('high')
    expect(job.work_tags).to eq(%w[boiler urgent])

    ticket = base_ticket.reload
    expect(ticket.dom_servis_dispatch_source).to eq('form')
    expect(ticket.dom_servis_dispatch_priority).to eq('high')
    expect(ticket.dom_servis_service_type).to eq('Boiler repair')
    expect(ticket.preferences.dig('dom_servis_intake', 'source')).to eq('form')
    expect(ticket.preferences.dig('dom_servis_intake', 'partner_org_id')).to eq(partner_org.id)
  end

  it 'is idempotent for the same ticket' do
    first = described_class.new(payload:, ticket: base_ticket, actor_user: dispatcher).execute
    second = described_class.new(payload:, ticket: base_ticket, actor_user: dispatcher).execute

    expect(second.id).to eq(first.id)
    expect(DomServis::DispatchJob.count).to eq(1)
  end

  it 'creates a direct dispatch job without a backing ticket for non-native sources' do
    payload = {
      source:           'ai',
      partner_org_id:   partner_org.id,
      channel_key:      'ai_service',
      source_reference: 'ai-request-001',
      raw_payload:      { input: 'Boiler leak in apartment 42' },
      dispatch:         {
        source:          'ai',
        organization_id: partner_org.id,
        service_type:    'Boiler repair',
        address:         'Lenina 10',
        client_name:     'Ivan Petrov',
        client_phone:    '+79001234567',
        priority:        'medium',
        description:     'Boiler leak in apartment 42',
      },
    }

    job = described_class.new(payload:, actor_user: dispatcher).execute

    expect(job).to be_persisted
    expect(job.ticket_id).to be_nil
    expect(job.source).to eq('ai')
    expect(job.source_reference).to eq('ai-request-001')
    expect(job.intake_channel_key).to eq('ai_service')
    expect(job.intake_payload).to eq({ 'input' => 'Boiler leak in apartment 42' })
    expect(job.organization_id).to eq(partner_org.id)
    expect(job.service_type).to eq('Boiler repair')
    expect(job.address).to eq('Lenina 10')
  end

  it 'is idempotent for the same external source reference' do
    direct_payload = {
      source:           'webhook',
      partner_org_id:   partner_org.id,
      channel_key:      'partner_webhook',
      source_reference: 'webhook-request-001',
      raw_payload:      { ticket: 'external-123' },
      dispatch:         {
        source:          'webhook',
        organization_id: partner_org.id,
        service_type:    'Boiler repair',
        address:         'Lenina 10',
      },
    }

    first = described_class.new(payload: direct_payload, actor_user: dispatcher).execute
    second = described_class.new(payload: direct_payload, actor_user: dispatcher).execute

    expect(second.id).to eq(first.id)
    expect(DomServis::DispatchJob.count).to eq(1)
  end
end
