/**
 * 屏幕中心那枚"聚合出来的大勋章"。
 *
 * 为什么用 @ObservedV2：它的尺寸/坐标/透明度是逐帧变化的，
 * 之前写成页面的 @Local、由 @Builder 渲染，实测**只有粒子在动、大勋章不出现**
 * （页面的普通状态在动画里的刷新时机不可靠）。
 * 换成可观察模型 + 独立子组件后，和粒子走同一条渲染路径，稳定刷新。
 */
@ObservedV2
export class HeroBadge {
  /** 徽章图标（emoji） */
  @Trace icon: string = '';
  /** 中心坐标（相对统计页根容器，vp） */
  @Trace x: number = 0;
  @Trace y: number = 0;
  /** 尺寸（vp）：出现时从小放大，归位时缩到卡片里那枚的大小 */
  @Trace size: number = 30;
  @Trace opacity: number = 0;
  /** 光晕的扩散与强弱 */
  @Trace glowScale: number = 0.4;
  @Trace glowOpacity: number = 0;
}
