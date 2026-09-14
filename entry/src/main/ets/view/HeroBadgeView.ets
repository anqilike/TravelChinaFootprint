import { HeroBadge } from '../viewmodel/HeroBadge';

/**
 * 中心大勋章：金色光晕 + 外圈光环 + 徽章本体。
 * 尺寸由 hero.size 驱动，所以"出现时放大、归位时缩小"是同一个属性在做动画。
 */
@ComponentV2
export struct HeroBadgeView {
  @Param hero: HeroBadge = new HeroBadge();

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 金色光晕
      Column()
        .width(this.hero.size)
        .height(this.hero.size)
        .borderRadius(this.hero.size / 2)
        .radialGradient({
          center: ['50%', '50%'],
          radius: '50%',
          colors: [['#80F5C542', 0.0], ['#40F5C542', 0.45], ['#00F5C542', 1.0]]
        })
        .opacity(this.hero.glowOpacity)
        .scale({ x: this.hero.glowScale, y: this.hero.glowScale })

      // 外圈光环
      Column()
        .width(this.hero.size * 0.72)
        .height(this.hero.size * 0.72)
        .borderRadius(this.hero.size * 0.36)
        .border({ width: 2, color: '#CCF5C542' })
        .opacity(this.hero.glowOpacity)
        .scale({ x: this.hero.glowScale, y: this.hero.glowScale })

      // 徽章本体
      Text(this.hero.icon)
        .fontSize(this.hero.size * 0.5)
    }
    .width(this.hero.size)
    .height(this.hero.size)
    .position({ x: this.hero.x - this.hero.size / 2, y: this.hero.y - this.hero.size / 2 })
    .opacity(this.hero.opacity)
    .hitTestBehavior(HitTestMode.None)
  }
}
