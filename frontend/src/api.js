const base = '/api'

async function get(path, params = {}) {
  const qs = new URLSearchParams()
  for (const [k, v] of Object.entries(params)) {
    if (v === null || v === undefined) continue
    if (Array.isArray(v)) v.forEach(x => qs.append(k, x))
    else qs.append(k, v)
  }
  const url = qs.toString() ? `${base}${path}?${qs}` : `${base}${path}`
  const res = await fetch(url)
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`)
  return res.json()
}

export const api = {
  search: (q, limit = 25) => get('/search', { q, limit }),
  person: id => get(`/person/${id}`),
  ego: (id, hops = 1, relTypes = []) => get(`/ego/${id}`, { hops, relTypes }),
  path: (from, to) => get('/path', { from, to }),
  lineage: (id, hops = 3) => get(`/lineage/${id}`, { hops }),
  atlas: id => get(`/atlas/${id}`),
  source: textId => get(`/source/${textId}`),
  cohorts: id => get(`/cohort/${id}`),
  nianhaoAll: () => get('/nianhao'),
  place: addrId => get(`/place/${addrId}`),
  searchPlaces: q => get('/place/search', { q }),
  group: params => get('/group', params),
  groupOptions: () => get('/group/options'),
  community: cid => get(`/community/${cid}`)
}
