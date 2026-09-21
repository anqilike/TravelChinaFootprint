/**
 * 开发者信息（对外公示用，单一数据源）。
 *
 * 为什么单独抽一个文件：
 *  1. 隐私政策（应用内 + 网页版）、「我的 → 关于」、以及商户服务申请材料里的
 *     「隐私页 / 关于页截图」必须是**同一套信息**，散落各处迟早对不上；
 *  2. 华为商户服务审核明确要求：截图需展示"应用由×××开发"，
 *     且应用名称要能对上，所以这几项在这里统一定义。
 */
export class DeveloperInfo {
  /** 应用名称（必须与 module.json5 的 label 一致） */
  static readonly APP_NAME: string = '走遍中国';
  /** 开发者署名：审核要求能看出"应用由谁开发" */
  static readonly DEVELOPER: string = '吕志方（个人开发者）';
  /**
   * 对外联系邮箱：出现在隐私政策与「关于」页，用于审核联系与用户投诉。
   * ⚠️ 必须换成真实可用的邮箱后再出商户服务材料截图。
   */
  static readonly CONTACT_EMAIL: string = '（待填写：联系邮箱）';
  /** 版权署名 */
  static readonly COPYRIGHT: string = '© 2026 吕志方';
}
