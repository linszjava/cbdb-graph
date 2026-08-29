<script setup>
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue'
import Graph from 'graphology'
import Sigma from 'sigma'
import { EdgeRectangleProgram } from 'sigma/rendering'
import FA2Layout from 'graphology-layout-forceatlas2/worker'
import forceAtlas2 from 'graphology-layout-forceatlas2'
import { useGraphStore } from '../stores/graph'
import { dynastyColor, communityColor } from '../dynasty'
import { phraseRelation as phrase } from '../relation-phrase'

const store = useGraphStore()
const el = ref(null)
const hovered = ref(null)
const picked = ref(null)   // 被点中的边：关系 + 史料出处
let renderer = null
let layout = null
let graph = null
let highlighted = new Map()   // 悬停时被高亮的边 → 原样式

const EDGE_COLOR = { ASSOC: 'rgba(16,100,111,.30)', KIN: 'rgba(168,68,58,.34)' }

const renderError = ref('')
const shownCommunity = ref(null)   // 图例中被展开的社群
const legendOpen = ref(false)
const relPanelOpen = ref(false)

const relTypesInGraph = computed(() => {
  const cnt = new Map()
  for (const e of store.activeGraph.edges) {
    const k = e.label || '关系未详'
    const cur = cnt.get(k) || { label: k, type: e.type, n: 0 }
    cur.n++
    cnt.set(k, cur)
  }
  return [...cnt.values()].sort((a, b) => b.n - a.n)
})

function toggleRelLabel(label) {
  const cur = store.relLabelFilter
  store.relLabelFilter = cur.includes(label)
    ? cur.filter(x => x !== label)
    : [...cur, label]
}      // 默认收起 —— 它挡住的正是图的左上角，需要时再展开

// 当前图里出现的社群，按人数降序。只在按社群着色时才有意义。
const communitiesInGraph = computed(() => {
  if (store.colorBy !== 'community') return []
  const cnt = new Map()
  for (const n of store.renderGraph.nodes) {
    if (n.community == null) continue
    cnt.set(n.community, (cnt.get(n.community) || 0) + 1)
  }
  // 本图中只有一人的社群没有信息量，折叠成一行计数
  const all = [...cnt.entries()].sort((a, b) => b[1] - a[1])
  return all.filter(([, n]) => n > 1).slice(0, 10)
            .map(([cid, inGraph]) => ({ cid, inGraph }))
})

const singletons = computed(() => {
  if (store.colorBy !== 'community') return 0
  const cnt = new Map()
  for (const n of store.renderGraph.nodes) {
    if (n.community == null) continue
    cnt.set(n.community, (cnt.get(n.community) || 0) + 1)
  }
  return [...cnt.values()].filter(n => n === 1).length
})

// 图例里显示的都取画像 —— 已折叠掉单人社群，数量可控
watch(communitiesInGraph, list => {
  for (const c of list) store.resolveCommunity(c.cid)
}, { immediate: true })

function build() {
  try { buildInner() } catch (e) {
    renderError.value = `图形渲染失败：${e.message}`
    console.error('[NetworkCanvas]', e)
  }
}

