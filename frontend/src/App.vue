<script setup>
import { computed, defineAsyncComponent, onMounted, onBeforeUnmount } from 'vue'
import { useGraphStore } from './stores/graph'
import SearchPanel from './components/SearchPanel.vue'
import NetworkCanvas from './components/NetworkCanvas.vue'
import LineageView from './components/LineageView.vue'
import CohortView from './components/CohortView.vue'
import GroupPanel from './components/GroupPanel.vue'
import PlaceView from './components/PlaceView.vue'
import { exportNodesCsv, exportEdgesCsv, exportGexf } from './export'
import PersonPanel from './components/PersonPanel.vue'
import { dynastyList } from './dynasty'

// ECharts 与中国地图 geojson 合计逾 1 MB，只在打开地图页时才加载
const AtlasView = defineAsyncComponent(() => import('./components/AtlasView.vue'))

const store = useGraphStore()

const views = [
  { k: 'network', label: '关系网络', mod: 'M3' },
  { k: 'lineage', label: '家族世系', mod: 'M4' },
  { k: 'atlas',   label: '宦游地图', mod: 'M5' },
  { k: 'cohort',  label: '科举同年', mod: 'M9' },
  { k: 'group',   label: '群体网络', mod: 'M10' },
  { k: 'place',   label: '政区层级', mod: 'M11' }
]

// 轨迹过长时折叠中段，只留首项与最近几步
const visibleTrail = computed(() => {
  const all = store.trail.map((t, index) => ({ ...t, index }))
  const KEEP = 5
  let items = all
  if (all.length > KEEP + 1) {
    items = [all[0], { gap: true }, ...all.slice(-KEEP)]
  }
  return items.map((t, i) => ({ ...t, last: i === items.length - 1 }))
})

// 网络图与群体图可导出；世系、地图、同年各有专门格式，暂不导出
const canExport = computed(() =>
  ['network', 'group'].includes(store.view) && store.renderGraph.nodes.length > 0)
const exportName = computed(() =>
  store.person?.nameChn || store.groupFilter.status || store.groupFilter.choronym || 'cbdb')

function toggleRel(t) {
  const s = new Set(store.relTypes)
  s.has(t) ? s.delete(t) : s.add(t)
  if (s.size === 0) return          // 至少保留一种，否则图会空掉
  store.relTypes = [...s]
  store.reload()
}
function setHops(n) { store.hops = n; store.reload() }

// 让浏览器的前进/后退键也能走轨迹 —— 用户下意识就会按它
function onPop(e) {
  const i = e.state && e.state.trailIndex
  if (typeof i === 'number') store.goTo(i)
}
onMounted(() => window.addEventListener('popstate', onPop))
onBeforeUnmount(() => window.removeEventListener('popstate', onPop))
</script>

<template>
  <div class="app">
    <aside class="left">
      <div class="brand">
        <h1>CBDB 图谱工作台</h1>
        <p>中国历代人物传记资料库</p>
      </div>
      <SearchPanel />
    </aside>

    <main class="center">
      <div class="trailbar" v-if="store.trail.length">
        <button class="nav" :disabled="!store.canBack" @click="store.back()" title="后退">←</button>
        <button class="nav" :disabled="!store.canForward" @click="store.forward()" title="前进">→</button>
        <nav class="crumbs">
          <template v-for="(t, i) in visibleTrail" :key="i">
            <span v-if="t.gap" class="gap">…</span>
            <button v-else
                    :class="{ cur: t.index === store.trailIndex }"
                    @click="store.goTo(t.index)">{{ t.label }}</button>
            <span v-if="!t.last" class="sep">›</span>
          </template>
        </nav>
      </div>

      <div class="tabs">
        <button v-for="t in views" :key="t.k"
                :class="{ on: store.view === t.k }" @click="store.setView(t.k)">
          {{ t.label }}<span class="mid">{{ t.mod }}</span>
        </button>
      </div>

      <div class="toolbar">
        <GroupPanel v-if="store.view === 'group'" />

        <div class="grp" v-if="store.view === 'network'">
          <label>跳数</label>
          <button v-for="n in [1,2,3]" :key="n"
                  :class="{ on: store.hops === n }" @click="setHops(n)">{{ n }}</button>
        </div>
        <div class="grp" v-if="store.view === 'network'">
          <label>关系</label>
          <button :class="{ on: store.relTypes.includes('ASSOC') }"
                  @click="toggleRel('ASSOC')">社会</button>
          <button :class="{ on: store.relTypes.includes('KIN') }"
                  @click="toggleRel('KIN')">亲属</button>
        </div>
        <div class="grp" v-if="['network','group'].includes(store.view)">
          <label>着色</label>
          <button :class="{ on: store.colorBy === 'dynasty' }"
                  @click="store.colorBy = 'dynasty'">朝代</button>
          <button :class="{ on: store.colorBy === 'community' }"
                  @click="store.colorBy = 'community'">社群</button>
        </div>
        <div class="stat" v-if="['network','group'].includes(store.view) && store.nodeCount">
          {{ store.nodeCount }} 节点 · {{ store.edgeCount }} 边
        </div>
        <div class="stat" v-else-if="store.view === 'lineage' && store.lineage.nodes.length">
          {{ store.lineage.nodes.length }} 位亲属
        </div>
        <div class="stat" v-else-if="store.view === 'atlas' && store.atlas.length">
          {{ store.atlas.length }} 个地理落点
        </div>
        <div class="stat" v-else-if="store.view === 'cohort' && store.cohorts.length">
          {{ store.cohorts.length }} 榜
        </div>
        <div class="stat" v-else-if="store.view === 'place' && store.place">
          {{ store.place.total }} 人
        </div>

        <div class="grp export" v-if="canExport">
          <label>导出</label>
          <button @click="exportNodesCsv(store.renderGraph, exportName)">节点</button>
          <button @click="exportEdgesCsv(store.renderGraph, exportName)">边</button>
          <button @click="exportGexf(store.renderGraph, exportName)">GEXF</button>
        </div>
        <div class="err" v-if="store.error">{{ store.error }}</div>
      </div>

      <div class="stage">
        <NetworkCanvas v-if="store.view === 'network'" />
        <LineageView v-else-if="store.view === 'lineage'" />
        <CohortView v-else-if="store.view === 'cohort'" />
        <NetworkCanvas v-else-if="store.view === 'group'" />
        <PlaceView v-else-if="store.view === 'place'" />
        <AtlasView v-else />
      </div>

      <div class="legend" v-if="['network','group'].includes(store.view) && store.colorBy === 'dynasty'">
        <span v-for="[d,c] in dynastyList()" :key="d">
          <i :style="{ background: c }"></i>{{ d }}
        </span>
      </div>
    </main>

    <aside class="right"><PersonPanel /></aside>
  </div>
