<script setup>
import { useGraphStore } from '../stores/graph'
const store = useGraphStore()
</script>

<template>
  <div class="gp">
    <div class="row">
      <label>身份</label>
      <select v-model="store.groupFilter.status" @change="store.loadGroup()">
        <option value="">不限</option>
        <option v-for="s in store.groupOpts.statuses" :key="s.value" :value="s.value">
          {{ s.value }}（{{ s.n }}）
        </option>
      </select>
    </div>
    <div class="row">
      <label>郡望</label>
      <select v-model="store.groupFilter.choronym" @change="store.loadGroup()">
        <option value="">不限</option>
        <option v-for="c in store.groupOpts.choronyms" :key="c.value" :value="c.value">
          {{ c.value }}（{{ c.n }}）
        </option>
      </select>
    </div>
    <div class="row">
      <label>朝代</label>
      <select v-model="store.groupFilter.dynasty" @change="store.loadGroup()">
        <option value="">不限</option>
        <option v-for="d in ['宋','明','唐','元','清']" :key="d" :value="d">{{ d }}</option>
      </select>
    </div>
    <p class="hint">只显示群体<b>内部</b>的交往边——要看的是这批人彼此如何相连。</p>
  </div>
</template>

<style scoped>
.gp { display: flex; align-items: center; gap: 14px; flex-wrap: wrap; }
.row { display: flex; align-items: center; gap: 5px; }
.row label { font-size: 11px; color: var(--ink-mute); }
select {
  border: 1px solid var(--line); background: var(--surface); color: var(--ink);
  border-radius: 3px; padding: 3px 6px; font-size: 12px; max-width: 190px;
}
select:focus { outline: 2px solid var(--azurite); outline-offset: -1px; }
.hint { margin: 0; font-size: 11px; color: var(--ink-mute); }
.hint b { color: var(--azurite); }
</style>
