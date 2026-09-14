import { curves } from '@kit.ArkUI';
import { Motion, Palette } from '../common/Theme';
import { BadgeCell } from '../viewmodel/BadgeCell';

/**
 * 单枚成就徽章卡片。
 *
 * 单独抽成组件的原因见 BadgeCell 的注释：
 * 它读取的是 @ObservedV2 对象的 @Trace 字段，字段一变本组件就刷新，
 * 不受父级 ForEach 的复用策略影响——点亮动画才能真的跑起来。
 */
@ComponentV2
export struct BadgeCard {
  @Param cell: BadgeCell = new BadgeCell('', '', '', '');
  /** 在网格里的序号，用于入场动效错开时间 */
  @Param index: number = 0;
  /** 页面入场标记（父组件控制） */
  @Param entered: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        // 图标区：光晕 + 扩散光环 + 图标
        Stack({ alignContent: Alignment.Center }) {
          // 常驻金色光晕（已解锁才亮）；庆祝时随扩散动画放大淡出
          Column()
            .width(50)
            .height(50)
            .borderRadius(25)
            .radialGradient({
              center: ['50%', '50%'],
              radius: '50%',
              colors: [['#59F5C542', 0.0], ['#2EF5C542', 0.55], ['#00F5C542', 1.0]]
            })
            .opacity(this.cell.unlocked
              ? (this.cell.celebrating ? this.cell.glowOpacity : 0.85) : 0)
            .scale({
              x: this.cell.celebrating ? this.cell.glowScale : 1,
              y: this.cell.celebrating ? this.cell.glowScale : 1
            })

          // 扩散光环：只在庆祝时出现，像一圈气浪推开
          if (this.cell.celebrating) {
            Column()
              .width(44)
              .height(44)
              .borderRadius(22)
              .border({ width: 2, color: '#B3F5C542' })
              .scale({ x: this.cell.glowScale, y: this.cell.glowScale })
              .opacity(this.cell.glowOpacity)
          }

          Text(this.cell.icon)
            .fontSize(26)
            .scale({
              x: this.cell.celebrating ? this.cell.iconScale : 1,
              y: this.cell.celebrating ? this.cell.iconScale : 1
            })
            // 浮起 + 转圈（绕 Y 轴转满一圈，像硬币翻面）
            .translate({ y: this.cell.celebrating ? this.cell.iconLift : 0 })
            .rotate({ y: 1, angle: this.cell.celebrating ? this.cell.iconSpin : 0 })
            // 未解锁的徽章用灰度滤镜压下去，比单纯降透明度更像"还没点亮"
            .grayscale(this.cell.unlocked ? 0 : 1)
            .opacity(this.cell.unlocked ? 1 : 0.65)
        }
        .width(50)
        .height(50)

        Text(this.cell.name)
          .fontSize(13)
          .fontColor(this.cell.unlocked ? Palette.text : Palette.textDim)
          .fontWeight(this.cell.unlocked ? FontWeight.Medium : FontWeight.Normal)
          .margin({ top: 6 })
          .maxLines(1)
        Text(this.cell.desc)
          .fontSize(10)
          .fontColor(Palette.textDim)
          .margin({ top: 2 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
        Text(this.cell.unlocked ? '★ 已解锁' : `${this.cell.progress}/${this.cell.target}`)
          .fontSize(10)
          .fontColor(this.cell.unlocked ? Palette.gold : Palette.textDim)
          .fontWeight(this.cell.unlocked ? FontWeight.Medium : FontWeight.Normal)
          .margin({ top: 6 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding(8)

      // 扫光：一条斜向白光从卡片左侧扫到右侧（只在庆祝时出现）
      if (this.cell.celebrating) {
        Column()
          .width(26)
          .height(220)
          .linearGradient({
            angle: 18,
            colors: [['#00FFFFFF', 0.0], ['#80FFFFFF', 0.5], ['#00FFFFFF', 1.0]]
          })
          .translate({ x: this.cell.shineX })
          .rotate({ angle: 16 })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    // 三列布局：每格占比 31.5%，配合 SpaceBetween 正好一行三个
    .width('31.5%')
    .height(122)
    .margin({ bottom: 10 })
    .borderRadius(16)
    .clip(true)
    .backgroundColor(this.cell.unlocked ? '#33F5C542' : '#1A0F1626')
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, { colorMode: ThemeColorMode.DARK })
    .border({
      width: this.cell.unlocked ? 0.8 : 0.5,
      color: this.cell.unlocked ? '#66F5C542' : '#14FFFFFF'
    })
    // 徽章浮起时会越过卡片上沿，抬高层级避免被上一行的卡片压住
    .zIndex(this.cell.celebrating ? 3 : 1)
    // 入场：逐枚错开淡入上浮，一行三个像"依次落位"
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 12 })
    .animation({
      duration: Motion.normal + 60,
      delay: 40 + this.index * 45,
      curve: curves.springMotion(0.42, 0.9)
    })
  }
}
