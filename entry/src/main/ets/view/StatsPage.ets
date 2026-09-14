import { AchievementEngine, AchievementItem } from '../viewmodel/AchievementEngine';
import { FootprintListener, footprintStore } from '../viewmodel/FootprintStore';
import { BadgeCell } from '../viewmodel/BadgeCell';
import { BadgeCard } from './BadgeCard';
import { CelebrationBanner } from '../viewmodel/CelebrationBanner';
import { CelebrationBannerView } from './CelebrationBannerView';
import { CityRepository } from '../repository/CityRepository';
import { Dimens, Motion, Palette } from '../common/Theme';
import { MaterialKit } from '../common/MaterialKit';
import { WindowService } from '../common/WindowService';
import { curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'StatsPage';

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
  /** 正在庆祝的徽章 id（空串表示没有） */
  @Local celebratingId: string = '';
  /** 顶部"成就解锁"横幅（可观察模型，滑入/流光靠它驱动） */
  @Local banner: CelebrationBanner = new CelebrationBanner();
  /**
   * 9 枚徽章的可观察模型：动画参数存在模型里、由 BadgeCard 这个独立子组件读取，
   * 这样字段一变子组件就刷新，不受 ForEach 复用策略影响。
   */
  @Local cells: BadgeCell[] = [];
  private cellById: Map<string, BadgeCell> = new Map<string, BadgeCell>();
  /** 待庆祝队列 */
  private celebrateQueue: string[] = [];
  /** 是否有庆祝流程在跑（含 480ms 的等待期），防止重复排程 */
  private celebrationRunning: boolean = false;
  /** 防止 aboutToAppear 与 @Monitor 同时触发导致重复检测 */
  private detecting: boolean = false;
  /**
   * 由父组件传入：当前是否停留在统计页。
   *
   * 为什么需要它：新解锁检测必须在**每次进入本页**时做一遍。
   * 只写在 aboutToAppear 里的话，页面创建过一次之后再切回来就不会触发，
   * 用户点亮城市后切过来什么都看不到——这就是"没看到动画"的原因。
   */
  @Param active: boolean = false;

  @Monitor('active')
  onActiveChanged(): void {
    if (this.active) {
      this.detectNewlyUnlocked();
    }
  }
  /**
   * 订阅足迹变化：取消点亮会让某些徽章失去达成条件，
   * 这时要把它们从"已庆祝"集合里移除，之后再达成才会重新播放动画。
   */
  private footprintListener: FootprintListener = (code: string, visited: boolean) => {
    // 点亮/取消都会影响达成情况，先把最新进度同步进徽章模型
    this.syncCells();
    if (!visited) {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      AchievementEngine.forgetLocked(context, AchievementEngine.evaluate(footprintStore.visitedCodes));
    }
  };

  aboutToAppear(): void {
    this.safeTop = WindowService.safeTop;
    this.safeBottom = WindowService.safeBottom;
    this.ensureCells();
    this.playEnter();
    this.detectNewlyUnlocked();
    footprintStore.subscribe(this.footprintListener);
  }

  /** 首次创建 9 个可观察徽章模型（只建一次，之后复用） */
  private ensureCells(): void {
    if (this.cells.length === 0) {
      const items: AchievementItem[] = AchievementEngine.evaluate(footprintStore.visitedCodes);
      const list: BadgeCell[] = [];
      for (const item of items) {
        const cell: BadgeCell = new BadgeCell(item.id, item.name, item.desc, item.icon);
        list.push(cell);
        this.cellById.set(item.id, cell);
      }
      this.cells = list;
    }
    this.syncCells();
  }

  /** 把最新的达成情况同步进模型（只有真的变了才赋值，避免多余的刷新） */
  private syncCells(): void {
    const items: AchievementItem[] = AchievementEngine.evaluate(footprintStore.visitedCodes);
    for (const item of items) {
      const cell: BadgeCell | undefined = this.cellById.get(item.id);
      if (cell === undefined) {
        continue;
      }
      if (cell.progress !== item.progress) {
        cell.progress = item.progress;
      }
      if (cell.target !== item.target) {
        cell.target = item.target;
      }
      if (cell.unlocked !== item.unlocked) {
        cell.unlocked = item.unlocked;
      }
    }
  }

  aboutToDisappear(): void {
    footprintStore.unsubscribe(this.footprintListener);
  }

  /** 找出"新解锁、还没庆祝过"的徽章，等入场动画放完再依次播放点亮动画 */
  private async detectNewlyUnlocked(): Promise<void> {
    if (this.detecting) {
      return;
    }
    this.detecting = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const items: AchievementItem[] = AchievementEngine.evaluate(footprintStore.visitedCodes);
      const fresh: string[] = await AchievementEngine.takeNewlyUnlocked(context, items);
      // 追加而不是覆盖：aboutToAppear 与 @Monitor 可能先后各触发一次检测，
      // 后一次拿到的 fresh 通常是空的——如果直接赋值，就会把刚排好的队列清空，
      // 结果动画一次都播不出来（实测踩过：两次检测只隔 9ms）。
      for (const id of fresh) {
        if (this.celebratingId !== id && !this.celebrateQueue.includes(id)) {
          this.celebrateQueue.push(id);
        }
      }
      // 一次最多庆祝 3 枚，避免"一口气炸 9 个"反而显得吵
      if (this.celebrateQueue.length > 3) {
        this.celebrateQueue = this.celebrateQueue.slice(0, 3);
      }
      if (this.celebrateQueue.length > 0 && !this.celebrationRunning) {
        this.celebrationRunning = true;
        setTimeout(() => {
          this.runCelebration();
        }, 480);
      }
    } catch (err) {
      this.celebrateQueue = [];
    } finally {
      this.detecting = false;
    }
  }

  private runCelebration(): void {
    const id: string | undefined = this.celebrateQueue.shift();
    // 上一枚复位（动画已播完），保证同时只有一枚处于庆祝态
    if (this.celebratingId.length > 0) {
      this.resetCell(this.celebratingId);
    }
    if (id === undefined) {
      this.celebratingId = '';
      this.celebrationRunning = false;
      return;
    }
    this.celebratingId = id;
    this.playUnlockAnimation(id);
    setTimeout(() => {
      this.runCelebration();
    }, 3150);
  }

  /** 复位某一枚的庆祝状态 */
  private resetCell(id: string): void {
    const cell: BadgeCell | undefined = this.cellById.get(id);
    if (cell === undefined) {
      return;
    }
    cell.celebrating = false;
    cell.shineX = -140;
  }

  /**
   * 单枚徽章的点亮庆祝动画（约 3 秒）。整套动作都发生在卡片内部 + 顶部横幅，
   * 不依赖任何全屏浮层或坐标换算——那正是之前几种方案失败的地方。
   *
   *  ① 卡片聚焦 —— 卡片轻微弹起，底色转亮金、边框加粗发光；
   *  ② 勋章升起 —— 徽章抬起 12vp、放大到 1.8 倍，同时绕 Y 轴匀速转满两圈；
   *  ③ 光轮爆发 —— 金色光晕炸开，两圈光环依次向外扩散并淡出；
   *  ④ 落回     —— 徽章带弹性落回原位，卡片跟着回弹，同时一道扫光划过卡片；
   *  ⑤ 顶部横幅 —— "成就解锁 · 首站"金色横幅从屏幕顶部弹入、流光扫过，最后收回。
   *
   * 所有可变状态都放在 @ObservedV2 模型里（BadgeCell / CelebrationBanner），
   * 由独立子组件渲染；时间轴用 `UIContext.animateTo` 的 delay 排布。
   */
  private playUnlockAnimation(id: string): void {
    const cell: BadgeCell | undefined = this.cellById.get(id);
    if (cell === undefined) {
      return;
    }
    // 初值：全部回到常态，避免上一次庆祝的残留
    cell.celebrating = true;
    cell.cardScale = 1;
    cell.iconLift = 0;
    cell.iconScale = 1;
    cell.iconSpin = 0;
    cell.glowScale = 0.6;
    cell.glowOpacity = 0;
    cell.ring1Scale = 0.5;
    cell.ring1Opacity = 0;
    cell.ring2Scale = 0.5;
    cell.ring2Opacity = 0;
    cell.shineX = -140;
    // 顶部横幅初值
    this.banner.icon = cell.icon;
    this.banner.title = '成就解锁';
    this.banner.subtitle = `${cell.name} · ${cell.desc}`;
    this.banner.offsetY = -160;
    this.banner.opacity = 0;
    this.banner.scale = 0.92;
    this.banner.shimmerX = -220;
    hilog.info(DOMAIN, TAG, 'celebration start: %{public}s', id);

    setTimeout(() => {
      const ui: UIContext = this.getUIContext();
      // ① 卡片弹起一下
      ui.animateTo({ duration: 260, curve: curves.springMotion(0.4, 0.7) }, () => {
        cell.cardScale = 1.06;
      });
      // 顶部横幅滑入 + 流光扫过
      ui.animateTo({ duration: 520, delay: 120, curve: curves.springMotion(0.45, 0.72) }, () => {
        this.banner.offsetY = 0;
        this.banner.opacity = 1;
        this.banner.scale = 1;
      });
      ui.animateTo({ duration: 900, delay: 560, curve: Curve.EaseInOut }, () => {
        this.banner.shimmerX = 360;
      });
      // ② 勋章升起 + 放大 + 绕 Y 轴转两圈
      ui.animateTo({ duration: 460, delay: 200, curve: curves.springMotion(0.45, 0.68) }, () => {
        cell.iconLift = -12;
        cell.iconScale = 1.8;
      });
      ui.animateTo({ duration: 900, delay: 200, curve: Curve.Linear }, () => {
        cell.iconSpin = 720;
      });
      // ③ 光晕爆发 + 两圈光环依次扩散
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
      // ④ 带弹性落回原位
      ui.animateTo({ duration: 500, delay: 1040, curve: curves.springMotion(0.4, 0.58) }, () => {
        cell.iconLift = 0;
        cell.iconScale = 1.0;
      });
      ui.animateTo({ duration: 380, delay: 1040, curve: curves.springMotion(0.4, 0.6) }, () => {
        cell.cardScale = 1.0;
      });
      // ⑤ 扫光划过卡片 + 光晕收尾
      ui.animateTo({ duration: 700, delay: 1120, curve: Curve.EaseOut }, () => {
        cell.shineX = 150;
      });
      ui.animateTo({ duration: 600, delay: 1280, curve: Curve.EaseInOut }, () => {
        cell.glowOpacity = 0;
      });
      // 横幅收回
      ui.animateTo({ duration: 420, delay: 2560, curve: Curve.EaseIn }, () => {
        this.banner.offsetY = -160;
        this.banner.opacity = 0;
      });
    }, 60);

    // 收尾：卡片与横幅都回到常态
    setTimeout(() => {
      this.finishCelebration(id);
    }, 3100);
  }

  private finishCelebration(id: string): void {
    const cell: BadgeCell | undefined = this.cellById.get(id);
    if (cell !== undefined) {
      cell.celebrating = false;
      cell.cardScale = 1;
      cell.iconLift = 0;
      cell.iconScale = 1;
      cell.iconSpin = 0;
      cell.glowOpacity = 0;
      cell.ring1Opacity = 0;
      cell.ring2Opacity = 0;
      cell.shineX = -140;
    }
    this.banner.opacity = 0;
    this.banner.offsetY = -160;
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
          // key 用稳定的 id 即可：卡片内容由 BadgeCard 读 @ObservedV2 的 @Trace 字段驱动刷新，
          // 不依赖 ForEach 的 diff（详见 BadgeCell 的注释）
          ForEach(this.cells, (cell: BadgeCell, index: number) => {
            BadgeCard({
              cell: cell,
              index: index,
              entered: this.entered
            })
          }, (cell: BadgeCell) => cell.id)
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

      // 顶部"成就解锁"横幅：固定贴在顶部，靠 translate 滑入滑出，不影响页面布局
      CelebrationBannerView({ banner: this.banner, topInset: this.safeTop })
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
