import { CityItem } from '../model/CityDict';
import { CityRepository } from '../repository/CityRepository';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'AchievementEngine';
const SEEN_STORE: string = 'achievement_store';
const SEEN_KEY: string = 'seen_ids';

/** 成就徽章 */
export interface AchievementItem {
  id: string;
  name: string;
  desc: string;
  icon: string;
  progress: number;
  target: number;
  unlocked: boolean;
}

const REGION_EAST: string[] = ['上海市', '江苏省', '浙江省', '安徽省', '福建省', '江西省', '山东省', '台湾省'];
/** 四个直辖市：集齐是很典型的一条"打卡线" */
const MUNICIPALITY_CODES: string[] = ['110000', '120000', '310000', '500000'];

/** 成就计算：全部本地计算，不依赖服务端 */
export class AchievementEngine {
  private static store: preferences.Preferences | undefined = undefined;

  /**
   * 取出"本次新解锁、但用户还没看到过"的徽章 id，用于播放点亮动画。
   *
   * 为什么要落盘：徽章是在地图页点亮城市时解锁的，用户往往过一会儿才切到统计页。
   * 如果只在内存里比较，杀进程重进就分不清"新解锁"和"早就解锁"，
   * 要么动画不播、要么每次进页面都重播一遍。
   *
   * 副作用：调用后会把当前所有已解锁徽章记为"已见"。
   */
  static async takeNewlyUnlocked(context: common.UIAbilityContext,
    items: AchievementItem[]): Promise<string[]> {
    const unlocked: string[] = [];
    for (const item of items) {
      if (item.unlocked) {
        unlocked.push(item.id);
      }
    }
    try {
      if (AchievementEngine.store === undefined) {
        const options: preferences.Options = { name: SEEN_STORE };
        AchievementEngine.store = await preferences.getPreferences(context, options);
      }
      const store: preferences.Preferences | undefined = AchievementEngine.store;
      if (store === undefined) {
        return [];
      }
      const raw: string = store.getSync(SEEN_KEY, '') as string;
      const seen: string[] = raw.length === 0 ? [] : raw.split(',');
      const fresh: string[] = [];
      for (const id of unlocked) {
        if (!seen.includes(id)) {
          fresh.push(id);
        }
      }
      await store.put(SEEN_KEY, unlocked.join(','));
      await store.flush();
      hilog.info(DOMAIN, TAG, 'newly unlocked: %{public}s', fresh.join(','));
      return fresh;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'takeNewlyUnlocked failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  /**
   * 把"已经取消达成"的徽章从"已庆祝"集合里移除。
   *
   * 场景：用户取消点亮某座城市后，「首站」不再达成 → 徽章回到未点亮状态；
   * 之后他再点亮一座城市，这枚徽章应该**重新庆祝一次**，而不是因为
   * seen_ids 里还留着它就静悄悄地亮起来。
   */
  static async forgetLocked(context: common.UIAbilityContext,
    items: AchievementItem[]): Promise<void> {
    try {
      if (AchievementEngine.store === undefined) {
        const options: preferences.Options = { name: SEEN_STORE };
        AchievementEngine.store = await preferences.getPreferences(context, options);
      }
      const store: preferences.Preferences | undefined = AchievementEngine.store;
      if (store === undefined) {
        return;
      }
      const raw: string = store.getSync(SEEN_KEY, '') as string;
      if (raw.length === 0) {
        return;
      }
      const seen: string[] = raw.split(',');
      const locked: string[] = [];
      for (const item of items) {
        if (!item.unlocked) {
          locked.push(item.id);
        }
      }
      const kept: string[] = seen.filter((id: string) => !locked.includes(id));
      if (kept.length === seen.length) {
        return;
      }
      await store.put(SEEN_KEY, kept.join(','));
      await store.flush();
      hilog.info(DOMAIN, TAG, 'forget locked badges: %{public}s', raw);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'forgetLocked failed: %{public}s', JSON.stringify(err));
    }
  }

  static evaluate(visitedCodes: string[]): AchievementItem[] {
    const count: number = visitedCodes.length;
    const provinces: Set<string> = new Set<string>();
    for (const code of visitedCodes) {
      const city: CityItem | undefined = CityRepository.get(code);
      if (city !== undefined && city.parent.length > 0) {
        provinces.add(city.parent);
      }
    }

    let eastCovered: number = 0;
    for (const province of REGION_EAST) {
      if (provinces.has(province)) {
        eastCovered = eastCovered + 1;
      }
    }
    const allProvinces: number = CityRepository.provinces().length;

    let municipalityCovered: number = 0;
    for (const code of MUNICIPALITY_CODES) {
      if (visitedCodes.includes(code)) {
        municipalityCovered = municipalityCovered + 1;
      }
    }

    const list: AchievementItem[] = [];
    list.push(AchievementEngine.make('first', '首站', '点亮第 1 座城市', '🏅', count, 1));
    list.push(AchievementEngine.make('ten', '十城', '点亮 10 座城市', '🏅', count, 10));
    list.push(AchievementEngine.make('fifty', '五十城', '点亮 50 座城市', '🏅', count, 50));
    list.push(AchievementEngine.make('hundred', '百城', '点亮 100 座城市', '🏆', count, 100));
    list.push(AchievementEngine.make('twohundred', '两百城', '点亮 200 座城市', '🏆', count, 200));
    list.push(AchievementEngine.make('province-half', '半壁江山', '覆盖一半省级行政区', '🏆',
      provinces.size, Math.ceil(allProvinces / 2)));
    list.push(AchievementEngine.make('east', '华东全境', '走遍华东 8 个省级行政区', '🧭', eastCovered, REGION_EAST.length));
    list.push(AchievementEngine.make('municipality', '四大直辖', '打卡北京/天津/上海/重庆', '🏛',
      municipalityCovered, MUNICIPALITY_CODES.length));
    list.push(AchievementEngine.make('all', '全国制霸', '点亮全部 370 个市州级单元', '👑', count, CityRepository.total()));
    return list;
  }

  private static make(id: string, name: string, desc: string, icon: string, progress: number,
    target: number): AchievementItem {
    return {
      id: id,
      name: name,
      desc: desc,
      icon: icon,
      progress: progress > target ? target : progress,
      target: target,
      unlocked: progress >= target
    };
  }
}
