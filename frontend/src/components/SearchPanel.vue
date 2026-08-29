<script setup>
import { ref, watch } from 'vue'
import { useGraphStore } from '../stores/graph'

const store = useGraphStore()
const q = ref('')
let timer = null

watch(q, v => {
  clearTimeout(timer)
  timer = setTimeout(() => store.search(v), 250)
})

const era = h => {
  if (h.birthYear && h.deathYear) return `${h.birthYear}–${h.deathYear}`
  if (h.indexYear) return `约 ${h.indexYear}`
  return '生卒未详'
}
</script>

<template>
  <div class="panel">
    <input v-model="q" placeholder="搜索人物：苏轼、朱熹、王安石…" autofocus />
    <p v-if="!q" class="hint">简体繁体皆可。库中 660,834 人。</p>
    <ul v-else class="hits">
      <li v-for="h in store.hits" :key="h.id"
          :class="{ active: h.id === store.centerId }"
          @click="store.select(h.id)">
        <div class="row">
          <span class="nm">{{ h.nameChn }}</span>
          <span class="dy">{{ h.dynasty || '未详' }}</span>
        </div>
        <div class="meta">{{ h.name }} · {{ era(h) }}</div>
        <div class="alts" v-if="h.altLabels?.length">{{ h.altLabels.slice(0, 3).join(' · ') }}</div>
      </li>
      <li v-if="store.hits.length === 0" class="empty">无匹配结果</li>
    </ul>
  </div>
</template>

<style scoped>
.panel { display: flex; flex-direction: column; min-height: 0; }
input {
  width: 100%; padding: 10px 12px; border: 1px solid var(--line);
  border-radius: 3px; background: var(--surface); color: var(--ink);
}
input:focus { outline: 2px solid var(--azurite); outline-offset: -1px; border-color: transparent; }
.hint { color: var(--ink-mute); font-size: 12px; margin: 10px 2px 0; }
.hits { list-style: none; margin: 10px 0 0; padding: 0; overflow-y: auto; min-height: 0; }
.hits li {
  padding: 9px 11px; border: 1px solid transparent; border-radius: 3px;
  cursor: pointer; margin-bottom: 2px;
}
.hits li:hover { background: var(--surface-alt); }
.hits li.active { background: var(--azurite-lo); border-color: var(--azurite); }
.row { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
.nm { font-size: 15px; font-weight: 500; }
.dy { font-size: 11px; color: var(--azurite); flex-shrink: 0; }
.meta { font-size: 11.5px; color: var(--ink-mute); margin-top: 1px; }
.alts { font-size: 11px; color: var(--azurite); margin-top: 2px; }
.empty { color: var(--ink-mute); cursor: default; font-size: 13px; }
.empty:hover { background: none; }
</style>
