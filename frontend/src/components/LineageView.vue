<script setup>
import { ref, onMounted, onBeforeUnmount, watch, computed } from 'vue'
import Graph from 'graphology'
import Sigma from 'sigma'
import { EdgeRectangleProgram } from 'sigma/rendering'
import { useGraphStore } from '../stores/graph'
import { generationColor, EGO_COLOR } from '../lineage-color'
import { phraseRelation as phrase } from '../relation-phrase'

const store = useGraphStore()
const el = ref(null)
const hovered = ref(null)
let renderer = null

// 世系不用力导向 —— 世代是有序的，按代分带排布才读得懂
const BAND_H = 165        // 代与代的间距
const GAP_X = 54          // 同代相邻两人的间距
const ROW_H = 36          // 宽代际折行后的行距
const MAX_ROW = 16        // 单行上限，超出折行，避免代际被拉成极长的一条

const bands = computed(() => {
  const m = new Map()
  for (const n of store.lineage.nodes) {
    const g = n.generation
    const key = g === null || g === undefined ? 'unknown' : g
    if (!m.has(key)) m.set(key, [])
    m.get(key).push(n)
  }
  return m
})

const rampStops = computed(() => {
  const { min, max } = genRange.value
  const out = []
  for (let i = 0; i < 7; i++) out.push(Math.round(min + (max - min) * (i / 6)))
  return out
})

const genRange = computed(() => {
  const gs = store.lineage.nodes.map(n => n.generation).filter(g => g !== null && g !== undefined)
  return { min: gs.length ? Math.min(...gs) : 0, max: gs.length ? Math.max(...gs) : 0 }
})

function build() {
  if (renderer) { renderer.kill(); renderer = null }
  const { nodes, edges } = store.lineage
  if (!nodes.length || !el.value) return

  const graph = new Graph({ multi: true })
  const b = bands.value
  const known = [...b.keys()].filter(k => k !== 'unknown').sort((a, z) => a - z)
  const unknownY = (known.length ? Math.max(...known) : 0) + 2

  for (const [key, list] of b) {
    const gen = key === 'unknown' ? unknownY : key

    // 本人置于所在代的正中，否则会落在最左端
    // 注意是 >= 0：subgraphAll 返回的子图里 ego 恰好排在第一个，
    // 写成 > 0 会把这种情况漏掉，本人就留在了最左端
    const ci = list.findIndex(n => n.isCenter)
    if (ci >= 0) {
      const [ego] = list.splice(ci, 1)
      list.splice(Math.floor(list.length / 2), 0, ego)
    }

    const rows = []
    for (let i = 0; i < list.length; i += MAX_ROW) rows.push(list.slice(i, i + MAX_ROW))

    rows.forEach((row, ri) => {
      const width = (row.length - 1) * GAP_X
      row.forEach((n, i) => {
        graph.addNode(String(n.id), {
          label: (n.label) || String(n.id),
          // y 轴向下为晚辈，与族谱阅读习惯一致
          x: -width / 2 + i * GAP_X,
          y: -gen * BAND_H - ri * ROW_H,
          size: n.isCenter ? 14 : 8,
          // 颜色编码代际，性别用饱和度作次级区分（按性别着色没信息量：库中九成是男性）
          color: n.isCenter ? EGO_COLOR
                 : generationColor(n.generation, genRange.value.min, genRange.value.max, n.female),
          isCenter: n.isCenter,
          generation: key === 'unknown' ? null : key,
          female: n.female, dynasty: n.dynasty,
          birthYear: n.birthYear, deathYear: n.deathYear
        })
      })
    })
  }

  for (const e of edges) {
    const s = String(e.source), t = String(e.target)
    if (!graph.hasNode(s) || !graph.hasNode(t)) continue
    const marital = (e.marstep || 0) > 0 && (e.upstep || 0) === 0 && (e.dwnstep || 0) === 0
    graph.addEdgeWithKey(e.id, s, t, {
      size: marital ? 1.6 : 1,
      color: marital ? 'rgba(140,106,125,.5)' : 'rgba(16,100,111,.34)',
      relLabel: e.label, relType: e.type, marital
    })
  }

  renderer = new Sigma(graph, el.value, {
    renderLabels: true,
    // 标签是屏幕固定字号，拉开图上间距再自适应缩放等于没变。
    // 真正控制重叠的是碰撞网格：格子越大、密度越低，默认视图下显示的标签越少，
    // 放大后自然显现更多。
    labelDensity: 0.6,
    labelGridCellSize: 130,
    labelRenderedSizeThreshold: 7,
    labelFont: '"Noto Sans SC", sans-serif',
    labelColor: { color: getComputedStyle(document.body).getPropertyValue('--ink').trim() || '#101A1D' },
    edgeProgramClasses: { rectangle: EdgeRectangleProgram },
    defaultEdgeType: 'rectangle'
  })

  if (import.meta.env.DEV) window.__lineage = renderer   // 仅开发期，便于定位坐标

  renderer.on('clickNode', ({ node }) => store.select(Number(node)))
  renderer.on('enterNode', ({ node }) => {
    const a = graph.getNodeAttributes(node)
    const center = String(store.centerId)

    // 代际在金字塔的行位置上已经看得见了，提示框真正该给的是具体称谓。
    // KIN 边 X→Y 读作「Y 是 X 的 R」，方向决定主语。
    const rels = []
    if (node !== center && graph.hasNode(center)) {
      graph.forEachEdge(node, (key, attr, src, tgt) => {
        if (src !== center && tgt !== center) return
        const label = attr.relLabel || '亲属关系未详'
        if (rels.some(r => r.label === label && r.toEgo === (src === center))) return
        rels.push({
          label,
          type: attr.relType || 'KIN',
          toEgo: src === center,
          subject: src === center ? graph.getNodeAttribute(center, 'label') : a.label,
          object: src === center ? a.label : graph.getNodeAttribute(center, 'label')
        })
      })
    }
    hovered.value = {
      label: a.label,
      gen: a.generation,
      isCenter: a.isCenter,
      rels,
      life: a.birthYear || a.deathYear ? `${a.birthYear ?? '?'}–${a.deathYear ?? '?'}` : null,
      dynasty: a.dynasty, female: a.female
    }
  })
  renderer.on('leaveNode', () => { hovered.value = null })
}

