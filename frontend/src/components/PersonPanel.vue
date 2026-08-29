<script setup>
import { computed } from 'vue'
import { useGraphStore } from '../stores/graph'
import { toNianHao } from '../nianhao'

const store = useGraphStore()
const p = computed(() => store.person)
const nm = computed(() => p.value?.nameChn)

const life = computed(() => {
  if (!p.value) return ''
  const { birthYear: b, deathYear: d, indexYear: i } = p.value
  if (b && d) return `${b}–${d}`
  if (b) return `${b}– `
  if (d) return `–${d}`
  if (i) return `约 ${i}`
  return '生卒未详'
})

// 史料里写的是年号纪年，不是公元
const lifeNH = computed(() => {
  if (!p.value) return ''
  const dy = p.value.dynasty
  const b = toNianHao(p.value.birthYear, dy)
  const d = toNianHao(p.value.deathYear, dy)
  if (b && d) return `${b} – ${d}`
  return b || d || ''
})

const uniq = (arr, key) => {
  const seen = new Set(), out = []
  for (const x of arr || []) {
    const v = x?.[key]
    if (!v || seen.has(v)) continue
    seen.add(v); out.push(x)
  }
  return out
}
const addresses = computed(() => uniq(p.value?.addresses, 'place'))
const offices = computed(() => uniq(p.value?.offices, 'office'))
const entries = computed(() => uniq(p.value?.entries, 'entry'))
const texts = computed(() => uniq(p.value?.texts, 'title'))
</script>

<template>
  <div v-if="p" class="prof">
    <header>
      <h2>{{ nm }}</h2>
      <p class="sub">{{ p.name }} · {{ p.dynasty || '朝代未详' }} · {{ life }}</p>
      <p class="nh" v-if="lifeNH">{{ lifeNH }}</p>

      <div class="chips" v-if="p.altLabels?.length || p.choronym">
        <span v-for="a in p.altLabels" :key="a" class="chip alt-chip">{{ a }}</span>
        <span v-if="p.choronym" class="chip chor">郡望 {{ p.choronym }}</span>
      </div>
      <div class="chips" v-if="p.statuses?.length">
        <span v-for="st in p.statuses" :key="st" class="chip st">{{ st }}</span>
      </div>
      <div class="degrees">
        <span><b>{{ p.assocDegree }}</b> 社会关系</span>
        <span><b>{{ p.kinDegree }}</b> 亲属关系</span>
      </div>
      <div class="metrics" v-if="p.betweenness != null">
        <span>中介中心性 <b>{{ Math.round(p.betweenness).toLocaleString() }}</b></span>
        <span>PageRank <b>{{ p.pagerank?.toFixed(1) }}</b></span>
      </div>
    </header>

    <section v-if="entries.length">
      <h3>入仕</h3>
      <ul><li v-for="e in entries.slice(0,6)" :key="e.entry">
        {{ e.entry }}<em v-if="e.year"> · {{ e.year }}</em></li></ul>
    </section>

    <section v-if="offices.length">
      <h3>历任 <span class="n">{{ offices.length }}</span></h3>
      <ul><li v-for="o in offices.slice(0,12)" :key="o.office">
        {{ o.office }}<em v-if="o.firstYear"> · {{ o.firstYear }}</em></li></ul>
    </section>

    <section v-if="addresses.length">
      <h3>地理</h3>
      <ul><li v-for="a in addresses.slice(0,10)" :key="a.place">
        <em>{{ a.type }}</em>
        <button v-if="a.placeId" class="lnk" @click="store.openPlace(a.placeId); store.setView('place')">
          {{ a.place }}
        </button>
        <template v-else>{{ a.place }}</template>
      </li></ul>
    </section>

    <section v-if="texts.length">
      <h3>著述 <span class="n">{{ texts.length }}</span></h3>
      <ul><li v-for="t in texts.slice(0,12)" :key="t.title">
        {{ t.title }}<em v-if="t.role"> · {{ t.role }}</em></li></ul>
    </section>

    <section v-if="p.notes" class="notes">
      <h3>史料注记</h3>
      <p>{{ p.notes }}</p>
    </section>
  </div>
  <div v-else class="blank">选择人物后显示档案</div>
</template>

<style scoped>
.prof { padding: 20px 22px 40px; overflow-y: auto; height: 100%; }
.blank { display: grid; place-items: center; height: 100%; color: var(--ink-mute); font-size: 13px; }
header { padding-bottom: 16px; border-bottom: 1px solid var(--line); }
h2 { margin: 0; font-size: 24px; font-weight: 600; }
.sub { margin: 5px 0 0; color: var(--ink-soft); font-size: 13px; }
.alt { margin: 3px 0 0; color: var(--ink-mute); font-size: 12px; }
.nh { margin: 2px 0 0; color: var(--azurite); font-size: 12px; }
.chips { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 9px; }
.chip { font-size: 11px; padding: 1px 7px; border-radius: 2px; border: 1px solid var(--line); color: var(--ink-mute); }
.chip.alt-chip { border-color: var(--azurite); color: var(--azurite); background: var(--azurite-lo); }
.chip.chor { border-color: var(--cinnabar); color: var(--cinnabar); }
.chip.st { border-color: var(--malachite); color: var(--malachite); }
.degrees { display: flex; gap: 18px; margin-top: 13px; font-size: 12px; color: var(--ink-mute); }
.degrees b { color: var(--azurite); font-size: 16px; font-weight: 600; margin-right: 3px; }
.metrics {
  display: flex; gap: 16px; margin-top: 8px; font-size: 11px; color: var(--ink-mute);
  padding-top: 8px; border-top: 1px dashed var(--line);
}
.metrics b {
  color: var(--ink-soft); font-family: "JetBrains Mono", monospace;
  font-variant-numeric: tabular-nums; font-weight: 500;
}
section { margin-top: 20px; }
h3 {
  margin: 0 0 8px; font-size: 11px; letter-spacing: .1em;
  text-transform: uppercase; color: var(--ink-mute); font-weight: 500;
}
h3 .n { color: var(--azurite); letter-spacing: 0; }
ul { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 5px; }
li { font-size: 13px; color: var(--ink-soft); }
li em { font-style: normal; color: var(--ink-mute); font-size: 11.5px; }
.lnk { border: 0; background: none; padding: 0; font: inherit; color: var(--azurite); text-decoration: underline; text-decoration-style: dotted; text-underline-offset: 2px; }
.lnk:hover { text-decoration-style: solid; }
.notes p {
  margin: 0; font-size: 12.5px; line-height: 1.75; color: var(--ink-mute);
  background: var(--surface-alt); padding: 12px 14px; border-radius: 3px;
  max-height: 260px; overflow-y: auto;
}
</style>