</template>

<style scoped>
.app {
  display: grid;
  grid-template-columns: 290px 1fr 330px;
  height: 100%;
}
aside { background: var(--surface); display: flex; flex-direction: column; min-height: 0; }
.left { border-right: 1px solid var(--line); padding: 18px 16px; gap: 14px; }
.right { border-left: 1px solid var(--line); }
.brand h1 { margin: 0; font-size: 16px; font-weight: 600; letter-spacing: -.01em; }
.brand p { margin: 3px 0 0; font-size: 11.5px; color: var(--ink-mute); }
.center { display: flex; flex-direction: column; min-width: 0; position: relative; }
.stage { flex: 1; min-height: 0; position: relative; }
.trailbar {
  display: flex; align-items: center; gap: 8px;
  padding: 7px 16px; border-bottom: 1px solid var(--line); background: var(--surface-alt);
  overflow-x: auto;
}
.trailbar .nav {
  border: 1px solid var(--line); background: var(--surface); color: var(--ink-soft);
  border-radius: 3px; padding: 1px 8px; font-size: 13px; line-height: 1.5; flex-shrink: 0;
}
.trailbar .nav:disabled { opacity: .35; cursor: default; }
.trailbar .nav:not(:disabled):hover { border-color: var(--azurite); color: var(--azurite); }
.crumbs { display: flex; align-items: center; gap: 4px; min-width: 0; }
.crumbs button {
  border: 0; background: none; color: var(--ink-mute); font-size: 12.5px;
  padding: 1px 4px; border-radius: 2px; white-space: nowrap;
}
.crumbs button:hover { color: var(--azurite); background: var(--surface); }
.crumbs button.cur { color: var(--ink); font-weight: 500; }
.crumbs .sep, .crumbs .gap { color: var(--ink-mute); font-size: 11px; flex-shrink: 0; }
.tabs {
  display: flex; border-bottom: 1px solid var(--line); background: var(--surface);
  overflow-x: auto; scrollbar-width: none;
}
.tabs::-webkit-scrollbar { display: none; }
.tabs button {
  border: 0; background: transparent; color: var(--ink-mute);
  padding: 11px 15px 9px; font-size: 13.5px;
  border-bottom: 2px solid transparent; display: flex; align-items: baseline; gap: 5px;
  white-space: nowrap; flex-shrink: 0;
}
.tabs button:hover { color: var(--ink); }
.tabs button.on { color: var(--azurite); border-bottom-color: var(--azurite); font-weight: 500; }
.tabs .mid { font-family: "JetBrains Mono", monospace; font-size: 10px; opacity: .55; }
@media (max-width: 1200px) { .tabs .mid { display: none; } }
.toolbar {
  display: flex; align-items: center; gap: 20px; flex-wrap: wrap;
  padding: 11px 16px; border-bottom: 1px solid var(--line); background: var(--surface);
}
.grp { display: flex; align-items: center; gap: 5px; }
.grp label { font-size: 11px; color: var(--ink-mute); margin-right: 3px; }
.grp button {
  border: 1px solid var(--line); background: transparent; color: var(--ink-soft);
  border-radius: 3px; padding: 3px 10px; font-size: 12px;
}
.grp button:hover { border-color: var(--azurite); }
.grp button.on { background: var(--azurite); border-color: var(--azurite); color: #fff; }
.stat { margin-left: auto; font-size: 11.5px; color: var(--ink-mute); }
.grp.export { margin-left: auto; }
.grp.export + .stat { margin-left: 0; }
.err { font-size: 12px; color: var(--cinnabar); }
.legend {
  display: flex; flex-wrap: wrap; gap: 12px;
  padding: 8px 16px; border-top: 1px solid var(--line);
  background: var(--surface); font-size: 11px; color: var(--ink-mute);
}
.legend span { display: flex; align-items: center; gap: 4px; }
.legend i { width: 8px; height: 8px; border-radius: 2px; display: inline-block; }
@media (max-width: 1100px) {
  .app { grid-template-columns: 240px 1fr; }
  .right { display: none; }
}
</style>
