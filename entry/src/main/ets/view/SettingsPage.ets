import { common } from '@kit.AbilityKit';
import { curves, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
import { CityRepository } from '../repository/CityRepository';
import { VisitRepository } from '../repository/VisitRepository';
import { VisitRecord } from '../model/VisitRecord';
import { ExportService } from '../service/ExportService';
import { AccountService } from '../service/AccountService';
import { CloudSyncService } from '../service/CloudSyncService';
import { footprintStore } from '../viewmodel/FootprintStore';
import { Dimens, Motion, Palette } from '../common/Theme';
import { MaterialKit } from '../common/MaterialKit';
import { WindowService } from '../common/WindowService';
import { deviceInfo } from '@kit.BasicServicesKit';
import { PrivacyPolicyView } from './PrivacyPolicy';
import { AchievementEngine } from '../viewmodel/AchievementEngine';
import { AchievementEffects, EffectInfo } from '../viewmodel/AchievementEffects';
import { BadgeCell } from '../viewmodel/BadgeCell';
import { BadgeCard } from './BadgeCard';
import { LitColors, LitColorPreset } from '../viewmodel/LitColors';

const DOMAIN: number = 0x0000;
const TAG: string = 'SettingsPage';

/**
 * 我的 / 设置（P-10）。
 * 首版提供：数据导出、显示选项、地图与数据来源说明（含地图合规信息）。
 */
@ComponentV2
export struct SettingsPage {
  @Local largeFont: boolean = false;
  @Local colorBlindSafe: boolean = false;
  @Local exporting: boolean = false;
  /** 沉浸式布局下避开状态栏（vp） */
  @Local safeTop: number = 0;
  /** 底部导航条高度（vp），滚动内容要额外让出这么多 */
  @Local safeBottom: number = 0;
  /** 华为账号登录态 */
  @Local loggedIn: boolean = false;
  @Local accountShortId: string = '';
  /** 云同步状态 */
  @Local syncing: boolean = false;
  @Local syncStatus: string = '';
  @Local lastSyncText: string = '尚未同步';
  /** 隐私政策阅读弹层 */
  @Local policyShown: boolean = false;
  /** 清除本机数据的二次确认 */
  @Local clearing: boolean = false;
  /** 入场动效标记 */
  @Local entered: boolean = false;
  /** 当前选中的徽章点亮动画编号 */
  @Local effectIndex: number = 0;
  /** 当前选中的点亮配色编号 */
  @Local litColorIndex: number = 0;
  /** 试播用的演示徽章（与统计页里的徽章共用同一套渲染与动画） */
  private demoCell: BadgeCell = new BadgeCell('demo', '演示徽章', '点亮时的动画效果', '🏅');

  /** 华为账号一键登录按钮参数（Account Kit 官方组件） */
  private loginParams: loginComponentManager.LoginWithHuaweiIDButtonParams = {
    style: loginComponentManager.Style.BUTTON_RED,
    loginType: loginComponentManager.LoginType.ID,
    supportDarkMode: true,
    borderRadius: 22
  };

  private loginController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .setAgreementStatus(loginComponentManager.AgreementStatus.ACCEPTED)
      .onClickLoginWithHuaweiIDButton((err, credential) => {
        if (err !== undefined && err !== null) {
          this.syncStatus = `登录未完成（${err.code}）`;
          hilog.warn(DOMAIN, TAG, 'huawei id login failed: %{public}s', JSON.stringify(err));
          return;
        }
        AccountService.signIn(credential.openID, credential.unionID).then(() => {
          this.loggedIn = AccountService.isLoggedIn();
          this.accountShortId = AccountService.shortId();
          this.syncStatus = '';
          promptAction.showToast({ message: '已登录华为账号，可以云同步了' });
        });
      });

  aboutToAppear(): void {
    this.safeTop = WindowService.safeTop;
    this.safeBottom = WindowService.safeBottom;
    this.loggedIn = AccountService.isLoggedIn();
    this.accountShortId = AccountService.shortId();
    this.playEnter();
    this.demoCell.unlocked = true;
    this.demoCell.progress = 1;
    this.demoCell.target = 1;
    this.loadEffectIndex();
    this.loadLitColor();
  }

  private async loadEffectIndex(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.effectIndex = await AchievementEngine.getEffectIndex(context);
    } catch (err) {
      this.effectIndex = 0;
    }
  }

  private async loadLitColor(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.litColorIndex = await AchievementEngine.getLitColorIndex(context);
    } catch (err) {
      this.litColorIndex = 0;
    }
  }

  /** 选中某个配色并落盘；回到地图页时会自动换色 */
  private pickLitColor(index: number): void {
    this.litColorIndex = index;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AchievementEngine.setLitColorIndex(context, index);
  }

  private currentEffect(): EffectInfo {
    return AchievementEffects.info(this.effectIndex);
  }

  /** 换下一个效果并立即试播，方便逐个对比 */
  private nextEffect(): void {
    this.effectIndex = (this.effectIndex + 1) % AchievementEffects.count();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AchievementEngine.setEffectIndex(context, this.effectIndex);
    this.previewEffect();
  }

  /** 在当前效果上重播一遍 */
  private previewEffect(): void {
    const ui: UIContext = this.getUIContext();
    AchievementEffects.play(this.effectIndex, this.demoCell, ui);
    setTimeout(() => {
      this.demoCell.celebrating = false;
      this.demoCell.resetAnimation();
    }, 3300);
  }

  /** 首次进入本页时淡入 + 轻微上浮，让页签切换不再"生硬地换一整屏" */
  private playEnter(): void {
    this.entered = false;
    setTimeout(() => {
      this.entered = true;
    }, 30);
  }

  /** 退出登录（只清登录态，不动本地足迹） */
  private async doSignOut(): Promise<void> {
    await AccountService.signOut();
    this.loggedIn = false;
    this.accountShortId = '';
    this.syncStatus = '';
    promptAction.showToast({ message: '已退出华为账号（本地足迹保留）' });
  }

  /**
   * 云同步：先推本地 → 再拉云端 → 按 updatedAt 取新合并回本地。
   * 未开通云同步时给出友好提示（AGC 细节只进日志），不影响本地使用。
   */
  private async doSync(): Promise<void> {
    if (this.syncing) {
      return;
    }
    if (!AccountService.isLoggedIn()) {
      this.syncStatus = '请先登录华为账号';
      return;
    }
    this.syncing = true;
    this.syncStatus = '正在同步…';
    try {
      const openId: string = AccountService.getOpenId();
      const local: VisitRecord[] = await VisitRepository.loadAllRecords();
      const pushed: number = await CloudSyncService.push(openId, local);
      const cloud: VisitRecord[] = await CloudSyncService.pull(openId);
      const written: number = await VisitRepository.mergeFromCloud(cloud);
      await footprintStore.refreshStats();
      this.syncStatus = `同步完成：上传 ${pushed} 条，拉取 ${cloud.length} 条，合并 ${written} 条`;
      this.lastSyncText = `上次同步：${new Date().toLocaleString()}`;
    } catch (err) {
      const error: Error = err as Error;
      this.syncStatus = error.message;
      hilog.error(DOMAIN, TAG, 'cloud sync failed: %{public}s', JSON.stringify(err));
    } finally {
      this.syncing = false;
    }
  }

  private async doExport(): Promise<void> {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const path: string = await ExportService.exportJson(context, footprintStore.visitedCodes);
      const fileName: string = path.substring(path.lastIndexOf('/') + 1);
      promptAction.showToast({ message: `已导出 ${footprintStore.visitedCount} 条记录：${fileName}` });
      hilog.info(DOMAIN, TAG, 'export ok: %{public}s', path);
    } catch (err) {
      promptAction.showToast({ message: '导出失败，请重试' });
      hilog.error(DOMAIN, TAG, 'export failed');
    } finally {
      this.exporting = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
        Text('我的')
          .fontSize(22)
          .fontColor(Palette.text)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .margin({ bottom: 14 })

        // 华为账号：未登录显示官方一键登录按钮，登录后显示账号标识与退出入口
        Column() {
          Row() {
            Column() {
              Text(this.loggedIn ? '华' : '未')
                .fontSize(17)
                .fontColor(this.loggedIn ? Palette.gold : Palette.textDim)
                .fontWeight(FontWeight.Medium)
            }
            .width(44)
            .height(44)
            .borderRadius(14)
            .backgroundColor(this.loggedIn ? '#33F5C542' : '#1AFFFFFF')
            .justifyContent(FlexAlign.Center)
            .margin({ right: 14 })

            Column() {
              Text(this.loggedIn ? '华为账号已登录' : '登录华为账号')
                .fontSize(15)
                .fontColor(Palette.text)
              Text(this.loggedIn
                ? `账号标识 ${this.accountShortId} · 已连接华为账号`
                : '登录后即可使用云同步（即将开放）；不登录也能正常使用')
                .fontSize(11)
                .fontColor(Palette.textDim)
                .margin({ top: 4 })
                .maxLines(2)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')

          if (!this.loggedIn) {
            // Account Kit 官方一键登录按钮（自带协议勾选与华为账号授权流程）
            LoginWithHuaweiIDButton({ params: this.loginParams, controller: this.loginController })
              .width('100%')
              .height(44)
              .margin({ top: 14 })
          } else {
            Text('退出登录')
              .fontSize(13)
              .fontColor(Palette.textDim)
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ top: 10, bottom: 10 })
              .borderRadius(18)
              .backgroundColor('#1AFFFFFF')
              .margin({ top: 14 })
              .onClick(() => {
                this.doSignOut();
              })
          }
        }
        .width('100%')
        .padding(16)
        .borderRadius(Dimens.cardRadius)
        .backgroundColor('#2E0A1020')
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, { colorMode: ThemeColorMode.DARK })
        .border({ width: 0.5, color: '#1FFFFFFF' })

        // 数据
        Text('数据')
          .fontSize(13)
          .fontColor(Palette.textDim)
          .width('100%')
          .margin({ top: 22, bottom: 8 })

        Column() {
          // 云同步（需要先登录华为账号）
          Row() {
            Column() {
              Text('云同步')
                .fontSize(15)
                .fontColor(Palette.text)
              Text(this.syncStatus.length > 0 ? this.syncStatus : this.lastSyncText)
                .fontSize(11)
                .fontColor(this.syncStatus.indexOf('失败') >= 0 ? Palette.danger : Palette.textDim)
                .margin({ top: 4 })
                .maxLines(2)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text(this.syncing ? '同步中…' : '立即同步')
              .fontSize(13)
              .fontColor(this.loggedIn && !this.syncing ? Palette.gold : Palette.textDim)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(999)
              .backgroundColor('#1AFFFFFF')
              .onClick(() => {
                this.doSync();
              })
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })

          Divider().color(Palette.line)

          Row() {
            Column() {
              Text('导出我的足迹')
                .fontSize(15)
                .fontColor(Palette.text)
              Text('导出为 JSON 文件（含已点亮的城市清单）')
                .fontSize(11)
                .fontColor(Palette.textDim)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('导出')
              .fontSize(13)
              .fontColor(Palette.gold)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(999)
              .backgroundColor(Palette.surfaceSoft)
              .onClick(() => {
                this.doExport();
              })
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })

          Divider().color(Palette.line)

          // 清除本机数据：隐私合规要求"用户能删掉自己的数据"，也给换机/重来一个干净入口
          Row() {
            Column() {
              Text('清除本机足迹数据')
                .fontSize(15)
                .fontColor(Palette.text)
              Text('删除本机全部点亮记录（云端数据需另行处理）')
                .fontSize(11)
                .fontColor(Palette.textDim)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(this.clearing ? '清除中…' : '清除')
              .fontSize(13)
              .fontColor(Palette.danger)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(999)
              .backgroundColor(Palette.surfaceSoft)
              .onClick(() => {
                this.confirmClear();
              })
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })

          Divider().color(Palette.line)

          this.switchRow('大字号模式', this.largeFont, (value: boolean) => {
            this.largeFont = value;
          })

          Divider().color(Palette.line)

          this.switchRow('色盲友好模式（增加描边辅助）', this.colorBlindSafe, (value: boolean) => {
            this.colorBlindSafe = value;
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .borderRadius(Dimens.cardRadius)
        .backgroundColor('#26070B14')
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, { colorMode: ThemeColorMode.DARK })
        .border({ width: 0.5, color: '#14FFFFFF' })

        // 点亮颜色：8 种配色，点选即换（点名 + 城市名一起换色系）
        Text('点亮颜色')
          .fontSize(13)
          .fontColor(Palette.textDim)
          .width('100%')
          .margin({ top: 22, bottom: 8 })

        Column() {
          Row() {
            Text(`当前：${LitColors.get(this.litColorIndex).name}`)
              .fontSize(15)
              .fontColor(Palette.text)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)
            // 示例文字：用当前配色的"深色版"，就是地图上城市名的颜色
            Text('已点亮')
              .fontSize(13)
              .fontColor(LitColors.get(this.litColorIndex).label)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding({ top: 14, bottom: 10 })

          // 8 个色块：选中的带白色描边
          // 注意 key 里带上"是否选中"：ForEach 只按 key 做 diff，
          // 只用序号的话切换选中态时高亮不会刷新。
          Row({ space: 10 }) {
            ForEach(LitColors.presets(), (preset: LitColorPreset, index: number) => {
              Circle()
                .width(30)
                .height(30)
                .fill(preset.dot)
                .stroke(this.litColorIndex === index ? '#FFFFFFFF' : '#33FFFFFF')
                .strokeWidth(this.litColorIndex === index ? 2.5 : 1)
                .onClick(() => {
                  this.pickLitColor(index);
                })
            }, (preset: LitColorPreset, index: number) =>
              `lit_${index}_${this.litColorIndex === index ? 1 : 0}`)
          }
          .width('100%')
          .padding({ bottom: 12 })

          Text('地图上已点亮城市的圆点用上面的颜色，城市名用同色系的深色版本（保证压在浅色底图上也能看清）。')
            .fontSize(11)
            .fontColor(Palette.textDim)
            .margin({ bottom: 14 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .borderRadius(Dimens.cardRadius)
        .backgroundColor('#26070B14')
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, { colorMode: ThemeColorMode.DARK })
        .border({ width: 0.5, color: '#14FFFFFF' })

        // 成就动画：10 种徽章点亮效果，可逐个切换并当场试播
        Text('成就动画')
          .fontSize(13)
          .fontColor(Palette.textDim)
          .width('100%')
          .margin({ top: 22, bottom: 8 })

        Column() {
          Row() {
            Column({ space: 4 }) {
              Text(`效果 ${this.currentEffect().id + 1} / ${AchievementEffects.count()}　${this.currentEffect().name}`)
                .fontSize(15)
                .fontColor(Palette.text)
                .fontWeight(FontWeight.Medium)
              Text(this.currentEffect().desc)
                .fontSize(11)
                .fontColor(Palette.textDim)
                .maxLines(2)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text('换一个')
              .fontSize(13)
              .fontColor(Palette.gold)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(999)
              .backgroundColor(Palette.surfaceSoft)
              .onClick(() => {
                this.nextEffect();
              })
          }
          .width('100%')
          .padding({ top: 14, bottom: 10 })

          Row() {
            // 试播用的徽章卡片：和统计页用的是同一个组件，所见即所得
            BadgeCard({ cell: this.demoCell, index: 0, entered: true, cardWidth: 132 })
            Column({ space: 8 }) {
              Text('点「重播」可以反复看当前效果；')
                .fontSize(11)
                .fontColor(Palette.textDim)
              Text('切换到统计页解锁新徽章时，用的就是这里选定的效果。')
                .fontSize(11)
                .fontColor(Palette.textDim)
              Button('重播一次')
                .height(34)
                .borderRadius(17)
                .fontSize(13)
                .backgroundColor(Palette.gold)
                .fontColor('#1A1405')
                .onClick(() => {
                  this.previewEffect();
                })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 14, bottom: 10 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .borderRadius(Dimens.cardRadius)
        .backgroundColor('#26070B14')
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, { colorMode: ThemeColorMode.DARK })
        .border({ width: 0.5, color: '#14FFFFFF' })

        // 关于
        Text('关于')
          .fontSize(13)
          .fontColor(Palette.textDim)
          .width('100%')
          .margin({ top: 22, bottom: 8 })

        Column() {
          this.infoRow('地图服务', '华为 Map Kit（@kit.MapKit）')
          Divider().color(Palette.line)
          this.infoRow('地图审图号', '由地图服务提供方在地图上标注（本应用已开启显示）')
          Divider().color(Palette.line)
          this.infoRow('沉浸光感', MaterialKit.isSupported()
            ? `已启用（底部页签栏系统材质 · ${MaterialKit.diagnostics}）`
            : `未启用（${MaterialKit.lastError}）`)
          Divider().color(Palette.line)
          this.infoRow('点亮单元', `市州级行政区 ${CityRepository.total()} 个`)
          Divider().color(Palette.line)
          this.infoRow('城市字典版本', `${CityRepository.dictVersion()}（${CityRepository.dictGeneratedAt()}）`)
          Divider().color(Palette.line)
          this.infoRow('数据来源', '公开行政区划数据（GCJ-02）+ 民政部行政区划代码')
          Divider().color(Palette.line)
          // 隐私政策：应用内必须能直接读到全文（应用市场审核要求）
          Row() {
            Text('隐私政策')
              .fontSize(14)
              .fontColor(Palette.text)
              .layoutWeight(1)
            Text('查看全文')
              .fontSize(12)
              .fontColor(Palette.gold)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .borderRadius(999)
              .backgroundColor(Palette.surfaceSoft)
              .onClick(() => {
                this.policyShown = true;
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          Divider().color(Palette.line)
          this.infoRow('版本', 'v1.0.0（versionCode 1000000）')
          Divider().color(Palette.line)
          this.infoRow('权限说明', '位置（仅前台、按需触发）；网络（地图瓦片）')
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .borderRadius(Dimens.cardRadius)
        .backgroundColor('#26070B14')
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, { colorMode: ThemeColorMode.DARK })
        .border({ width: 0.5, color: '#14FFFFFF' })

          Text('本应用为个人足迹记录工具，不提供地图搜索、导航等互联网地图服务；若后续增加此类功能，将按法规要求完善资质。')
            .fontSize(11)
            .fontColor(Palette.textDim)
            .margin({ top: 16, bottom: Dimens.navSpace + this.safeBottom })
            .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16 + this.safeTop })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)

      // 顶部渐隐遮罩：滚动内容接近状态栏时自动淡出，
      // 避免文字和系统的时间 / 信号图标叠在一起（华为自带联系人就是这个策略）。
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
    .bindSheet(this.policyShown, this.policySheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      backgroundColor: Palette.surface,
      onDisappear: () => {
        this.policyShown = false;
      }
    })
  }

  @Builder
  policySheet() {
    Column() {
      PrivacyPolicyView()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 8 })
    .backgroundColor(Palette.surface)
  }

  /** 清除本机数据：先弹二次确认，避免误触 */
  private confirmClear(): void {
    this.getUIContext().showAlertDialog({
      title: '清除本机全部足迹数据？',
      message: '本机记录的点亮城市、日期与备注都会被删除，操作不可撤销。'
        + '如果你已经登录华为账号并同步过，云端数据不会因此被删除。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '确认清除',
        fontColor: Palette.danger,
        action: () => {
          this.doClear();
        }
      }
    });
  }

  private async doClear(): Promise<void> {
    if (this.clearing) {
      return;
    }
    this.clearing = true;
    try {
      await VisitRepository.clearAll();
      await footprintStore.reload();
      promptAction.showToast({ message: '本机足迹数据已清除' });
      hilog.info(DOMAIN, TAG, 'local footprint data cleared');
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      promptAction.showToast({ message: `清除失败：${error.message}` });
      hilog.error(DOMAIN, TAG, 'clear failed: %{public}s', JSON.stringify(err));
    } finally {
      this.clearing = false;
    }
  }

  @Builder
  switchRow(label: string, checked: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor(Palette.text)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(Palette.gold)
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(Palette.text)
        .layoutWeight(1)
      Text(value)
        .fontSize(12)
        .fontColor(Palette.textDim)
        .textAlign(TextAlign.End)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
  }
}
