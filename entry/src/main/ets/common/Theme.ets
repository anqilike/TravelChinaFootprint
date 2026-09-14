/**
 * 全局视觉规范（对应《设计前指导书》3.4 节）
 *
 * 设计语言：「暗夜金脉」——极夜蓝黑做底，金色代表"已点亮"。
 * 鸿蒙 7 适配：所有悬浮面板 / 卡片 / 控件都在 backgroundColor 之外
 * 叠加一层 uiMaterial 沉浸光感材质（见 common/MaterialKit.ets），
 * 低版本设备自动退回纯色，不会出现"半透明看不见"的问题。
 */
export class Palette {
  /** 页面底色：极夜蓝黑 */
  static readonly bg: string = '#070B14';
  /** 卡片底：比底色亮一档，作为材质的降级底色 */
  static readonly surface: string = '#111A29';
  static readonly surfaceSoft: string = '#0C1320';
  static readonly line: string = '#1E2A40';
  /** 主文字：纯白。沉浸光感材质上的文字必须是纯白才够醒目（灰色在玻璃上会发闷） */
  static readonly text: string = '#FFFFFF';
  static readonly textDim: string = '#8A99B5';
  static readonly gold: string = '#F5C542';
  static readonly goldLight: string = '#FFD97D';
  /** 深金：金色文字压在浅色底图上时用 */
  static readonly goldDeep: string = '#C8861A';
  static readonly cyan: string = '#22D3EE';
  static readonly danger: string = '#FF6B6B';
  static readonly unlitFill: string = '#22304A';
  static readonly unlitStroke: string = '#3B4A69';

  /** 材质染色：必须是带透明度的颜色，太实会挡掉沉浸光感的滤色 */
  static readonly glassPanel: string = '#2E0A1020';
  static readonly glassCard: string = '#1F0A1020';
  static readonly glassControl: string = '#24101828';
  /**
   * 底部悬浮页签栏染色：比卡片重一档。
   * 页签栏经常压在浅色地图上，染色太淡时金色/灰色图标对比度不够。
   */
  static readonly glassBar: string = '#5E0A1020';
  /** 金色光晕（用于"已点亮"的发光感） */
  static readonly goldGlowSoft: string = '#59F5C542';
  static readonly goldGlowFaint: string = '#1FF5C542';
}

/**
 * 地图标注视觉规范。
 * 目标是"看起来像底图自己画出来的"：无底板、白色描边、深灰字；
 * 已点亮城市换成琥珀金，在浅色底图上仍有足够对比度，同时保留"金色 = 去过"的语言。
 */
export class MapLabelStyle {
  /** 白色描边（halo），保证文字压在山脉 / 河流等复杂底纹上依然可读 */
  static readonly halo: string = '#FFFFFF';
  /**
   * 与底图标签完全一致的文字色（近黑）。
   * 取样方式：在底图国名"中华人民共和国"的字形核心（笔画内部）取最密集像素，
   * 实测 RGB(46~52) → 取 #303030。注意不要取抗锯齿边缘，否则会得到偏灰的错值。
   */
  static readonly labelText: string = '#303030';
  /** 已点亮城市：琥珀金（比 goldLight 深，避免在浅色底图上发飘） */
  static readonly visitedText: string = '#C8861A';
}

export class Dimens {
  static readonly pagePadding: number = 16;
  static readonly cardRadius: number = 20;
  static readonly pillRadius: number = 24;
  static readonly fabSize: number = 46;
  /** 悬浮底部导航高度（含内边距） */
  static readonly navHeight: number = 62;
  /** 页面内容为悬浮导航预留的底部空间 */
  static readonly navSpace: number = 96;
  static readonly gap: number = 12;
}

/**
 * 动效规范。鸿蒙 7 的"沉浸光感"强调交互要有物理反馈：
 * 按下有形变、状态切换有过渡，而不是生硬地跳变。
 */
export class Motion {
  /** 按压形变比例 */
  static readonly pressScale: number = 0.94;
  /** 常规过渡时长（毫秒） */
  static readonly normal: number = 240;
  /**
   * 底部页签切换时长（毫秒）。
   * 比 normal 稍长一点，配合弹簧曲线收尾，让"地图 → 我的"这种跨三页的跳转也有落定感。
   */
  static readonly pageSwitch: number = 320;
  /** 缓慢过渡（用于光晕、进度） */
  static readonly slow: number = 420;
}

/** 地图容器初始相机位置：中国全图 */
export class MapDefaults {
  /**
   * 初始镜头：必须把中国国土完整框进来（西起 73°E 的帕米尔高原，东到 135°E 的黑龙江入海口）。
   *
   * 实测取舍：zoom 3.6 经度视野只有约 46°，新疆会被切掉；zoom 3.1 视野约 65°，
   * 但标签相对地图太大、东部省份互相压字。取 **3.4（视野约 52°）**：
   * 既能同时容下新疆（85°E）与黑龙江（127°E），又比 3.1 松快一档。
   */
  static readonly centerLat: number = 35.5;
  static readonly centerLng: number = 105.5;
  static readonly zoom: number = 3.4;
  /**
   * 点按地图时，判定为"想点亮这座城市"的最大**屏幕**距离（vp）。
   *
   * 为什么不用公里：同一个屏幕距离，在不同缩放级别对应的公里数差几十倍。
   * 全国视野下 60 公里只有约 12 物理像素（点位本身也只有约 12 像素宽），
   * 手指落点根本压不进去——这就是"一个城市要点好几次才弹页面"的原因。
   * 44vp ≈ 一根手指的落点半径，也是系统对最小可点区域的经验值。
   */
  static readonly tapRadiusVp: number = 56;
  /**
   * 自己识别"点按"的位移容差（vp）。
   * 手指点一下通常会抖动几像素，地图 SDK 会把它当成拖拽从而**不回调 mapClick**——
   * 这就是"一个城市要点好几次"的另一半原因。我们在 MapComponent 上自己收 onTouch，
   * 位移小于这个值、且时长够短，就判定为一次点击。
   */
  static readonly tapSlopVp: number = 16;
  /** 判定为点击的最长按压时间（毫秒），超过按长按处理 */
  static readonly tapMaxMs: number = 500;
  /**
   * 分级标注阈值（按缩放级别三段式，互不重叠）：
   *  zoom < capitalZoom（4.5）      → 只标省名（+ 底图自带的国家名）
   *  capitalZoom ≤ zoom < nameZoom  → 只标 34 个省会 / 首府（此时不标省名）
   *  zoom ≥ nameZoom（7）           → 铺开全部 370 个地级市名
   *
   * 阈值取 4.5 的原因：底图自带样式在 zoom≈4 就开始画省名（实测截图确认），
   * 若我们的省名拖到 5 才退场，中间会出现"同一省份两个名字"的重复。
   * 已在 Petal Maps Studio 里把「省份」设为隐藏，从源头消除重复。
   */
  static readonly capitalZoom: number = 4.5;
  /** 达到该缩放级别才显示城市名标注 */
  static readonly nameZoom: number = 7;
  /**
   * 单屏最多显示多少个地级市名。
   * 由于自绘标签之间已做碰撞避让（见 MapPage.labelConflicts），
   * 这个上限只用于兜底性能，不再承担"防糊成一团"的职责。
   */
  static readonly maxLabels: number = 120;
}
