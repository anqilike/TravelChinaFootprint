import { promptAction } from '@kit.ArkUI';
import { CityItem } from '../model/CityDict';
import { CityRepository } from '../repository/CityRepository';
import { footprintStore } from '../viewmodel/FootprintStore';
import { Dimens, Motion, Palette } from '../common/Theme';
import { WindowService } from '../common/WindowService';

/**
 * 足迹清单（P-07）。
 * 已点亮 / 未点亮两个视图，支持搜索；点右侧按钮直接点亮或取消。
 */
@ComponentV2
export struct CityListPage {
  @Local showVisited: boolean = true;
  @Local keyword: string = '';
  /** 批量点亮模式 */
  @Local batchMode: boolean = false;
  /** 批量模式下已勾选的城市 */
  @Local selected: string[] = [];
  @Local submitting: boolean = false;
  /** 沉浸式布局下避开状态栏（vp） */
  @Local safeTop: number = 0;
  /** 底部导航条高度（vp），滚动内容要额外让出这么多 */
  @Local safeBottom: number = 0;

  aboutToAppear(): void {
    this.safeTop = WindowService.safeTop;
    this.safeBottom = WindowService.safeBottom;
  }

  private isSelected(code: string): boolean {
    return this.selected.includes(code);
  }

  private toggleSelect(code: string): void {
    if (this.isSelected(code)) {
      this.selected = this.selected.filter((item: string) => item !== code);
    } else {
      const next: string[] = this.selected.slice();
      next.push(code);
      this.selected = next;
    }
  }

  private async submitBatch(): Promise<void> {
    if (this.submitting || this.selected.length === 0) {
      return;
    }
    this.submitting = true;
    try {
      const count: number = await footprintStore.lightUpBatch(this.selected);
      promptAction.showToast({ message: `已点亮 ${count} 座城市` });
      this.selected = [];
      this.batchMode = false;
    } catch (err) {
      promptAction.showToast({ message: '批量点亮失败，请重试' });
    } finally {
      this.submitting = false;
    }
  }

  private currentList(): CityItem[] {
    const matched: CityItem[] = CityRepository.search(this.keyword);
    const result: CityItem[] = [];
    for (const city of matched) {
      const visited: boolean = footprintStore.isVisited(city.code);
      if (visited === this.showVisited) {
        result.push(city);
      }
    }
    return result;
  }

