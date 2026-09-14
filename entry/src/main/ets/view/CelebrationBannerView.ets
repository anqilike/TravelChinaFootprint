import { Palette } from '../common/Theme';
import { CelebrationBanner } from '../viewmodel/CelebrationBanner';

/**
 * 顶部"成就解锁"横幅：金色渐变卡片 + 流光扫过。
 * 位置固定贴在顶部（用 translate 做滑入滑出，不触发重新布局）。
 */
@ComponentV2
export struct CelebrationBannerView {
  @Param banner: CelebrationBanner = new CelebrationBanner();
  /** 状态栏高度（vp），横幅要避开 */
  @Param topInset: number = 0;

  build() {
    Row({ space: 12 }) {
      // 徽章图标
      Text(this.banner.icon)
        .fontSize(30)

      Column({ space: 2 }) {
        Text(this.banner.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#3A2A05')
        Text(this.banner.subtitle)
          .fontSize(11)
          .fontColor('#6B5313')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('NEW')
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor('#3A2A05')
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(999)
        .backgroundColor('#66FFFFFF')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .borderRadius(18)
    .linearGradient({
      angle: 100,
      colors: [['#FFE58A', 0.0], ['#F5C542', 0.55], ['#E0A81F', 1.0]]
    })
    // 流光层：盖在横幅上的一条斜向白光
    .overlay(this.shimmer(), { align: Alignment.Center })
    .shadow({ radius: 24, color: '#8CF5C542', offsetX: 0, offsetY: 10 })
    .translate({ y: this.banner.offsetY })
    .scale({ x: this.banner.scale, y: this.banner.scale })
    .opacity(this.banner.opacity)
    .hitTestBehavior(HitTestMode.None)
    .position({ x: 0, y: this.topInset + 8 })
  }

  @Builder
  shimmer() {
    Column() {
      Column()
        .width(38)
        .height(200)
        .linearGradient({
          angle: 18,
          colors: [['#00FFFFFF', 0.0], ['#59FFFFFF', 0.5], ['#00FFFFFF', 1.0]]
        })
        .translate({ x: this.banner.shimmerX })
        .rotate({ angle: 16 })
    }
    .width('100%')
    .height('100%')
    .borderRadius(18)
    .clip(true)
  }
}