function buildInner() {
  renderError.value = ''
  highlighted = new Map()
  // 换了人物就把上一张图的悬停提示与钉住卡片清掉，否则会残留旧关系
  hovered.value = null
  picked.value = null
  if (layout) { layout.kill(); layout = null }
  if (renderer) { renderer.kill(); renderer = null }

  graph = new Graph({ multi: true })

  const { nodes, edges } = store.renderGraph
  if (!nodes.length) return

  nodes.forEach(n => {
    graph.addNode(String(n.id), {
      label: (n.label) || String(n.id),
      x: n.isCenter ? 0 : (Math.random() - 0.5) * 400,
      y: n.isCenter ? 0 : (Math.random() - 0.5) * 400,
      size: n.isCenter ? 14 : 5,
      color: n.isCenter ? '#A8443A'
             : (store.colorBy === 'community' ? communityColor(n.community) : dynastyColor(n.dynasty)),
      dynasty: n.dynasty, year: n.year, isCenter: n.isCenter
    })
  })

  edges.forEach(e => {
    const s = String(e.source), t = String(e.target)
    if (!graph.hasNode(s) || !graph.hasNode(t)) return
    graph.addEdgeWithKey(e.id, s, t, {
      size: 1.8,
      color: EDGE_COLOR[e.type] || 'rgba(120,140,140,.3)',
      relLabel: e.label, relType: e.type, year: e.year,
      sourceRef: e.sourceRef, pages: e.pages, textTitle: e.textTitle
    })
  })

  // 度数驱动节点大小，让枢纽人物在图上先被看见
  graph.forEachNode(k => {
    if (graph.getNodeAttribute(k, 'isCenter')) return
    const d = graph.degree(k)
    graph.setNodeAttribute(k, 'size', Math.min(4 + Math.sqrt(d) * 1.6, 13))
  })

  renderer = new Sigma(graph, el.value, {
    renderLabels: true,
    labelDensity: 0.18,
    labelGridCellSize: 120,
    labelRenderedSizeThreshold: 9,
    labelFont: '"Noto Sans SC", sans-serif',
    labelColor: { color: getComputedStyle(document.body).getPropertyValue('--ink').trim() || '#101A1D' },
    // rectangle 程序不在默认注册表里，须自行注册后才能用。
    // 默认的 'line' 以 gl.LINES 绘制，既忽略 size 也无法拾取 —— 边会点不中。
    edgeProgramClasses: { rectangle: EdgeRectangleProgram },
    defaultEdgeType: 'rectangle',
    // Sigma v3 默认不监听边事件（性能考虑），M8 点边查出处必须显式打开
    enableEdgeEvents: true,
    zIndex: true
  })

  if (import.meta.env.DEV) window.__sigma = renderer   // 仅开发期，便于定位坐标

  renderer.on('clickNode', async ({ node }) => {
    const center = String(store.centerId)
    if (node === center) { picked.value = null; return }

    const a = graph.getNodeAttributes(node)
    const centerLabel = graph.hasNode(center) ? graph.getNodeAttribute(center, 'label') : ''
    const rels = []
    graph.forEachEdge(node, (key, attr, src, tgt) => {
      if (src !== center && tgt !== center) return
      rels.push({
        label: attr.relLabel || '关系未详', year: attr.year, type: attr.relType,
        subject: src === center ? centerLabel : a.label,
        object: src === center ? a.label : centerLabel,
        textTitle: attr.textTitle,
        sourceRef: attr.sourceRef, pages: attr.pages,
        source: null, loading: attr.sourceRef != null
      })
    })

    picked.value = { personId: Number(node), label: a.label, dynasty: a.dynasty, rels }
    await fillSources(picked.value)
  })

  // M8：点边查出处
  renderer.on('clickEdge', async ({ edge }) => {
    const a = graph.getEdgeAttributes(edge)
    const [src, tgt] = graph.extremities(edge)
    const other = String(store.centerId) === src ? tgt : src
    const rel = {
      label: a.relLabel || '关系未详', year: a.year, type: a.relType,
      textTitle: a.textTitle,
      subject: graph.getNodeAttribute(src, 'label'),
      object: graph.getNodeAttribute(tgt, 'label'),
      sourceRef: a.sourceRef, pages: a.pages,
      source: null, loading: a.sourceRef != null
    }
    picked.value = {
      personId: Number(other),
      label: graph.getNodeAttribute(other, 'label'),
      dynasty: graph.getNodeAttribute(other, 'dynasty'),
      rels: [rel]
    }
    await fillSources(picked.value)
  })
  renderer.on('clickStage', () => { picked.value = null })
  renderer.on('enterNode', ({ node }) => {
    const a = graph.getNodeAttributes(node)
    const center = String(store.centerId)
    const centerLabel = graph.hasNode(center) ? graph.getNodeAttribute(center, 'label') : ''

    // 找出此人与中心人物之间的边 —— 一对人之间可能同时有多种关系
    const rels = []
    if (node !== center && graph.hasNode(center)) {
      graph.forEachEdge(node, (key, attr, src, tgt) => {
        if (src !== center && tgt !== center) return
        // 同一对人的同类关系可能有多条（如楼钥为苏轼作过九篇题跋），
        // 悬停时折叠成一行计数，详情留给点击后的卡片
        const key2 = (attr.relType || '') + '|' + (attr.relLabel || '') + '|' +
                     (src === center ? '>' : '<')
        const hit = rels.find(x => x.key === key2)
        if (hit) hit.count++
        else rels.push({
          key: key2,
          label: attr.relLabel || '关系未详',
          type: attr.relType,
          year: attr.year,
          count: 1,
          // CBDB 的边 A→B 读作「B 是 A 的某关系」，方向决定主语是谁
          subject: src === center ? centerLabel : a.label,
          object: src === center ? a.label : centerLabel
        })
        highlight(key)
      })
    }
    if (a.community != null) store.resolveCommunity(a.community)
    hovered.value = {
      label: a.label, dynasty: a.dynasty, year: a.year,
      degree: graph.degree(node), isCenter: node === center, rels,
      community: a.community
    }
  })
  renderer.on('leaveNode', () => { hovered.value = null; clearHighlights() })

  /**
   * 按需补齐出处。必须通过 picked.value.rels 这个响应式代理写入 ——
   * 改写构造时捕获的原始数组不会触发视图更新，卡片会永远停在「查出处中」。
   */
  async function fillSources(card) {
    for (let i = 0; i < card.rels.length; i++) {
      const ref = card.rels[i].sourceRef
      if (ref == null) continue
      const src = await store.resolveSource(ref)
      if (picked.value !== card) return          // 期间已切换选中项
      picked.value.rels[i].source = src
      picked.value.rels[i].loading = false
    }
  }

  function highlight(key) {
    if (highlighted.has(key)) return
    highlighted.set(key, {
      size: graph.getEdgeAttribute(key, 'size'),
      color: graph.getEdgeAttribute(key, 'color')
    })
    graph.setEdgeAttribute(key, 'size', 4)
    graph.setEdgeAttribute(key, 'color', 'rgba(168,68,58,.9)')
  }

  function clearHighlights() {
    for (const [key, prev] of highlighted) {
      if (!graph.hasEdge(key)) continue
      graph.setEdgeAttribute(key, 'size', prev.size)
      graph.setEdgeAttribute(key, 'color', prev.color)
    }
    highlighted.clear()
  }

  // 悬停加粗，给出「这条边可点」的反馈
  renderer.on('enterEdge', ({ edge }) => {
    graph.setEdgeAttribute(edge, 'size', 4)
    graph.setEdgeAttribute(edge, 'color', 'rgba(16,100,111,.85)')
    el.value.style.cursor = 'pointer'
  })
  renderer.on('leaveEdge', ({ edge }) => {
    const t = graph.getEdgeAttribute(edge, 'relType')
    graph.setEdgeAttribute(edge, 'size', 1.8)
    graph.setEdgeAttribute(edge, 'color', EDGE_COLOR[t] || 'rgba(120,140,140,.3)')
    el.value.style.cursor = ''
  })

  const settings = {
    ...forceAtlas2.inferSettings(graph),
    barnesHutOptimize: graph.order > 300,
    outboundAttractionDistribution: true,
    adjustSizes: true,
    scalingRatio: 14,
    gravity: 1.2,
    slowDown: 5
  }

  // 先同步跑一轮把大结构定下来，避免弱连接节点停在初始位置形成弧形残影。
  // 迭代数随规模递减 —— 几千节点跑 400 轮会把主线程卡住好几秒
  const iters = graph.order > 3000 ? 80 : graph.order > 1200 ? 160 : 400
  forceAtlas2.assign(graph, { iterations: iters, settings })
  renderer.refresh()

  // 再交给 Web Worker 做细部抛光 —— 迭代放主线程会把 UI 卡死
  layout = new FA2Layout(graph, { settings })
  layout.start()
  setTimeout(() => layout && layout.stop(), graph.order > 1200 ? 6000 : 3000)
}

