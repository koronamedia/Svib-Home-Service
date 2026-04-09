<script setup>
import { computed, reactive, ref } from 'vue'
import jobsSeed from './data/jobs.json'

const currentUser = {
  name: 'Master1 Master2626',
  role: 'Мастер',
  organization: 'Дом-Сервис',
  initials: 'MM',
}

const state = reactive({
  jobs: jobsSeed.map((job) => ({ ...job })),
  workspace: 'pool',
  day: 'all',
  tag: 'all',
  filterPanelOpen: false,
  accountMenuOpen: false,
  selectedJobId: null,
})

const workspaceOptions = [
  { id: 'mine', label: 'Мои' },
  { id: 'pool', label: 'Пул' },
  { id: 'active', label: 'В работе' },
  { id: 'done', label: 'Готово' },
]

const dayOptions = [
  { id: 'all', label: 'Все дни' },
  { id: '2026-04-10', label: 'Сегодня' },
  { id: '2026-04-11', label: 'Завтра' },
]

const allTags = computed(() => {
  const tags = new Set()
  state.jobs.forEach((job) => job.tags.forEach((tag) => tags.add(tag)))
  return ['all', ...Array.from(tags)]
})

const workspaceCount = (workspaceId) =>
  state.jobs.filter((job) => matchesWorkspace(job, workspaceId)).length

const filteredJobs = computed(() =>
  state.jobs.filter((job) => {
    if (!matchesWorkspace(job, state.workspace)) return false
    if (state.day !== 'all' && job.scheduledDate !== state.day) return false
    if (state.tag !== 'all' && !job.tags.includes(state.tag)) return false
    return true
  }),
)

const selectedJob = computed(() => state.jobs.find((job) => job.id === state.selectedJobId) || null)

const topSummary = computed(() => {
  const active = workspaceCount('active')
  const pool = workspaceCount('pool')
  return `${active} в работе • ${pool} в пуле`
})

const queueTitle = computed(() => {
  const map = {
    mine: 'Мои заявки',
    pool: 'Заявки из пула',
    active: 'Заявки в работе',
    done: 'Завершённые заявки',
  }
  return map[state.workspace]
})

function matchesWorkspace(job, workspaceId) {
  if (workspaceId === 'mine') return job.assigneeName === currentUser.name && job.status !== 'done'
  if (workspaceId === 'pool') return job.status === 'pool'
  if (workspaceId === 'active') return job.status === 'active'
  if (workspaceId === 'done') return job.status === 'done'
  return true
}

function setWorkspace(workspaceId) {
  state.workspace = workspaceId
  state.selectedJobId = null
}

function openJob(jobId) {
  state.selectedJobId = jobId
}

function closeDrawer() {
  state.selectedJobId = null
}

function applyAction(job, action) {
  if (action === 'take') {
    job.status = 'mine'
    job.statusLabel = 'Моя'
    job.assigneeName = currentUser.name
    job.actions = ['start', 'release']
    state.workspace = 'mine'
  }

  if (action === 'start') {
    job.status = 'active'
    job.statusLabel = 'В работе'
    job.actions = ['done', 'release']
    state.workspace = 'active'
  }

  if (action === 'done') {
    job.status = 'done'
    job.statusLabel = 'Готово'
    job.actions = []
    state.workspace = 'done'
  }

  if (action === 'release') {
    job.status = 'pool'
    job.statusLabel = 'В пуле'
    job.assigneeName = null
    job.actions = ['take']
    state.workspace = 'pool'
  }

  state.selectedJobId = job.id
}

function actionLabel(action) {
  return {
    take: 'Взять',
    start: 'В работу',
    done: 'Готово',
    release: 'В пул',
  }[action]
}

setWorkspace(state.workspace)
</script>

