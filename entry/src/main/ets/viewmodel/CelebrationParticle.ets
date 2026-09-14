/**
 * 成就庆祝用的一颗粒子。
 *
 * 为什么用 @ObservedV2：粒子数量多（18 颗）、每帧都要改坐标，
 * 如果走 ForEach 的普通对象，ArkUI 按 key 复用节点、根本不会重新求值
 * （徽章动画踩过这个坑）。做成可观察模型后，每颗粒子由一个独立子组件渲染，
 * 字段一变就刷新，互不干扰。
 */
@ObservedV2
export class CelebrationParticle {
  /** 圆心坐标（相对统计页根容器，vp） */
  @Trace x: number = 0;
  @Trace y: number = 0;
  @Trace opacity: number = 0;
  @Trace scale: number = 1;
  /** 粒子直径（vp）与颜色 */
  @Trace size: number = 6;
  @Trace color: string = '#F5C542';

  constructor(size: number, color: string) {
    this.size = size;
    this.color = color;
  }
}
