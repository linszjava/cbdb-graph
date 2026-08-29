<script setup>
import { ref, onMounted, onBeforeUnmount, watch, computed } from 'vue'
import * as echarts from 'echarts'
import chinaGeo from 'china-geojson/src/geojson/china.json'
import { useGraphStore } from '../stores/graph'

const store = useGraphStore()
const el = ref(null)
let chart = null
let registered = false

const points = computed(() => store.atlas.filter(p => p.x && p.y))
const posted = computed(() => points.value.filter(p => p.kind === 'POSTED_AT'))
const lived = computed(() => points.value.filter(p => p.kind === 'LIVED_IN'))

// 有纪年的任职地按时间连成宦游轨迹
const trajectory = computed(() => {
  const seq = posted.value.filter(p => p.firstYear).sort((a, b) => a.firstYear - b.firstYear)
  const lines = []
  for (let i = 1; i < seq.length; i++) {
    if (seq[i - 1].name === seq[i].name) continue
    lines.push({
      coords: [[seq[i - 1].x, seq[i - 1].y], [seq[i].x, seq[i].y]],
      value: `${seq[i - 1].name} → ${seq[i].name}`
    })
  }
  return lines
})

const ink = () => getComputedStyle(document.body).getPropertyValue('--ink').trim() || '#101A1D'
const line = () => getComputedStyle(document.body).getPropertyValue('--line').trim() || '#D6E1E1'
const surf = () => getComputedStyle(document.body).getPropertyValue('--surface-alt').trim() || '#EAF0F0'

function render() {
  if (!el.value) return
  if (!registered) { echarts.registerMap('china', chinaGeo); registered = true }
  if (!chart) chart = echarts.init(el.value, null, { renderer: 'canvas' })

  const mk = p => ({
    name: p.name,
    value: [p.x, p.y],
    year: p.firstYear,
    office: p.office,
    subtype: p.subtype
  })

  chart.setOption({
    backgroundColor: 'transparent',
    tooltip: {
      trigger: 'item',
      formatter: pm => {
        const d = pm.data
        if (!d || !d.name) return pm.name || ''
        const bits = [`<b>${d.name}</b>`]
        if (d.office) bits.push(d.office)
        if (d.subtype) bits.push(d.subtype)
        if (d.year) bits.push(`${d.year} 年`)
        return bits.join('<br/>')
      }
    },
    geo: {
      map: 'china',
      roam: true,
      zoom: 1.15,
      center: [110, 34],
      itemStyle: { areaColor: surf(), borderColor: line(), borderWidth: 0.8 },
      emphasis: { itemStyle: { areaColor: surf() }, label: { show: false } },
      // 现代省界与历史政区不符，仅作方位参照
      silent: true
    },
    series: [
      {
        name: '宦游轨迹',
        type: 'lines',
        coordinateSystem: 'geo',
        data: trajectory.value,
        lineStyle: { color: '#A8443A', width: 1.1, opacity: .45, curveness: .22 },
        effect: { show: false },
        zlevel: 1
      },
      {
        name: '居址',
        type: 'scatter',
        coordinateSystem: 'geo',
        data: lived.value.map(mk),
        symbolSize: 7,
        itemStyle: { color: '#3F7F63', opacity: .75 },
        zlevel: 2
      },
      {
        name: '任职地',
        type: 'scatter',
        coordinateSystem: 'geo',
        data: posted.value.map(mk),
        symbolSize: 10,
        itemStyle: { color: '#10646F', opacity: .9 },
        zlevel: 3
      }
    ]
  }, true)
}

const onResize = () => chart && chart.resize()
onMounted(() => { render(); window.addEventListener('resize', onResize) })
onBeforeUnmount(() => {
  window.removeEventListener('resize', onResize)
  chart?.dispose(); chart = null
})
watch(() => store.atlas, render, { deep: false })
</script>

<template>
  <div class="wrap">
    <div ref="el" class="map"></div>

    <div v-if="store.loading" class="overlay">载入中…</div>
    <div v-else-if="!points.length" class="overlay">该人物没有带坐标的地理记录</div>

    <div v-if="points.length" class="key">
      <span><i style="background:#10646F"></i>任职地 {{ posted.length }}</span>
      <span><i style="background:#3F7F63"></i>居址 {{ lived.length }}</span>
      <span><i class="ln" style="background:#A8443A"></i>宦游轨迹 {{ trajectory.length }} 段</span>
    </div>

    <p v-if="points.length" class="caveat">底图为现代省界，与历史政区不符，仅作方位参照</p>
  </div>
</template>

<style scoped>
.wrap { position: relative; height: 100%; background: var(--surface); }
.map { position: absolute; inset: 0; }
.overlay {
  position: absolute; inset: 0; display: grid; place-items: center;
  color: var(--ink-mute); pointer-events: none; font-size: 14px;
}
.key {
  position: absolute; left: 14px; top: 14px; display: flex; gap: 14px;
  background: var(--surface); border: 1px solid var(--line); border-radius: 3px;
  padding: 6px 12px; font-size: 11.5px; color: var(--ink-mute);
}
.key span { display: flex; align-items: center; gap: 5px; }
.key i { width: 8px; height: 8px; border-radius: 50%; }
.key i.ln { width: 15px; height: 2px; border-radius: 1px; }
.caveat {
  position: absolute; right: 14px; bottom: 12px; margin: 0;
  font-size: 11px; color: var(--ink-mute);
}
</style>
