import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import uiMaterial from '@ohos.arkui.uiMaterial';
import { curves } from '@kit.ArkUI';
import { DatabaseHelper } from '../repository/DatabaseHelper';
import { footprintStore } from '../viewmodel/FootprintStore';
import { AccountService } from '../service/AccountService';
import { Dimens, Motion, Palette } from '../common/Theme';
import { MaterialKit } from '../common/MaterialKit';
import { WindowService } from '../common/WindowService';
import { PrivacyConsent } from '../common/PrivacyConsent';
import { MapPage } from '../view/MapPage';
import { CityListPage } from '../view/CityListPage';
import { StatsPage } from '../view/StatsPage';
import { SettingsPage } from '../view/SettingsPage';
import { PrivacyPolicyView } from '../view/PrivacyPolicy';

const DOMAIN: number = 0x0000;
const TAG: string = 'Index';

/**
 * 底部悬浮页签栏样式。
 *
 * 为什么用 AttributeModifier 而不是直接写在 Tabs 的链式调用里：
 *  1) 沉浸光感的浮起样式 `barFloatingStyle` 是 API 26（鸿蒙 7）才有的属性，
 *     本 App 的 compatibleSdkVersion 是 5.0.0(12)，鸿蒙 6 及更早的设备上没有这个方法。
 *     放在这里可以用 try/catch 兜住"方法不存在"的情况，退回旧版"整条页签栏 + 真模糊"。
 *  2) `barBottomMargin` 要等窗口避让区测量完才知道（手势条高度因机型而异），
 *     用属性修饰器可以在测完之后重新 new 一个，让 ArkUI 重新应用一次样式。
 *
 * 官方《组件适配沉浸光感》给出的三个硬性条件（缺一不可）：
 *   barOverlap(true) + vertical(false) + barPosition(BarPosition.End)
 * 只有三者同时满足，`systemMaterial` 才会真的被系统渲染出来。
 */
class FloatingTabBarModifier implements AttributeModifier<TabsAttribute> {
  private bottomMargin: number = 12;
  private material: uiMaterial.ImmersiveMaterial | undefined = undefined;

  constructor(bottomMargin: number, material: uiMaterial.ImmersiveMaterial | undefined) {
    this.bottomMargin = bottomMargin;
    this.material = material;
  }

  applyNormalAttribute(instance: TabsAttribute): void {
    try {
      instance.barFloatingStyle({
        // 左右留 16vp，页签栏成为一条悬浮胶囊（宽度 = 屏宽 - 32）
        barSideMargin: 16,
        // 距容器底部：手势条高度 + 8vp 呼吸位
        barBottomMargin: this.bottomMargin,
        // 官方设计规范：底部悬浮 = THIN 材质 + 渐变颜色蒙层。
        // 蒙层从底部往上 140vp 由深到透明，负责"压住"地图，材质负责通透和折射。
        maskHeight: 140,
        maskColor: '#47070B14',
        systemMaterial: this.material
      });
    } catch (err) {
      // 鸿蒙 6 及更早：没有 barFloatingStyle（API 26 新增），
      // 退回"页签栏铺满 + 系统组件级模糊"，视觉上仍是深色毛玻璃。
      hilog.warn(DOMAIN, TAG, 'barFloatingStyle unavailable, fallback: %{public}s', JSON.stringify(err));
      instance.barBackgroundColor('#B80C1320');
      instance.barBackgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, { colorMode: ThemeColorMode.DARK });
    }
  }
}

/**
 * 应用主框架：底部 4 个页签（地图 / 清单 / 统计 / 我的）。
 *
 * 鸿蒙 7 适配要点：
 *  1) 底部导航是**系统 Tabs 的悬浮页签栏**（barFloatingStyle + uiMaterial 沉浸光感），
 *     不是自绘导航。原因见 FloatingTabBarModifier 的注释：官方规定只有底部 TabBar
 *     和 Navigation 标题栏这两个位置，普通组件的材质才会被渲染；
 *     自己拿 Button 拼一条导航，系统只会打一条 "Material inactive: out of scope"。
 *  2) 图标用矢量 SVG 交给 BottomTabBarStyle.iconStyle 着色，选中金色、未选中低饱和灰；
 *  3) 页签栏浮在内容之上（barOverlap），底图从玻璃后面透出来被糊掉，
 *     这就是"沉浸光感"里底部悬浮那一档的标准形态。
 */
