import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CityItem } from '../model/CityDict';
import { CityRepository } from '../repository/CityRepository';

const DOMAIN: number = 0x0000;
const TAG: string = 'ExportService';

/** 导出的单条记录 */
interface ExportVisit {
  adcode: string;
  name: string;
  parent: string;
  exportDate: number;
}

interface ExportFile {
  app: string;
  schemaVersion: number;
  dictVersion: string;
  exportedAt: number;
  totalUnits: number;
  visitedCount: number;
  visits: ExportVisit[];
}

/**
 * 数据导出：把已点亮的城市写成 JSON 文件，落在应用沙箱 files 目录。
 * 数据可携带是用户的基本权利，所以首版就提供（对应指导书 F-05 验收标准）。
 */
export class ExportService {
  static async exportJson(context: common.UIAbilityContext, visitedCodes: string[]): Promise<string> {
    const visits: ExportVisit[] = [];
    for (const code of visitedCodes) {
      const city: CityItem | undefined = CityRepository.get(code);
      if (city !== undefined) {
        visits.push({
          adcode: city.code,
          name: city.name,
          parent: city.parent,
          exportDate: Date.now()
        });
      }
    }
    const payload: ExportFile = {
      app: 'TravelChinaFootprint',
      schemaVersion: 1,
      dictVersion: CityRepository.dictVersion(),
      exportedAt: Date.now(),
      totalUnits: CityRepository.total(),
      visitedCount: visits.length,
      visits: visits
    };
    const fileName: string = `huaxia_footprint_${Date.now()}.json`;
    const filePath: string = `${context.filesDir}/${fileName}`;
    const file: fileIo.File = fileIo.openSync(filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, JSON.stringify(payload));
    } finally {
      fileIo.closeSync(file);
    }
    hilog.info(DOMAIN, TAG, 'exported %{public}d cities to %{public}s', visits.length, fileName);
    return filePath;
  }
}
