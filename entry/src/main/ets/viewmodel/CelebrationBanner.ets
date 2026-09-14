/**
 * 顶部"成就解锁"横幅的状态。
 *
 * 同样用 @ObservedV2：横幅的滑入/滑出/流光都是逐帧变化的，
 * 只有可观察模型 + 独立子组件这条路径在本项目里被验证过能稳定刷新。
 */
@ObservedV2
export class CelebrationBanner {
  /** 徽章图标与两行文案 */
  @Trace icon: string = '';
  @Trace title: string = '';
  @Trace subtitle: string = '';
  /** 垂直位移：从屏幕上方滑入（负值在上方） */
  @Trace offsetY: number = -160;
  @Trace opacity: number = 0;
  @Trace scale: number = 0.92;
  /** 流光扫过的水平位移 */
  @Trace shimmerX: number = -220;
}
