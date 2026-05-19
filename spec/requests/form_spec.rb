# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Form', type: :request do

  describe 'request handling' do

    it 'does get config call' do
      post '/api/v1/form_config', params: {}, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(json_response).to be_a(Hash)
      expect(json_response['error']).to eq('Not authorized')
    end

    it 'does get config call with form_ticket_create' do
      Setting.set('form_ticket_create', true)
      post '/api/v1/form_config', params: {}, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(json_response).to be_a(Hash)
      expect(json_response['error']).to eq('Not authorized')

    end

    it 'does get config call & do submit' do
      Setting.set('form_ticket_create', true)
      fingerprint = SecureRandom.hex(40)
      post '/api/v1/form_config', params: { fingerprint: fingerprint }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response).to be_a(Hash)
      expect(json_response['enabled']).to be(true)
      expect(json_response['endpoint']).to eq('http://zammad.example.com/api/v1/form_submit')
      expect(json_response['token']).to be_truthy
      token = json_response['token']

      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: 'invalid' }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json_response).to be_a(Hash)
      expect(json_response['error']).to eq('Authorization failed')

      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json_response).to be_a(Hash)

      expect(json_response['errors']).to be_truthy
      expect(json_response['errors']['name']).to eq('required')
      expect(json_response['errors']['email']).to eq('required')
      expect(json_response['errors']['title']).to eq('required')
      expect(json_response['errors']['body']).to eq('required')

      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, email: 'some' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json_response).to be_a(Hash)

      expect(json_response['errors']).to be_truthy
      expect(json_response['errors']['name']).to eq('required')
      expect(json_response['errors']['email']).to eq('invalid')
      expect(json_response['errors']['title']).to eq('required')
      expect(json_response['errors']['body']).to eq('required')

      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'discard@zammad.com', title: 'test', body: 'hello' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json_response).to be_a(Hash)

      expect(json_response['errors']).to be_falsey
      expect(json_response['ticket']).to be_truthy
      expect(json_response['ticket']['id']).to be_truthy
      expect(json_response['ticket']['number']).to be_truthy

      travel 5.hours

      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'discard@zammad.com', title: 'test', body: 'hello' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response).to be_a(Hash)

      expect(json_response['errors']).to be_falsey
      expect(json_response['ticket']).to be_truthy
      expect(json_response['ticket']['id']).to be_truthy
      expect(json_response['ticket']['number']).to be_truthy

      travel 20.hours

      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'discard@zammad.com', title: 'test', body: 'hello' }, as: :json
      expect(response).to have_http_status(:unauthorized)

    end

    it 'does get config call & do submit - second test' do
      Setting.set('form_ticket_create', true)
      fingerprint = SecureRandom.hex(40)
      post '/api/v1/form_config', params: { fingerprint: fingerprint }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response).to be_a(Hash)
      expect(json_response['enabled']).to be(true)
      expect(json_response['endpoint']).to eq('http://zammad.example.com/api/v1/form_submit')
      expect(json_response['token']).to be_truthy
      token = json_response['token']

      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: 'invalid' }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json_response).to be_a(Hash)
      expect(json_response['error']).to eq('Authorization failed')

      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json_response).to be_a(Hash)

      expect(json_response['errors']).to be_truthy
      expect(json_response['errors']['name']).to eq('required')
      expect(json_response['errors']['email']).to eq('required')
      expect(json_response['errors']['title']).to eq('required')
      expect(json_response['errors']['body']).to eq('required')

      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, email: 'some' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json_response).to be_a(Hash)

      expect(json_response['errors']).to be_truthy
      expect(json_response['errors']['name']).to eq('required')
      expect(json_response['errors']['email']).to eq('invalid')
      expect(json_response['errors']['title']).to eq('required')
      expect(json_response['errors']['body']).to eq('required')

      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'somebody@somedomainthatisinvalid.com', title: 'test', body: 'hello' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json_response).to be_a(Hash)

      expect(json_response['errors']).to be_truthy
      expect(json_response['errors']['email']).to eq('invalid')

    end

    it 'does limits', :rack_attack do
      Setting.set('form_ticket_create_by_ip_per_hour', 2)
      Setting.set('form_ticket_create', true)
      fingerprint = SecureRandom.hex(40)

      post '/api/v1/form_config', params: { fingerprint: fingerprint }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json_response['token']).to be_truthy
      token = json_response['token']

      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'discard@zammad.com', title: 'test', body: 'hello' }, as: :json
      expect(response).to have_http_status(:ok)

      3.times do |count|
        post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'discard@zammad.com', title: "test#{count}", body: 'hello' }, as: :json
      end
      expect(response).to have_http_status(:too_many_requests)

      @headers = { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '1.2.3.5' }
      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'discard@zammad.com', title: 'test-2', body: 'hello' }, as: :json
      expect(response).to have_http_status(:ok)

      3.times do |count|
        post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'discard@zammad.com', title: "test-2-#{count}", body: 'hello' }, as: :json
      end
      expect(response).to have_http_status(:too_many_requests)

      @headers = { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '::1' }
      post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'discard@zammad.com', title: 'test-3', body: 'hello' }, as: :json

      3.times do |count|
        post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'discard@zammad.com', title: "test-3-#{count}", body: 'hello' }, as: :json
      end
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'does customer_ticket_create false disables form' do
      Setting.set('form_ticket_create', false)
      Setting.set('customer_ticket_create', true)

      fingerprint = SecureRandom.hex(40)

      post '/api/v1/form_config', params: { fingerprint: fingerprint }, as: :json

      token = json_response['token']
      params = {
        fingerprint: fingerprint,
        token:       token,
        name:        'Bob Smith',
        email:       'discard@zammad.com',
        title:       'test',
        body:        'hello'
      }

      post '/api/v1/form_submit', params: params, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    describe 'form_allowed_params Setting', db_strategy: :reset do
      let(:fingerprint) { SecureRandom.hex(40) }
      let(:token)       { json_response['token'] }
      let(:ticket)      { Ticket.find json_response.dig('ticket', 'id') }
      let(:custom_attr) { create(:object_manager_attribute_text) }

      before do
        custom_attr
        ObjectManager::Attribute.migration_execute

        Setting.set('form_allowed_params', form_allowed_params)
        Setting.set('form_ticket_create', true)
        post '/api/v1/form_config', params: { fingerprint: }, as: :json

        post '/api/v1/form_submit', params: {
          fingerprint:,
          token:,
          name:  'Bob Smith',
          email: 'discard@zammad.com',
          title: 'test-last',
          body:  'hello',
          custom_attr.name => 'some note'
        }, as: :json
      end

      context 'when blank' do
        let(:form_allowed_params) { [] }

        it 'rejects additional parameters' do
          expect(ticket).to have_attributes(custom_attr.name => be_blank)
        end
      end

      context 'when present' do
        let(:form_allowed_params) { [custom_attr.name] }

        it 'allows additional parameters' do
          expect(ticket).to have_attributes(custom_attr.name => 'some note')
        end
      end
    end

    context 'when ApplicationHandleInfo context' do
      let(:fingerprint) { SecureRandom.hex(40) }
      let(:token)       { json_response['token'] }

      before do
        allow(ApplicationHandleInfo).to receive('context=')
        Setting.set('form_ticket_create', true)
        post '/api/v1/form_config', params: { fingerprint: fingerprint }, as: :json
      end

      it 'gets switched to "form"' do
        post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'discard@zammad.com', title: 'test-last', body: 'hello' }, as: :json
        expect(ApplicationHandleInfo).to have_received('context=').with('form').at_least(1)
      end

      it 'reverts back to default' do
        post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'discard@zammad.com', title: 'test-last', body: 'hello' }, as: :json
        expect(ApplicationHandleInfo.context).not_to eq 'form'
      end

      context 'when form_allowed_params is not blank' do
        before do
          Setting.set('form_allowed_params', %w[note])
        end

        it 'does not switch context to "form"' do
          post '/api/v1/form_submit', params: { fingerprint: fingerprint, token: token, name: 'Bob Smith', email: 'discard@zammad.com', title: 'test-last', body: 'hello' }, as: :json
          expect(ApplicationHandleInfo).not_to have_received('context=').with('form')
        end
      end
    end

    describe 'Dom-Servis intake bridge', db_strategy: :reset do
      let(:fingerprint)  { SecureRandom.hex(40) }
      let(:token)        { json_response['token'] }
      let(:group)        { create(:group, name: '000 Intake Bridge Group') }
      let(:partner_org)  { create(:organization, name: 'Dom-Servis Partner Org') }
      let(:forged_org)   { create(:organization, name: 'Forged Org') }

      before do
        Setting.set('form_ticket_create', true)
        Setting.set('form_ticket_create_group_id', group.id)
        Setting.set('form_allowed_params', %w[
          organization_id
          dom_servis_service_type
          dom_servis_address
          dom_servis_client_name
          dom_servis_client_phone
          dom_servis_visit_day
          dom_servis_visit_date
          dom_servis_visit_time
          dom_servis_dispatch_priority
          dom_servis_description
          dom_servis_comment
          dom_servis_work_tags
        ])
        Setting.set('dom_servis_form_intake_enabled', true)
        Setting.set('dom_servis_form_organization_id', partner_org.id)

        post '/api/v1/form_config', params: { fingerprint: fingerprint }, as: :json
      end

      it 'creates a dispatch job from the form ticket and binds the configured partner organization' do
        params = {
          fingerprint: fingerprint,
          token:       token,
          name:        'Bob Smith',
          email:       'discard@zammad.com',
          title:       'Need help with boiler',
          body:        'The boiler is leaking and needs inspection.',
          organization_id: forged_org.id,
          dom_servis_service_type: 'Boiler repair',
          dom_servis_address:      'Lenina 10',
          dom_servis_client_name:   'Bob Smith',
          dom_servis_client_phone:  '+79001234567',
          dom_servis_visit_day:     'mon',
          dom_servis_visit_date:    '2026-03-23',
          dom_servis_visit_time:    '10:00-12:00',
          dom_servis_dispatch_priority: 'high',
          dom_servis_description:   'Need replacement and inspection.',
          dom_servis_comment:       'Call before arrival',
          dom_servis_work_tags:     'boiler,urgent',
        }

        post '/api/v1/form_submit', params: params, as: :json

        expect(response).to have_http_status(:ok)
        expect(json_response).to be_a(Hash)
        expect(json_response['errors']).to be_falsey
        expect(json_response['ticket']).to be_truthy

        ticket = Ticket.find(json_response['ticket']['id'])
        job = DomServis::DispatchJob.find_by(ticket_id: ticket.id)

        expect(job).to be_persisted
        expect(job.organization_id).to eq(partner_org.id)
        expect(job.source).to eq('form')
        expect(job.source_reference).to eq(ticket.number)
        expect(job.intake_channel_key).to eq('zammad_form')
        expect(job.intake_payload).to be_a(Hash)
        expect(job.intake_payload['ticket_number']).to eq(ticket.number)
        expect(job.service_type).to eq('Boiler repair')
        expect(job.address).to eq('Lenina 10')
        expect(job.work_tags).to eq(%w[boiler urgent])
        expect(ticket.preferences.dig('dom_servis_intake', 'partner_org_id')).to eq(partner_org.id)
        expect(ticket.dom_servis_dispatch_source).to eq('form')
        expect(ticket.dom_servis_dispatch_priority).to eq('high')
        expect(ticket.dom_servis_service_type).to eq('Boiler repair')
        expect(ticket.preferences.dig('dom_servis_intake', 'source')).to eq('form')
      end
    end
  end
end
