/**
 * 成就徽章的可观察模型。
 *
 * 为什么不用「普通对象 + ForEach」：
 *  ArkUI 的 ForEach 只按 key 做 diff，键值不变时**不会重建**子节点，
 *  写在项里的动画状态（缩放 / 位移 / 旋转）永远不会被重新求值——
 *  实测表现就是"徽章点亮动画完全看不到"。
 *
 * 正确做法：把每枚徽章做成 @ObservedV2 + @Trace，交给一个**独立的子组件**渲染。
 * 字段变化会直接驱动那个子组件刷新，完全不依赖 ForEach 的 diff 策略。
 */
@ObservedV2
export class BadgeCell {
  id: string;
  name: string;
  desc: string;
  icon: string;

  /** 解锁状态与进度（由足迹数据驱动） */
  @Trace progress: number = 0;
  @Trace target: number = 1;
  @Trace unlocked: boolean = false;

  /**
   * 是否正在庆祝。
   * 庆祝时卡片里的静态徽章会隐藏（它已经"散成粒子"飞到屏幕中心去了），
   * 大勋章飞回原位后才恢复显示。
   */
  @Trace celebrating: boolean = false;
  /** ① 卡片聚焦：轻微弹起 + 底色高亮（0=常态，1=高亮） */
  @Trace cardScale: number = 1;
  @Trace cardHighlight: number = 0;

  /** ② 勋章本体：升起高度 / 缩放 / 绕 Y 轴旋转角度 */
  @Trace iconLift: number = 0;
  @Trace iconScale: number = 1;
  @Trace iconSpin: number = 0;

  /** ③ 光晕与两圈扩散光环 */
  @Trace glowScale: number = 0.6;
  @Trace glowOpacity: number = 0;
  @Trace ring1Scale: number = 0.5;
  @Trace ring1Opacity: number = 0;
  @Trace ring2Scale: number = 0.5;
  @Trace ring2Opacity: number = 0;

  /** ⑤ 卡片扫光的水平位移 */
  @Trace shineX: number = -140;

  constructor(id: string, name: string, desc: string, icon: string) {
    this.id = id;
    this.name = name;
    this.desc = desc;
    this.icon = icon;
  }
}
