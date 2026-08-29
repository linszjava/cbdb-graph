// 世系着色：颜色编码代际（族谱的主结构），性别用饱和度作次级区分。
// 按性别着色没有信息量 —— 库中九成是男性，整棵树会是一片同色。

// 明度自祖辈向孙辈单调递增 —— 越年长越深，一眼能读出方向
const OLDEST = [110, 72, 40]    // 深琥珀，最年长的祖辈
const MIDDLE = [46, 125, 138]   // 石青，与本人同辈
const YOUNGEST = [154, 190, 90]  // 石绿偏藤黄，最年轻的孙辈

const lerp = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t))
const hex = c => '#' + c.map(v => Math.max(0, Math.min(255, v)).toString(16).padStart(2, '0')).join('')

/**
 * @param {number|null} gen  代际，0 为与本人同辈，负为祖辈，正为孙辈
 * @param {number} min       本图中最小代际
 * @param {number} max       本图中最大代际
 * @param {boolean} female
 */
export function generationColor(gen, min, max, female) {
  if (gen === null || gen === undefined) return female ? '#A8A0A4' : '#8E9698'

  let rgb
  if (gen < 0) {
    const t = min < 0 ? gen / min : 0        // 0 → 同辈色，1 → 最老
    rgb = lerp(MIDDLE, OLDEST, t)
  } else if (gen > 0) {
    const t = max > 0 ? gen / max : 0
    rgb = lerp(MIDDLE, YOUNGEST, t)
  } else {
    rgb = MIDDLE
  }

  // 女性：同一代际色向浅处提，保留代际可读性又能一眼区分
  if (female) rgb = lerp(rgb, [255, 255, 255], 0.42)
  return hex(rgb)
}

export const EGO_COLOR = '#A8443A'   // 朱，只给本人
