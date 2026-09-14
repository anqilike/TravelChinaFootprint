import { CelebrationParticle } from '../viewmodel/CelebrationParticle';

/**
 * 单颗粒子的渲染节点：一个发光的小圆点。
 * 位置/透明度/缩放全部由 CelebrationParticle 的 @Trace 字段驱动。
 */
@ComponentV2
export struct CelebrationParticleView {
  @Param dot: CelebrationParticle = new CelebrationParticle(6, '#F5C542');

  build() {
    Circle()
      .width(this.dot.size)
      .height(this.dot.size)
      .fill(this.dot.color)
      .shadow({ radius: 8, color: '#99F5C542', offsetX: 0, offsetY: 0 })
      .opacity(this.dot.opacity)
      .scale({ x: this.dot.scale, y: this.dot.scale })
      .position({ x: this.dot.x - this.dot.size / 2, y: this.dot.y - this.dot.size / 2 })
      .hitTestBehavior(HitTestMode.None)
  }
}
