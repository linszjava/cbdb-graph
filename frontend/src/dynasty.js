// 朝代着色：青碧体系内的分色，冷暖跨度足以区分而不刺眼
const PALETTE = {
  '宋': '#10646F', '唐': '#8A6D3B', '明': '#3F7F63', '清': '#6A5A8C',
  '元': '#A8443A', '五代': '#4A7C8C', '金': '#7D6E52', '隋': '#5C7A6A',
  '南北朝': '#8C6A7D', '北魏': '#7A5C4A', '中华民国': '#4C6B8A'
}
const FALLBACK = '#7C8E90'
export const dynastyColor = d => PALETTE[d] || FALLBACK
export const dynastyList = () => Object.entries(PALETTE)

// 社群着色：黄金角散列色相，相邻社群不撞色。
// 必须返回 hex —— Sigma 的颜色解析器不认 `hsl(h s% l%)` 这种空格分隔语法，
// 解析失败会静默退回黑色。
export function communityColor(id) {
  if (id === null || id === undefined) return '#7C8E90'
  const h = ((id * 137.508) % 360) / 360
  return hslHex(h, 0.42, 0.46)
}

function hslHex(h, s, l) {
  const f = n => {
    const k = (n + h * 12) % 12
    const a = s * Math.min(l, 1 - l)
    const v = l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))
    return Math.round(v * 255).toString(16).padStart(2, '0')
  }
  return `#${f(0)}${f(8)}${f(4)}`
}
