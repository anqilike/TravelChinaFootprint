import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { IapOutcome, IapProduct, IapService, PRICE_FALLBACK } from '../service/IapService';
import { MembershipService } from '../service/MembershipService';

const DOMAIN: number = 0x0000;
const TAG: string = 'PaywallStore';

/**
 * 购买面板的状态与购买流程。
 *
 * 做成全局单例（和 footprintStore 一个套路）的原因：
 *  · 地图页、清单页、我的页都可能触发购买，三处共用同一份"正在购买 / 提示文案"状态；
 *  · 购买成功后写回 MembershipService，界面通过 membershipState 自动刷新，
 *    不需要各页面互相传递回调（ArkUI 状态管理 V2 里跨组件传函数很容易踩刷新的坑）。
 */
@ObservedV2
export class PaywallStore {
  /** 面板是否展示 */
  @Trace visible: boolean = false;
  /** 触发购买的城市名（用于"点亮「成都」需要开通"这类文案） */
  @Trace cityName: string = '';
  /** 本地化价格，取自 AGC 商品信息 */
  @Trace priceLabel: string = PRICE_FALLBACK;
  /** 商品名，取自 AGC 商品信息 */
  @Trace productName: string = '走遍中国 · 终身会员';
  /** 正在拉起收银台 */
  @Trace purchasing: boolean = false;
  /** 正在恢复购买 */
  @Trace restoring: boolean = false;
  /** 面板内的提示文案（错误 / 取消 / 找回成功） */
  @Trace statusText: string = '';
  /** 账号服务地不支持结算等情况：仍在展示面板，但按钮只提示原因 */
  @Trace envBlocked: boolean = false;
  /** 本次购买是否发生在沙盒环境（仅调试信息） */
  @Trace sandbox: boolean = false;
  /**
   * 购买 / 找回成功后的回调，由发起拦截的页面在 open() 之前设置。
   * 用"挂在 store 上的普通属性"而不是组件间传函数，是为了避开
   * ArkUI 状态管理 V2 里跨组件函数属性的刷新坑（本项目已经踩过一次）。
   */
  onPurchased: (() => void) | undefined = undefined;

  private context: common.UIAbilityContext | undefined = undefined;
  private envChecked: boolean = false;
  private productLoaded: boolean = false;

  /** App 启动时注入 UIAbilityContext */
  attach(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /** 打开面板（页面在拦截到"需要会员"时调用） */
  open(cityName: string): void {
    this.cityName = cityName;
    this.statusText = '';
    this.visible = true;
    this.refreshProductInfo();
  }

  close(): void {
    this.visible = false;
  }

  /** 手动"恢复购买"（在面板里点） */
  async restore(): Promise<boolean> {
    if (this.context === undefined || this.restoring) {
      return false;
    }
    this.restoring = true;
    this.statusText = '';
    const ok: boolean = await this.restoreInternal(false);
    this.restoring = false;
    return ok;
  }

  /**
   * 启动时静默找回：官方《权益发放》要求单机应用启动时查询一次已购非消耗型商品，
   * 覆盖"卸载重装 / 换新手机"的场景。已经是会员就不再查（省一次网络请求，离线也能用）。
   */
  async restoreOnLaunch(): Promise<void> {
    if (this.context === undefined || MembershipService.isMember()) {
      return;
    }
    await this.restoreInternal(true);
  }

  /**
   * 拉起收银台购买。返回 true 代表权益已发放（会员已开通）。
   * 官方要求：发放权益成功之后才能调用 finishPurchase 确认发货。
   */
  async buy(): Promise<boolean> {
    const context: common.UIAbilityContext | undefined = this.context;
    if (context === undefined || this.purchasing) {
      return false;
    }
    this.purchasing = true;
    this.statusText = '';
    try {
      const outcome: IapOutcome = await IapService.purchase(context);
      if (outcome.canceled) {
        this.purchasing = false;
        this.statusText = '已取消，随时可以再来开通';
        return false;
      }
      if (!outcome.success) {
        this.statusText = outcome.message;
        // 官方要求：返回"已拥有 / 系统错误"时要检查是否存在已购未发货的订单
        const restored: boolean = await this.restoreInternal(true);
        this.purchasing = false;
        if (restored) {
          this.visible = false;
          return true;
        }
        return false;
      }
    await MembershipService.grant(outcome.orderId, outcome.sandbox);
    await IapService.finish(context, outcome.orderId, outcome.purchaseToken, outcome.productType);
    this.sandbox = outcome.sandbox;
    this.purchasing = false;
    this.visible = false;
    this.notifyPurchased();
    hilog.info(DOMAIN, TAG, 'purchase done, sandbox=%{public}d', outcome.sandbox ? 1 : 0);
    return true;
    } catch (err) {
      this.purchasing = false;
      this.statusText = '购买失败，请稍后重试';
      hilog.error(DOMAIN, TAG, 'purchase error: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /** 拉取商品名 / 价格，并检查账号服务地 */
  private async refreshProductInfo(): Promise<void> {
    const context: common.UIAbilityContext | undefined = this.context;
    if (context === undefined) {
      return;
    }
    if (!this.envChecked) {
      const reason: string = await IapService.checkEnvironment(context);
      this.envBlocked = reason.length > 0;
      if (this.envBlocked) {
        this.statusText = reason;
      }
      this.envChecked = true;
    }
    if (!this.productLoaded) {
      const product: IapProduct | undefined = await IapService.queryProduct(context);
      if (product !== undefined) {
        this.productName = product.name;
        this.priceLabel = product.priceLabel;
        this.productLoaded = true;
      }
    }
  }

  /** silent=true 时不写界面文案（启动静默找回 / 购买失败后的补发货检查） */
  private async restoreInternal(silent: boolean): Promise<boolean> {
    const context: common.UIAbilityContext | undefined = this.context;
    if (context === undefined) {
      return false;
    }
    const owned: IapOutcome[] = await IapService.queryOwned(context);
    if (owned.length === 0) {
      if (!silent) {
        this.statusText = '没有查到该华为账号的购买记录';
      }
      return false;
    }
    const order: IapOutcome = owned[0];
    await MembershipService.grant(order.orderId, order.sandbox);
    await IapService.finish(context, order.orderId, order.purchaseToken, order.productType);
    if (!silent) {
      this.statusText = '';
      this.visible = false;
    }
    this.notifyPurchased();
    hilog.info(DOMAIN, TAG, 'membership restored from store');
    return true;
  }

  private notifyPurchased(): void {
    const callback: (() => void) | undefined = this.onPurchased;
    if (callback !== undefined) {
      callback();
    }
  }
}

export const paywallStore: PaywallStore = new PaywallStore();