@Entry
@ComponentV2
struct Index {
  @Local currentIndex: number = 0;
  @Local loading: boolean = true;
  @Local loadError: string = '';
  /** 底部手势条高度（vp），悬浮导航要往上让出这么多，避免被系统手势条压住 */
  @Local safeBottom: number = 0;
  /** 页签栏样式修饰器，窗口避让区测完后重新构造一次 */
  @Local barModifier: AttributeModifier<TabsAttribute> = new FloatingTabBarModifier(12, undefined);
  /** 是否已经读过本机的隐私政策同意状态（读完之前不渲染主界面，避免闪一下） */
  @Local consentChecked: boolean = false;
  /** 是否已同意隐私政策；未同意时主界面之上盖一层同意弹层 */
  @Local consentGiven: boolean = false;
  private tabsController: TabsController = new TabsController();

  aboutToAppear(): void {
    // 再试一次：Ability.onCreate 阶段窗口还没就绪，材质能力探测可能返回 false，
    // 这里（UI 上下文已可用）重试，成功后底部页签栏的材质才会真的渲染出来。
    MaterialKit.init();
    this.start();
  }

  /**
   * 启动顺序：先读隐私政策同意状态，再初始化数据。
   * 官方与华为应用市场审核都要求"征得同意后再收集个人信息"，
   * 所以这一步必须排在数据库、定位、账号之前。
   */
  private async start(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await PrivacyConsent.init(context);
      this.consentGiven = PrivacyConsent.isAgreed();
    } catch (err) {
      this.consentGiven = false;
      hilog.warn(DOMAIN, TAG, 'consent check failed: %{public}s', JSON.stringify(err));
    }
    this.consentChecked = true;
    await this.bootstrap();
  }

  /** 启动引导：打开数据库 → 加载城市字典 → 读取本地足迹 */
  private async bootstrap(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await DatabaseHelper.init(context);
      await footprintStore.init(context);
      await AccountService.init(context);
      await WindowService.measure(context);
      this.safeBottom = WindowService.safeBottom;
      // 材质对象要等 MaterialKit.init() 之后再取；这里也量到了手势条高度，重新构造一次修饰器
      this.barModifier = new FloatingTabBarModifier(8 + this.safeBottom, MaterialKit.floatingTabBar());
      this.loading = false;
      hilog.info(DOMAIN, TAG, 'bootstrap done: safeBottom=%{public}d material=%{public}s',
        this.safeBottom, MaterialKit.diagnostics);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      this.loadError = `初始化失败：${error.message}`;
      this.loading = false;
      hilog.error(DOMAIN, TAG, 'bootstrap failed: %{public}s', JSON.stringify(err));
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (!this.consentChecked || this.loading) {
        this.splash('正在准备地图数据…', true)
      } else if (this.loadError.length > 0) {
        this.splash(this.loadError, false)
      } else {
        Stack() {
          // 背景层：极夜渐变 + 两处柔光。
          // 它有两个作用：1) 给非地图页一个不空的底；2) 让上面的沉浸光感材质"有东西可折射"，
          // 否则纯色背景上的玻璃材质看起来和普通半透明没区别。
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 170,
              colors: [['#121C31', 0.0], ['#070B14', 0.55], ['#0A1120', 1.0]]
            })
            // 背景层要铺到状态栏和导航条底下（官方"组件安全区方案"：背景类元素用 expandSafeArea 延伸绘制）
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          Column()
            .width(300)
            .height(300)
            .borderRadius(150)
            .backgroundColor('#1FF5C542')
            .blur(90)
            .position({ x: -110, y: -70 })

          Column()
            .width(340)
            .height(340)
            .borderRadius(170)
            .backgroundColor('#1422D3EE')
            .blur(100)
            .position({ x: 180, y: 420 })

          // 页签栏的渐变蒙层、圆角、材质全部由 barFloatingStyle 负责；
          // 这里不再自己叠"底部渐变遮罩"——自绘的那层会画在页签栏之上，把材质糊住。
          Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
            TabContent() {
              MapPage()
            }
            .tabBar(this.navTab($r('app.media.ic_nav_map'), '地图'))

            TabContent() {
              CityListPage()
            }
            .tabBar(this.navTab($r('app.media.ic_nav_list'), '清单'))

            TabContent() {
              // 传入"当前是否停留在统计页"：成就的新解锁检测要在每次进入时做一遍
              StatsPage({ active: this.currentIndex === 2 })
            }
            .tabBar(this.navTab($r('app.media.ic_nav_chart'), '统计'))

            TabContent() {
              SettingsPage()
            }
            .tabBar(this.navTab($r('app.media.ic_nav_user'), '我的'))
          }
          // vertical=false + barPosition=End：页签栏在容器底部（沉浸光感的必要条件之一）
          .vertical(false)
          // barOverlap=true：页签栏浮在内容之上，而不是把内容顶上去（必要条件之二）
          .barOverlap(true)
          // 切换动画三件套（官方《使用动画》+ Tabs 参考）：
          //  1) CONTENT_FIRST_WITH_JUMP：先把目标页加载好，再"无动画跳到目标页附近、最后一段做动画"。
          //     这是关键的体验修复——默认动画会按页签序号差横向滑动，
          //     从"地图"(0) 直接切到"我的"(3) 时内容要从三屏外飞进来，看着很生硬；
          //     开了这个模式后，长距离跳转只播最后一段，观感和其他切换一致。
          //  2) 用弹簧曲线代替默认的线性缓动，收尾有自然的"落定感"。
          //  3) 时长略长于默认，给弹簧留出回弹空间。
          .animationMode(AnimationMode.CONTENT_FIRST_WITH_JUMP)
          .animationDuration(Motion.pageSwitch)
          .animationCurve(curves.springMotion(0.42, 0.9))
          // 悬浮样式 + 沉浸光感材质（必要条件之三，见 FloatingTabBarModifier）
          .attributeModifier(this.barModifier)
          .width('100%')
          .height('100%')
          .onChange((index: number) => {
            this.currentIndex = index;
          })
        }
        .width('100%')
        .height('100%')

        // 首次启动的隐私政策同意弹层：盖在主界面之上，不同意就退出应用。
        // 说明：这是国内应用市场审核的硬性要求（显著提示 + 征得同意）。
        if (!this.consentGiven) {
          this.privacyGate()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.bg)
  }

  @Builder
  privacyGate() {
    Column() {
      Column({ space: 12 }) {
        Text('欢迎使用「走遍中国」')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.text)
          .width('100%')
        Text('在使用前，请你阅读并同意我们的隐私政策。我们坚持最小必要原则：'
          + '不注册也能用全部核心功能，位置与账号都由你主动触发。')
          .fontSize(12)
          .lineHeight(19)
          .fontColor(Palette.textDim)
          .width('100%')

        Column() {
          PrivacyPolicyView()
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius(14)
        .backgroundColor(Palette.surfaceSoft)
        .border({ width: 0.5, color: Palette.line })

        Row({ space: 12 }) {
          Button('不同意并退出')
            .layoutWeight(1)
            .height(44)
            .borderRadius(22)
            .fontSize(14)
            .backgroundColor(Palette.surface)
            .fontColor(Palette.textDim)
            .onClick(() => {
              this.exitApp();
            })
          Button('同意并继续')
            .layoutWeight(1)
            .height(44)
            .borderRadius(22)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(Palette.gold)
            .fontColor('#1A1405')
            .onClick(() => {
              this.acceptPrivacy();
            })
        }
        .width('100%')
      }
      .width('100%')
      .height('78%')
      .padding(20)
      .borderRadius(24)
      .backgroundColor(Palette.surface)
      .border({ width: 0.5, color: Palette.line })
      .shadow({ radius: 30, color: '#B3000000', offsetX: 0, offsetY: 12 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#D9070B14')
  }

  private async acceptPrivacy(): Promise<void> {
    await PrivacyConsent.agree();
    this.consentGiven = true;
  }

  /** 不同意：按审核要求，不提供任何服务并退出应用 */
  private exitApp(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.terminateSelf().catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'terminateSelf failed: %{public}s', JSON.stringify(err));
    });
  }

  @Builder
  splash(message: string, busy: boolean) {
    Column() {
      if (busy) {
        LoadingProgress()
          .width(44)
          .height(44)
          .color(Palette.gold)
        Text(message)
          .fontSize(13)
          .fontColor(Palette.textDim)
          .margin({ top: 14 })
      } else {
        Text(message)
          .fontSize(13)
          .fontColor(Palette.textDim)
          .textAlign(TextAlign.Center)
        Button('重试')
          .width(128)
          .height(42)
          .borderRadius(21)
          .backgroundColor(Palette.gold)
          .fontColor('#1A1405')
          .fontSize(14)
          .margin({ top: 18 })
          .onClick(() => {
            this.loading = true;
            this.loadError = '';
            this.bootstrap();
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  /**
   * 页签样式：图标 + 文字，选中金色、未选中灰。
   *
   * 高亮胶囊、按压反馈、图标与文字的排布全部交给系统绘制
   * （官方《组件适配沉浸光感》里"底部页签"就是 BottomTabBarStyle 这一条路径），
   * 我们只提供图标资源、文案和配色。
   */
  private navTab(icon: Resource, label: string): BottomTabBarStyle {
    return new BottomTabBarStyle(icon, label)
      .labelStyle({
        selectedColor: Palette.goldLight,
        // 玻璃材质上的文字必须是纯白，灰色在浅色底图透上来时会发闷、看不清
        unselectedColor: Palette.text,
        font: { size: 10, weight: FontWeight.Medium }
      })
      .iconStyle({
        selectedColor: Palette.gold,
        unselectedColor: Palette.text
      });
  }
}
