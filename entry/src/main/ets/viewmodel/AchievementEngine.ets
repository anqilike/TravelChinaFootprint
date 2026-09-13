import { CityItem } from '../model/CityDict';
import { CityRepository } from '../repository/CityRepository';

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
