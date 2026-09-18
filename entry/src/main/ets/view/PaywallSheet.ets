import { promptAction } from '@kit.ArkUI';
import { Palette } from '../common/Theme';
import { FREE_QUOTA, membershipState } from '../service/MembershipService';
import { paywallStore } from '../viewmodel/PaywallStore';

/**
 * 终身会员购买面板（底部半模态）。
 *
 * 设计依据（华为《IAP Kit 接入规范》，违反可能影响上架）：
 *  1. **不得**在商品购买页展示支付方式信息：不出现"华为支付 / 应用内支付"等
 *     名称与 logo，只保留一个明确的购买按钮；
 *  2. 点击购买后直接拉起系统收银台，中间用加载动效过渡；
 *  3. 商品价格必须使用 AGC 返回的本地化价格（paywallStore.priceLabel），
 *     不能自己写死；拿不到商品信息时才用兜底文案。
 *
 * 状态来源：paywallStore（交互状态）+ membershipState（会员与免费额度），
 * 两者都是 @ObservedV2，购买成功后界面自动刷新，不需要页面手动通知。
 */
@ComponentV2
export struct PaywallSheet {
  /** 权益条目 */
  private benefits: string[] = [
    '无限点亮全国 370 座市州，不再受免费额度限制',
    '一次买断，终身有效，后续版本不再收费',
    '换新手机或重装后，用同一华为账号即可找回'
  ];

  build() {
    Column() {
      // 顶部：徽标 + 标题 + 副标题
      Row() {
        Column() {
          Text('★')
            .fontSize(26)
            .fontColor(Palette.gold)
        }
          .width(52)
          .height(52)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#33F5C542')
          .borderRadius(16)

        Column() {
          Text('走遍中国 · 终身会员')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.text)
          Text(this.subtitle())
            .fontSize(12)
            .fontColor(Palette.textDim)
            .margin({ top: 4 })
            .maxLines(2)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 14 })
      }
      .width('100%')

      // 权益清单
      Column() {
        ForEach(this.benefits, (item: string) => {
          Row() {
            Text('✓')
              .fontSize(13)
              .fontColor(Palette.gold)
              .width(20)
            Text(item)
              .fontSize(13)
              .fontColor(Palette.text)
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ top: 8 })
        }, (item: string) => item)
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
      .margin({ top: 16 })

      // 主按钮：价格来自 AGC（queryProducts 的 localPrice）
      Button() {
        Row() {
          if (paywallStore.purchasing) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color('#1A1206')
              .margin({ right: 8 })
          }
          Text(this.buyLabel())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1206')
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(50)
      .borderRadius(25)
      .backgroundColor(Palette.gold)
      .margin({ top: 16 })
      .stateStyles({
        normal: this.normalFeedback,
        pressed: this.pressedFeedback
      })
      .onClick(() => {
        this.onBuy();
      })

      // 次级入口：恢复购买
      Text(paywallStore.restoring ? '正在查找…' : '已购买过？恢复购买')
        .fontSize(13)
        .fontColor(Palette.textDim)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 12, bottom: 12 })
        .onClick(() => {
          this.onRestore();
        })

      // 状态提示（取消 / 失败 / 找回结果）
      if (paywallStore.statusText.length > 0) {
        Text(paywallStore.statusText)
          .fontSize(12)
          .fontColor(Palette.goldLight)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 8 })
      }

      Text('购买成功后立即解锁；未成年人请在监护人指导下购买。')
        .fontSize(11)
        .fontColor(Palette.textDim)
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 10, bottom: 20 })
    .alignItems(HorizontalAlign.Start)
  }

  @Styles
  pressedFeedback() {
    .scale({ x: 0.98, y: 0.98 })
    .opacity(0.9)
  }

  @Styles
  normalFeedback() {
    .scale({ x: 1.0, y: 1.0 })
    .opacity(1.0)
  }

  /** 副标题：优先说明"为什么现在弹出来"，其次说明免费额度 */
  private subtitle(): string {
    if (membershipState.member) {
      return '终身会员已开通';
    }
    if (paywallStore.cityName.length > 0) {
      return `点亮「${paywallStore.cityName}」需要先开通终身会员`;
    }
    return `免费体验的 ${FREE_QUOTA} 座城市已用完`;
  }

  /** 按钮文案：商品信息拿到前用兜底价格，避免出现空白按钮 */
  private buyLabel(): string {
    if (paywallStore.purchasing) {
      return '正在拉起收银台…';
    }
    if (membershipState.member) {
      return '已开通';
    }
    return `${paywallStore.priceLabel} 开通终身会员`;
  }

  private onBuy(): void {
    if (membershipState.member || paywallStore.purchasing) {
      return;
    }
    if (paywallStore.envBlocked) {
      promptAction.showToast({ message: paywallStore.statusText });
      return;
    }
    paywallStore.buy().then((ok: boolean) => {
      if (ok) {
        promptAction.showToast({ message: '终身会员已开通，全部城市已解锁' });
      }
    });
  }

  private onRestore(): void {
    if (paywallStore.restoring) {
      return;
    }
    paywallStore.restore().then((ok: boolean) => {
      if (ok) {
        promptAction.showToast({ message: '已找回你的终身会员' });
      } else if (paywallStore.statusText.length > 0) {
        promptAction.showToast({ message: paywallStore.statusText });
      }
    });
  }
}
