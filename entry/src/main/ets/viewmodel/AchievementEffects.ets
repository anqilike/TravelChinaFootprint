import { curves } from '@kit.ArkUI';
import { BadgeCell } from './BadgeCell';

/** 一种徽章点亮动画的描述 */
export interface EffectInfo {
  id: number;
  name: string;
  desc: string;
}

/**
 * 徽章点亮动画库：10 种风格各异的"成就解锁"效果。
 *
 * 设计约定：
 *  · 每种效果都只改 BadgeCell 上的 @Trace 字段（缩放 / 位移 / 三轴旋转 / 光晕 / 光环 / 扫光），
 *    渲染全部交给 BadgeCard —— 这是本项目里唯一被验证能稳定驱动动画的路径；
 *  · 时间轴用 UIContext.animateTo 的 delay 排布，相邻动画首尾相接；
 *  · 每种效果总时长控制在 1.5~2.6 秒，播放前统一 resetAnimation()。
 *
 * 在「我的 → 成就动画」里可以逐个切换并试播。
 */
export class AchievementEffects {
  static list(): EffectInfo[] {
    const items: EffectInfo[] = [
      { id: 0, name: '勋章升起', desc: '抬起放大 + 绕 Y 轴转两圈 + 双层光轮' },
      { id: 1, name: '抛硬币', desc: '绕 X 轴翻三圈后落定，像抛起一枚金币' },
      { id: 2, name: '心跳脉冲', desc: '两次心跳式缩放，配一圈光轮扩散' },
      { id: 3, name: '摇铃', desc: '左右摆动后定格，卡片跟着轻轻晃' },
      { id: 4, name: '爆闪', desc: '连续三次高亮频闪，光晕瞬间炸开' },
      { id: 5, name: '穿越', desc: '放大到 2.6 倍再收回来，平面转一圈' },
      { id: 6, name: '蓄力弹出', desc: '先左右抖动蓄力，再猛地弹出放大' },
      { id: 7, name: '转盘', desc: '平面内连转两圈，配两道错开的光环' },
      { id: 8, name: '呼吸浮现', desc: '从透明缓缓浮现并放大，克制优雅' },
      { id: 9, name: '天降', desc: '从上方砸下，落地挤压回弹 + 冲击波' }
    ];
    return items;
  }

  static count(): number {
    return AchievementEffects.list().length;
  }

  static info(index: number): EffectInfo {
    const items: EffectInfo[] = AchievementEffects.list();
    const safe: number = (index < 0 || index >= items.length) ? 0 : index;
    return items[safe];
  }

  /** 播放指定效果。返回大致时长（毫秒），调用方据此安排收尾 */
  static play(index: number, cell: BadgeCell, ui: UIContext): number {
    cell.resetAnimation();
    cell.celebrating = true;
    const safe: number = (index < 0 || index >= AchievementEffects.count()) ? 0 : index;
    if (safe === 1) {
      return AchievementEffects.coinFlip(cell, ui);
    }
    if (safe === 2) {
      return AchievementEffects.heartbeat(cell, ui);
    }
    if (safe === 3) {
      return AchievementEffects.bellSwing(cell, ui);
    }
    if (safe === 4) {
      return AchievementEffects.flash(cell, ui);
    }
    if (safe === 5) {
      return AchievementEffects.zoomThrough(cell, ui);
    }
    if (safe === 6) {
      return AchievementEffects.chargePop(cell, ui);
    }
    if (safe === 7) {
      return AchievementEffects.spinner(cell, ui);
    }
    if (safe === 8) {
      return AchievementEffects.breatheIn(cell, ui);
    }
    if (safe === 9) {
      return AchievementEffects.dropLand(cell, ui);
    }
    return AchievementEffects.riseSpin(cell, ui);
  }

  /** 通用的"卡片扫光 + 光晕收尾" */
  private static finish(cell: BadgeCell, ui: UIContext, at: number): void {
    ui.animateTo({ duration: 700, delay: at, curve: Curve.EaseOut }, () => {
      cell.shineX = 150;
    });
    ui.animateTo({ duration: 500, delay: at + 120, curve: Curve.EaseInOut }, () => {
      cell.glowOpacity = 0;
    });
  }

