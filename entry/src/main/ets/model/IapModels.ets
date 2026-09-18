import { util } from '@kit.ArkTS';

/**
 * IAP Kit 数据模型（字段与官方《IAP Kit 数据模型》一致）。
 *
 * 数据链路：
 *   createPurchase / queryPurchases
 *     → PurchaseData（JSON 字符串，含 jwsPurchaseOrder）
 *       → 解码 JWS 载荷得到 PurchaseOrderPayload（真正可用的订单信息）
 *
 * 官方文档：
 *  · 接入购买：harmonyos-guides/iap-integrate-purchase
 *  · 权益发放：harmonyos-guides/iap-delivering-products
 *  · 数据模型：harmonyos-references/iap-data-model
 */

/** createPurchase / queryPurchases 返回的 PurchaseData */
export interface IapPurchaseData {
  /** 商品类型：0 消耗型 / 1 非消耗型 / 2 自动续期 / 3 非续期订阅 */
  type: number;
  /** 订单信息（JWS 格式），本 App 只用到这一个字段 */
  jwsPurchaseOrder?: string;
  jwsSubscriptionStatus?: string;
}

/** 解码 jwsPurchaseOrder 后的订单信息 */
export interface IapOrderPayload {
  /** NORMAL 生产环境 / SANDBOX 沙盒环境 */
  environment: string;
  /** 购买订单号（finishPurchase 需要） */
  purchaseOrderId: string;
  /** 购买令牌（finishPurchase 需要） */
  purchaseToken: string;
  applicationId: string;
  productId: string;
  /** 商品类型，注意官方这里是**字符串**："1" 表示非消耗型 */
  productType: string;
  quantity?: number;
  purchaseTime: number;
  /** "1" 已发货 / "2" 未发货 */
  finishStatus?: string;
  needFinish?: boolean;
  /** 实付价格，单位：分 */
  price: number;
  /** 币种，如 CNY */
  currency: string;
  developerPayload?: string;
  /** 有值代表订单已撤销（退款），此时不应发货 */
  purchaseOrderRevocationReasonCode?: string;
  revocationTime?: number;
  offerTypeCode?: string;
  offerId?: string;
}

/**
 * JWS 解码工具。
 *
 * 说明（与官方口径保持一致）：
 *  · 官方建议把 purchaseData 发给应用服务器做**验签**，本 App 是单机应用
 *    （官方《权益发放》明确：单机应用的服务器交互放在客户端完成），
 *    所以这里只做**载荷解码**，订单本身来自 IAP Kit 系统接口而非第三方输入，
 *    配合启动时向华为侧复查已购列表，足够防"本地篡改会员标志"这一级别的风险；
 *  · 验签需要内置华为根证书链，属于服务端方案，本 App 暂不引入。
 */
export class JwsUtil {
  /** 取出 JWS 的载荷部分（第二段）并解成 JSON 字符串 */
  static decodePayload(jws: string): string {
    const parts: string[] = jws.split('.');
    if (parts.length < 2 || parts[1].length === 0) {
      throw new Error('非法订单数据');
    }
    return JwsUtil.base64UrlToString(parts[1]);
  }

  /**
   * Base64URL → 字符串。
   * JWS 用的是 base64url 变体（把 +/ 换成 -_，且去掉末尾 =），
   * 系统解码器只认标准 base64，所以要先还原字符并补齐 padding。
   */
  static base64UrlToString(input: string): string {
    let text: string = input.replace(/-/g, '+').replace(/_/g, '/');
    while (text.length % 4 !== 0) {
      text += '=';
    }
    const bytes: Uint8Array = new util.Base64Helper().decodeSync(text);
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }

  /** 解析 PurchaseData 字符串 */
  static parsePurchaseData(purchaseData: string): IapPurchaseData {
    return JSON.parse(purchaseData) as IapPurchaseData;
  }

  /** PurchaseData → PurchaseOrderPayload */
  static toOrderPayload(purchaseData: string): IapOrderPayload {
    const data: IapPurchaseData = JwsUtil.parsePurchaseData(purchaseData);
    const jws: string | undefined = data.jwsPurchaseOrder;
    if (jws === undefined || jws.length === 0) {
      throw new Error('订单数据缺少 jwsPurchaseOrder');
    }
    return JSON.parse(JwsUtil.decodePayload(jws)) as IapOrderPayload;
  }

  /** 订单是否有效（未撤销，即没有退款） */
  static isValidOrder(order: IapOrderPayload): boolean {
    const code: string | undefined = order.purchaseOrderRevocationReasonCode;
    return code === undefined || code.length === 0;
  }
}