onMounted(build)
onBeforeUnmount(() => { layout?.kill(); renderer?.kill() })
watch(() => store.renderGraph, build, { deep: false })
watch(() => store.colorBy, build)
</script>

<template>
  <div class="canvas-wrap">
    <div ref="el" class="canvas"></div>

    <div v-if="renderError" class="overlay err">{{ renderError }}</div>
    <div v-else-if="store.loading" class="overlay">载入中…</div>
    <div v-else-if="!store.renderGraph.nodes.length" class="overlay hint">
      <template v-if="store.relLabelFilter.length">该关系类型下没有节点</template>
      <template v-else>{{ store.view === 'group' ? '先在上方选一个身份、郡望或朝代' : '在左侧搜索一个人物开始' }}</template>
    </div>

    <div v-if="hovered && !picked" class="tip">
      <strong>{{ hovered.label }}</strong>
      <span>{{ hovered.dynasty || '朝代未详' }}<template v-if="hovered.year"> · {{ hovered.year }}</template></span>

      <div v-if="hovered.rels && hovered.rels.length" class="rels">
        <div v-for="(r, i) in hovered.rels" :key="i" class="rel">
          <span class="s">{{ phrase(r).a }}</span>
          <span class="r" :class="{ kin: phrase(r).kin }">{{ phrase(r).mid }}</span>
          <span class="s">{{ phrase(r).b }}</span>
          <span class="n" v-if="r.count > 1">×{{ r.count }}</span>
          <span class="y" v-if="r.year">{{ r.year }}</span>
        </div>
      </div>
      <span v-else-if="!hovered.isCenter" class="none">与中心人物无直接关系（经他人相连）</span>

      <span class="deg">本图中 {{ hovered.degree }} 条连线</span>
      <span class="comm" v-if="hovered.community != null && store.communities[hovered.community]">
        属 {{ store.communities[hovered.community].label }} 群
        <i>{{ store.communities[hovered.community].size }} 人</i>
      </span>
    </div>

    <div v-if="picked" class="src-card">
      <button class="x" @click="picked = null" aria-label="关闭">×</button>
      <div class="hd">
        <strong>{{ picked.label }}</strong>
        <span class="dy">{{ picked.dynasty || '朝代未详' }}</span>
      </div>

      <div class="rels" v-if="picked.rels.length">
        <div v-for="(r, i) in picked.rels" :key="i" class="one">
          <div class="line">
            <span class="s">{{ phrase(r).a }}</span>
            <span class="r" :class="{ kin: phrase(r).kin }">{{ phrase(r).mid }}</span>
            <span class="s">{{ phrase(r).b }}</span>
            <span class="y" v-if="r.year">{{ r.year }}</span>
          </div>
          <div class="txt" v-if="r.textTitle">{{ r.textTitle }}</div>
          <div class="prov">
            <template v-if="r.loading">查出处中…</template>
            <template v-else-if="r.source">
              {{ r.source.titleChn }}<span v-if="r.pages"> · 页码 {{ r.pages }}</span>
            </template>
            <template v-else>未著录出处</template>
          </div>
        </div>
      </div>
      <p v-else class="none">与中心人物无直接关系</p>

      <button class="go" @click="store.select(picked.personId); picked = null">
        以此人为中心 →
      </button>
    </div>

    <div v-if="communitiesInGraph.length" class="legend-comm" :class="{ folded: !legendOpen }">
      <button class="hd" @click="legendOpen = !legendOpen"
              :title="legendOpen ? '收起' : '展开'">
        <span class="t">社群</span>
        <span class="n" v-if="!legendOpen">{{ communitiesInGraph.length }}</span>
        <span class="cx">{{ legendOpen ? '－' : '＋' }}</span>
      </button>

      <template v-if="legendOpen">
      <div v-for="c in communitiesInGraph" :key="c.cid" class="item"
           :class="{ open: shownCommunity === c.cid }"
           @click="shownCommunity = shownCommunity === c.cid ? null : c.cid; store.resolveCommunity(c.cid)">
        <i :style="{ background: communityColor(c.cid) }"></i>
        <span class="nm">{{ store.communities[c.cid]?.label || '载入中…' }}</span>
        <span class="ct">{{ c.inGraph }}</span>

        <div v-if="shownCommunity === c.cid && store.communities[c.cid]" class="detail" @click.stop>
          <p class="line">
            全库 <b>{{ store.communities[c.cid].size }}</b> 人 ·
            {{ store.communities[c.cid].dynasty || '朝代未详' }}
            <template v-if="store.communities[c.cid].eraFrom">
              · {{ store.communities[c.cid].eraFrom }}–{{ store.communities[c.cid].eraTo }}
            </template>
          </p>
          <p class="line" v-if="store.communities[c.cid].topMembers?.length">
            <em>代表</em>
            <button v-for="m in store.communities[c.cid].topMembers.slice(0,8)" :key="m.id"
                    @click="store.select(m.id)">{{ m.name }}</button>
          </p>
          <p class="line" v-if="store.communities[c.cid].topStatuses?.length">
            <em>身份</em>{{ store.communities[c.cid].topStatuses.slice(0,4).map(s => s.value).join('、') }}
          </p>
          <p class="line" v-if="store.communities[c.cid].topPlaces?.length">
            <em>籍贯</em>{{ store.communities[c.cid].topPlaces.slice(0,4).map(p => p.value).join('、') }}
          </p>
        </div>
      </div>
      <p v-if="singletons" class="single">另有 {{ singletons }} 个社群在本图中各仅 1 人</p>
      </template>
    </div>

    <div v-if="relTypesInGraph.length" class="relpanel" :class="{ folded: !relPanelOpen }">
      <button class="hd" @click="relPanelOpen = !relPanelOpen">
        <span class="t">关系类型</span>
        <span class="n" v-if="store.relLabelFilter.length">已选 {{ store.relLabelFilter.length }}</span>
        <span class="n" v-else-if="!relPanelOpen">{{ relTypesInGraph.length }}</span>
        <span class="cx">{{ relPanelOpen ? '－' : '＋' }}</span>
      </button>

      <template v-if="relPanelOpen">
        <div class="chips">
          <button v-for="r in relTypesInGraph" :key="r.label"
                  :class="{ on: store.relLabelFilter.includes(r.label), kin: r.type === 'KIN' }"
                  @click="toggleRelLabel(r.label)">
            {{ r.label }}<em>{{ r.n }}</em>
          </button>
        </div>
        <button v-if="store.relLabelFilter.length" class="clear"
                @click="store.relLabelFilter = []">显示全部关系</button>
      </template>
    </div>

    <div v-if="store.activeGraph.truncated" class="trunc">
      仅显示 {{ store.nodeCount }} 个 —— 该人物共有 {{ store.activeGraph.totalAvailable }} 位直接关联者
    </div>
  </div>
