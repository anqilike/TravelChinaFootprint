import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'AccountService';
const STORE_NAME: string = 'account_store';
const KEY_OPEN_ID: string = 'open_id';
const KEY_UNION_ID: string = 'union_id';
const KEY_LOGIN_TIME: string = 'login_time';

/**
 * 华为账号登录态。
 *
 * 说明：
 *  · 登录本身走 Account Kit 的官方组件（LoginWithHuaweiIDButton），拿到的凭据里含
 *    openID / unionID / authorizationCode / idToken；
 *  · 本 App **不需要自建账号体系**：用 openID 作为云同步的数据归属标识即可，
 *    openID 只在本机保存，不上传第三方；
 *  · 不保存 authorizationCode / idToken（有有效期，且属于敏感凭据），
 *    需要时由 Account Kit 组件重新获取。
 */
export class AccountService {
  private static store: preferences.Preferences | undefined = undefined;
  private static openId: string = '';
  private static unionId: string = '';
  private static loginTime: number = 0;

  /** 启动时调用一次，把上次的登录态读回内存 */
  static async init(context: common.UIAbilityContext): Promise<void> {
    if (AccountService.store !== undefined) {
      return;
    }
    try {
      const options: preferences.Options = { name: STORE_NAME };
      const store: preferences.Preferences = await preferences.getPreferences(context, options);
      AccountService.store = store;
      AccountService.openId = store.getSync(KEY_OPEN_ID, '') as string;
      AccountService.unionId = store.getSync(KEY_UNION_ID, '') as string;
      AccountService.loginTime = store.getSync(KEY_LOGIN_TIME, 0) as number;
      hilog.info(DOMAIN, TAG, 'account restored, logged in=%{public}d',
        AccountService.openId.length > 0 ? 1 : 0);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'account init failed: %{public}s', JSON.stringify(err));
    }
  }

  static isLoggedIn(): boolean {
    return AccountService.openId.length > 0;
  }

  static getOpenId(): string {
    return AccountService.openId;
  }

  /** 登录成功后由页面调用，落盘保存 */
  static async signIn(openId: string, unionId: string): Promise<void> {
    AccountService.openId = openId;
    AccountService.unionId = unionId;
    AccountService.loginTime = Date.now();
    const store: preferences.Preferences | undefined = AccountService.store;
    if (store === undefined) {
      return;
    }
    await store.put(KEY_OPEN_ID, openId);
    await store.put(KEY_UNION_ID, unionId);
    await store.put(KEY_LOGIN_TIME, AccountService.loginTime);
    await store.flush();
    hilog.info(DOMAIN, TAG, 'account signed in');
  }

  /** 退出登录：只清本机登录态，不动本地足迹数据 */
  static async signOut(): Promise<void> {
    AccountService.openId = '';
    AccountService.unionId = '';
    AccountService.loginTime = 0;
    const store: preferences.Preferences | undefined = AccountService.store;
    if (store === undefined) {
      return;
    }
    await store.delete(KEY_OPEN_ID);
    await store.delete(KEY_UNION_ID);
    await store.delete(KEY_LOGIN_TIME);
    await store.flush();
    hilog.info(DOMAIN, TAG, 'account signed out');
  }

  static lastLoginTime(): number {
    return AccountService.loginTime;
  }

  /** 界面上展示用的短标识：openID 后 6 位 */
  static shortId(): string {
    const id: string = AccountService.openId;
    if (id.length <= 6) {
      return id;
    }
    return `…${id.substring(id.length - 6)}`;
  }
}
