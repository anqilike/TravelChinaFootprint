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
  /** 卡片整体绕 Z 轴旋转（摆动类效果用） */
  @Trace cardRotate: number = 0;

  /** ② 勋章本体：升起高度 / 缩放 / 三轴旋转 / 水平抖动 / 透明度 */
  @Trace iconLift: number = 0;
  @Trace iconScale: number = 1;
  /** 绕 Y 轴旋转（左右翻面） */
  @Trace iconSpin: number = 0;
  /** 绕 X 轴旋转（上下翻，像抛硬币） */
  @Trace iconSpinX: number = 0;
  /** 绕 Z 轴旋转（平面内转圈） */
  @Trace iconSpinZ: number = 0;
  /** 水平抖动偏移 */
  @Trace iconShake: number = 0;
  @Trace iconOpacity: number = 1;

  /** ③ 光晕与两圈扩散光环 */
  @Trace glowScale: number = 0.6;
  @Trace glowOpacity: number = 0;
  @Trace ring1Scale: number = 0.5;
  @Trace ring1Opacity: number = 0;
  @Trace ring2Scale: number = 0.5;
  @Trace ring2Opacity: number = 0;

  /** ⑤ 卡片扫光的水平位移 */
  @Trace shineX: number = -140;

  /** 复位到常态（每个效果播放前都会先调用一次） */
  resetAnimation(): void {
    this.cardScale = 1;
    this.cardRotate = 0;
    this.iconLift = 0;
    this.iconScale = 1;
    this.iconSpin = 0;
    this.iconSpinX = 0;
    this.iconSpinZ = 0;
    this.iconShake = 0;
    this.iconOpacity = 1;
    this.glowScale = 0.6;
    this.glowOpacity = 0;
    this.ring1Scale = 0.5;
    this.ring1Opacity = 0;
    this.ring2Scale = 0.5;
    this.ring2Opacity = 0;
    this.shineX = -140;
  }

  constructor(id: string, name: string, desc: string, icon: string) {
    this.id = id;
    this.name = name;
    this.desc = desc;
    this.icon = icon;
  }
}
