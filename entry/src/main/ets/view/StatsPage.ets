import { AchievementEngine, AchievementItem } from '../viewmodel/AchievementEngine';
import { footprintStore } from '../viewmodel/FootprintStore';
import { CityRepository } from '../repository/CityRepository';
import { Dimens, Palette } from '../common/Theme';
import { MaterialKit } from '../common/MaterialKit';
import { WindowService } from '../common/WindowService';

/**
 * 统计与成就（P-08）。
 * 全部数据本地计算，实时联动地图与清单。
 */
@ComponentV2
export struct StatsPage {
  /** 沉浸式布局下避开状态栏（vp） */
  @Local safeTop: number = 0;
  /** 底部导航条高度（vp），滚动内容要额外让出这么多 */
  @Local safeBottom: number = 0;

  aboutToAppear(): void {
    this.safeTop = WindowService.safeTop;
    this.safeBottom = WindowService.safeBottom;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
        Text('我的足迹')
          .fontSize(22)
          .fontColor(Palette.text)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .margin({ bottom: 14 })

        // 核心数字：环形进度（金色光环 = 已点亮比例）
        Row() {
          Stack() {
            Progress({
              value: footprintStore.visitedCount,
              total: footprintStore.totalUnits === 0 ? 1 : footprintStore.totalUnits,
              type: ProgressType.Ring
            })
              .width(104)
              .height(104)
              .color(Palette.gold)
              .backgroundColor('#33FFFFFF')
              .style({ strokeWidth: 9, enableSmoothEffect: true })

            Column() {
              Text(`${(footprintStore.coverage * 100).toFixed(1)}%`)
                .fontSize(19)
                .fontColor(Palette.goldLight)
                .fontWeight(FontWeight.Medium)
              Text('覆盖率')
                .fontSize(10)
                .fontColor(Palette.textDim)
                .margin({ top: 2 })
            }
          }
          .width(104)
          .height(104)

          Column() {
            Row() {
              Text(`${footprintStore.visitedCount}`)
                .fontSize(40)
                .fontColor(Palette.goldLight)
                .fontWeight(FontWeight.Medium)
              Text(` / ${footprintStore.totalUnits}`)
                .fontSize(14)
                .fontColor(Palette.textDim)
                .margin({ left: 6, bottom: 6 })
            }
            .alignItems(VerticalAlign.Bottom)

            Text('个市州级行政区已点亮')
              .fontSize(12)
              .fontColor(Palette.textDim)
              .margin({ top: 2 })

            Text(`覆盖 ${footprintStore.provinceCount} / ${footprintStore.provinceTotal} 个省级行政区`)
              .fontSize(12)
              .fontColor(Palette.textDim)
              .margin({ top: 8 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .padding({ left: 18 })
        }
        .width('100%')
        .width('100%')
        .padding(18)
        .borderRadius(Dimens.cardRadius)
        .backgroundColor('#2E0A1020')
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, { colorMode: ThemeColorMode.DARK })
        .border({ width: 0.5, color: '#1FFFFFFF' })

        // 覆盖率明细
        Column() {
          this.statRow('到访最多的城市', footprintStore.mostVisitedCity.length > 0 ?
            `${footprintStore.mostVisitedCity}（${footprintStore.mostVisitedTimes} 次）` : '—')
          Divider().color(Palette.line)
          this.statRow('城市字典版本', `${CityRepository.dictVersion()} · ${CityRepository.dictGeneratedAt()}`)
        }
        .width('100%')
        .padding({ left: 18, right: 18 })
        .borderRadius(Dimens.cardRadius)
        .backgroundColor('#26070B14')
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, { colorMode: ThemeColorMode.DARK })
        .border({ width: 0.5, color: '#14FFFFFF' })
        .margin({ top: 12 })

        // 成就
        Text('成就徽章')
          .fontSize(17)
          .fontColor(Palette.text)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .margin({ top: 24, bottom: 12 })

        // 成就徽章：一行 3 个、共 3 行（9 枚）
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(AchievementEngine.evaluate(footprintStore.visitedCodes), (item: AchievementItem) => {
            Column() {
              Text(item.icon)
                .fontSize(22)
              Text(item.name)
                .fontSize(13)
                .fontColor(Palette.text)
                .margin({ top: 6 })
                .maxLines(1)
              Text(item.desc)
                .fontSize(10)
                .fontColor(Palette.textDim)
                .margin({ top: 2 })
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
              Text(item.unlocked ? '已解锁' : `${item.progress}/${item.target}`)
                .fontSize(10)
                .fontColor(item.unlocked ? Palette.gold : Palette.textDim)
                .margin({ top: 6 })
            }
            // 三列布局：每格占比 31.5%，配合 SpaceBetween 正好一行三个
            .width('31.5%')
            .height(122)
            .justifyContent(FlexAlign.Center)
            .padding(8)
            .margin({ bottom: 10 })
            .borderRadius(16)
            .backgroundColor(item.unlocked ? '#33F5C542' : '#1A0F1626')
            .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, { colorMode: ThemeColorMode.DARK })
            .border({ width: 0.5, color: item.unlocked ? '#66F5C542' : '#14FFFFFF' })
            .opacity(item.unlocked ? 1.0 : 0.55)
          }, (item: AchievementItem) => item.id)
        }
        .width('100%')

        Text('说明：本页所有统计均在设备本地计算；点亮单元为"市州级行政区"，含省直辖县级单位与兵团城市。')
          .fontSize(11)
          .fontColor(Palette.textDim)
          .margin({ top: 16 })
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16 + this.safeTop,
          bottom: Dimens.navSpace + this.safeBottom })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)

      // 顶部渐隐遮罩：滚动内容接近状态栏时淡出，不与系统时间/信号图标打架
      Column()
        .width('100%')
        .height(this.safeTop + 12)
        .linearGradient({
          angle: 180,
          colors: [['#FF070B14', 0.0], ['#F2070B14', 0.7], ['#00070B14', 1.0]]
        })
        .hitTestBehavior(HitTestMode.None)
        .position({ x: 0, y: 0 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.bg)
  }

  @Builder
  statRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(Palette.text)
      Blank()
      Text(value)
        .fontSize(13)
        .fontColor(Palette.textDim)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
  }
}
