// 子图导出。研究者最终要把结果拿去 Gephi 精修或写进论文，
// 所以除了 CSV 还给 GEXF —— Gephi 的原生格式。

function download(name, text, mime = 'text/csv;charset=utf-8') {
  const url = URL.createObjectURL(new Blob(['﻿' + text], { type: mime }))
  const a = document.createElement('a')
  a.href = url; a.download = name
  document.body.appendChild(a); a.click(); a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

const esc = v => {
  const s = v === null || v === undefined ? '' : String(v)
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

export function exportNodesCsv(graph, base) {
  const cols = ['id', 'label', 'dynasty', 'year', 'birthYear', 'deathYear', 'female', 'community']
  const rows = [cols.join(',')]
  for (const n of graph.nodes) rows.push(cols.map(c => esc(n[c])).join(','))
  download(`${base}-nodes.csv`, rows.join('\n'))
}

export function exportEdgesCsv(graph, base) {
  const cols = ['source', 'target', 'type', 'label', 'year', 'textTitle', 'sourceRef', 'pages']
  const rows = [cols.join(',')]
  for (const e of graph.edges) rows.push(cols.map(c => esc(e[c])).join(','))
  download(`${base}-edges.csv`, rows.join('\n'))
}

const xml = s => String(s ?? '').replace(/[<>&"']/g, c =>
  ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' }[c]))

export function exportGexf(graph, base) {
  const attrs = [['dynasty', 'string'], ['year', 'integer'], ['community', 'integer']]
  const decl = attrs.map(([id], i) => `<attribute id="${i}" title="${id}" type="${attrs[i][1]}"/>`).join('')
  const nodes = graph.nodes.map(n =>
    `<node id="${n.id}" label="${xml(n.label)}"><attvalues>` +
    attrs.map(([k], i) => n[k] == null ? '' : `<attvalue for="${i}" value="${xml(n[k])}"/>`).join('') +
    `</attvalues></node>`).join('')
  const edges = graph.edges.map((e, i) =>
    `<edge id="${i}" source="${e.source}" target="${e.target}" label="${xml(e.label)}"/>`).join('')
  const doc =
    `<?xml version="1.0" encoding="UTF-8"?>
<gexf xmlns="http://www.gexf.net/1.2draft" version="1.2">
<meta><creator>CBDB 图谱工作台</creator><description>${xml(base)}</description></meta>
<graph mode="static" defaultedgetype="undirected">
<attributes class="node">${decl}</attributes>
<nodes>${nodes}</nodes>
<edges>${edges}</edges>
</graph></gexf>`
  download(`${base}.gexf`, doc, 'application/xml;charset=utf-8')
}
