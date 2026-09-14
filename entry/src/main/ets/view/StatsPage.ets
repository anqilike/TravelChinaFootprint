import { AchievementEngine, AchievementItem } from '../viewmodel/AchievementEngine';
import { FootprintListener, footprintStore } from '../viewmodel/FootprintStore';
import { BadgeCell } from '../viewmodel/BadgeCell';
import { BadgeCard } from './BadgeCard';
import { CelebrationParticle } from '../viewmodel/CelebrationParticle';
import { CelebrationParticleView } from './CelebrationParticleView';
import { HeroBadge } from '../viewmodel/HeroBadge';
import { HeroBadgeView } from './HeroBadgeView';
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
  /** 庆祝浮层：粒子（18 颗，散开 → 汇聚 → 星芒） */
  @Local particles: CelebrationParticle[] = [];
  /** 屏幕中心那枚"聚合出来的大勋章"（可观察模型，动画由它自己驱动） */
  @Local hero: HeroBadge = new HeroBadge();
  /** 根容器尺寸，用来算"屏幕中心" */
  private rootWidth: number = 0;
  private rootHeight: number = 0;
  /** 根容器在窗口坐标系里的左上角，用来把图标位置换算成浮层坐标 */
  private rootGlobalX: number = 0;
  private rootGlobalY: number = 0;
  /** 每枚徽章图标的中心（窗口坐标系），由 BadgeCard 上报 */
  private iconAreas: Map<string, number[]> = new Map<string, number[]>();
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
    this.ensureParticles();
    this.playEnter();
    this.detectNewlyUnlocked();
    footprintStore.subscribe(this.footprintListener);
  }

  /** 创建庆祝用的 18 颗粒子（只建一次，之后复用同一批对象） */
  private ensureParticles(): void {
    if (this.particles.length > 0) {
      return;
    }
    const list: CelebrationParticle[] = [];
    // 48 颗：徽章"分解"得足够碎，聚拢时才有成团的体积感
    for (let i = 0; i < 48; i++) {
      const size: number = i % 7 === 0 ? 9 : (i % 3 === 0 ? 6 : 4);
      const color: string = i % 5 === 0 ? '#FFF6D5' : (i % 3 === 0 ? '#FFD97D' : '#F5C542');
      list.push(new CelebrationParticle(size, color));
    }
    this.particles = list;
  }

  /** BadgeCard 上报图标位置：存下中心点（窗口坐标），庆祝时用来算起点与终点 */
  private onIconArea = (id: string, x: number, y: number, w: number, h: number): void => {
    this.iconAreas.set(id, [x + w / 2, y + h / 2]);
  };

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
   * 单枚徽章的点亮庆祝动画（约 2.6 秒）：
   *
   *  ① 散开（0~0.42s）  —— 卡片里的徽章隐去，18 颗粒子从它的位置向外炸开；
   *  ② 汇聚（0.42~0.94s）—— 粒子拖着金光飞向**屏幕中心**并收拢；
   *  ③ 点亮（0.9s~）    —— 中心炸出一枚大勋章，光晕扩散 + 光环呼吸，闪两次；
   *  ④ 星芒（1.5s~）    —— 粒子再次向外飞散，像光芒迸射后消散；
   *  ⑤ 归位（1.95~2.5s）—— 大勋章缩小飞回它原来的卡片位置，随后卡片里的徽章恢复显示。
   *
   * 时间轴全部用 `UIContext.animateTo` 的 delay 排布（官方《使用动画》的显式动画），
   * 同一条属性上的相邻动画首尾相接，靠 delay 错开而不是嵌套回调，读起来更直观。
   */
  private playUnlockAnimation(id: string): void {
    const cell: BadgeCell | undefined = this.cellById.get(id);
    if (cell === undefined) {
      return;
    }
    // 起点：徽章图标中心（窗口坐标 → 浮层坐标）；终点：屏幕中心偏上一点（避开底部页签栏）
    const area: number[] | undefined = this.iconAreas.get(id);
    const originX: number = area === undefined ? this.rootWidth / 2 : area[0] - this.rootGlobalX;
    const originY: number = area === undefined ? this.rootHeight / 2 : area[1] - this.rootGlobalY;
    const centerX: number = this.rootWidth / 2;
    const centerY: number = this.rootHeight / 2 - 48;

    cell.celebrating = true;
    cell.shineX = -140;
    this.hero.icon = cell.icon;
    this.hero.x = originX;
    this.hero.y = originY;
    this.hero.size = 30;
    this.hero.opacity = 0;
    this.hero.glowScale = 0.4;
    this.hero.glowOpacity = 0;
    for (const p of this.particles) {
      p.x = originX;
      p.y = originY;
      p.opacity = 0;
      p.scale = 1;
    }
    hilog.info(DOMAIN, TAG, 'celebration start: %{public}s', id);

    setTimeout(() => {
      const ui: UIContext = this.getUIContext();
      const count: number = this.particles.length;
      for (let i = 0; i < count; i++) {
        const p: CelebrationParticle = this.particles[i];
        const angle: number = (i / count) * Math.PI * 2 + (i % 3) * 0.35;
        const scatterDist: number = 56 + (i % 8) * 20;
        // ① 散开
        ui.animateTo({ duration: 380, delay: i * 8, curve: Curve.EaseOut }, () => {
          p.x = originX + Math.cos(angle) * scatterDist;
          p.y = originY + Math.sin(angle) * scatterDist;
          p.opacity = 1;
          p.scale = 1.1;
        });
        // ② 汇聚到屏幕中心
        ui.animateTo({ duration: 520, delay: 400 + i * 8, curve: Curve.EaseInOut }, () => {
          p.x = centerX + ((i % 5) - 2) * 6;
          p.y = centerY + ((i % 4) - 1.5) * 6;
          p.opacity = 0.3;
          p.scale = 0.7;
        });
        // ④ 星芒：再次向外飞散并消散
        ui.animateTo({ duration: 460, delay: 1620 + i * 10, curve: Curve.EaseOut }, () => {
          p.x = centerX + Math.cos(angle) * (120 + (i % 6) * 24);
          p.y = centerY + Math.sin(angle) * (120 + (i % 6) * 24);
          p.opacity = 0;
          p.scale = 0.4;
        });
      }
      // ③ 大勋章在中心点亮：从小放大到 150vp
      ui.animateTo({ duration: 460, delay: 960, curve: curves.springMotion(0.45, 0.62) }, () => {
        this.hero.opacity = 1;
        this.hero.size = 150;
      });
      // 光晕爆发
      ui.animateTo({ duration: 700, delay: 960, curve: Curve.EaseOut }, () => {
        this.hero.glowOpacity = 0.95;
        this.hero.glowScale = 1.5;
      });
      // 闪闪发光：光晕呼吸两次
      ui.animateTo({ duration: 300, delay: 1680, curve: Curve.EaseInOut }, () => {
        this.hero.glowOpacity = 0.3;
        this.hero.glowScale = 1.15;
      });
      ui.animateTo({ duration: 300, delay: 1980, curve: Curve.EaseInOut }, () => {
        this.hero.glowOpacity = 0.9;
        this.hero.glowScale = 1.4;
      });
      ui.animateTo({ duration: 320, delay: 2300, curve: Curve.EaseInOut }, () => {
        this.hero.glowOpacity = 0;
        this.hero.glowScale = 1.0;
      });
      // ⑤ 逐渐缩小并飞回原来的卡片位置（终态尺寸 = 卡片里那枚徽章的大小）
      ui.animateTo({ duration: 560, delay: 2380, curve: curves.springMotion(0.42, 0.82) }, () => {
        this.hero.x = originX;
        this.hero.y = originY;
        this.hero.size = 50;
        this.hero.opacity = 0.95;
      });
      // 卡片扫光
      ui.animateTo({ duration: 700, delay: 2380, curve: Curve.EaseOut }, () => {
        cell.shineX = 150;
      });
    }, 40);

    // 收尾：隐藏浮层、恢复卡片里的徽章
    setTimeout(() => {
      this.finishCelebration(id);
    }, 3000);
  }

  private finishCelebration(id: string): void {
    const cell: BadgeCell | undefined = this.cellById.get(id);
    if (cell !== undefined) {
      cell.celebrating = false;
      cell.shineX = -140;
    }
    this.hero.opacity = 0;
    for (const p of this.particles) {
      p.opacity = 0;
    }
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
              entered: this.entered,
              onIconArea: this.onIconArea
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

      // 成就庆祝浮层：粒子散开 → 屏幕中心重组 → 闪耀 → 飞回原位
      if (this.celebratingId.length > 0) {
        this.celebrationStage()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.bg)
    // 记录根容器尺寸与窗口位置：浮层要按它把"图标的窗口坐标"换算成浮层坐标
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.rootWidth = Number(newArea.width);
      this.rootHeight = Number(newArea.height);
      this.rootGlobalX = Number(newArea.globalPosition.x);
      this.rootGlobalY = Number(newArea.globalPosition.y);
    })
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 14 })
    .animation({ duration: Motion.normal + 80, curve: curves.springMotion(0.42, 0.9) })
  }

  /**
   * 庆祝浮层：整屏铺开、不拦截触摸。
   * 48 颗粒子 + 中心的大勋章，全部由 @ObservedV2 的 @Trace 状态驱动。
   */
  @Builder
  celebrationStage() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.particles, (p: CelebrationParticle, index: number) => {
        CelebrationParticleView({ dot: p })
      }, (p: CelebrationParticle, index: number) => `particle_${index}`)

      // 中心大勋章：由 HeroBadge 模型驱动，出现时放大、归位时缩回卡片大小
      HeroBadgeView({ hero: this.hero })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
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