<template>
  <div class="sandbox-page">
    <div class="sandbox-phone-frame">
      <main class="dom-servis-dispatch-board">
        <section class="dom-servis-dispatch-board__shell is-mobile">
          <header class="dom-servis-dispatch-board__mobile-topbar">
            <div class="dom-servis-dispatch-board__mobile-brand">
              <div class="dom-servis-dispatch-board__eyebrow">Дом-Сервис</div>
              <strong>Dispatch</strong>
            </div>

            <div class="dom-servis-dispatch-board__mobile-topbar-actions">
              <div class="dom-servis-dispatch-board__mobile-role">{{ currentUser.role }}</div>
              <button class="dom-servis-dispatch-icon-button" @click="state.accountMenuOpen = true">
                ☰
              </button>
            </div>
          </header>

          <section class="dom-servis-dispatch-board__mobile-stage">
            <div class="dom-servis-dispatch-board__mobile-stage-copy">
              <div class="dom-servis-dispatch-board__mobile-stage-eyebrow">Рабочий режим</div>
              <h1>{{ queueTitle }}</h1>
              <p>{{ topSummary }}</p>
            </div>

            <div class="dom-servis-dispatch-board__mobile-segments">
              <button
                v-for="item in workspaceOptions"
                :key="item.id"
                class="dom-servis-dispatch-segment"
                :class="{ 'is-active': state.workspace === item.id }"
                @click="setWorkspace(item.id)"
              >
                <span>{{ item.label }}</span>
                <strong>{{ workspaceCount(item.id) }}</strong>
              </button>
            </div>

            <div class="dom-servis-dispatch-board__mobile-toolbar">
              <button class="dom-servis-dispatch-chip dom-servis-dispatch-chip--primary" @click="state.filterPanelOpen = true">
                Фильтры
              </button>
              <div class="dom-servis-dispatch-chip">
                {{ state.day === 'all' ? 'Все дни' : dayOptions.find((item) => item.id === state.day)?.label }}
              </div>
              <div class="dom-servis-dispatch-chip">{{ state.tag === 'all' ? 'Все теги' : state.tag }}</div>
            </div>
          </section>

          <section class="dom-servis-dispatch-board__mobile-queue">
            <div class="dom-servis-dispatch-board__mobile-queue-head">
              <div>
                <div class="dom-servis-dispatch-board__mobile-queue-label">Очередь</div>
                <strong>{{ filteredJobs.length }} заявк<span v-if="filteredJobs.length === 1">а</span><span v-else-if="filteredJobs.length < 5">и</span><span v-else>ок</span></strong>
              </div>
              <button class="dom-servis-dispatch-link-button" @click="state.filterPanelOpen = true">
                Изменить
              </button>
            </div>
          </section>

          <section class="dom-servis-dispatch-board__list">
            <article
              v-for="job in filteredJobs"
              :key="job.id"
              class="dom-servis-dispatch-card"
              :class="[`dom-servis-dispatch-card--${job.status}`, { 'is-selected': selectedJob?.id === job.id }]"
              @click="openJob(job.id)"
            >
              <div class="dom-servis-dispatch-card__row dom-servis-dispatch-card__row--top">
                <span class="dom-servis-dispatch-card__code">{{ job.jobCode }}</span>
                <span class="dom-servis-dispatch-card__status" :class="`dom-servis-dispatch-card__status--${job.status}`">
                  {{ job.statusLabel }}
                </span>
              </div>

              <div class="dom-servis-dispatch-card__schedule">{{ job.scheduleLabel }}</div>
              <div class="dom-servis-dispatch-card__address">{{ job.address }}</div>
              <div class="dom-servis-dispatch-card__service">{{ job.serviceType }}</div>

              <div class="dom-servis-dispatch-card__meta">
                <span>{{ job.clientName }}</span>
                <span>{{ job.clientPhone }}</span>
              </div>

              <div class="dom-servis-dispatch-card__footer">
                <span class="dom-servis-dispatch-card__priority" :class="`dom-servis-dispatch-card__priority--${job.priority}`">
                  {{ job.priorityLabel }}
                </span>

                <button
                  v-if="job.actions[0]"
                  class="dom-servis-dispatch-card__action"
                  :class="`dom-servis-dispatch-card__action--${job.actions[0]}`"
                  @click.stop="applyAction(job, job.actions[0])"
                >
                  {{ actionLabel(job.actions[0]) }}
                </button>
              </div>
            </article>

            <div v-if="filteredJobs.length === 0" class="dom-servis-dispatch-board__empty">
              <strong>По текущему срезу заявок нет.</strong>
              <span>Смени режим или открой фильтры.</span>
            </div>
          </section>
        </section>

        <div v-if="state.filterPanelOpen" class="dom-servis-overlay" @click.self="state.filterPanelOpen = false">
          <section class="dom-servis-sheet">
            <div class="dom-servis-sheet__head">
              <strong>Фильтры мастера</strong>
              <button class="dom-servis-dispatch-icon-button" @click="state.filterPanelOpen = false">✕</button>
            </div>

            <div class="dom-servis-sheet__group">
              <div class="dom-servis-sheet__label">День</div>
              <div class="dom-servis-sheet__chips">
                <button
                  v-for="item in dayOptions"
                  :key="item.id"
                  class="dom-servis-dispatch-chip"
                  :class="{ 'is-active': state.day === item.id }"
                  @click="state.day = item.id"
                >
                  {{ item.label }}
                </button>
              </div>
            </div>

            <div class="dom-servis-sheet__group">
              <div class="dom-servis-sheet__label">Теги</div>
              <div class="dom-servis-sheet__chips">
                <button
                  v-for="item in allTags"
                  :key="item"
                  class="dom-servis-dispatch-chip"
                  :class="{ 'is-active': state.tag === item }"
                  @click="state.tag = item"
                >
                  {{ item === 'all' ? 'Все теги' : item }}
                </button>
              </div>
            </div>
          </section>
        </div>

        <div v-if="state.accountMenuOpen" class="dom-servis-overlay" @click.self="state.accountMenuOpen = false">
          <section class="dom-servis-sheet dom-servis-sheet--menu">
            <div class="dom-servis-sheet__profile">
              <div class="dom-servis-dispatch-board__user-avatar">{{ currentUser.initials }}</div>
              <div>
                <strong>{{ currentUser.name }}</strong>
                <span>{{ currentUser.organization }}</span>
              </div>
            </div>
            <button class="dom-servis-menu-button">Профиль</button>
            <button class="dom-servis-menu-button">Главная Zammad</button>
            <button class="dom-servis-menu-button dom-servis-menu-button--danger">Выход</button>
          </section>
        </div>

        <div v-if="selectedJob" class="dom-servis-overlay dom-servis-overlay--drawer" @click.self="closeDrawer">
          <aside class="dom-servis-drawer">
            <div class="dom-servis-drawer__head">
              <div>
                <div class="dom-servis-dispatch-board__eyebrow">Карточка заявки</div>
                <h2>{{ selectedJob.address }}</h2>
                <p>{{ selectedJob.serviceType }}</p>
              </div>
              <button class="dom-servis-dispatch-icon-button" @click="closeDrawer">✕</button>
            </div>

            <div class="dom-servis-drawer__meta">
              <div>
                <span>Когда</span>
                <strong>{{ selectedJob.scheduleLabel }}</strong>
              </div>
              <div>
                <span>Клиент</span>
                <strong>{{ selectedJob.clientName }}</strong>
              </div>
              <div>
                <span>Телефон</span>
                <strong>{{ selectedJob.clientPhone }}</strong>
              </div>
              <div>
                <span>Организация</span>
                <strong>{{ selectedJob.organizationName }}</strong>
              </div>
            </div>

            <div class="dom-servis-drawer__section">
              <span class="dom-servis-drawer__label">Комментарий</span>
              <p>{{ selectedJob.comment }}</p>
            </div>

            <div class="dom-servis-drawer__section">
              <span class="dom-servis-drawer__label">Описание</span>
              <p>{{ selectedJob.description }}</p>
            </div>

            <div class="dom-servis-drawer__section">
              <span class="dom-servis-drawer__label">Теги</span>
              <div class="dom-servis-sheet__chips">
                <span v-for="tag in selectedJob.tags" :key="tag" class="dom-servis-dispatch-chip">{{ tag }}</span>
              </div>
            </div>

            <div v-if="selectedJob.actions.length" class="dom-servis-drawer__actions">
              <button
                v-for="action in selectedJob.actions"
                :key="action"
                class="dom-servis-dispatch-card__action"
                :class="`dom-servis-dispatch-card__action--${action}`"
                @click="applyAction(selectedJob, action)"
              >
                {{ actionLabel(action) }}
              </button>
            </div>
          </aside>
        </div>
      </main>
    </div>
  </div>
</template>
