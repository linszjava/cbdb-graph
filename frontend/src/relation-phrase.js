/**
 * 统一把关系词放在两名中间。
 *
 * 两类边的方向约定不同，靠箭头补回方向信息：
 *   KIN   边 X→Y 读作「Y 是 X 的 R」→ 显示 X ─妾→ Y（苏轼的妾是王朝云）
 *   ASSOC 边 X→Y 读作「X 对 Y 做了 R」→ 显示 X ─致书Y→ Y
 */
export function phraseRelation(r) {
  return { a: r.subject, mid: r.label, b: r.object, kin: r.type === 'KIN' }
}