</template>

<style scoped>
.canvas-wrap { position: relative; height: 100%; background: var(--surface); }
.canvas { position: absolute; inset: 0; }
.overlay {
  position: absolute; inset: 0; display: grid; place-items: center;
  color: var(--ink-mute); pointer-events: none; font-size: 14px;
}
.overlay.err { color: var(--cinnabar); }
.tip {
  position: absolute; left: 14px; bottom: 14px;
  background: var(--surface); border: 1px solid var(--line);
  border-radius: 3px; padding: 9px 13px;
  display: flex; flex-direction: column; gap: 1px;
  font-size: 12px; color: var(--ink-mute); pointer-events: none;
  box-shadow: 0 6px 20px -10px rgba(0,0,0,.3);
}
.tip { max-width: 300px; }
.tip strong { font-size: 15px; color: var(--ink); font-weight: 500; }
.tip .rels {
  display: flex; flex-direction: column; gap: 4px;
  margin: 7px 0 5px; padding-top: 7px; border-top: 1px dashed var(--line);
}
.tip .rel { display: flex; align-items: baseline; gap: 5px; flex-wrap: wrap; }
.tip .rel .s { color: var(--ink); font-size: 12.5px; }
.tip .rel .r::before, .src-card .line .r::before { content: "─"; opacity: .5; margin-right: 2px; }
.tip .rel .r::after, .src-card .line .r::after { content: "→"; opacity: .7; margin-left: 2px; }
.tip .rel .r.kin, .src-card .line .r.kin { color: var(--malachite); border-color: var(--malachite); }
.tip .rel .r {
  color: var(--cinnabar); font-size: 12px;
  padding: 0 5px; border: 1px solid var(--cinnabar); border-radius: 2px;
}
.tip .rel .k { color: var(--ink-mute); font-size: 12px; }
.tip .rel .n {
  color: var(--azurite); font-size: 11px; font-weight: 500;
  font-family: "JetBrains Mono", monospace;
}
.tip .rel .y { color: var(--ink-mute); font-size: 11px; font-family: "JetBrains Mono", monospace; }
.tip .none { color: var(--ink-mute); font-style: italic; margin-top: 5px; }
.tip .deg { margin-top: 4px; }
.src-card {
  position: absolute; right: 14px; bottom: 14px; width: 292px;
  max-height: 62%; overflow-y: auto;
  background: var(--surface); border: 1px solid var(--line);
  border-left: 3px solid var(--azurite); border-radius: 3px;
  padding: 14px 16px 14px; font-size: 12.5px;
  box-shadow: 0 8px 26px -12px rgba(0,0,0,.35);
}
.src-card .x {
  position: absolute; right: 8px; top: 6px; border: 0; background: none;
  color: var(--ink-mute); font-size: 16px; line-height: 1; padding: 2px 5px;
}
.src-card .x:hover { color: var(--ink); }
.src-card .hd { display: flex; align-items: baseline; gap: 8px; padding-right: 18px; }
.src-card .hd strong { color: var(--ink); font-size: 15px; font-weight: 500; }
.src-card .hd .dy { color: var(--azurite); font-size: 11px; }
.src-card .rels {
  display: flex; flex-direction: column; gap: 9px;
  margin: 10px 0 12px; padding-top: 9px; border-top: 1px dashed var(--line);
}
.src-card .line { display: flex; align-items: baseline; gap: 5px; flex-wrap: wrap; }
.src-card .line .s { color: var(--ink); }
.src-card .line .r {
  color: var(--cinnabar); font-size: 11.5px;
  padding: 0 5px; border: 1px solid var(--cinnabar); border-radius: 2px;
}
.src-card .line .k { color: var(--ink-mute); font-size: 12px; }
.src-card .line .y {
  color: var(--ink-mute); font-size: 11px;
  font-family: "JetBrains Mono", monospace;
}
.src-card .txt { color: var(--ink-soft); font-size: 11.5px; margin-top: 3px; }
.src-card .prov { color: var(--ink-mute); font-size: 11px; margin-top: 2px; }
.src-card .none { color: var(--ink-mute); margin: 10px 0 12px; font-style: italic; }
.src-card .go {
  width: 100%; border: 1px solid var(--azurite); background: transparent;
  color: var(--azurite); border-radius: 3px; padding: 6px; font-size: 12px;
}
.src-card .go:hover { background: var(--azurite); color: #fff; }
.legend-comm {
  position: absolute; left: 14px; top: 14px; width: 232px;
  max-height: 78%; overflow-y: auto;
  background: var(--surface); border: 1px solid var(--line); border-radius: 3px;
  padding: 9px 10px; font-size: 12px;
  box-shadow: 0 8px 26px -14px rgba(0,0,0,.35);
}
.legend-comm.folded { width: auto; padding: 5px 6px; }
.legend-comm .hd {
  display: flex; align-items: center; gap: 6px; width: 100%;
  border: 0; background: none; padding: 0 2px 6px; margin-bottom: 6px;
  border-bottom: 1px solid var(--line);
  font-size: 10px; letter-spacing: .1em; text-transform: uppercase;
  color: var(--ink-mute);
}
.legend-comm.folded .hd { border-bottom: 0; padding-bottom: 0; margin-bottom: 0; }
.legend-comm .hd:hover { color: var(--azurite); }
.legend-comm .hd .t { flex: 1; text-align: left; }
.legend-comm .hd .n {
  font-family: "JetBrains Mono", monospace; color: var(--azurite); letter-spacing: 0;
}
.legend-comm .hd .cx { font-size: 12px; line-height: 1; }
.legend-comm .item {
  display: flex; align-items: center; gap: 6px; flex-wrap: wrap;
  padding: 4px 5px; border-radius: 2px; cursor: pointer;
}
.legend-comm .item:hover { background: var(--surface-alt); }
.legend-comm .item.open { background: var(--surface-alt); }
.legend-comm .item i { width: 9px; height: 9px; border-radius: 2px; flex-shrink: 0; }
.legend-comm .nm { color: var(--ink); flex: 1; min-width: 0; }
.legend-comm .ct {
  color: var(--ink-mute); font-size: 11px;
  font-family: "JetBrains Mono", monospace; font-variant-numeric: tabular-nums;
}
.legend-comm .detail {
  flex-basis: 100%; margin-top: 5px; padding-top: 6px;
  border-top: 1px dashed var(--line); cursor: default;
}
.legend-comm .line { margin: 0 0 4px; font-size: 11.5px; color: var(--ink-soft); line-height: 1.65; }
.legend-comm .line em { font-style: normal; color: var(--ink-mute); margin-right: 5px; }
.legend-comm .line b { color: var(--azurite); }
.legend-comm .detail button {
  border: 0; background: none; color: var(--azurite); padding: 0 3px;
  font-size: 11.5px; text-decoration: underline; text-decoration-style: dotted;
}
.legend-comm .detail button:hover { text-decoration-style: solid; }
.legend-comm .single {
  margin: 6px 0 0; padding-top: 6px; border-top: 1px dashed var(--line);
  font-size: 11px; color: var(--ink-mute);
}
.relpanel {
  position: absolute; right: 14px; bottom: 14px; width: 264px;
  max-height: 62%; overflow-y: auto;
  background: var(--surface); border: 1px solid var(--line); border-radius: 3px;
  padding: 9px 10px; font-size: 12px;
  box-shadow: 0 8px 26px -14px rgba(0,0,0,.35);
}
.relpanel.folded { width: auto; padding: 5px 6px; }
.relpanel .hd {
  display: flex; align-items: center; gap: 6px; width: 100%;
  border: 0; background: none; padding: 0 2px 6px; margin-bottom: 6px;
  border-bottom: 1px solid var(--line);
  font-size: 10px; letter-spacing: .1em; text-transform: uppercase; color: var(--ink-mute);
}
.relpanel.folded .hd { border-bottom: 0; padding-bottom: 0; margin-bottom: 0; }
.relpanel .hd:hover { color: var(--azurite); }
.relpanel .hd .t { flex: 1; text-align: left; }
.relpanel .hd .n {
  font-family: "JetBrains Mono", monospace; color: var(--azurite); letter-spacing: 0;
}
.relpanel .hd .cx { font-size: 12px; line-height: 1; }
.relpanel .chips { display: flex; flex-wrap: wrap; gap: 4px; }
.relpanel .chips button {
  border: 1px solid var(--line); background: var(--surface); color: var(--ink-soft);
  border-radius: 3px; padding: 2px 7px; font-size: 11.5px;
  display: inline-flex; align-items: baseline; gap: 4px;
}
.relpanel .chips button:hover { border-color: var(--azurite); color: var(--azurite); }
.relpanel .chips button.on {
  background: var(--azurite); border-color: var(--azurite); color: #fff;
}
.relpanel .chips button.kin { border-style: dashed; }
.relpanel .chips button.kin.on { background: var(--cinnabar); border-color: var(--cinnabar); }
.relpanel .chips em {
  font-style: normal; font-size: 10px; opacity: .65;
  font-family: "JetBrains Mono", monospace;
}
.relpanel .clear {
  margin-top: 8px; width: 100%; border: 1px solid var(--line); background: transparent;
  color: var(--ink-mute); border-radius: 3px; padding: 4px; font-size: 11.5px;
}
.relpanel .clear:hover { border-color: var(--azurite); color: var(--azurite); }
.tip .comm {
  margin-top: 4px; padding-top: 4px; border-top: 1px dashed var(--line);
  color: var(--malachite); font-size: 11.5px;
}
.tip .comm i { font-style: normal; color: var(--ink-mute); margin-left: 4px; }
.trunc {
  position: absolute; right: 14px; top: 14px;
  background: var(--azurite-lo); border: 1px solid var(--azurite);
  color: var(--azurite); border-radius: 3px;
  padding: 6px 11px; font-size: 11.5px;
}
</style>
