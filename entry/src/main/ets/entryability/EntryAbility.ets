import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { MaterialKit } from '../common/MaterialKit';

const DOMAIN: number = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 本产品以暗色为默认主题（见设计规范 3.4）
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    // 鸿蒙 7 的沉浸光感材质（低版本设备会自动跳过）
    MaterialKit.init();
    hilog.info(DOMAIN, 'TravelChinaFootprint', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'TravelChinaFootprint', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'TravelChinaFootprint', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'TravelChinaFootprint', '%{public}s', 'Succeeded in loading the content.');
      this.enableImmersiveWindow(windowStage);
    });
  }

  /**
   * 沉浸式窗口：让地图铺满到状态栏底下，同时把状态栏 / 导航栏的前景色设为白色，
   * 避免出现"黑底黑字"。低版本或异常情况只记录日志，不影响主流程。
   */
  private enableImmersiveWindow(windowStage: window.WindowStage): void {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, 'TravelChinaFootprint', 'setWindowLayoutFullScreen failed: %{public}s',
          JSON.stringify(err));
      });
      mainWindow.setWindowSystemBarProperties({
        statusBarContentColor: '#FFFFFF',
        navigationBarContentColor: '#FFFFFF'
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, 'TravelChinaFootprint', 'setWindowSystemBarProperties failed: %{public}s',
          JSON.stringify(err));
      });
    } catch (err) {
      hilog.warn(DOMAIN, 'TravelChinaFootprint', 'immersive window unavailable: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'TravelChinaFootprint', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'TravelChinaFootprint', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'TravelChinaFootprint', '%{public}s', 'Ability onBackground');
  }
}