/** generation 0 表示「与本人同辈」（兄弟、配偶、堂表亲都在这一层），只有 ego 本身才是「本人」 */
function genLabel(g, isCenter) {
  if (isCenter) return '本人'
  if (g === null || g === undefined) return '世代未详'
  if (g === 0) return '同辈'
  return g < 0 ? `${-g} 世祖辈` : `${g} 世孙辈`
}

onMounted(build)
onBeforeUnmount(() => renderer?.kill())
watch(() => store.lineage, build, { deep: false })
</script>

<template>
  <div class="wrap">
    <div ref="el" class="canvas"></div>

    <div v-if="store.loading" class="overlay">载入中…</div>
    <div v-else-if="!store.lineage.nodes.length" class="overlay">
      该人物没有可展示的亲属记录
    </div>

    <div v-if="store.lineage.nodes.length" class="key">
      <span><i :style="{ background: EGO_COLOR }"></i>本人</span>
      <span class="ramp">
        <em>祖辈</em>
        <i v-for="g in rampStops" :key="g" :style="{ background: generationColor(g, genRange.min, genRange.max, false) }"></i>
        <em>孙辈</em>
      </span>
      <span><i style="background:#a5c7ad; border:1px solid #8facad"></i>女（同代际浅色）</span>
      <span><i class="ln" style="background:#8C6A7D"></i>婚姻</span>
      <span><i class="ln" style="background:#10646F"></i>血亲</span>
    </div>

    <div v-if="hovered" class="tip">
      <strong>{{ hovered.label }}</strong>

      <div v-if="hovered.rels && hovered.rels.length" class="rels">
        <div v-for="(r, i) in hovered.rels" :key="i" class="rel">
          <span class="s">{{ phrase(r).a }}</span>
          <span class="r" :class="{ kin: phrase(r).kin }">{{ phrase(r).mid }}</span>
          <span class="s">{{ phrase(r).b }}</span>
        </div>
      </div>
      <!-- 没有直接亲属边时才退回代际，此时代际是唯一能给的信息 -->
      <span v-else>{{ genLabel(hovered.gen, hovered.isCenter) }}</span>

      <span v-if="hovered.female">女</span>
      <span v-if="hovered.life">{{ hovered.life }}</span>
    </div>
  </div>
</template>

<style scoped>
.wrap { position: relative; height: 100%; background: var(--surface); }
.canvas { position: absolute; inset: 0; }
.overlay {
  position: absolute; inset: 0; display: grid; place-items: center;
  color: var(--ink-mute); pointer-events: none; font-size: 14px;
}
.key {
  position: absolute; right: 14px; top: 14px; display: flex; gap: 13px;
  background: var(--surface); border: 1px solid var(--line); border-radius: 3px;
  padding: 6px 12px; font-size: 11px; color: var(--ink-mute);
}
.key span { display: flex; align-items: center; gap: 4px; }
.key i { width: 8px; height: 8px; border-radius: 2px; }
.key .ramp { gap: 3px; }
.key .ramp i { width: 11px; height: 8px; border-radius: 0; margin: 0; }
.key .ramp i:first-of-type { border-radius: 2px 0 0 2px; }
.key .ramp i:last-of-type { border-radius: 0 2px 2px 0; }
.key .ramp em { font-style: normal; }
.key i.ln { width: 14px; height: 2px; border-radius: 1px; }
.tip {
  position: absolute; left: 14px; bottom: 14px;
  background: var(--surface); border: 1px solid var(--line); border-radius: 3px;
  padding: 9px 13px; display: flex; flex-direction: column; gap: 1px;
  font-size: 12px; color: var(--ink-mute); pointer-events: none;
}
.tip { max-width: 280px; }
.tip strong { font-size: 15px; color: var(--ink); font-weight: 500; }
.tip .rels {
  display: flex; flex-direction: column; gap: 4px;
  margin: 6px 0 3px; padding-top: 6px; border-top: 1px dashed var(--line);
}
.tip .rel { display: flex; align-items: baseline; gap: 4px; flex-wrap: wrap; }
.tip .rel .s { color: var(--ink); font-size: 12.5px; }
.tip .rel .k { color: var(--ink-mute); font-size: 12px; }
.tip .rel .r::before, .src-card .line .r::before { content: "─"; opacity: .5; margin-right: 2px; }
.tip .rel .r::after, .src-card .line .r::after { content: "→"; opacity: .7; margin-left: 2px; }
.tip .rel .r.kin, .src-card .line .r.kin { color: var(--malachite); border-color: var(--malachite); }
.tip .rel .r {
  color: var(--cinnabar); font-size: 12px;
  padding: 0 5px; border: 1px solid var(--cinnabar); border-radius: 2px;
}
</style>
