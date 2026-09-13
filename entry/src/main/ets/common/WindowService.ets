import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'WindowService';

/**
 * 沉浸式窗口的"安全区"测量。
 *
 * 为什么需要：
 *  App 开启了 setWindowLayoutFullScreen(true)，内容会铺到状态栏 / 手势条底下。
 *  地图、底图这类"背景层"希望铺满（沉浸感），
 *  但顶部信息卡、悬浮按钮必须避开状态栏与手势条，否则会像"压住时间电量"那样难看、也点不到。
 *
 * 用法：EntryAbility 启动后调用 WindowService.measure()，
 * 页面在 aboutToAppear 里读取 WindowService.safeTop / safeBottom（单位 vp）。
 */
export class WindowService {
  /** 状态栏高度（vp），顶部内容需要避开这么多 */
  static safeTop: number = 0;
  /** 底部手势条 / 导航栏高度（vp） */
  static safeBottom: number = 0;

  static async measure(context: common.UIAbilityContext): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(context);
      WindowService.applyAvoidAreas(mainWindow);
      // 按官方《开发应用沉浸式效果》的建议：注册监听，动态获取避让区变化
      // （窗口在全屏/悬浮/分屏间切换、旋转、折叠屏展开折叠时都会回调）
      mainWindow.on('avoidAreaChange', () => {
        WindowService.applyAvoidAreas(mainWindow);
      });
      hilog.info(DOMAIN, TAG, 'safe area top=%{public}d bottom=%{public}d',
        WindowService.safeTop, WindowService.safeBottom);
    } catch (err) {
      // 取不到就退回一组保守值，保证内容不会被状态栏压住
      WindowService.safeTop = 38;
      WindowService.safeBottom = 16;
      hilog.warn(DOMAIN, TAG, 'measure failed, use fallback: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 读取避让区。
   * 顶部用 TYPE_SYSTEM（状态栏）；
   * 底部**必须用 TYPE_NAVIGATION_INDICATOR**（导航条/手势条），
   * 这是官方文档明确给出的取法——TYPE_SYSTEM 的 bottomRect 在手势导航机型上通常是 0，
   * 用它算底部间距会让可交互元素贴到手势条上。
   */
  private static applyAvoidAreas(mainWindow: window.Window): void {
    try {
      const systemArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      WindowService.safeTop = px2vp(systemArea.topRect.height);
    } catch (err) {
      WindowService.safeTop = 38;
    }
    try {
      const navArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      WindowService.safeBottom = px2vp(navArea.bottomRect.height);
    } catch (err) {
      WindowService.safeBottom = 16;
    }
  }
}
