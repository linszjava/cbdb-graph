// 年号换算。647 条一次性加载后本地换算 —— 档案页上每个年份都发请求太碎。
let table = []

export function loadNianHao(rows) { table = rows || [] }

/**
 * @param {number} year     公元年
 * @param {string} dynasty  人物朝代，用于在并存政权中择用（宋金对峙、南北朝）
 * @returns {string|null}   如「元丰3年」
 */
export function toNianHao(year, dynasty) {
  if (!year || !table.length) return null
  const hits = table.filter(n => n.firstYear <= year && n.lastYear >= year)
  if (!hits.length) return null
  // 朝代名互为前缀即认为同一政权（「宋」对「北宋」「南宋」）
  const same = dynasty
    ? hits.find(n => n.dynastyChn && (n.dynastyChn.includes(dynasty) || dynasty.includes(n.dynastyChn)))
    : null
  const n = same || hits[0]
  const nth = year - n.firstYear + 1
  return n.nameChn + (nth === 1 ? '元年' : nth + '年')
}
