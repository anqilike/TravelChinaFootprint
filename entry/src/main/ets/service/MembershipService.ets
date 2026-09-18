import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'MembershipService';
const STORE_NAME: string = 'membership_store';
const KEY_MEMBER: string = 'is_member';
const KEY_FREE_CITIES: string = 'free_cities';
const KEY_ORDER_ID: string = 'order_id';
const KEY_SANDBOX: string = 'sandbox';
const KEY_GRANT_TIME: string = 'grant_time';
const KEY_MIGRATED: string = 'quota_migrated';

/** 免费体验额度：终身可免费点亮 5 座城市（第 6 座起需要终身会员） */
export const FREE_QUOTA: number = 5;

/**
 * 给界面观察的会员状态。
 * 状态管理 V2 的 @ObservedV2 + @Trace：字段变化会自动刷新读到它的界面，
 * 所以「地图上的免费名额」「我的页的会员卡片」「购买面板」都读这一个对象，
 * 购买成功后不需要各页面手动刷新。
 */
@ObservedV2
export class MembershipState {
  @Trace member: boolean = false;
  @Trace freeUsed: number = 0;
  @Trace orderShort: string = '';
  @Trace sandbox: boolean = false;
  @Trace grantTime: number = 0;
}

export const membershipState: MembershipState = new MembershipState();

/**
 * 会员与免费额度。
 *
 * 产品规则（对应《设计前指导书》付费章节）：
 *  1. 免费额度是**终身累计**的 5 座城市，不是每月刷新；
 *  2. 记录的是"用掉额度的城市编码集合"，不是简单计数器——
 *     这样"取消点亮再重新点亮同一座城市"不会重复扣额度，
 *     而"点亮→取消→换一座城市点亮"也不能绕过限制；
 *  3. 已经点亮的城市永久保留：老用户（升级前就点亮了 20 座）不会被回滚，
 *     只是"再点亮新城市"时才需要开通会员。升级时会把这批用户的前 5 座城市
 *     记为已用额度（ensureMigration），保证规则一致。
 */
export class MembershipService {
  private static store: preferences.Preferences | undefined = undefined;
  private static member: boolean = false;
  private static freeCities: string[] = [];
  private static orderId: string = '';
  private static sandbox: boolean = false;
  private static grantTime: number = 0;