  // ① 勋章升起：抬起放大 + 绕 Y 轴转两圈 + 双层光轮
  private static riseSpin(cell: BadgeCell, ui: UIContext): number {
    ui.animateTo({ duration: 260, curve: curves.springMotion(0.4, 0.7) }, () => {
      cell.cardScale = 1.06;
    });
    ui.animateTo({ duration: 460, delay: 200, curve: curves.springMotion(0.45, 0.68) }, () => {
      cell.iconLift = -12;
      cell.iconScale = 1.8;
    });
    ui.animateTo({ duration: 900, delay: 200, curve: Curve.Linear }, () => {
      cell.iconSpin = 720;
    });
    ui.animateTo({ duration: 700, delay: 260, curve: Curve.EaseOut }, () => {
      cell.glowOpacity = 0.95;
      cell.glowScale = 1.9;
    });
    ui.animateTo({ duration: 900, delay: 280, curve: Curve.EaseOut }, () => {
      cell.ring1Scale = 2.4;
      cell.ring1Opacity = 0.9;
    });
    ui.animateTo({ duration: 900, delay: 460, curve: Curve.EaseOut }, () => {
      cell.ring2Scale = 2.8;
      cell.ring2Opacity = 0.7;
    });
    ui.animateTo({ duration: 520, delay: 880, curve: Curve.EaseIn }, () => {
      cell.ring1Opacity = 0;
      cell.ring2Opacity = 0;
    });
    ui.animateTo({ duration: 500, delay: 1040, curve: curves.springMotion(0.4, 0.58) }, () => {
      cell.iconLift = 0;
      cell.iconScale = 1.0;
    });
    ui.animateTo({ duration: 380, delay: 1040, curve: curves.springMotion(0.4, 0.6) }, () => {
      cell.cardScale = 1.0;
    });
    AchievementEffects.finish(cell, ui, 1120);
    return 2100;
  }

  // ② 抛硬币：绕 X 轴翻三圈
  private static coinFlip(cell: BadgeCell, ui: UIContext): number {
    ui.animateTo({ duration: 420, curve: curves.springMotion(0.42, 0.62) }, () => {
      cell.iconLift = -26;
      cell.iconScale = 1.6;
      cell.cardScale = 1.04;
    });
    ui.animateTo({ duration: 1100, curve: Curve.Linear }, () => {
      cell.iconSpinX = 1080;
    });
    ui.animateTo({ duration: 700, delay: 120, curve: Curve.EaseOut }, () => {
      cell.glowOpacity = 0.9;
      cell.glowScale = 1.8;
    });
    ui.animateTo({ duration: 800, delay: 240, curve: Curve.EaseOut }, () => {
      cell.ring1Scale = 2.2;
      cell.ring1Opacity = 0.85;
    });
    ui.animateTo({ duration: 600, delay: 900, curve: Curve.EaseIn }, () => {
      cell.ring1Opacity = 0;
    });
    ui.animateTo({ duration: 520, delay: 1100, curve: curves.springMotion(0.4, 0.5) }, () => {
      cell.iconLift = 0;
      cell.iconScale = 1.0;
      cell.cardScale = 1.0;
    });
    AchievementEffects.finish(cell, ui, 1150);
    return 2150;
  }

