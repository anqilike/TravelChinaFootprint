import { iap } from '@kit.IAPKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { IapOrderPayload, JwsUtil } from '../model/IapModels';

const DOMAIN: number = 0x0000;
const TAG: string = 'IapService';

/**
 * 终身会员商品 ID。
 * 必须与 AppGallery Connect「运营 → 产品运营 → 商品管理」里配置的商品 ID 完全一致；
 * 商品 ID 保存后无法修改，删除后也无法再次使用，所以这里的常量不要随意改动。
 */
export const PRODUCT_LIFETIME: string = 'travelchina_lifetime';
/** 商品信息拿不到时界面上的兜底价格文案（真实价格始终以 AGC 返回的本地价为准） */
export const PRICE_FALLBACK: string = '¥6.00';

/** 展示用的商品信息 */
export interface IapProduct {
  id: string;
  name: string;
  description: string;
  /** 华为按用户账号服务地返回的本地化价格，例如 ¥6.00 */
  priceLabel: string;
}

/** 一次购买 / 一次恢复购买的结果 */
export interface IapOutcome {
  success: boolean;
  /** 用户主动取消（不算失败，界面不要报错） */
  canceled: boolean;
  orderId: string;
  purchaseToken: string;
  productType: number;
  /** 是否沙盒环境订单（IAP Kit 沙盒测试） */
  sandbox: boolean;
  /** 面向用户的提示文案 */
  message: string;
}

/**
 * 华为应用内支付（IAP Kit）封装。
 *
 * 官方要求（《IAP Kit 接入规范》）：数字商品必须走 IAP Kit，不能接第三方支付；
 * 商品购买页不得展示支付方式名称 / logo，只保留"购买"按钮。
 *
 * 官方推荐流程（《接入购买》《权益发放》），本类按顺序实现：
 *   1. queryEnvironmentStatus  检查账号服务地是否支持结算
 *   2. queryProducts           取商品名 / 本地价格
 *   3. createPurchase          拉起收银台，返回 PurchaseData
 *   4. 解码 jwsPurchaseOrder   得到 PurchaseOrderPayload
 *   5. finishPurchase          确认发货（必须在发放权益之后）
 *   6. queryPurchases(CURRENT_ENTITLEMENT) 用于"恢复购买 / 换机找回"
 */
