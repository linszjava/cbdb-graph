<script setup>
import { computed } from 'vue'
import { useGraphStore } from '../stores/graph'
import { toNianHao } from '../nianhao'

const store = useGraphStore()

// 榜按人数降序，进士类优先 —— 同年之谊主要指进士同榜
const cohorts = computed(() => {
  const rank = c => (c.entryChn || '').includes('进士') ? 0 : 1
  return [...store.cohorts].sort((a, b) => rank(a) - rank(b) || b.size - a.size)
})

const era = m => m.birthYear && m.deathYear ? `${m.birthYear}–${m.deathYear}`
  : m.indexYear ? `约 ${m.indexYear}` : ''
</script>

<template>
  <div class="wrap">
    <div v-if="store.loading" class="overlay">载入中…</div>
    <div v-else-if="!cohorts.length" class="overlay">
      该人物没有带纪年的科举或学校入仕记录
    </div>

    <div v-else class="list">
      <p class="lead">
        同榜及第者称「同年」，是宋以降政治派系形成的核心机制。
        库中原无此类关系，由 <b>{{ store.cohorts.length }}</b> 条入仕记录反查同榜生成。
      </p>

      <section v-for="c in cohorts" :key="c.cohortId" class="cohort">
        <header>
          <h3>
            {{ c.year }}
            <span class="nh" v-if="toNianHao(c.year, store.person?.dynasty)">
              {{ toNianHao(c.year, store.person?.dynasty) }}
            </span>
          </h3>
          <span class="kind">{{ c.entryChn }}</span>
          <span class="cnt">{{ c.size }} 人</span>
        </header>
        <div class="members">
          <button v-for="m in c.members" :key="m.id"
                  :class="{ self: m.id === store.centerId }"
                  @click="store.select(m.id)"
                  :title="era(m)">
            {{ m.nameChn }}
          </button>
          <span v-if="c.size > c.members.length" class="more">
            另有 {{ c.size - c.members.length }} 人未列
          </span>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.wrap { position: relative; height: 100%; background: var(--surface); overflow-y: auto; }
.overlay { position: absolute; inset: 0; display: grid; place-items: center; color: var(--ink-mute); font-size: 14px; }
.list { padding: 18px 22px 40px; }
.lead {
  font-size: 12.5px; color: var(--ink-mute); margin: 0 0 18px;
  padding-bottom: 14px; border-bottom: 1px solid var(--line); line-height: 1.7;
}
.lead b { color: var(--azurite); }
.cohort { margin-bottom: 22px; }
.cohort header { display: flex; align-items: baseline; gap: 9px; margin-bottom: 8px; }
.cohort h3 {
  margin: 0; font-size: 17px; font-weight: 600;
  font-variant-numeric: tabular-nums; color: var(--ink);
}
.cohort h3 .nh { font-size: 12px; color: var(--azurite); font-weight: 400; margin-left: 3px; }
.kind { font-size: 12px; color: var(--ink-soft); }
.cnt {
  margin-left: auto; font-size: 11px; color: var(--ink-mute);
  font-family: "JetBrains Mono", monospace;
}
.members { display: flex; flex-wrap: wrap; gap: 4px; }
.members button {
  border: 1px solid var(--line); background: var(--surface);
  color: var(--ink-soft); border-radius: 3px; padding: 2px 8px; font-size: 12.5px;
}
.members button:hover { border-color: var(--azurite); color: var(--azurite); }
.members button.self {
  background: var(--cinnabar); border-color: var(--cinnabar); color: #fff; font-weight: 500;
}
.more { font-size: 11.5px; color: var(--ink-mute); align-self: center; margin-left: 4px; }
</style>
