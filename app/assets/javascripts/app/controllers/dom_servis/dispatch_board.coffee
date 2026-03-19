class App.DomServisDispatchBoard extends App.Controller
  className: 'dom-servis-dispatch-board'

  events:
    'click .js-status-filter': 'setStatusFilter'
    'click .js-day-filter': 'setDayFilter'
    'click .js-week-shift': 'shiftWeek'
    'click .js-week-reset': 'resetWeek'
    'change .js-week-picker': 'pickWeek'
    'click .js-open-create': 'openCreate'
    'click .js-close-create': 'closeCreate'
    'click .js-open-edit': 'openEdit'
    'click .js-close-edit': 'closeEdit'
    'click .js-refresh-jobs': 'refreshJobs'
    'click .js-create-job': 'createJob'
    'click .js-save-edit': 'saveEdit'
    'click .js-take-job': 'takeJob'
    'click .js-release-job': 'releaseJob'
    'click .js-set-status': 'setStatus'
    'change .js-change-priority': 'changePriority'
    'change .js-change-visit-day': 'changeVisitDay'

  constructor: ->
    super

    @statusFilter = 'open'
    @dayFilter = 'all'
    @selectedWeekStart = @startOfWeek(new Date())
    @effectivePolicy = null
    @policyRegistry = {}
    @jobs = []
    @loading = true
    @errorMessage = null
    @createOpen = false
    @editOpen = false
    @editingJobId = null
    @editSaving = false

    @render()
    @loadEffectivePolicy()
    @loadJobs()

  active: (state) =>
    return @shown if state is undefined
    @shown = state

  changed: ->
    false

  show: =>
    @title 'Диспетчеризация'
    @navupdate '#dom_servis/dispatch'
    @render() if !@loading

  render: ->
    defaultVisitDay = @defaultVisitDay()
    editJob = @currentEditJob()

    @html App.view('dom_servis_dispatch/board')(
      loading: @loading
      error: @errorMessage
      dispatcherAccess: @dispatcherAccess()
      masterAccess: @masterAccess()
      roleLabel: @roleLabel()
      canCreateJob: @canCreatePublishedJob()
      stats: @buildStats()
      statusFilters: @buildScopedStatusFilters()
      weekControls: @buildWeekControls()
      dayFilters: @buildDayFilters()
      createOpen: @createOpen
      editOpen: @editOpen
      editSaving: @editSaving
      editJob: @buildEditJobView(editJob)
      editGroups: @buildEditGroups(editJob)
      jobCards: @buildJobCards()
      defaultVisitDay: defaultVisitDay
      defaultVisitDate: @nextDateForDay(defaultVisitDay)
      todayLabel: @weekdayLabel(defaultVisitDay)
    )

  loadJobs: =>
    @loading = true
    @errorMessage = null
    @render()

    @ajax(
      id: 'dom_servis_dispatch_board_index'
      type: 'GET'
      url: "#{@apiPath}/dom_servis/dispatch/jobs"
      data:
        expand: true
        per_page: 200
        sort_by: 'created_at,id'
        order_by: 'DESC,DESC'
      processData: true
      success: (data) =>
        @jobs = @sortJobs(data || [])
        @loading = false
        @render()
      error: (xhr) =>
        @jobs = []
        @loading = false
        @errorMessage = @extractError(xhr, 'Не удалось загрузить заявки диспетчеризации.')
        @render()
    )

  loadEffectivePolicy: =>
    @ajax(
      id: 'dom_servis_dispatch_effective_policy'
      type: 'GET'
      url: "#{@apiPath}/dom_servis/dispatch/policy"
      success: (data) =>
        data ||= {}
        @policyRegistry = data.registry || {}
        @effectivePolicy =
          role_key: data.role_key
          actions: data.actions || {}
          statuses: data.statuses || {}
          fields: data.fields || {}
        @render() if !@loading
      error: =>
        @policyRegistry = {}
        @effectivePolicy = null
        @render() if !@loading
    )

  refreshJobs: (e) =>
    @preventDefault(e)
    @loadEffectivePolicy()
    @loadJobs()

  setStatusFilter: (e) =>
    @preventDefault(e)
    @statusFilter = $(e.currentTarget).data('filter')
    @render()

  setDayFilter: (e) =>
    @preventDefault(e)
    @dayFilter = $(e.currentTarget).data('filter')
    @render()

  shiftWeek: (e) =>
    @preventDefault(e)
    offset = parseInt($(e.currentTarget).data('offset'), 10) || 0
    @selectedWeekStart = @shiftDate(@selectedWeekStartDate(), offset * 7)
    @dayFilter = 'all'
    @render()

  resetWeek: (e) =>
    @preventDefault(e)
    @selectedWeekStart = @startOfWeek(new Date())
    @dayFilter = 'all'
    @render()

  pickWeek: (e) =>
    pickedDate = @parseDateValue($(e.currentTarget).val())
    return if !pickedDate

    @selectedWeekStart = @startOfWeek(pickedDate)
    @dayFilter = 'all'
    @render()

  openCreate: (e) =>
    @preventDefaultAndStopPropagation(e)
    return if !@canCreatePublishedJob()
    @editOpen = false
    @editingJobId = null
    @createOpen = true
    @render()

  closeCreate: (e) =>
    @preventDefaultAndStopPropagation(e)
    @createOpen = false
    @render()

  openEdit: (e) =>
    @preventDefaultAndStopPropagation(e)
    id = $(e.currentTarget).data('id')
    job = @findJob(id)
    return if !job
    return if !@canOpenEdit(job)

    @createOpen = false
    @editingJobId = job.id
    @editOpen = true
    @editSaving = false
    @render()

  closeEdit: (e) =>
    @preventDefaultAndStopPropagation(e) if e
    @editOpen = false
    @editingJobId = null
    @editSaving = false
    @render()

  createJob: (e) =>
    e.preventDefault()
    return if !@canCreatePublishedJob()

    payload = @createPayload()
    return if !payload

    @formDisable(@$('.js-create-job'), 'button')

    job = new App.DomServisDispatchJob(payload)
    ui = @

    job.save(
      done: ->
        ui.notify(
          type: 'success'
          msg: 'Заявка создана и опубликована в пул.'
          timeout: 3000
        )
        ui.createOpen = false
        ui.dayFilter = payload.visit_day || 'all'
        ui.selectedWeekStart = ui.startOfWeek(ui.parseDateValue(payload.visit_date) || new Date())
        ui.loadJobs()
      fail: (settings, details) ->
        ui.formEnable(ui.$('.js-create-job'), 'button')
        ui.notify(
          type: 'error'
          msg: details.error_human || details.error || 'Заявку не удалось создать.'
          timeout: 6000
        )
    )

  saveEdit: (e) =>
    e.preventDefault()
    job = @currentEditJob()
    return if !job
    return if !@canOpenEdit(job)

    payload = @buildEditPayload(job)
    return if payload is false

    if _.isEmpty(payload)
      @notify(type: 'success', msg: 'Изменений нет.', timeout: 2500)
      return

    @editSaving = true
    @formDisable(@$('.js-save-edit'), 'button')

    @ajax(
      id: "dom_servis_dispatch_update_#{job.id}"
      type: 'PUT'
      url: "#{@apiPath}/dom_servis/dispatch/jobs/#{job.id}"
      data: JSON.stringify(payload)
      processData: true
      success: =>
        @notify(type: 'success', msg: 'Заявка сохранена.', timeout: 3000)
        @editOpen = false
        @editingJobId = null
        @editSaving = false
        @loadJobs()
      error: (xhr) =>
        @editSaving = false
        @formEnable(@$('.js-save-edit'), 'button')
        @notify(type: 'error', msg: @extractError(xhr, 'Не удалось сохранить заявку.'), timeout: 6000)
    )

  takeJob: (e) =>
    @preventDefault(e)
    return if !@actionAllowed('take_job')
    id = $(e.currentTarget).data('id')
    return if !id

    @ajax(
      id: "dom_servis_dispatch_take_#{id}"
      type: 'POST'
      url: "#{@apiPath}/dom_servis/dispatch/jobs/#{id}/take"
      success: =>
        @notify(type: 'success', msg: 'Заявка взята в работу.', timeout: 3000)
        @loadJobs()
      error: (xhr) =>
        @notify(type: 'error', msg: @extractError(xhr, 'Не удалось взять заявку.'), timeout: 6000)
        @loadJobs()
    )

  releaseJob: (e) =>
    @preventDefault(e)
    return if !@actionAllowed('release_to_pool')
    id = $(e.currentTarget).data('id')
    return if !id

    @ajax(
      id: "dom_servis_dispatch_release_#{id}"
      type: 'POST'
      url: "#{@apiPath}/dom_servis/dispatch/jobs/#{id}/release"
      success: =>
        @notify(type: 'success', msg: 'Заявка возвращена в пул.', timeout: 3000)
        @loadJobs()
      error: (xhr) =>
        @notify(type: 'error', msg: @extractError(xhr, 'Не удалось вернуть заявку в пул.'), timeout: 6000)
        @loadJobs()
    )

  setStatus: (e) =>
    @preventDefault(e)
    id = $(e.currentTarget).data('id')
    status = $(e.currentTarget).data('status')
    return if !id || !status
    return if !@statusAllowed(status)

    @ajax(
      id: "dom_servis_dispatch_status_#{id}_#{status}"
      type: 'POST'
      url: "#{@apiPath}/dom_servis/dispatch/jobs/#{id}/status"
      data: JSON.stringify(status: status)
      processData: true
      success: =>
        @notify(type: 'success', msg: "Статус обновлён: #{@statusLabel(status)}.", timeout: 3000)
        @loadJobs()
      error: (xhr) =>
        @notify(type: 'error', msg: @extractError(xhr, 'Не удалось обновить статус.'), timeout: 6000)
        @loadJobs()
    )

  changePriority: (e) =>
    id = $(e.currentTarget).data('id')
    priority = $(e.currentTarget).val()
    return if !id || !priority
    return if !@actionAllowed('change_priority')

    @ajax(
      id: "dom_servis_dispatch_priority_#{id}"
      type: 'POST'
      url: "#{@apiPath}/dom_servis/dispatch/jobs/#{id}/change_priority"
      data: JSON.stringify(priority: priority)
      processData: true
      success: =>
        @notify(type: 'success', msg: 'Приоритет обновлён.', timeout: 3000)
        @loadJobs()
      error: (xhr) =>
        @notify(type: 'error', msg: @extractError(xhr, 'Не удалось обновить приоритет.'), timeout: 6000)
        @loadJobs()
    )

  changeVisitDay: (e) =>
    id = $(e.currentTarget).data('id')
    visitDay = $(e.currentTarget).val()
    return if !id || !visitDay
    return if !@actionAllowed('move_job_day')

    @ajax(
      id: "dom_servis_dispatch_move_day_#{id}"
      type: 'POST'
      url: "#{@apiPath}/dom_servis/dispatch/jobs/#{id}/move_day"
      data: JSON.stringify(
        visit_day: visitDay
        visit_date: @nextDateForDay(visitDay)
      )
      processData: true
      success: =>
        @notify(type: 'success', msg: "Заявка перенесена на #{@weekdayLabel(visitDay)}.", timeout: 3000)
        @loadJobs()
      error: (xhr) =>
        @notify(type: 'error', msg: @extractError(xhr, 'Не удалось перенести заявку.'), timeout: 6000)
        @loadJobs()
    )

  createPayload: ->
    serviceType = @$('.js-create-service-type').val()?.trim()
    address = @$('.js-create-address').val()?.trim()
    clientPhone = @$('.js-create-client-phone').val()?.trim()
    visitDay = @$('.js-create-visit-day').val()?.trim()
    visitDate = @$('.js-create-visit-date').val()?.trim()

    if !serviceType
      @notify(type: 'error', msg: 'Укажи тип работ.', timeout: 4000)
      return null

    if !address
      @notify(type: 'error', msg: 'Укажи адрес.', timeout: 4000)
      return null

    if !clientPhone
      @notify(type: 'error', msg: 'Укажи телефон клиента.', timeout: 4000)
      return null

    if !visitDay
      @notify(type: 'error', msg: 'Выбери день недели.', timeout: 4000)
      return null

    {
      service_type: serviceType
      address: address
      client_name: @$('.js-create-client-name').val()?.trim()
      client_phone: clientPhone
      visit_day: visitDay
      visit_date: visitDate || @nextDateForDay(visitDay)
      visit_time: @$('.js-create-visit-time').val()?.trim()
      priority: @$('.js-create-priority').val()?.trim() || 'medium'
      description: @$('.js-create-description').val()?.trim()
      comment: @$('.js-create-comment').val()?.trim()
      work_tags: @parseTags(@$('.js-create-work-tags').val())
      status: 'pool'
      source: 'manual'
    }

  buildEditPayload: (job) ->
    payload = {}

    _.each @editableEditFields(job), (field) =>
      input = @$(".js-edit-field[data-field='#{field.key}']")
      return if input.length < 1

      value = @readEditValue(field, input)
      normalized = @normalizeEditValue(field.key, value)
      return if !@fieldValueChanged(job, field.key, normalized)

      payload[field.key] = normalized

    @normalizeSchedulePayload(job, payload)

  normalizeSchedulePayload: (job, payload) ->
    return payload if _.isEmpty(payload)

    if payload.visit_date?
      payload.visit_day = @weekdayKeyFromDate(payload.visit_date)

    if payload.visit_day? && !payload.visit_date?
      payload.visit_date = @nextDateForDay(payload.visit_day)

    payload

  readEditValue: (field, input) ->
    switch field.type
      when 'textarea'
        input.val()?.trim()
      when 'user_select'
        input.val()
      when 'select'
        input.val()
      when 'date', 'time'
        input.val()?.trim()
      else
        input.val()?.trim()

  normalizeEditValue: (fieldKey, value) ->
    switch fieldKey
      when 'work_tags'
        @parseTags(value)
      when 'assignee_id'
        return null if !value
        parseInt(value, 10)
      when 'client_name', 'client_phone', 'visit_time', 'description', 'comment', 'address', 'service_type', 'source', 'visit_date'
        value || ''
      else
        value

  fieldValueChanged: (job, fieldKey, nextValue) ->
    currentValue = @jobFieldValue(job, fieldKey)

    if fieldKey is 'work_tags'
      return !_.isEqual(@normalizeTags(currentValue), @normalizeTags(nextValue))

    if fieldKey is 'assignee_id'
      currentId = if currentValue? then parseInt(currentValue, 10) else null
      nextId = if nextValue? then parseInt(nextValue, 10) else null
      return currentId isnt nextId

    "#{currentValue || ''}" isnt "#{nextValue || ''}"

  buildStats: ->
    currentUserId = App.User.current()?.id
    weekJobs = @jobsForSelectedWeek()

    {
      total: _.size(weekJobs)
      pool: _.filter(weekJobs, (job) -> job.status is 'pool').length
      active: _.filter(weekJobs, (job) -> job.status in ['taken', 'in_progress']).length
      mine: _.filter(weekJobs, (job) -> job.assignee_id is currentUserId).length
      done: _.filter(weekJobs, (job) -> job.status is 'done').length
      today: _.filter(weekJobs, (job) => @isToday(job)).length
    }

  buildScopedStatusFilters: ->
    weekJobs = @jobsForSelectedWeek()

    [
      { id: 'open', label: 'Открытые', count: _.filter(weekJobs, (job) -> job.status in ['pool', 'taken', 'in_progress']).length }
      { id: 'pool', label: 'Пул', count: _.filter(weekJobs, (job) -> job.status is 'pool').length }
      { id: 'active', label: 'В работе', count: _.filter(weekJobs, (job) -> job.status in ['taken', 'in_progress']).length }
      { id: 'mine', label: 'Мои', count: _.filter(weekJobs, (job) -> job.assignee_id is App.User.current()?.id).length }
      { id: 'done', label: 'Готово', count: _.filter(weekJobs, (job) -> job.status is 'done').length }
      { id: 'all', label: 'Все', count: _.size(weekJobs) }
    ].map (item) =>
      item.active = item.id is @statusFilter
      item

  buildWeekControls: ->
    startDate = @selectedWeekStartDate()
    endDate = @shiftDate(startDate, 6)

    {
      startLabel: @formatDate(startDate)
      endLabel: @formatDate(endDate)
      pickerValue: @formatDateValue(startDate)
      isCurrent: @isCurrentWeek(startDate)
    }

  buildDayFilters: ->
    filters = [{ id: 'all', label: 'Все дни', count: _.size(@jobsForStatusFilter()) }]

    _.each @weekdayItems(), (item) =>
      count = _.filter(@jobsForStatusFilter(), (job) => @jobVisitDay(job) is item.id).length
      filters.push({ id: item.id, label: item.label, count: count, shortLabel: item.shortLabel })

    _.map filters, (item) =>
      item.active = item.id is @dayFilter
      item

  buildJobCards: ->
    currentUserId = App.User.current()?.id
    dispatcherAccess = @dispatcherAccess()
    adminAccess = @adminAccess()
    masterAccess = @masterAccess()

    _.map @filteredJobs(), (job) =>
      assigneeName = @resolveAssigneeName(job)
      visitDay = @jobVisitDay(job)
      canOperate = dispatcherAccess || job.assignee_id is currentUserId

      {
        id: job.id
        jobCode: job.job_code || @fallbackJobCode(job)
        serviceType: job.service_type || 'Без названия'
        address: job.address || 'Адрес не указан'
        clientName: job.client_name || 'Клиент не указан'
        clientPhone: job.client_phone || ''
        visitDate: job.visit_date || ''
        visitTime: job.visit_time || ''
        visitDay: visitDay
        visitDayLabel: @weekdayLabel(visitDay)
        scheduleLabel: @scheduleLabel(job)
        priority: job.priority || 'medium'
        priorityLabel: @priorityLabel(job.priority)
        status: job.status || 'pool'
        statusLabel: @statusLabel(job.status)
        assigneeName: assigneeName
        description: job.description || ''
        comment: job.comment || ''
        workTags: @normalizeTags(job.work_tags)
        canTake: job.status is 'pool' && @actionAllowed('take_job')
        canRelease: job.assignee_id? && canOperate && @actionAllowed('release_to_pool')
        canStart: canOperate && job.status is 'taken' && @actionAllowed('set_status_in_progress') && @statusAllowed('in_progress')
        canFinish: canOperate && job.status in ['taken', 'in_progress'] && @actionAllowed('set_status_done') && @statusAllowed('done')
        canCancel: dispatcherAccess && job.status in ['pool', 'taken', 'in_progress'] && @actionAllowed('cancel_job') && @statusAllowed('cancelled')
        canQuickEdit: @actionAllowed('edit_all_fields') || @actionAllowed('change_priority') || @actionAllowed('move_job_day')
        canChangePriority: @actionAllowed('change_priority') && @fieldEditable('priority')
        canMoveVisitDay: @actionAllowed('move_job_day') && @fieldEditable('visit_day')
        canEdit: @canOpenEdit(job)
        adminAccess: adminAccess
        masterAccess: masterAccess
      }

  buildEditJobView: (job) ->
    return null if !job

    {
      id: job.id
      jobCode: job.job_code || @fallbackJobCode(job)
      title: job.service_type || 'Без названия'
      statusLabel: @statusLabel(job.status)
      scheduleLabel: @scheduleLabel(job)
    }

  buildEditGroups: (job) ->
    return [] if !job

    groups = []
    registryGroups = @policyRegistry.field_groups || []
    fieldIndex = @registryFieldIndex()
    visibleKeys = []

    _.each registryGroups, (group) =>
      items = []
      _.each group.items || [], (entry) =>
        return if !@fieldVisible(entry.key)
        visibleKeys.push(entry.key)
        fieldItem = @buildEditFieldItem(job, entry.key, entry)
        items.push(fieldItem) if fieldItem

      if items.length > 0
        groups.push(
          key: group.key
          label: @fieldGroupLabel(group.key, group.label)
          items: items
        )

    _.each @defaultModalFieldOrder(), (fieldKey) =>
      return if _.contains(visibleKeys, fieldKey)
      return if !@fieldVisible(fieldKey)

      entry = fieldIndex[fieldKey] || { key: fieldKey, label: @fieldLabel(fieldKey), source: 'db', group: @fieldDefinition(fieldKey)?.group || 'other' }
      fieldItem = @buildEditFieldItem(job, fieldKey, entry)
      return if !fieldItem

      groupKey = fieldItem.group
      group = _.find(groups, (candidate) -> candidate.key is groupKey)

      if !group
        group =
          key: groupKey
          label: @fieldGroupLabel(groupKey)
          items: []
        groups.push(group)

      group.items.push(fieldItem)

    _.filter(groups, (group) -> group.items.length > 0)

  buildEditFieldItem: (job, fieldKey, entry = {}) ->
    definition = @fieldDefinition(fieldKey)
    source = entry.source || definition?.source || 'db'
    editable = @fieldEditableOnBoard(fieldKey)
    type = definition?.type || @defaultFieldType(fieldKey, source)
    unsupported = type is 'unsupported'

    {
      key: fieldKey
      label: @fieldLabel(fieldKey, entry.label)
      group: definition?.group || entry.group || 'other'
      type: type
      editable: editable && !unsupported
      unsupported: unsupported
      wide: definition?.wide == true
      value: @fieldInputValue(job, fieldKey)
      displayValue: @fieldDisplayValue(job, fieldKey, unsupported)
      options: @fieldOptions(fieldKey)
      hint: @fieldHint(fieldKey, unsupported)
    }

  editableEditFields: (job) ->
    fields = []

    _.each @buildEditGroups(job), (group) ->
      _.each group.items, (item) ->
        fields.push(item) if item.editable

    fields

  canOpenEdit: (job) ->
    return false if !job
    return false if !@actionAllowed('edit_all_fields')

    _.some @buildEditGroups(job), (group) ->
      _.some group.items, (item) -> item.editable || (!item.editable && item.displayValue?)

  registryFieldIndex: ->
    result = {}

    _.each @policyRegistry.field_groups || [], (group) ->
      _.each group.items || [], (entry) ->
        result[entry.key] = entry

    result

  fieldDefinition: (fieldKey) ->
    definitions =
      id:
        type: 'readonly'
        group: 'identity'
      job_code:
        type: 'readonly'
        group: 'identity'
      source:
        type: 'select'
        group: 'identity'
      status:
        type: 'readonly'
        group: 'lifecycle'
      priority:
        type: 'select'
        group: 'lifecycle'
      visit_day:
        type: 'select'
        group: 'schedule'
      visit_date:
        type: 'date'
        group: 'schedule'
      visit_time:
        type: 'time'
        group: 'schedule'
      address:
        type: 'text'
        group: 'customer'
      client_name:
        type: 'text'
        group: 'customer'
      client_phone:
        type: 'text'
        group: 'customer'
      service_type:
        type: 'text'
        group: 'job_content'
      description:
        type: 'textarea'
        group: 'job_content'
        wide: true
      comment:
        type: 'textarea'
        group: 'job_content'
        wide: true
      work_tags:
        type: 'text'
        group: 'job_content'
        wide: true
      assignee_id:
        type: 'user_select'
        group: 'assignment'
      ticket_id:
        type: 'readonly'
        group: 'assignment'
      published_at:
        type: 'readonly'
        group: 'lifecycle'
      created_at:
        type: 'readonly'
        group: 'lifecycle'
      taken_at:
        type: 'readonly'
        group: 'lifecycle'
      updated_at:
        type: 'readonly'
        group: 'lifecycle'
      completed_at:
        type: 'readonly'
        group: 'lifecycle'
      cancelled_at:
        type: 'readonly'
        group: 'lifecycle'
      organization:
        type: 'unsupported'
        group: 'customer'
      attachments:
        type: 'unsupported'
        group: 'attachments'

    definitions[fieldKey]

  defaultFieldType: (fieldKey, source) ->
    return 'unsupported' if source is 'virtual'

    switch fieldKey
      when 'description', 'comment' then 'textarea'
      else 'text'

  fieldLabel: (fieldKey, fallback = null) ->
    labels =
      id: 'ID'
      job_code: 'Номер заявки'
      source: 'Источник'
      status: 'Статус'
      priority: 'Приоритет'
      visit_day: 'День недели'
      visit_date: 'Дата визита'
      visit_time: 'Время визита'
      address: 'Адрес'
      client_name: 'Клиент'
      client_phone: 'Телефон'
      service_type: 'Тип работ'
      description: 'Описание задачи'
      comment: 'Комментарий диспетчера'
      work_tags: 'Теги работ'
      assignee_id: 'Исполнитель'
      ticket_id: 'Связанная заявка Zammad'
      published_at: 'Опубликована'
      created_at: 'Создана'
      taken_at: 'Взята'
      updated_at: 'Обновлена'
      completed_at: 'Завершена'
      cancelled_at: 'Отменена'
      organization: 'Организация'
      attachments: 'Вложения'

    labels[fieldKey] || fallback || fieldKey

  fieldGroupLabel: (groupKey, fallback = null) ->
    labels =
      identity: 'Идентификация'
      customer: 'Клиент'
      schedule: 'Планирование'
      job_content: 'Содержание заявки'
      assignment: 'Назначение'
      lifecycle: 'Жизненный цикл'
      attachments: 'Вложения'
      other: 'Дополнительно'

    labels[groupKey] || fallback || groupKey

  fieldHint: (fieldKey, unsupported = false) ->
    return 'Поле уже есть в матрице доступа, но его хранение или отдельный editor будут подключены следующим шагом.' if unsupported
    return 'Список исполнителей строится по активным пользователям Дом-Сервис.' if fieldKey is 'assignee_id'
    return 'Теги перечисляются через запятую.' if fieldKey is 'work_tags'
    null

  fieldInputValue: (job, fieldKey) ->
    value = @jobFieldValue(job, fieldKey)

    switch fieldKey
      when 'work_tags'
        @normalizeTags(value).join(', ')
      when 'assignee_id'
        if value? then "#{value}" else ''
      when 'source'
        value || 'manual'
      when 'priority'
        value || 'medium'
      when 'visit_day'
        value || @jobVisitDay(job)
      else
        value || ''

  fieldDisplayValue: (job, fieldKey, unsupported = false) ->
    return 'Пока не подключено к рабочей форме.' if unsupported

    value = @jobFieldValue(job, fieldKey)

    switch fieldKey
      when 'status'
        @statusLabel(job.status)
      when 'priority'
        @priorityLabel(job.priority)
      when 'visit_day'
        @weekdayLabel(@jobVisitDay(job))
      when 'assignee_id'
        @resolveAssigneeName(job)
      when 'source'
        @sourceLabel(job.source)
      when 'work_tags'
        tags = @normalizeTags(value)
        if tags.length > 0 then tags.join(', ') else '—'
      else
        if value? && "#{value}".length > 0 then value else '—'

  fieldOptions: (fieldKey) ->
    switch fieldKey
      when 'priority'
        [
          { id: 'low', label: 'Низкий' }
          { id: 'medium', label: 'Средний' }
          { id: 'high', label: 'Высокий' }
          { id: 'critical', label: 'Критичный' }
        ]
      when 'visit_day'
        _.map @weekdayItems(), (item) -> { id: item.id, label: item.shortLabel }
      when 'source'
        [
          { id: 'manual', label: 'Вручную' }
          { id: 'ai', label: 'AI / разбор' }
        ]
      when 'assignee_id'
        [{ id: '', label: 'Не назначен' }].concat(@assigneeOptions())
      else
        []

  assigneeOptions: ->
    users = App.User.all() || []

    _.chain(users)
      .filter((user) ->
        user?.active isnt false && (
          user.permission('dom_servis.master') ||
          user.permission('dom_servis.dispatcher') ||
          user.permission('dom_servis.admin')
        )
      )
      .sortBy((user) -> (user.displayName() || '').toLowerCase())
      .map((user) -> { id: "#{user.id}", label: user.displayName() || user.login || user.email || "##{user.id}" })
      .value()

  currentEditJob: ->
    return null if !@editOpen || !@editingJobId
    @findJob(@editingJobId)

  findJob: (id) ->
    _.find @jobs, (job) -> "#{job.id}" is "#{id}"

  filteredJobs: ->
    list = @jobsForStatusFilter()

    if @dayFilter isnt 'all'
      list = _.filter(list, (job) => @jobVisitDay(job) is @dayFilter)

    @sortJobs(list)

  jobsForSelectedWeek: ->
    startDate = @selectedWeekStartDate()
    endDate = @shiftDate(startDate, 6)

    _.filter @jobs, (job) =>
      visitDate = @jobVisitDate(job)
      return false if !visitDate
      visitDate >= startDate && visitDate <= endDate

  jobsForStatusFilter: ->
    currentUserId = App.User.current()?.id
    weekJobs = @jobsForSelectedWeek()

    switch @statusFilter
      when 'all'
        weekJobs
      when 'pool'
        _.filter(weekJobs, (job) -> job.status is 'pool')
      when 'active'
        _.filter(weekJobs, (job) -> job.status in ['taken', 'in_progress'])
      when 'mine'
        _.filter(weekJobs, (job) -> job.assignee_id is currentUserId)
      when 'done'
        _.filter(weekJobs, (job) -> job.status is 'done')
      else
        _.filter(weekJobs, (job) -> job.status in ['pool', 'taken', 'in_progress'])

  sortJobs: (jobs) ->
    _.sortBy jobs, (job) => @jobSortValue(job)

  jobSortValue: (job) ->
    schedule = "#{job.visit_date || '9999-12-31'} #{job.visit_time || '23:59'}"
    "#{schedule}_#{job.created_at || ''}_#{job.id || ''}"

  jobFieldValue: (job, fieldKey) ->
    job[fieldKey]

  resolveAssigneeName: (job) ->
    if _.isObject(job.assignee) && job.assignee?.displayName
      return job.assignee.displayName

    if _.isString(job.assignee) && job.assignee.length > 0
      return job.assignee

    if job.assignee_id && App.User.exists(job.assignee_id)
      return App.User.findNative(job.assignee_id).displayName()

    'Свободна'

  roleLabel: ->
    return 'Владелец/администратор' if @adminAccess()
    return 'Диспетчер' if @dispatcherOnlyAccess()
    return 'Мастер' if @masterAccess()
    'Пользователь'

  dispatcherAccess: ->
    @permissionCheck('dom_servis.admin') || @permissionCheck('dom_servis.dispatcher')

  adminAccess: ->
    @permissionCheck('dom_servis.admin')

  dispatcherOnlyAccess: ->
    @permissionCheck('dom_servis.dispatcher')

  masterAccess: ->
    @permissionCheck('dom_servis.master') && !@dispatcherAccess()

  actionAllowed: (actionKey) ->
    return false if !@effectivePolicy?.actions
    @effectivePolicy.actions[actionKey] is true

  canCreatePublishedJob: ->
    @actionAllowed('create_job') && @actionAllowed('publish_to_pool')

  statusAllowed: (statusKey) ->
    return false if !@effectivePolicy?.statuses
    @effectivePolicy.statuses[statusKey] is true

  fieldVisible: (fieldKey) ->
    return false if !@effectivePolicy?.fields
    @effectivePolicy.fields[fieldKey]?.visible is true

  fieldEditable: (fieldKey) ->
    return false if !@effectivePolicy?.fields
    @effectivePolicy.fields[fieldKey]?.editable is true

  fieldEditableOnBoard: (fieldKey) ->
    return false if !@fieldEditable(fieldKey)
    return false if !@actionAllowed('edit_all_fields')

    if fieldKey is 'priority'
      return @actionAllowed('change_priority')

    if fieldKey is 'assignee_id'
      return @actionAllowed('change_assignee')

    if fieldKey is 'comment'
      return @actionAllowed('add_comment')

    if fieldKey in ['visit_day', 'visit_date']
      return @actionAllowed('move_job_day') || @actionAllowed('move_job_week')

    true

  scheduleLabel: (job) ->
    dayLabel = @weekdayLabel(@jobVisitDay(job))
    datePart = job.visit_date || 'без точной даты'
    timePart = job.visit_time || 'время не задано'
    "#{dayLabel}, #{datePart}, #{timePart}"

  sourceLabel: (source) ->
    switch source
      when 'ai' then 'AI / разбор'
      else 'Вручную'

  jobVisitDay: (job) ->
    job.visit_day || @weekdayKeyFromDate(job.visit_date) || @defaultVisitDay()

  jobVisitDate: (job) ->
    parsedDate = @parseDateValue(job.visit_date)
    return parsedDate if parsedDate

    fallbackDay = @jobVisitDay(job)
    return null if !fallbackDay

    @dateForDayInWeek(fallbackDay)

  defaultVisitDay: ->
    return @dayFilter if @dayFilter && @dayFilter isnt 'all'

    unless @isCurrentWeek(@selectedWeekStartDate())
      return 'mon'

    switch new Date().getDay()
      when 1 then 'mon'
      when 2 then 'tue'
      when 3 then 'wed'
      when 4 then 'thu'
      when 5 then 'fri'
      when 6 then 'sat'
      else 'sun'

  weekdayItems: ->
    [
      { id: 'mon', label: 'Понедельник', shortLabel: 'Пн' }
      { id: 'tue', label: 'Вторник', shortLabel: 'Вт' }
      { id: 'wed', label: 'Среда', shortLabel: 'Ср' }
      { id: 'thu', label: 'Четверг', shortLabel: 'Чт' }
      { id: 'fri', label: 'Пятница', shortLabel: 'Пт' }
      { id: 'sat', label: 'Суббота', shortLabel: 'Сб' }
      { id: 'sun', label: 'Воскресенье', shortLabel: 'Вс' }
    ]

  weekdayLabel: (key) ->
    item = _.find(@weekdayItems(), (weekday) -> weekday.id is key)
    item?.shortLabel || '—'

  weekdayKeyFromDate: (value) ->
    return null if !value

    date = new Date(value)
    return null if isNaN(date.getTime())

    switch date.getDay()
      when 1 then 'mon'
      when 2 then 'tue'
      when 3 then 'wed'
      when 4 then 'thu'
      when 5 then 'fri'
      when 6 then 'sat'
      else 'sun'

  nextDateForDay: (dayKey) ->
    date = @selectedWeekStartDate()
    targetDay =
      switch dayKey
        when 'mon' then 1
        when 'tue' then 2
        when 'wed' then 3
        when 'thu' then 4
        when 'fri' then 5
        when 'sat' then 6
        else 0

    offset = (targetDay - 1 + 7) % 7
    date.setDate(date.getDate() + offset)
    @formatDateValue(date)

  selectedWeekStartDate: ->
    @parseDateValue(@selectedWeekStart) || @startOfWeek(new Date())

  startOfWeek: (dateValue) ->
    date = @parseDateValue(dateValue) || new Date()
    normalized = new Date(date.getFullYear(), date.getMonth(), date.getDate())
    day = normalized.getDay()
    diff = if day is 0 then -6 else 1 - day
    normalized.setDate(normalized.getDate() + diff)
    normalized

  shiftDate: (dateValue, days) ->
    date = @parseDateValue(dateValue) || new Date()
    shifted = new Date(date.getFullYear(), date.getMonth(), date.getDate())
    shifted.setDate(shifted.getDate() + days)
    shifted

  parseDateValue: (value) ->
    return null if !value
    return new Date(value.getFullYear(), value.getMonth(), value.getDate()) if _.isDate(value)
    return null if !_.isString(value) || value.length is 0

    parts = value.split('-')
    return null if parts.length isnt 3

    year = parseInt(parts[0], 10)
    month = parseInt(parts[1], 10) - 1
    day = parseInt(parts[2], 10)
    parsed = new Date(year, month, day)
    return null if isNaN(parsed.getTime())

    parsed

  formatDateValue: (dateValue) ->
    date = @parseDateValue(dateValue) || new Date()
    year = date.getFullYear()
    month = ("0#{date.getMonth() + 1}").slice(-2)
    day = ("0#{date.getDate()}").slice(-2)
    "#{year}-#{month}-#{day}"

  formatDate: (dateValue) ->
    date = @parseDateValue(dateValue) || new Date()
    day = ("0#{date.getDate()}").slice(-2)
    month = ("0#{date.getMonth() + 1}").slice(-2)
    "#{day}.#{month}.#{date.getFullYear()}"

  dateForDayInWeek: (dayKey) ->
    startDate = @selectedWeekStartDate()
    index = _.findIndex(@weekdayItems(), (item) -> item.id is dayKey)
    return null if index < 0
    @shiftDate(startDate, index)

  isCurrentWeek: (startDate) ->
    @formatDateValue(startDate) is @formatDateValue(@startOfWeek(new Date()))

  isToday: (job) ->
    visitDate = @jobVisitDate(job)
    return false if !visitDate
    @formatDateValue(visitDate) is @formatDateValue(new Date())

  parseTags: (value) ->
    return [] if !value

    _.chain(value.split(','))
      .map((item) -> item.trim())
      .filter((item) -> item.length > 0)
      .uniq()
      .value()

  normalizeTags: (value) ->
    if _.isArray(value)
      return _.filter(value, (item) -> item)

    if _.isString(value)
      return @parseTags(value)

    []

  fallbackJobCode: (job) ->
    createdAt = new Date(job.created_at || Date.now())
    datePart = createdAt.toISOString().slice(0, 10).replace(/-/g, '')
    rawId = "#{job.id || ''}".replace(/\D/g, '')
    tail = ("0000#{rawId}").slice(-4)
    "#{datePart}-#{tail}"

  defaultModalFieldOrder: ->
    [
      'id'
      'job_code'
      'source'
      'status'
      'priority'
      'visit_day'
      'visit_date'
      'visit_time'
      'address'
      'client_name'
      'client_phone'
      'service_type'
      'description'
      'comment'
      'work_tags'
      'assignee_id'
      'ticket_id'
      'published_at'
      'created_at'
      'taken_at'
      'updated_at'
      'completed_at'
      'cancelled_at'
      'organization'
      'attachments'
    ]

  statusLabel: (status) ->
    switch status
      when 'taken' then 'Взята'
      when 'in_progress' then 'В работе'
      when 'done' then 'Готово'
      when 'cancelled' then 'Отменена'
      else 'В пуле'

  priorityLabel: (priority) ->
    switch priority
      when 'low' then 'Низкий'
      when 'high' then 'Высокий'
      when 'critical' then 'Критичный'
      else 'Средний'

  extractError: (xhr, fallback) ->
    xhr?.responseJSON?.error_human || xhr?.responseJSON?.error || fallback

class DomServisDispatchBoardRouter extends App.ControllerPermanent
  @requiredPermission: ['dom_servis.admin', 'dom_servis.dispatcher', 'dom_servis.master']

  constructor: (params) ->
    super

    @authenticateCheckRedirect()

    App.TaskManager.execute(
      key: 'DomServisDispatchBoard'
      controller: 'DomServisDispatchBoard'
      params: params
      show: true
      persistent: true
    )

App.Config.set('dom_servis/dispatch', DomServisDispatchBoardRouter, 'Routes')
App.Config.set('DomServisDispatchBoard', { controller: 'DomServisDispatchBoard', permission: ['dom_servis.admin', 'dom_servis.dispatcher', 'dom_servis.master'] }, 'permanentTask')
App.Config.set('DomServisDispatchBoard', { prio: 1200, parent: '', name: 'Диспетчеризация', target: '#dom_servis/dispatch', key: 'DomServisDispatchBoard', permission: ['dom_servis.admin', 'dom_servis.dispatcher', 'dom_servis.master'], class: 'checklist' }, 'NavBar')