  private async toggle(city: CityItem): Promise<void> {
    if (footprintStore.isVisited(city.code)) {
      await footprintStore.unlight(city.code);
      promptAction.showToast({ message: `已取消点亮 ${city.name}` });
    } else {
      await footprintStore.lightUp(city.code);
      promptAction.showToast({ message: `已点亮 ${city.name}` });
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
      // 顶部：标题 + 分段 + 搜索（玻璃卡片）。
      // 左右留边用外层 padding，不用 width('100%') + margin（后者会让右侧溢出屏幕）。
      Column() {
        Column() {
          Row() {
            Column() {
              Text('足迹清单')
                .fontSize(22)
                .fontColor(Palette.text)
                .fontWeight(FontWeight.Medium)
              Text(`${footprintStore.visitedCount} / ${footprintStore.totalUnits} 个市州级行政区`)
                .fontSize(11)
                .fontColor(Palette.textDim)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text(this.batchMode ? '退出批量' : '批量点亮')
              .fontSize(12)
              .fontColor(this.batchMode ? Palette.text : Palette.gold)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius(999)
              .backgroundColor('#1FF5C542')
              .border({ width: 0.5, color: '#4DF5C542' })
              .onClick(() => {
                this.batchMode = !this.batchMode;
                if (!this.batchMode) {
                  this.selected = [];
                }
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Row() {
            // 注意：这里不能用 @Builder 传字符串（ArkUI 的 @Builder 按值传参不参与刷新，
            // 会出现"点亮了城市但分段数字还是 0"的问题），必须让 Text 直接读状态。
            Text('已点亮 ' + footprintStore.visitedCount)
              .fontSize(13)
              .fontColor(this.showVisited ? Palette.text : Palette.textDim)
              .fontWeight(this.showVisited ? FontWeight.Medium : FontWeight.Normal)
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .padding({ top: 10, bottom: 10 })
              .borderRadius(Dimens.pillRadius)
              .backgroundColor(this.showVisited ? '#33F5C542' : Color.Transparent)
              .animation({ duration: Motion.normal, curve: Curve.EaseOut })
              .onClick(() => {
                this.showVisited = true;
              })

            Text('未点亮 ' + (footprintStore.totalUnits - footprintStore.visitedCount))
              .fontSize(13)
              .fontColor(this.showVisited ? Palette.textDim : Palette.text)
              .fontWeight(this.showVisited ? FontWeight.Normal : FontWeight.Medium)
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .padding({ top: 10, bottom: 10 })
              .borderRadius(Dimens.pillRadius)
              .backgroundColor(this.showVisited ? Color.Transparent : '#33F5C542')
              .animation({ duration: Motion.normal, curve: Curve.EaseOut })
              .onClick(() => {
                this.showVisited = false;
              })
          }
          .width('100%')
          .padding(3)
          .borderRadius(Dimens.pillRadius)
          .backgroundColor('#66070B14')
          .margin({ top: 14 })

          TextInput({ placeholder: '搜索城市、省份', text: this.keyword })
            .height(44)
            .borderRadius(14)
            .backgroundColor('#66070B14')
            .placeholderColor(Palette.textDim)
            .fontColor(Palette.text)
            .margin({ top: 10 })
            .onChange((value: string) => {
              this.keyword = value;
            })
        }
        .width('100%')
        .padding(16)
        .borderRadius(Dimens.cardRadius)
        .backgroundColor('#26070B14')
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, { colorMode: ThemeColorMode.DARK })
        .border({ width: 0.5, color: '#1FFFFFFF' })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 + this.safeTop, bottom: 10 })

      List({ space: 8 }) {
        ForEach(this.currentList(), (city: CityItem) => {
          ListItem() {
            Row() {
              // 状态指示条：已点亮是金色，未点亮是灰蓝
              Column()
                .width(3)
                .height(34)
                .borderRadius(2)
                .backgroundColor(footprintStore.isVisited(city.code) ? Palette.gold : Palette.unlitStroke)
                .margin({ right: 12 })

              Column() {
                Text(city.name)
                  .fontSize(15)
                  .fontColor(Palette.text)
                Text(`${city.parent} · ${city.code}`)
                  .fontSize(11)
                  .fontColor(Palette.textDim)
                  .margin({ top: 3 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.batchMode) {
                Text(this.isSelected(city.code) ? '✓' : '○')
                  .fontSize(16)
                  .fontColor(this.isSelected(city.code) ? Palette.gold : Palette.textDim)
                  .width(28)
                  .textAlign(TextAlign.Center)
              } else {
                Text(footprintStore.isVisited(city.code) ? '已点亮' : '点亮')
                  .fontSize(13)
                  .fontColor(footprintStore.isVisited(city.code) ? Palette.gold : Palette.textDim)
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .borderRadius(999)
                  .backgroundColor(Palette.surfaceSoft)
                  .onClick(() => {
                    this.toggle(city);
                  })
              }
            }
            .width('100%')
            .padding(14)
            .borderRadius(16)
            .backgroundColor('#26070B14')
            .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, { colorMode: ThemeColorMode.DARK })
            .border({ width: 0.5, color: '#14FFFFFF' })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              if (this.batchMode && !footprintStore.isVisited(city.code)) {
                this.toggleSelect(city.code);
              }
            })
          }
        }, (city: CityItem) => city.code)
      }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
        .contentEndOffset(Dimens.navSpace + this.safeBottom)

      if (this.currentList().length === 0) {
        Text(this.showVisited ? '还没有点亮的城市，去地图上点一个吧' : '全部城市都已点亮')
          .fontSize(13)
          .fontColor(Palette.textDim)
          // 底部要同时让开悬浮导航和手势条，否则最后一行会被压住
          .margin({ bottom: Dimens.navSpace + this.safeBottom })
      }

      // 批量模式底部操作条
      if (this.batchMode) {
        Row() {
          Column() {
            Text(`已选 ${this.selected.length} 个城市`)
              .fontSize(13)
              .fontColor(Palette.text)
            Text('同一次点亮会记录为今天到访')
              .fontSize(10)
              .fontColor(Palette.textDim)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button(this.submitting ? '处理中…' : '点亮')
            .width(112)
            .height(40)
            .borderRadius(20)
            .fontSize(14)
            .backgroundColor(this.selected.length > 0 ? Palette.gold : Palette.line)
            .fontColor(this.selected.length > 0 ? '#1A1405' : Palette.textDim)
            .enabled(this.selected.length > 0 && !this.submitting)
            .onClick(() => {
              this.submitBatch();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .margin({ left: 16, right: 16, bottom: Dimens.navSpace + this.safeBottom - 14 })
        .borderRadius(Dimens.cardRadius)
        .backgroundColor('#B80C1320')
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, { colorMode: ThemeColorMode.DARK })
        .border({ width: 0.5, color: '#1FFFFFFF' })
      }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Palette.bg)

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

}
