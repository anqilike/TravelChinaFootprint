import { Palette } from '../common/Theme';
import { DeveloperInfo } from '../common/DeveloperInfo';

/** 隐私政策的一节：小标题 + 正文 */
interface PolicySection {
  title: string;
  body: string;
}

/**
 * 《走遍中国》隐私政策正文（v1.0）。
 *
 * 为什么写在代码里而不是只放在网页：华为应用市场要求"应用内可访问隐私政策"，
 * 同时要求 AGC 填写一个可公网访问的隐私政策网址；
 * 这里的文本与 docs/隐私政策.md 保持一致，两边改动要同步。
 *
 * ⚠️ 发布前必须把「联系邮箱」换成真实邮箱——审核会核对联系方式。
 */
const POLICY_SECTIONS: PolicySection[] = [
  {
    title: '一、我们收集哪些信息',
    body: '1. 位置信息（可选）：只有当你主动点击"定位到我的位置"时，应用才会通过系统定位能力'
      + '获取一次当前位置，用于识别你当前所在的地级市，方便一键点亮。\n'
      + '2. 足迹数据（仅本机）：你点亮的城市、日期、标签、备注、同行人，全部保存在本机应用沙箱内。\n'
      + '3. 华为账号信息（可选）：只有当你主动点击"登录华为账号"时，应用才会保存华为账号返回的'
      + ' openID / unionID，用于在云同步时区分数据归属。\n'
      + '4. 购买信息（可选）：应用提供一次性付费的终身会员。支付由系统收银台完成，'
      + '应用不接触、不保存你的银行卡号、支付账号等支付信息；只在本机保存订单号与"已开通"状态，'
      + '用于识别会员权益。'
  },
  {
    title: '二、我们不收集什么',
    body: '· 不读取通讯录、短信、相册、剪贴板；\n'
      + '· 不获取设备唯一标识（IMEI / OAID 等），不做用户画像；\n'
      + '· 不接入任何第三方广告或统计 SDK，不向第三方出售、共享你的个人信息；\n'
      + '· 位置信息不上传、不留存轨迹。'
  },
  {
    title: '三、信息如何存储与使用',
    body: '· 默认全部数据仅保存在本机（应用沙箱数据库 footprint.db），卸载应用即删除。\n'
      + '· 只有当你主动登录华为账号并点击"立即同步"后，足迹数据才会通过华为云同步到'
      + '你自己的账号下；开发者无法读取你在云端的个人数据。\n'
      + '· 位置信息仅用于"当前城市识别"，使用后即丢弃，不写日志、不上传。'
  },
  {
    title: '四、使用的第三方服务',
    body: '· 华为 Map Kit（地图底图、坐标转换、审图号展示）——由华为提供地图服务；\n'
      + '· 华为 Account Kit（华为账号登录）；\n'
      + '· 华为云（Cloud Foundation Kit，仅在开启云同步时使用）。\n'
      + '上述服务均按华为官方的隐私声明处理数据。'
  },
  {
    title: '五、你的权利',
    body: '· 查看与导出：在我的 → "导出我的足迹"，可导出 JSON 文件；\n'
      + '· 更正与删除：在我的 → 清单中删除对应记录，或在 我的 → "清除全部数据"；\n'
      + '· 撤回同意：卸载应用即撤回，本机数据同时被删除。'
  },
  {
    title: '六、未成年人保护',
    body: '本应用不面向 14 周岁以下儿童单独提供服务，也不会主动收集儿童个人信息。'
      + '如监护人发现相关情况，可通过下方联系方式要求删除。'
  },
  {
    title: '七、政策更新',
    body: '隐私政策如有实质性变更，应用会在启动时重新征求你的同意，并更新版本号。'
  },
  {
    title: '八、联系我们',
    // 这三行会被华为商户服务审核当作"应用开发者信息"的证明材料，
    // 统一取自 common/DeveloperInfo.ets，改一处三处同步（应用内、网页版、关于页）。
    body: `本应用「${DeveloperInfo.APP_NAME}」由 ${DeveloperInfo.DEVELOPER} 开发并提供。\n`
      + `开发者：${DeveloperInfo.DEVELOPER}\n`
      + `联系邮箱：${DeveloperInfo.CONTACT_EMAIL}\n`
      + '如果你对本政策有任何疑问、意见或投诉，可以通过上述邮箱联系我们，'
      + '我们将在 15 个工作日内回复。'
  }
];

/**
 * 隐私政策阅读视图：可滚动的完整正文。
 * 既用在"首次启动同意"弹层里，也用在「我的 → 关于 → 隐私政策」。
 */
@ComponentV2
export struct PrivacyPolicyView {
  build() {
    Scroll() {
      Column({ space: 14 }) {
        Text('走遍中国 · 隐私政策')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.text)
          .width('100%')

        Text(`版本 v1.0　生效日期：2026-09-14`)
          .fontSize(11)
          .fontColor(Palette.textDim)
          .width('100%')

        Text('导语：走遍中国是一款"记录你去过哪些城市"的本地工具应用。'
          + '我们坚持最小必要原则：不注册也能使用全部核心功能，位置与账号都由你主动触发。')
          .fontSize(12)
          .lineHeight(19)
          .fontColor(Palette.textDim)
          .width('100%')

        ForEach(POLICY_SECTIONS, (section: PolicySection) => {
          Column({ space: 6 }) {
            Text(section.title)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Palette.gold)
              .width('100%')
            Text(section.body)
              .fontSize(12)
              .lineHeight(19)
              .fontColor(Palette.text)
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (section: PolicySection) => section.title)
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .scrollBar(BarState.Auto)
    .width('100%')
    .height('100%')
  }
}
