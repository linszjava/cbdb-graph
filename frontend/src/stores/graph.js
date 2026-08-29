import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { api } from '../api'
import { loadNianHao } from '../nianhao'

export const useGraphStore = defineStore('graph', () => {
  const hits = ref([])
  const person = ref(null)
  const graph = ref({ nodes: [], edges: [], truncated: false, totalAvailable: 0 })
  const centerId = ref(null)
  const hops = ref(1)
  const relTypes = ref(['ASSOC', 'KIN'])
  const loading = ref(false)
  const error = ref('')
  const colorBy = ref('dynasty')       // dynasty | community

  // 访问轨迹：一路「以此人为中心」下钻后要能原路返回
  const cohorts = ref([])
  const place = ref(null)
  const placeHits = ref([])
  const groupGraph = ref({ nodes: [], edges: [], truncated: false, totalAvailable: 0 })
  const relLabelFilter = ref([])       // 选中的关系名，空数组表示不筛
  const communities = ref({})          // cid → 画像，按需取，取过不再取
  const groupOpts = ref({ statuses: [], choronyms: [] })
  const groupFilter = ref({ status: '', choronym: '', dynasty: '' })
  const trail = ref([])                // [{ id, label, dynasty }]
  const trailIndex = ref(-1)
  const view = ref('network')          // network | lineage | atlas
  const lineage = ref({ nodes: [], edges: [] })
  const atlas = ref([])
  const sourceCache = new Map()

  // 关系网络与群体网络各有各的图，切来切去不会互相覆盖
  const activeGraph = computed(() => view.value === 'group' ? groupGraph.value : graph.value)

  /**
   * 实际渲染的图 —— 按选中的关系名过滤。
   * 只留这些边，以及它们连到的节点；中心人物始终保留。
   * 画布与工具栏统计共用此结果，否则会出现「显示 141 节点」但只画了 31 个的错位。
   */
  const renderGraph = computed(() => {
    const g = activeGraph.value
    const picked = relLabelFilter.value
    if (!picked.length) return g
    const edges = g.edges.filter(e => picked.includes(e.label || '关系未详'))
    const keep = new Set([String(centerId.value)])
    for (const e of edges) { keep.add(String(e.source)); keep.add(String(e.target)) }
    return { ...g, nodes: g.nodes.filter(n => keep.has(String(n.id))), edges }
  })

  const nodeCount = computed(() => renderGraph.value.nodes.length)
  const edgeCount = computed(() => renderGraph.value.edges.length)

  async function search(q) {
    if (!q.trim()) { hits.value = []; return }
    error.value = ''
    try { hits.value = await api.search(q) }
    catch (e) { error.value = `检索失败：${e.message}` }
  }

  const canBack = computed(() => trailIndex.value > 0)
  const canForward = computed(() => trailIndex.value < trail.value.length - 1)

  /**
   * @param {number} id
   * @param {boolean} record 是否记入轨迹。从轨迹本身跳转时传 false，否则会把历史越叠越长
   */
  async function select(id, record = true) {
    if (record) {
      // 从轨迹中段再往前走，丢弃原来的「前进」分支，与浏览器行为一致
      if (trailIndex.value < trail.value.length - 1) {
        trail.value = trail.value.slice(0, trailIndex.value + 1)
      }
      const last = trail.value[trailIndex.value]
      if (!last || last.id !== id) {
        trail.value.push({ id, label: String(id), dynasty: '' })
        trailIndex.value = trail.value.length - 1
        // 压入浏览器历史，使前进/后退键与轨迹同步
        try { history.pushState({ trailIndex: trailIndex.value }, '') } catch { /* 忽略 */ }
      }
    }
    await load(id)
  }

  async function goTo(index) {
    const item = trail.value[index]
    if (!item) return
    trailIndex.value = index
    await select(item.id, false)
  }

  const back = () => canBack.value && goTo(trailIndex.value - 1)
  const forward = () => canForward.value && goTo(trailIndex.value + 1)

  async function load(id) {
    loading.value = true
    error.value = ''
    centerId.value = id
    try {
      // 档案与当前视图所需数据并行取，切换视图时再按需补齐
      const tasks = [api.person(id), api.ego(id, hops.value, relTypes.value)]
      const [p, g] = await Promise.all(tasks)
      person.value = p
      graph.value = g
      // 轨迹里先存的是 id 占位，档案回来后补上真名
      const cur = trail.value[trailIndex.value]
      if (cur && cur.id === id) { cur.label = p.nameChn; cur.dynasty = p.dynasty }
      lineage.value = { nodes: [], edges: [] }
      atlas.value = []
      cohorts.value = []
      relLabelFilter.value = []
      if (view.value !== 'network') await loadView()
    } catch (e) {
      error.value = `载入失败：${e.message}`
    } finally {
      loading.value = false
    }
  }

  async function loadView() {
    if (centerId.value === null) return
    loading.value = true
    error.value = ''
    try {
      if (view.value === 'lineage' && !lineage.value.nodes.length) {
        lineage.value = await api.lineage(centerId.value, 3)
      } else if (view.value === 'atlas' && !atlas.value.length) {
        atlas.value = await api.atlas(centerId.value)
      } else if (view.value === 'cohort' && !cohorts.value.length) {
        cohorts.value = await api.cohorts(centerId.value)
      }
    } catch (e) {
      error.value = `载入失败：${e.message}`
    } finally {
      loading.value = false
    }
  }

  async function setView(v) {
    view.value = v
    relLabelFilter.value = []
    if (v === 'group') {
      await loadGroupOptions()
      // 未选筛选条件时清空，否则会残留上一个视图的 ego 图，
      // 让人误以为「群体网络和关系网络内容一样」
      const f = groupFilter.value
      if (!f.status && !f.choronym && !f.dynasty) {
        groupGraph.value = { nodes: [], edges: [], truncated: false, totalAvailable: 0 }
      }
      return
    }
    if (v === 'place') { if (!place.value) await openPlaceOfPerson(); return }
    await loadView()
  }

  /** 进入政区视图时，默认落到当前人物的籍贯 */
  async function openPlaceOfPerson() {
    const natal = person.value?.addresses?.find(a => (a.type || '').startsWith('籍贯'))
    if (natal?.placeId) await openPlace(natal.placeId)
  }

  async function openPlace(addrId) {
    loading.value = true; error.value = ''
    try { place.value = await api.place(addrId) }
    catch (e) { error.value = `载入失败：${e.message}` }
    finally { loading.value = false }
  }

  async function searchPlaces(q) {
    if (!q || !q.trim()) { placeHits.value = []; return }
    try { placeHits.value = await api.searchPlaces(q) } catch { placeHits.value = [] }
  }

  async function loadGroupOptions() {
    if (groupOpts.value.statuses.length) return
    try { groupOpts.value = await api.groupOptions() } catch { /* 忽略 */ }
  }

  /** 群体网络不依赖当前人物，独立取数后直接灌进 graph 供网络图渲染 */
  async function loadGroup() {
    const f = groupFilter.value
    if (!f.status && !f.choronym && !f.dynasty) return
    loading.value = true; error.value = ''
    try {
      groupGraph.value = await api.group({
        status: f.status || undefined,
        choronym: f.choronym || undefined,
        dynasty: f.dynasty || undefined
      })
    } catch (e) {
      error.value = `载入失败：${e.message}`
    } finally { loading.value = false }
  }

  /** 社群画像按需取。Louvain 只给数字 ID，没有画像看到一堆人认不出是什么群体。 */
  async function resolveCommunity(cid) {
    if (cid == null) return null
    if (communities.value[cid] !== undefined) return communities.value[cid]
    communities.value[cid] = null                 // 占位，避免并发重复请求
    try {
      const c = await api.community(cid)
      communities.value = { ...communities.value, [cid]: c }
      return c
    } catch { return null }
  }

  /** 史料出处按需取，同一书目只查一次 */
  async function resolveSource(textId) {
    if (textId == null) return null
    if (sourceCache.has(textId)) return sourceCache.get(textId)
    try {
      const s = await api.source(textId)
      sourceCache.set(textId, s)
      return s
    } catch { return null }
  }

  async function reload() {
    // 切换跳数或关系类型只是重载当前人物，不记入轨迹
    if (centerId.value !== null) await load(centerId.value)
  }

  // 年号表一次性加载，之后本地换算
  api.nianhaoAll().then(loadNianHao).catch(() => {})

  return {
    hits, person, graph, groupGraph, activeGraph, renderGraph, relLabelFilter, cohorts, centerId, hops, relTypes, loading, error,
    colorBy, view, lineage, atlas, nodeCount, edgeCount,
    trail, trailIndex, canBack, canForward, groupOpts, groupFilter,
    place, placeHits, openPlace, searchPlaces,
    loadGroup, loadGroupOptions,
    communities, resolveCommunity,
    search, select, reload, setView, loadView, resolveSource,
    goTo, back, forward
  }
})
