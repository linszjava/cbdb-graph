<script setup>
import { ref, computed, watch } from 'vue'
import { useGraphStore } from '../stores/graph'

const store = useGraphStore()
const q = ref('')
let timer = null
watch(q, v => {
  clearTimeout(timer)
  timer = setTimeout(() => store.searchPlaces(v), 250)
})

const pl = computed(() => store.place)
// 下级按人物数降序 —— 关心的是哪个州县出人多
const children = computed(() =>
  [...(pl.value?.children || [])].sort((a, b) => b.people - a.people))

const span = computed(() => {
  if (!pl.value) return ''
  const { firstYear: f, lastYear: l } = pl.value
  return f && l ? `${f}–${l}` : ''
})

function pick(id) { q.value = ''; store.placeHits = []; store.openPlace(id) }
const era = p => p.birthYear && p.deathYear ? `${p.birthYear}–${p.deathYear}`
  : p.year ? `约 ${p.year}` : ''
</script>

<template>
  <div class="wrap">
    <div class="bar">
      <input v-model="q" placeholder="搜地名：临川、吉州、江南西路…" />
      <ul v-if="store.placeHits.length" class="hits">
        <li v-for="h in store.placeHits" :key="h.id" @click="pick(h.id)">
          <b>{{ h.name }}</b>
          <span v-if="h.parent" class="p">属 {{ h.parent }}</span>
          <span v-if="h.firstYear" class="y">{{ h.firstYear }}–{{ h.lastYear }}</span>
        </li>
      </ul>
    </div>

    <div v-if="store.loading" class="overlay">载入中…</div>
    <div v-else-if="!pl" class="overlay">搜一个地名，或先选一个人物（自动落到其籍贯）</div>

    <div v-else class="body">
      <nav class="crumbs" v-if="pl.ancestors?.length">
        <template v-for="(a, i) in [...pl.ancestors].reverse()" :key="a.id">
          <button @click="store.openPlace(a.id)">{{ a.name }}</button>
          <span class="sep">›</span>
        </template>
        <span class="cur">{{ pl.name }}</span>
      </nav>

      <header>
        <h2>{{ pl.name }}</h2>
        <span v-if="span" class="span">{{ span }}</span>
        <span class="total"><b>{{ pl.total }}</b> 人以此为籍贯（含下辖）</span>
      </header>

      <section v-if="children.length">
        <h3>下辖 <span class="n">{{ children.length }}</span></h3>
        <div class="kids">
          <button v-for="c in children" :key="c.id" @click="store.openPlace(c.id)">
            {{ c.name }}<em>{{ c.people }}</em>
          </button>
        </div>
      </section>

      <section v-if="pl.sample?.length">
        <h3>人物 <span class="n">按中介中心性排序</span></h3>
        <div class="people">
          <button v-for="p in pl.sample" :key="p.id"
                  @click="store.select(p.id)" :title="era(p)">
            {{ p.name }}
            <em v-if="p.dynasty">{{ p.dynasty }}</em>
          </button>
        </div>
        <p class="more" v-if="pl.total > pl.sample.length">
          另有 {{ pl.total - pl.sample.length }} 人未列
        </p>
      </section>
    </div>
  </div>
</template>

<style scoped>
.wrap { position: relative; height: 100%; background: var(--surface); overflow-y: auto; }
.bar { position: sticky; top: 0; z-index: 2; background: var(--surface); padding: 14px 22px 10px; border-bottom: 1px solid var(--line); }
.bar input {
  width: 100%; max-width: 340px; padding: 7px 11px; font: inherit; font-size: 13px;
  border: 1px solid var(--line); border-radius: 3px; background: var(--surface); color: var(--ink);
}
.bar input:focus { outline: 2px solid var(--azurite); outline-offset: -1px; }
.hits {
  list-style: none; margin: 6px 0 0; padding: 4px; max-width: 340px;
  max-height: 260px; overflow-y: auto;
  border: 1px solid var(--line); border-radius: 3px; background: var(--surface);
  box-shadow: 0 8px 22px -12px rgba(0,0,0,.3);
}
.hits li { padding: 6px 9px; border-radius: 2px; cursor: pointer; font-size: 13px; display: flex; gap: 7px; align-items: baseline; }
.hits li:hover { background: var(--surface-alt); }
.hits .p { color: var(--ink-mute); font-size: 11.5px; }
.hits .y { margin-left: auto; color: var(--ink-mute); font-size: 11px; font-family: "JetBrains Mono", monospace; }
.overlay { position: absolute; inset: 60px 0 0; display: grid; place-items: center; color: var(--ink-mute); font-size: 14px; }
.body { padding: 16px 22px 40px; }
.crumbs { display: flex; align-items: center; gap: 4px; flex-wrap: wrap; margin-bottom: 12px; }
.crumbs button { border: 0; background: none; color: var(--ink-mute); font-size: 12.5px; padding: 1px 4px; border-radius: 2px; }
.crumbs button:hover { color: var(--azurite); background: var(--surface-alt); }
.crumbs .sep { color: var(--ink-mute); font-size: 11px; }
.crumbs .cur { color: var(--ink); font-size: 12.5px; font-weight: 500; padding-left: 2px; }
header { display: flex; align-items: baseline; gap: 11px; flex-wrap: wrap; padding-bottom: 14px; border-bottom: 1px solid var(--line); }
header h2 { margin: 0; font-size: 24px; font-weight: 600; }
.span { font-size: 12px; color: var(--ink-mute); font-family: "JetBrains Mono", monospace; }
.total { margin-left: auto; font-size: 12.5px; color: var(--ink-mute); }
.total b { color: var(--azurite); font-size: 16px; font-weight: 600; }
section { margin-top: 20px; }
h3 { margin: 0 0 9px; font-size: 11px; letter-spacing: .1em; text-transform: uppercase; color: var(--ink-mute); font-weight: 500; }
h3 .n { color: var(--azurite); letter-spacing: 0; text-transform: none; }
.kids, .people { display: flex; flex-wrap: wrap; gap: 4px; }
.kids button, .people button {
  border: 1px solid var(--line); background: var(--surface); color: var(--ink-soft);
  border-radius: 3px; padding: 3px 9px; font-size: 12.5px;
  display: inline-flex; align-items: baseline; gap: 5px;
}
.kids button:hover, .people button:hover { border-color: var(--azurite); color: var(--azurite); }
.kids em, .people em {
  font-style: normal; font-size: 10.5px; color: var(--ink-mute);
  font-family: "JetBrains Mono", monospace;
}
.more { margin: 8px 0 0; font-size: 11.5px; color: var(--ink-mute); }
</style>
