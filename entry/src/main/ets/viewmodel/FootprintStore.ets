import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { CityItem } from '../model/CityDict';
import { CityRepository } from '../repository/CityRepository';
import { VisitRepository } from '../repository/VisitRepository';

const DOMAIN: number = 0x0000;
const TAG: string = 'FootprintStore';

/** 点亮状态变化的监听器（地图页用它做增量刷新） */
export type FootprintListener = (code: string, visited: boolean) => void;

/**
 * 全局足迹状态（状态管理 V2）。
 * - @Trace 字段驱动 UI 自动刷新
 * - 监听器用于地图这类"非声明式"的增量更新
 */
@ObservedV2
export class FootprintStore {
  /** 已点亮的城市编码 */
  @Trace visitedCodes: string[] = [];
  /** 已点亮数量 */
  @Trace visitedCount: number = 0;
  /** 可点亮单元总数（370） */
  @Trace totalUnits: number = 0;
  /** 已覆盖的省级行政区数量 */
  @Trace provinceCount: number = 0;
  /** 省级行政区总数（34） */
  @Trace provinceTotal: number = 0;
  /** 到访次数最多的城市（用于统计页文案） */
  @Trace mostVisitedCity: string = '';
  @Trace mostVisitedTimes: number = 0;
  /** 数据是否就绪 */
  @Trace ready: boolean = false;

  private visitedSet: Set<string> = new Set<string>();
  private listeners: FootprintListener[] = [];

  /** 初始化：加载城市字典 + 读取本地到访记录 */
  async init(context: common.UIAbilityContext): Promise<void> {
    await CityRepository.load(context);
    const codes: string[] = await VisitRepository.loadVisitedCodes();
    this.totalUnits = CityRepository.total();
    this.provinceTotal = CityRepository.provinces().length;
    this.setVisited(codes);
    await this.refreshStats();
    this.ready = true;
    hilog.info(DOMAIN, TAG, 'store ready: %{public}d/%{public}d', this.visitedCount, this.totalUnits);
  }

  isVisited(code: string): boolean {
    // 注意：这里必须读取 @Trace 的 visitedCodes，UI 才能建立观测依赖；
    // 如果只读内部的 Set，状态变化后界面（如城市详情卡片）不会自动刷新。
    const list: string[] = this.visitedCodes;
    return list.includes(code);
  }

  get coverage(): number {
    if (this.totalUnits === 0) {
      return 0;
    }
    return this.visitedCount / this.totalUnits;
  }

  subscribe(listener: FootprintListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: FootprintListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 点亮一座城市（带默认的到访记录） */
  async lightUp(code: string, tag: string = 'other', note: string = ''): Promise<void> {
    if (this.visitedSet.has(code)) {
      return;
    }
    await VisitRepository.addVisit(code, Date.now(), tag, note, 0);
    this.applyChange(code, true);
    await this.refreshStats();
  }

  /** 取消点亮 */
  async unlight(code: string): Promise<void> {
    if (!this.visitedSet.has(code)) {
      return;
    }
    await VisitRepository.removeCity(code);
    this.applyChange(code, false);
    await this.refreshStats();
  }

  /** 批量点亮 */
  async lightUpBatch(codes: string[]): Promise<number> {
    const pending: string[] = [];
    for (const code of codes) {
      if (!this.visitedSet.has(code)) {
        pending.push(code);
      }
    }
    if (pending.length === 0) {
      return 0;
    }
    await VisitRepository.addVisitsBatch(pending);
    for (const code of pending) {
      this.applyChange(code, true);
    }
    await this.refreshStats();
    return pending.length;
  }

  /** 由"当前定位城市"点亮 */
  async lightUpCurrent(city: CityItem): Promise<void> {
    await this.lightUp(city.code, 'other', '');
  }

  private applyChange(code: string, visited: boolean): void {
    if (visited) {
      if (!this.visitedSet.has(code)) {
        this.visitedSet.add(code);
        const next: string[] = this.visitedCodes.slice();
        next.push(code);
        this.visitedCodes = next;
        this.visitedCount = next.length;
      }
    } else {
      if (this.visitedSet.has(code)) {
        this.visitedSet.delete(code);
        const next: string[] = this.visitedCodes.filter((item: string) => item !== code);
        this.visitedCodes = next;
        this.visitedCount = next.length;
      }
    }
    this.recomputeProvinceCount();
    for (const listener of this.listeners) {
      listener(code, visited);
    }
  }

  private setVisited(codes: string[]): void {
    const unique: string[] = [];
    const set: Set<string> = new Set<string>();
    for (const code of codes) {
      if (!set.has(code)) {
        set.add(code);
        unique.push(code);
      }
    }
    this.visitedSet = set;
    this.visitedCodes = unique;
    this.visitedCount = unique.length;
    this.recomputeProvinceCount();
  }

  private recomputeProvinceCount(): void {
    const provinces: Set<string> = new Set<string>();
    for (const code of this.visitedCodes) {
      const city: CityItem | undefined = CityRepository.get(code);
      if (city !== undefined && city.parent.length > 0) {
        provinces.add(city.parent);
      }
    }
    this.provinceCount = provinces.size;
  }

  /** 重新计算统计信息（到访次数最多等） */
  async refreshStats(): Promise<void> {
    const stats = await VisitRepository.loadCityStats();
    let topCode: string = '';
    let topCount: number = 0;
    for (const stat of stats) {
      if (stat.count > topCount) {
        topCount = stat.count;
        topCode = stat.adcode;
      }
    }
    const city: CityItem | undefined = CityRepository.get(topCode);
    this.mostVisitedCity = city === undefined ? '' : city.name;
    this.mostVisitedTimes = topCount;
  }

  /**
   * 数据被整体改写后重新加载（例如「我的 → 清除本机足迹数据」）。
   * 会对"从已点亮变成未点亮"的城市逐个通知订阅者，
   * 否则地图上的点位会停在旧状态。
   */
  async reload(): Promise<void> {
    const previous: string[] = this.visitedCodes.slice();
    const codes: string[] = await VisitRepository.loadVisitedCodes();
    this.setVisited(codes);
    await this.refreshStats();
    for (const code of previous) {
      if (!codes.includes(code)) {
        for (const listener of this.listeners) {
          listener(code, false);
        }
      }
    }
    hilog.info(DOMAIN, TAG, 'store reloaded: %{public}d/%{public}d', this.visitedCount, this.totalUnits);
  }
}

/**
 * 全局单例。
 * 说明：状态管理 V2 的 @ObservedV2 对象被多个组件读取时，@Trace 字段变化会自动触发刷新；
 * 地图这类需要命令式更新的场景，通过 subscribe/unsubscribe 做增量同步。
 */
export const footprintStore: FootprintStore = new FootprintStore();
