import uiMaterial from '@ohos.arkui.uiMaterial';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Palette } from './Theme';

const DOMAIN: number = 0x0000;
const TAG: string = 'MaterialKit';

/**
 * 沉浸光感材质（HarmonyOS 7 / API 26 新增的 uiMaterial）。
 *
 * ⚠️ 一条踩过坑的硬约束（官方《沉浸光感常见问题》"组件不在沉浸光感生效范围"）：
 *   除了弹窗/半模态/菜单这类浮层，以及 Slider/Toggle/Select 之外，
 *   **其他组件（包括 Button）的 systemMaterial 只在 Navigation/NavDestination 标题栏
 *   或横向 Tabs 且 barPosition=BarPosition.End 的底部 TabBar 内生效**。
 *   放错地方时系统只会打一条日志：`Material inactive: out of scope.`，界面上毫无变化。
 *   所以本 App：
 *    · 底部页签栏 —— 走 Tabs.barFloatingStyle（本文件的 floatingTabBar()），材质真的会渲染；
 *    · 地图上的悬浮胶囊/圆按钮 —— 不走材质，直接用 backgroundBlurStyle 做真模糊。
 *   （同时用 backgroundColor 和材质也不行：材质画在背板层，背景色画在内容层，会把材质盖掉。）
 *
 * 材质语义（对应鸿蒙 7 "沉浸光感"设计语言）：
 *  · style        —— 材质厚度，越薄越通透，越厚越"磨砂"；
 *  · materialColor—— 材质层染色，必须是带透明度的颜色，全不透明会挡掉滤色；
 *  · interactive  —— 按压形变反馈；
 *  · lightEffect  —— 光感交互反馈（手指交互时材质表面出现的光晕颜色）。
 *
 * 使用方式：EntryAbility / Index.aboutToAppear 调用 MaterialKit.init()，
 * 页签栏样式里用 `MaterialKit.floatingTabBar()`。
 */
export class MaterialKit {
  /** 光感反馈色：金色光晕，贴合"点亮足迹"的产品语言 */
  private static readonly GLOW: string = '#7AFFD97D';
  /** 是否支持沉浸光感（鸿蒙 7 / API 26+） */
  private static supported: boolean = false;
  /** 初始化失败的诊断信息（用于界面上显示，方便定位为什么不生效） */
  static lastError: string = 'not-initialized';
  /**
   * 诊断串：把"系统是否真的会把材质渲染出来"的关键参数记下来，
   * 显示在「我的 → 关于 → 沉浸光感」。
   *  · api      —— 设备 API 版本（<26 一定没有材质）
   *  · level    —— 设备算力档位（EXQUISITE/GENTLE/SMOOTH），SMOOTH 只有底色没有滤色
   *  · state    —— module.json5 里 ohos.arkui.UIMaterial.state 的解析结果
   *  · filter   —— 是否支持沉浸式材质（false 时所有材质都是空操作）
   */
  static diagnostics: string = '';

  /** 底部页签栏专用：比普通卡片更"实"一点，压在浅色地图上也要看得清字 */
  private static barMaterial: uiMaterial.ImmersiveMaterial | undefined = undefined;

  /**
   * 初始化材质。在 EntryAbility.onCreate 中调用一次即可。
   * 低版本设备 / 不支持材质的设备会静默跳过，各页面拿到的都是 undefined。
   */
  static init(): void {
    // 已经成功就不再重复初始化；失败则允许重试
    // （实测：在 Ability.onCreate 阶段调用 isImmersiveMaterialSupported() 可能返回 false，
    //  等窗口/UI 上下文就绪后再调一次就正常了）
    if (MaterialKit.supported) {
      return;
    }
    try {
      if (deviceInfo.sdkApiVersion < 26) {
        MaterialKit.lastError = `api ${deviceInfo.sdkApiVersion}`;
        hilog.info(DOMAIN, TAG, 'immersive material skipped (api %{public}d)', deviceInfo.sdkApiVersion);
        return;
      }
      const deviceSupported: boolean = uiMaterial.isImmersiveMaterialSupported();
      const level: uiMaterial.MaterialLevel = uiMaterial.getGlobalMaterialLevel();
      const info: uiMaterial.MaterialInfo = uiMaterial.getMaterialInfo();
      MaterialKit.diagnostics =
        `api ${deviceInfo.sdkApiVersion} / 档位 ${level} / 应用开关 state=${info.state} / filter=${deviceSupported}`;
      hilog.info(DOMAIN, TAG, 'material probe: api=%{public}d level=%{public}d state=%{public}d filter=%{public}s',
        deviceInfo.sdkApiVersion, level, info.state, JSON.stringify(deviceSupported));
      if (!deviceSupported) {
        MaterialKit.lastError = `api ${deviceInfo.sdkApiVersion} / device=false`;
        hilog.info(DOMAIN, TAG, 'immersive material not supported by device');
        return;
      }
      // 底部页签栏：官方《沉浸光感 · 场景规范》里底部悬浮用 THIN + 渐变颜色蒙层。
      // 这里的染色比普通卡片重一档：页签栏经常压在浅色地图上，
      // 太透会让金色/灰色图标失去对比度（实测 #1F 透明度的染色在浅色底图上发飘）。
      MaterialKit.barMaterial = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THIN,
        materialColor: Palette.glassBar,
        colorInvert: false,
        applyShadow: true,
        interactive: false,
        // 手指按在页签上时，材质表面浮起一层金色光晕（沉浸光感的"光感"部分）
        lightEffect: { color: MaterialKit.GLOW }
      });
      MaterialKit.supported = true;
      MaterialKit.lastError = '';
      hilog.info(DOMAIN, TAG, 'immersive material ready');
    } catch (err) {
      MaterialKit.lastError = `exception: ${JSON.stringify(err)}`;
      hilog.warn(DOMAIN, TAG, 'immersive material unavailable: %{public}s', JSON.stringify(err));
    }
  }

  /** 当前设备是否真的用上了沉浸光感材质 */
  static isSupported(): boolean {
    return MaterialKit.supported;
  }

  /**
   * 底部页签栏（Tabs.barFloatingStyle 专用）。
   *
   * 为什么单独一个：官方《组件适配沉浸光感》规定，Tabs 的悬浮页签栏要同时满足
   * `barOverlap(true) + vertical(false) + barPosition(BarPosition.End)` 才会吃到材质。
   * 这条路径是系统原生绘制的，比自己拿 Button 拼一条导航（材质只在部分容器生效）可靠得多。
   * 返回值类型必须是 ImmersiveMaterial（barFloatingStyle.systemMaterial 的形参类型），
   * 不能用基类 Material，否则 ArkTS 编译期类型不匹配。
   */
  static floatingTabBar(): uiMaterial.ImmersiveMaterial | undefined {
    return MaterialKit.barMaterial;
  }
}
