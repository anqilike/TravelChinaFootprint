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
  /** 卡片宽度：网格里是 31.5%（一行三个），试播时可以用别的值 */
  @Param cardWidth: Length = '31.5%';

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        // 图标区：光晕 + 扩散光环 + 图标
        Stack({ alignContent: Alignment.Center }) {
          // 常驻金色光晕（已解锁才亮）；庆祝时随爆发动画放大淡出
          Column()
            .width(50)
            .height(50)
            .borderRadius(25)
            .radialGradient({
              center: ['50%', '50%'],
              radius: '50%',
              colors: [['#59F5C542', 0.0], ['#2EF5C542', 0.55], ['#00F5C542', 1.0]]
            })
            .opacity(this.cell.celebrating
              ? this.cell.glowOpacity
              : (this.cell.unlocked ? 0.85 : 0))
            .scale({
              x: this.cell.celebrating ? this.cell.glowScale : 1,
              y: this.cell.celebrating ? this.cell.glowScale : 1
            })

          // 两圈依次向外扩散的金色光环
          if (this.cell.celebrating) {
            Column()
              .width(46)
              .height(46)
              .borderRadius(23)
              .border({ width: 2, color: '#E6F5C542' })
              .scale({ x: this.cell.ring1Scale, y: this.cell.ring1Scale })
              .opacity(this.cell.ring1Opacity)
            Column()
              .width(46)
              .height(46)
              .borderRadius(23)
              .border({ width: 1.5, color: '#B3FFD97D' })
              .scale({ x: this.cell.ring2Scale, y: this.cell.ring2Scale })
              .opacity(this.cell.ring2Opacity)
          }

          // 徽章本体：升起 + 放大 + 绕 Y 轴转两圈
          Text(this.cell.icon)
            .fontSize(26)
            .scale({
              x: this.cell.celebrating ? this.cell.iconScale : 1,
              y: this.cell.celebrating ? this.cell.iconScale : 1
            })
            .translate({
              x: this.cell.celebrating ? this.cell.iconShake : 0,
              y: this.cell.celebrating ? this.cell.iconLift : 0
            })
            // 三轴旋转合成：每种效果只用其中一个轴，所以按"哪个角度非零"选轴、
            // 角度取三者之和即可（ArkUI 的 rotate 只能给一个轴向量 + 一个角度）
            .rotate({
              x: this.cell.celebrating && this.cell.iconSpinX !== 0 ? 1 : 0,
              y: this.cell.celebrating && this.cell.iconSpin !== 0 ? 1 : 0,
              z: this.cell.celebrating && this.cell.iconSpinZ !== 0 ? 1 : 0,
              angle: this.cell.celebrating
                ? this.cell.iconSpin + this.cell.iconSpinX + this.cell.iconSpinZ : 0
            })
            // 未解锁的徽章用灰度滤镜压下去，比单纯降透明度更像"还没点亮"
            .grayscale(this.cell.unlocked ? 0 : 1)
            .opacity(this.cell.celebrating
              ? this.cell.iconOpacity
              : (this.cell.unlocked ? 1 : 0.65))
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
    .width(this.cardWidth)
    .height(122)
    .margin({ bottom: 10 })
    .borderRadius(16)
    .clip(true)
    .backgroundColor(this.cell.unlocked ? '#33F5C542' : '#1A0F1626')
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, { colorMode: ThemeColorMode.DARK })
    .border({
      width: this.cell.celebrating ? 1.6 : (this.cell.unlocked ? 0.8 : 0.5),
      color: this.cell.unlocked ? '#66F5C542' : '#14FFFFFF'
    })
    // 徽章浮起时会越过卡片上沿，抬高层级避免被上一行的卡片压住
    .zIndex(this.cell.celebrating ? 3 : 1)
    // 庆祝时卡片自身弹起一下
    .scale({
      x: this.cell.celebrating ? this.cell.cardScale : 1,
      y: this.cell.celebrating ? this.cell.cardScale : 1
    })
    .rotate({ angle: this.cell.celebrating ? this.cell.cardRotate : 0 })
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
