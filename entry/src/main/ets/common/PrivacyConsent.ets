import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'PrivacyConsent';
const STORE_NAME: string = 'privacy_store';
const KEY_AGREED_VERSION: string = 'agreed_version';

/**
 * 当前隐私政策版本。
 * 政策内容有实质修改时把版本号 +1，用户下次启动会被重新询问一次
 * （这是《个人信息保护法》与华为应用市场审核的通行做法）。
 */
export const PRIVACY_VERSION: string = '1.0';

/**
 * 隐私政策同意状态。
 *
 * 为什么单独一个文件：华为应用市场审核明确要求「App 首次运行时应当以显著方式
 * 提示用户阅读隐私政策，并征得用户同意后再收集个人信息」，所以同意状态必须
 * **先于任何数据采集**落盘可读。这里用轻量的 preferences 存，
 * 不依赖业务数据库（数据库初始化本身也要等 UI 起来）。
 */
export class PrivacyConsent {
  private static store: preferences.Preferences | undefined = undefined;
  private static agreed: boolean = false;

  /** 启动时调用一次，把上次的同意状态读回内存 */
  static async init(context: common.UIAbilityContext): Promise<void> {
    if (PrivacyConsent.store !== undefined) {
      return;
    }
    try {
      const options: preferences.Options = { name: STORE_NAME };
      const store: preferences.Preferences = await preferences.getPreferences(context, options);
      PrivacyConsent.store = store;
      const version: string = store.getSync(KEY_AGREED_VERSION, '') as string;
      PrivacyConsent.agreed = version === PRIVACY_VERSION;
      hilog.info(DOMAIN, TAG, 'consent restored: agreed=%{public}d version=%{public}s',
        PrivacyConsent.agreed ? 1 : 0, version);
    } catch (err) {
      // 读不到就按"未同意"处理：宁可多问一次，也不替用户做决定
      PrivacyConsent.agreed = false;
      hilog.warn(DOMAIN, TAG, 'consent init failed: %{public}s', JSON.stringify(err));
    }
  }

  static isAgreed(): boolean {
    return PrivacyConsent.agreed;
  }

  /** 用户点了"同意并继续" */
  static async agree(): Promise<void> {
    PrivacyConsent.agreed = true;
    const store: preferences.Preferences | undefined = PrivacyConsent.store;
    if (store === undefined) {
      return;
    }
    await store.put(KEY_AGREED_VERSION, PRIVACY_VERSION);
    await store.flush();
    hilog.info(DOMAIN, TAG, 'consent granted');
  }
}