  /** 启动时调用一次 */
  static async init(context: common.UIAbilityContext): Promise<void> {
    if (MembershipService.store !== undefined) {
      return;
    }
    try {
      const options: preferences.Options = { name: STORE_NAME };
      const store: preferences.Preferences = await preferences.getPreferences(context, options);
      MembershipService.store = store;
      MembershipService.member = store.getSync(KEY_MEMBER, false) as boolean;
      MembershipService.orderId = store.getSync(KEY_ORDER_ID, '') as string;
      MembershipService.sandbox = store.getSync(KEY_SANDBOX, false) as boolean;
      MembershipService.grantTime = store.getSync(KEY_GRANT_TIME, 0) as number;
      const raw: string = store.getSync(KEY_FREE_CITIES, '') as string;
      MembershipService.freeCities = MembershipService.parseList(raw);
      MembershipService.publish();
      hilog.info(DOMAIN, TAG, 'membership restored: member=%{public}d freeUsed=%{public}d',
        MembershipService.member ? 1 : 0, MembershipService.freeCities.length);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'init failed: %{public}s', JSON.stringify(err));
    }
  }

  static isMember(): boolean {
    return MembershipService.member;
  }

  static isSandbox(): boolean {
    return MembershipService.sandbox;
  }

  static grantedAt(): number {
    return MembershipService.grantTime;
  }

  /** 已用掉的免费额度（0~5） */
  static freeUsedCount(): number {
    return MembershipService.freeCities.length;
  }

  /** 剩余免费额度 */
  static freeLeft(): number {
    const left: number = FREE_QUOTA - MembershipService.freeCities.length;
    return left > 0 ? left : 0;
  }

  /**
   * 这座城市的"点亮"是否需要先开通会员。
   * 已经点亮的城市（含老用户存量数据）永远允许重新点亮，不消耗新额度。
   */
  static canLight(code: string): boolean {
    if (MembershipService.member) {
      return true;
    }
    if (MembershipService.freeCities.includes(code)) {
      return true;
    }
    return MembershipService.freeCities.length < FREE_QUOTA;
  }

  /** 用掉一个免费额度（会员 / 已记录过的城市不重复计） */
  static async consumeFreeSlot(code: string): Promise<void> {
    if (MembershipService.member || MembershipService.freeCities.includes(code)) {
      return;
    }
    if (MembershipService.freeCities.length >= FREE_QUOTA) {
      return;
    }
    const next: string[] = MembershipService.freeCities.slice();
    next.push(code);
    MembershipService.freeCities = next;
    await MembershipService.persist(KEY_FREE_CITIES, JSON.stringify(next));
    MembershipService.publish();
  }

  /**
   * 老用户迁移：升级到付费版之前已经点亮的城市不回滚，
   * 只把它们中的前 5 座记为"已用免费额度"，之后点亮新城市就需要会员。
   * 只执行一次。
   */
  static async ensureMigration(visitedCodes: string[]): Promise<void> {
    const store: preferences.Preferences | undefined = MembershipService.store;
    if (store === undefined) {
      return;
    }
    try {
      const migrated: boolean = store.getSync(KEY_MIGRATED, false) as boolean;
      if (migrated) {
        return;
      }
      const next: string[] = MembershipService.freeCities.slice();
      for (const code of visitedCodes) {
        if (next.length >= FREE_QUOTA) {
          break;
        }
        if (!next.includes(code)) {
          next.push(code);
        }
      }
      MembershipService.freeCities = next;
      await store.put(KEY_MIGRATED, true);
      await store.put(KEY_FREE_CITIES, JSON.stringify(next));
      await store.flush();
      MembershipService.publish();
      hilog.info(DOMAIN, TAG, 'quota migrated, freeUsed=%{public}d', next.length);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'migration failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 购买成功 / 恢复购买成功：记为终身会员 */
  static async grant(orderId: string, sandbox: boolean): Promise<void> {
    MembershipService.member = true;
    MembershipService.orderId = orderId;
    MembershipService.sandbox = sandbox;
    MembershipService.grantTime = Date.now();
    const store: preferences.Preferences | undefined = MembershipService.store;
    if (store === undefined) {
      return;
    }
    await store.put(KEY_MEMBER, true);
    await store.put(KEY_ORDER_ID, orderId);
    await store.put(KEY_SANDBOX, sandbox);
    await store.put(KEY_GRANT_TIME, MembershipService.grantTime);
    await store.flush();
    MembershipService.publish();
    hilog.info(DOMAIN, TAG, 'membership granted, sandbox=%{public}d', sandbox ? 1 : 0);
  }

  /** 订单号后 6 位，用于界面展示（不展示完整订单号） */
  static orderShortId(): string {
    const id: string = MembershipService.orderId;
    if (id.length <= 6) {
      return id;
    }
    return `…${id.substring(id.length - 6)}`;
  }

  /**
   * 仅开发调试使用：把本机会员状态和免费额度清空，
   * 方便反复验证"第 6 座城市触发付费"的完整流程。
   * 入口只出现在 debug 构建里（见 SettingsPage 的 BuildProfile.DEBUG 判断）。
   */
  static async resetForDebug(): Promise<void> {
    MembershipService.member = false;
    MembershipService.freeCities = [];
    MembershipService.orderId = '';
    MembershipService.sandbox = false;
    MembershipService.grantTime = 0;
    const store: preferences.Preferences | undefined = MembershipService.store;
    if (store === undefined) {
      return;
    }
    await store.put(KEY_MEMBER, false);
    await store.put(KEY_FREE_CITIES, '');
    await store.put(KEY_ORDER_ID, '');
    await store.put(KEY_SANDBOX, false);
    await store.put(KEY_GRANT_TIME, 0);
    await store.flush();
    MembershipService.publish();
    hilog.info(DOMAIN, TAG, 'membership reset (debug only)');
  }

  /** 把内存状态同步到可观察对象（界面据此刷新） */
  private static publish(): void {
    membershipState.member = MembershipService.member;
    membershipState.freeUsed = MembershipService.freeCities.length;
    membershipState.sandbox = MembershipService.sandbox;
    membershipState.orderShort = MembershipService.orderShortId();
    membershipState.grantTime = MembershipService.grantTime;
  }

  private static async persist(key: string, value: string): Promise<void> {
    const store: preferences.Preferences | undefined = MembershipService.store;
    if (store === undefined) {
      return;
    }
    await store.put(key, value);
    await store.flush();
  }

  private static parseList(raw: string): string[] {
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed: string[] = JSON.parse(raw) as string[];
      return parsed === null ? [] : parsed;
    } catch (err) {
      return [];
    }
  }
}
