import { AchievementEngine, AchievementItem } from '../viewmodel/AchievementEngine';
import { FootprintListener, footprintStore } from '../viewmodel/FootprintStore';
import { CityRepository } from '../repository/CityRepository';
import { Dimens, Motion, Palette } from '../common/Theme';
import { MaterialKit } from '../common/MaterialKit';
import { WindowService } from '../common/WindowService';
import { curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

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
  /** 入场动效标记 */
  @Local entered: boolean = false;
  /**
   * 正在庆祝的徽章 id（空串表示没有）。
   * 只保留"一套"庆祝参数，因为同一时刻只会点亮一枚徽章；
   * 多枚新解锁时按队列依次播放。
   */
  @Local celebratingId: string = '';
  /** 徽章图标的弹跳缩放（弹簧曲线自然过冲） */
  @Local badgeScale: number = 1;
  /** 光晕的扩散缩放与透明度 */
  @Local burstScale: number = 1;
  @Local burstOpacity: number = 0;
  /** 卡片扫光的水平位移 */
  @Local shineX: number = -140;
  /** 待庆祝队列 */
  private celebrateQueue: string[] = [];
  /**
   * 订阅足迹变化：取消点亮会让某些徽章失去达成条件，
   * 这时要把它们从"已庆祝"集合里移除，之后再达成才会重新播放动画。
   */
  private footprintListener: FootprintListener = (code: string, visited: boolean) => {
    if (!visited) {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      AchievementEngine.forgetLocked(context, AchievementEngine.evaluate(footprintStore.visitedCodes));
    }
  };

  aboutToAppear(): void {
    this.safeTop = WindowService.safeTop;
    this.safeBottom = WindowService.safeBottom;
    this.playEnter();
    this.detectNewlyUnlocked();
    footprintStore.subscribe(this.footprintListener);
  }

  aboutToDisappear(): void {
    footprintStore.unsubscribe(this.footprintListener);
  }

  /** 找出"新解锁、还没庆祝过"的徽章，等入场动画放完再依次播放点亮动画 */
  private async detectNewlyUnlocked(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const items: AchievementItem[] = AchievementEngine.evaluate(footprintStore.visitedCodes);
      const fresh: string[] = await AchievementEngine.takeNewlyUnlocked(context, items);
      // 一次最多庆祝 3 枚，避免"一口气炸 9 个"反而显得吵
      this.celebrateQueue = fresh.slice(0, 3);
      if (this.celebrateQueue.length > 0) {
        setTimeout(() => {
          this.runCelebration();
        }, 480);
      }
    } catch (err) {
      this.celebrateQueue = [];
    }
  }

  private runCelebration(): void {
    const id: string | undefined = this.celebrateQueue.shift();
    if (id === undefined) {
      this.celebratingId = '';
      return;
    }
    this.playUnlockAnimation(id);
    setTimeout(() => {
      this.runCelebration();
    }, 1250);
  }

  /**
   * 单枚徽章的点亮动画（三段同时起跑，合成一个"爆发"观感）：
   *  1) 图标：0.78 → 1，配阻尼比 0.52 的弹簧曲线，自然过冲到约 1.15 再回弹；
   *  2) 光晕：从 0.55 倍扩散到 1.9 倍并淡出，像一圈金色气浪推开；
   *  3) 扫光：一道斜向白光从卡片左侧扫到右侧。
   * 全部用 UIContext.animateTo（官方《使用动画》的"显式动画"），
   * 先把初值写进去、下一帧再动，保证动画一定被触发。
   */
  private playUnlockAnimation(id: string): void {
    this.celebratingId = id;
    this.badgeScale = 0.78;
    this.burstScale = 0.55;
    this.burstOpacity = 0.9;
    this.shineX = -140;
    setTimeout(() => {
      const ui: UIContext = this.getUIContext();
      // 1) 图标弹出（弹簧过冲）
      ui.animateTo({ duration: 640, curve: curves.springMotion(0.5, 0.52) }, () => {
        this.badgeScale = 1.0;
      });
      // 2) 光晕扩散 + 淡出
      ui.animateTo({ duration: 900, curve: curves.springMotion(0.55, 0.85) }, () => {
        this.burstScale = 1.9;
        this.burstOpacity = 0;
      });
      // 3) 扫光（延迟一点起跑，跟在爆发后面）
      ui.animateTo({ duration: 760, delay: 90, curve: Curve.EaseOut }, () => {
        this.shineX = 150;
      });
    }, 40);
  }

  /** 首次进入本页时淡入 + 轻微上浮，让页签切换不再"生硬地换一整屏" */
  private playEnter(): void {
    this.entered = false;
    setTimeout(() => {
      this.entered = true;
    }, 30);
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
          // 注意：这里不能用"按值传参的 @Builder"（this.statRow(...)）。
          // 官方文档明确说明 @Builder 的按值参数不参与刷新：
          // 取消点亮后 mostVisitedCity 变了，传进去的字符串却不会重新求值，
          // 界面会一直停在"雅安市（1 次）"。直接读 @Trace 状态才能建立依赖。
          Row() {
            Text('到访最多的城市')
              .fontSize(14)
              .fontColor(Palette.text)
              .layoutWeight(1)
            Text(footprintStore.mostVisitedCity.length > 0
              ? `${footprintStore.mostVisitedCity}（${footprintStore.mostVisitedTimes} 次）` : '—')
              .fontSize(13)
              .fontColor(Palette.textDim)
              .textAlign(TextAlign.End)
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })
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
          ForEach(AchievementEngine.evaluate(footprintStore.visitedCodes),
            (item: AchievementItem, index: number) => {
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
                      .opacity(item.unlocked
                        ? (this.celebratingId === item.id ? this.burstOpacity : 0.85) : 0)
                      .scale({
                        x: this.celebratingId === item.id ? this.burstScale : 1,
                        y: this.celebratingId === item.id ? this.burstScale : 1
                      })

                    // 扩散光环：只在庆祝时出现，像一圈气浪推开
                    if (this.celebratingId === item.id) {
                      Column()
                        .width(44)
                        .height(44)
                        .borderRadius(22)
                        .border({ width: 2, color: '#B3F5C542' })
                        .scale({ x: this.burstScale, y: this.burstScale })
                        .opacity(this.burstOpacity)
                    }

                    Text(item.icon)
                      .fontSize(26)
                      .scale({
                        x: this.celebratingId === item.id ? this.badgeScale : 1,
                        y: this.celebratingId === item.id ? this.badgeScale : 1
                      })
                      // 未解锁的徽章用灰度滤镜压下去，比单纯降透明度更像"还没点亮"
                      .grayscale(item.unlocked ? 0 : 1)
                      .opacity(item.unlocked ? 1 : 0.65)
                  }
                  .width(50)
                  .height(50)

                  Text(item.name)
                    .fontSize(13)
                    .fontColor(item.unlocked ? Palette.text : Palette.textDim)
                    .fontWeight(item.unlocked ? FontWeight.Medium : FontWeight.Normal)
                    .margin({ top: 6 })
                    .maxLines(1)
                  Text(item.desc)
                    .fontSize(10)
                    .fontColor(Palette.textDim)
                    .margin({ top: 2 })
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .textAlign(TextAlign.Center)
                  Text(item.unlocked ? '★ 已解锁' : `${item.progress}/${item.target}`)
                    .fontSize(10)
                    .fontColor(item.unlocked ? Palette.gold : Palette.textDim)
                    .fontWeight(item.unlocked ? FontWeight.Medium : FontWeight.Normal)
                    .margin({ top: 6 })
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .padding(8)

                // 扫光：一条斜向白光从卡片左侧扫到右侧（只在庆祝时出现）
                if (this.celebratingId === item.id) {
                  Column()
                    .width(26)
                    .height(220)
                    .linearGradient({
                      angle: 18,
                      colors: [['#00FFFFFF', 0.0], ['#80FFFFFF', 0.5], ['#00FFFFFF', 1.0]]
                    })
                    .translate({ x: this.shineX })
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
              .backgroundColor(item.unlocked ? '#33F5C542' : '#1A0F1626')
              .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, { colorMode: ThemeColorMode.DARK })
              .border({
                width: item.unlocked ? 0.8 : 0.5,
                color: item.unlocked ? '#66F5C542' : '#14FFFFFF'
              })
              // 入场：逐枚错开淡入上浮，一行三个像"依次落位"
              .opacity(this.entered ? 1 : 0)
              .translate({ y: this.entered ? 0 : 12 })
              .animation({
                duration: Motion.normal + 60,
                delay: 40 + index * 45,
                curve: curves.springMotion(0.42, 0.9)
              })
              // key 必须带上"解锁状态 + 进度"：ArkUI 的 ForEach 只按 key 做 diff，
              // 只用 id 的话，取消点亮后 id 没变，这一项就被判定为"没变"而不重建，
              // 徽章会一直停在已点亮的样子（用户实测遇到的 bug）。
            }, (item: AchievementItem) =>
              `${item.id}_${item.unlocked ? 1 : 0}_${item.progress}`)
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
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 14 })
    .animation({ duration: Motion.normal + 80, curve: curves.springMotion(0.42, 0.9) })
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