  // ③ 心跳脉冲：两次心跳
  private static heartbeat(cell: BadgeCell, ui: UIContext): number {
    ui.animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      cell.iconScale = 1.28;
      cell.cardScale = 1.05;
    });
    ui.animateTo({ duration: 260, delay: 220, curve: Curve.EaseInOut }, () => {
      cell.iconScale = 1.0;
    });
    ui.animateTo({ duration: 220, delay: 480, curve: Curve.EaseOut }, () => {
      cell.iconScale = 1.22;
    });
    ui.animateTo({ duration: 300, delay: 700, curve: Curve.EaseInOut }, () => {
      cell.iconScale = 1.0;
      cell.cardScale = 1.0;
    });
    ui.animateTo({ duration: 900, delay: 300, curve: Curve.EaseOut }, () => {
      cell.glowOpacity = 0.85;
      cell.glowScale = 1.75;
    });
    ui.animateTo({ duration: 900, delay: 300, curve: Curve.EaseOut }, () => {
      cell.ring1Scale = 2.3;
      cell.ring1Opacity = 0.8;
    });
    ui.animateTo({ duration: 600, delay: 900, curve: Curve.EaseIn }, () => {
      cell.ring1Opacity = 0;
    });
    AchievementEffects.finish(cell, ui, 700);
    return 1700;
  }

  // ④ 摇铃：左右摆动后定格
  private static bellSwing(cell: BadgeCell, ui: UIContext): number {
    ui.animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      cell.iconSpinZ = -14;
      cell.cardRotate = -1.5;
      cell.iconScale = 1.25;
    });
    ui.animateTo({ duration: 220, delay: 180, curve: Curve.EaseInOut }, () => {
      cell.iconSpinZ = 12;
      cell.cardRotate = 1.2;
    });
    ui.animateTo({ duration: 200, delay: 400, curve: Curve.EaseInOut }, () => {
      cell.iconSpinZ = -8;
      cell.cardRotate = -0.8;
    });
    ui.animateTo({ duration: 260, delay: 600, curve: curves.springMotion(0.38, 0.5) }, () => {
      cell.iconSpinZ = 0;
      cell.cardRotate = 0;
    });
    ui.animateTo({ duration: 620, delay: 200, curve: Curve.EaseOut }, () => {
      cell.glowOpacity = 0.9;
      cell.glowScale = 1.7;
    });
    ui.animateTo({ duration: 800, delay: 260, curve: Curve.EaseOut }, () => {
      cell.ring1Scale = 2.1;
      cell.ring1Opacity = 0.75;
    });
    ui.animateTo({ duration: 600, delay: 900, curve: Curve.EaseIn }, () => {
      cell.ring1Opacity = 0;
    });
    ui.animateTo({ duration: 320, delay: 860, curve: curves.springMotion(0.4, 0.6) }, () => {
      cell.iconScale = 1.0;
    });
    AchievementEffects.finish(cell, ui, 760);
    return 1750;
  }

  // ⑤ 爆闪：三次高亮频闪
  private static flash(cell: BadgeCell, ui: UIContext): number {
    ui.animateTo({ duration: 90, curve: Curve.Linear }, () => {
      cell.iconOpacity = 0.15;
      cell.iconScale = 1.35;
    });
    ui.animateTo({ duration: 110, delay: 90, curve: Curve.Linear }, () => {
      cell.iconOpacity = 1;
      cell.glowOpacity = 1;
      cell.glowScale = 2.0;
    });
    ui.animateTo({ duration: 90, delay: 200, curve: Curve.Linear }, () => {
      cell.iconOpacity = 0.25;
    });
    ui.animateTo({ duration: 110, delay: 290, curve: Curve.Linear }, () => {
      cell.iconOpacity = 1;
    });
    ui.animateTo({ duration: 110, delay: 420, curve: Curve.Linear }, () => {
      cell.iconOpacity = 0.35;
    });
    ui.animateTo({ duration: 260, delay: 530, curve: curves.springMotion(0.4, 0.62) }, () => {
      cell.iconOpacity = 1;
      cell.iconScale = 1.0;
    });
    ui.animateTo({ duration: 500, delay: 100, curve: Curve.EaseOut }, () => {
      cell.cardScale = 1.07;
    });
    ui.animateTo({ duration: 400, delay: 700, curve: Curve.EaseInOut }, () => {
      cell.cardScale = 1.0;
    });
    ui.animateTo({ duration: 900, delay: 140, curve: Curve.EaseOut }, () => {
      cell.glowOpacity = 0;
      cell.glowScale = 2.3;
    });
    AchievementEffects.finish(cell, ui, 420);
    return 1600;
  }

  // ⑥ 穿越：放大到 2.6 倍再收回
  private static zoomThrough(cell: BadgeCell, ui: UIContext): number {
    ui.animateTo({ duration: 520, curve: Curve.EaseIn }, () => {
      cell.iconScale = 2.6;
      cell.iconOpacity = 0.9;
      cell.cardScale = 1.05;
    });
    ui.animateTo({ duration: 420, delay: 520, curve: curves.springMotion(0.4, 0.6) }, () => {
      cell.iconScale = 1.0;
      cell.cardScale = 1.0;
    });
    ui.animateTo({ duration: 900, curve: Curve.Linear }, () => {
      cell.iconSpinZ = 360;
    });
    ui.animateTo({ duration: 900, delay: 120, curve: Curve.EaseOut }, () => {
      cell.glowOpacity = 0.95;
      cell.glowScale = 2.2;
    });
    ui.animateTo({ duration: 1000, delay: 200, curve: Curve.EaseOut }, () => {
      cell.ring1Scale = 2.8;
      cell.ring1Opacity = 0.85;
    });
    ui.animateTo({ duration: 700, delay: 1000, curve: Curve.EaseIn }, () => {
      cell.ring1Opacity = 0;
    });
    AchievementEffects.finish(cell, ui, 900);
    return 1950;
  }

  // ⑦ 蓄力弹出：先抖动再弹出
  private static chargePop(cell: BadgeCell, ui: UIContext): number {
    ui.animateTo({ duration: 70, curve: Curve.Linear }, () => {
      cell.iconShake = -3.5;
      cell.iconScale = 0.94;
    });
    ui.animateTo({ duration: 70, delay: 70, curve: Curve.Linear }, () => {
      cell.iconShake = 3.5;
    });
    ui.animateTo({ duration: 70, delay: 140, curve: Curve.Linear }, () => {
      cell.iconShake = -3.0;
    });
    ui.animateTo({ duration: 70, delay: 210, curve: Curve.Linear }, () => {
      cell.iconShake = 3.0;
    });
    ui.animateTo({ duration: 70, delay: 280, curve: Curve.Linear }, () => {
      cell.iconShake = 0;
      cell.iconScale = 0.9;
    });
    ui.animateTo({ duration: 460, delay: 360, curve: curves.springMotion(0.42, 0.5) }, () => {
      cell.iconScale = 1.95;
      cell.iconLift = -10;
    });
    ui.animateTo({ duration: 460, delay: 900, curve: curves.springMotion(0.4, 0.58) }, () => {
      cell.iconScale = 1.0;
      cell.iconLift = 0;
    });
    ui.animateTo({ duration: 700, delay: 360, curve: Curve.EaseOut }, () => {
      cell.glowOpacity = 1;
      cell.glowScale = 2.1;
    });
    ui.animateTo({ duration: 900, delay: 420, curve: Curve.EaseOut }, () => {
      cell.ring1Scale = 2.6;
      cell.ring1Opacity = 0.9;
    });
    ui.animateTo({ duration: 620, delay: 1050, curve: Curve.EaseIn }, () => {
      cell.ring1Opacity = 0;
    });
    AchievementEffects.finish(cell, ui, 980);
    return 1900;
  }

  // ⑧ 转盘：平面内连转两圈
  private static spinner(cell: BadgeCell, ui: UIContext): number {
    ui.animateTo({ duration: 1000, curve: Curve.Linear }, () => {
      cell.iconSpinZ = 720;
    });
    ui.animateTo({ duration: 520, curve: curves.springMotion(0.45, 0.7) }, () => {
      cell.iconScale = 1.5;
      cell.cardScale = 1.05;
    });
    ui.animateTo({ duration: 480, delay: 1000, curve: curves.springMotion(0.4, 0.6) }, () => {
      cell.iconScale = 1.0;
      cell.cardScale = 1.0;
    });
    ui.animateTo({ duration: 900, delay: 200, curve: Curve.EaseOut }, () => {
      cell.glowOpacity = 0.9;
      cell.glowScale = 1.9;
    });
    ui.animateTo({ duration: 900, delay: 260, curve: Curve.EaseOut }, () => {
      cell.ring1Scale = 2.5;
      cell.ring1Opacity = 0.85;
    });
    ui.animateTo({ duration: 900, delay: 480, curve: Curve.EaseOut }, () => {
      cell.ring2Scale = 3.0;
      cell.ring2Opacity = 0.65;
    });
    ui.animateTo({ duration: 600, delay: 1100, curve: Curve.EaseIn }, () => {
      cell.ring1Opacity = 0;
      cell.ring2Opacity = 0;
    });
    AchievementEffects.finish(cell, ui, 1080);
    return 2050;
  }

  // ⑨ 呼吸浮现：从透明缓缓浮现
  private static breatheIn(cell: BadgeCell, ui: UIContext): number {
    cell.iconOpacity = 0;
    cell.iconScale = 0.6;
    ui.animateTo({ duration: 900, delay: 160, curve: Curve.EaseInOut }, () => {
      cell.iconOpacity = 1;
      cell.iconScale = 1.35;
    });
    ui.animateTo({ duration: 700, delay: 1060, curve: Curve.EaseInOut }, () => {
      cell.iconScale = 1.0;
    });
    ui.animateTo({ duration: 1500, delay: 120, curve: Curve.EaseInOut }, () => {
      cell.glowOpacity = 0.9;
      cell.glowScale = 1.8;
    });
    ui.animateTo({ duration: 1200, delay: 200, curve: Curve.EaseOut }, () => {
      cell.ring1Scale = 2.2;
      cell.ring1Opacity = 0.7;
    });
    ui.animateTo({ duration: 800, delay: 1200, curve: Curve.EaseIn }, () => {
      cell.ring1Opacity = 0;
    });
    AchievementEffects.finish(cell, ui, 1100);
    return 2100;
  }

  // ⑩ 天降：从上方砸下 + 落地挤压
  private static dropLand(cell: BadgeCell, ui: UIContext): number {
    cell.iconLift = -52;
    cell.iconOpacity = 0;
    ui.animateTo({ duration: 120, delay: 60, curve: Curve.EaseOut }, () => {
      cell.iconOpacity = 1;
    });
    ui.animateTo({ duration: 260, delay: 60, curve: Curve.EaseIn }, () => {
      cell.iconLift = 0;
    });
    // 落地挤压
    ui.animateTo({ duration: 90, delay: 320, curve: Curve.EaseOut }, () => {
      cell.iconScale = 1.35;
      cell.cardScale = 1.08;
    });
    ui.animateTo({ duration: 130, delay: 410, curve: Curve.EaseInOut }, () => {
      cell.iconScale = 0.92;
      cell.cardScale = 0.98;
    });
    ui.animateTo({ duration: 320, delay: 540, curve: curves.springMotion(0.4, 0.55) }, () => {
      cell.iconScale = 1.0;
      cell.cardScale = 1.0;
    });
    // 冲击波
    ui.animateTo({ duration: 800, delay: 330, curve: Curve.EaseOut }, () => {
      cell.ring1Scale = 2.8;
      cell.ring1Opacity = 0.95;
    });
    ui.animateTo({ duration: 800, delay: 430, curve: Curve.EaseOut }, () => {
      cell.ring2Scale = 2.2;
      cell.ring2Opacity = 0.7;
    });
    ui.animateTo({ duration: 600, delay: 950, curve: Curve.EaseIn }, () => {
      cell.ring1Opacity = 0;
      cell.ring2Opacity = 0;
    });
    ui.animateTo({ duration: 700, delay: 380, curve: Curve.EaseOut }, () => {
      cell.glowOpacity = 0.9;
      cell.glowScale = 1.9;
    });
    AchievementEffects.finish(cell, ui, 900);
    return 1800;
  }
}