export class IapService {
  /**
   * 检查当前华为账号是否可以使用应用内购买。
   * 返回空字符串代表可用，否则是给用户看的失败原因。
   */
  static async checkEnvironment(context: common.UIAbilityContext): Promise<string> {
    try {
      await iap.queryEnvironmentStatus(context);
      return '';
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'queryEnvironmentStatus failed: %{public}d', error.code);
      return IapService.errorText(error.code);
    }
  }

  /** 查询商品信息（名称 / 描述 / 本地价格） */
  static async queryProduct(context: common.UIAbilityContext): Promise<IapProduct | undefined> {
    try {
      const parameter: iap.QueryProductsParameter = {
        productType: iap.ProductType.NONCONSUMABLE,
        productIds: [PRODUCT_LIFETIME]
      };
      const list: Array<iap.Product> = await iap.queryProducts(context, parameter);
      if (list.length === 0) {
        return undefined;
      }
      const product: iap.Product = list[0];
      const localPrice: string | undefined = product.localPrice;
      return {
        id: product.id,
        name: product.name.length > 0 ? product.name : '走遍中国 · 终身会员',
        description: product.description,
        priceLabel: (localPrice !== undefined && localPrice.length > 0) ? localPrice : PRICE_FALLBACK
      };
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'queryProducts failed: %{public}d', error.code);
      return undefined;
    }
  }

  /** 拉起收银台完成购买（失败时已转成可读文案） */
  static async purchase(context: common.UIAbilityContext): Promise<IapOutcome> {
    try {
      const parameter: iap.PurchaseParameter = {
        productId: PRODUCT_LIFETIME,
        productType: iap.ProductType.NONCONSUMABLE
      };
      const result: iap.CreatePurchaseResult = await iap.createPurchase(context, parameter);
      const order: IapOrderPayload = JwsUtil.toOrderPayload(result.purchaseData);
      if (order.productId !== PRODUCT_LIFETIME) {
        hilog.error(DOMAIN, TAG, 'productId mismatch: %{public}s', order.productId);
        return IapService.failure('订单商品不匹配，请联系客服');
      }
      if (!JwsUtil.isValidOrder(order)) {
        return IapService.failure('该订单已退款，无法开通');
      }
      return {
        success: true,
        canceled: false,
        orderId: order.purchaseOrderId,
        purchaseToken: order.purchaseToken,
        productType: Number(order.productType),
        sandbox: order.environment === 'SANDBOX',
        message: ''
      };
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'createPurchase failed: %{public}d', error.code);
      if (error.code === iap.IAPErrorCode.USER_CANCELED) {
        return {
          success: false, canceled: true, orderId: '', purchaseToken: '',
          productType: 0, sandbox: false, message: ''
        };
      }
      return IapService.failure(IapService.errorText(error.code));
    }
  }

  /**
   * 查询该账号已购买的非消耗型商品（用于"恢复购买"和更换设备后找回会员）。
   * 官方《权益发放》要求：单机应用在启动时做一次，买到但未发货的订单要补发货。
   */
  static async queryOwned(context: common.UIAbilityContext): Promise<IapOutcome[]> {
    const owned: IapOutcome[] = [];
    try {
      let token: string | undefined = undefined;
      let guard: number = 0;
      while (guard < 10) {
        guard = guard + 1;
        const parameter: iap.QueryPurchasesParameter = {
          productType: iap.ProductType.NONCONSUMABLE,
          queryType: iap.PurchaseQueryType.CURRENT_ENTITLEMENT
        };
        if (token !== undefined) {
          parameter.continuationToken = token;
        }
        const result: iap.QueryPurchaseResult = await iap.queryPurchases(context, parameter);
        const list: string[] = result.purchaseDataList;
        for (const purchaseData of list) {
          const outcome: IapOutcome | undefined = IapService.toOutcome(purchaseData);
          if (outcome !== undefined) {
            owned.push(outcome);
          }
        }
        token = result.continuationToken;
        if (token === undefined || token.length === 0) {
          break;
        }
      }
      hilog.info(DOMAIN, TAG, 'queryOwned ok, count=%{public}d', owned.length);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'queryPurchases failed: %{public}d', error.code);
    }
    return owned;
  }

  /**
   * 确认发货（完成购买流程）。
   * 官方强调：必须在权益发放成功之后调用，否则会出现"华为已确认发货但应用没发货"。
   */
  static async finish(context: common.UIAbilityContext, orderId: string,
    purchaseToken: string, productType: number): Promise<void> {
    try {
      const parameter: iap.FinishPurchaseParameter = {
        productType: productType,
        purchaseToken: purchaseToken,
        purchaseOrderId: orderId
      };
      await iap.finishPurchase(context, parameter);
      hilog.info(DOMAIN, TAG, 'finishPurchase ok');
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      // 1001860053：这笔订单已经确认过发货，重复确认可以忽略
      hilog.warn(DOMAIN, TAG, 'finishPurchase failed: %{public}d', error.code);
    }
  }

  /** 当前是否处于沙盒测试环境（debug 签名 + 已添加的测试账号） */
  static async isSandbox(context: common.UIAbilityContext): Promise<boolean> {
    try {
      return await iap.isSandboxActivated(context);
    } catch (err) {
      return false;
    }
  }

  /** PurchaseData 字符串 → 结果对象（商品不匹配 / 已退款 / 解析失败返回 undefined） */
  private static toOutcome(purchaseData: string): IapOutcome | undefined {
    try {
      const order: IapOrderPayload = JwsUtil.toOrderPayload(purchaseData);
      if (order.productId !== PRODUCT_LIFETIME || !JwsUtil.isValidOrder(order)) {
        return undefined;
      }
      return {
        success: true,
        canceled: false,
        orderId: order.purchaseOrderId,
        purchaseToken: order.purchaseToken,
        productType: Number(order.productType),
        sandbox: order.environment === 'SANDBOX',
        message: ''
      };
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'order decode failed');
      return undefined;
    }
  }

  private static failure(message: string): IapOutcome {
    return {
      success: false, canceled: false, orderId: '', purchaseToken: '',
      productType: 0, sandbox: false, message: message
    };
  }

  /** 错误码 → 用户能看懂的文案 */
  private static errorText(code: number): string {
    if (code === iap.IAPErrorCode.USER_CANCELED) {
      return '已取消购买';
    }
    if (code === iap.IAPErrorCode.SYSTEM_ERROR) {
      return '系统繁忙，请稍后重试';
    }
    if (code === iap.IAPErrorCode.APP_NOT_AUTHORIZED) {
      return '应用内购买服务尚未生效，请稍后重试';
    }
    if (code === iap.IAPErrorCode.INVALID_PRODUCT) {
      return '商品不存在或已下架';
    }
    if (code === iap.IAPErrorCode.FREQUENT_CALLS) {
      return '操作太频繁，请稍后再试';
    }
    if (code === iap.IAPErrorCode.NETWORK_ERROR) {
      return '网络异常，请检查网络后重试';
    }
    if (code === iap.IAPErrorCode.PRODUCT_OWNED) {
      return '该账号已经购买过，正在为你恢复权益';
    }
    if (code === iap.IAPErrorCode.ACCOUNT_NOT_LOGGED_IN) {
      return '请先在「设置 → 华为账号」登录后再开通';
    }
    if (code === iap.IAPErrorCode.PRODUCT_TERRITORY_NOT_SUPPORTED) {
      return '当前华为账号的服务地暂不支持应用内购买';
    }
    if (code === 801) {
      return '当前设备不支持应用内购买';
    }
    return '购买失败，请稍后重试';
  }
}
