import { cloudDatabase } from '@kit.CloudFoundationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VisitRecord } from '../model/VisitRecord';

const DOMAIN: number = 0x0000;
const TAG: string = 'CloudSyncService';
/** 云数据库分区名（AGC 端创建云数据库时的 zone 名，默认 default） */
const ZONE_NAME: string = 'default';
/** AGC 端"对象类型"名称，必须与云侧创建的完全一致 */
const OBJECT_TYPE: string = 'visit_record';
/** 单页拉取条数（云数据库单次查询有上限，超出需要翻页） */
const PAGE_SIZE: number = 500;

/**
 * 云侧实体：字段名必须与 AGC「对象类型 visit_record」里的字段一一对应。
 *
 * AGC 侧需要创建的对象类型（云数据库 → 对象类型 visit_record）：
 *   recordId   String   设备端记录 id（唯一）
 *   userOpenId String   华为账号 openID（数据归属，按它隔离每个用户）
 *   adcode     String   行政区划代码
 *   visitDate  Long     到访时间戳
 *   leaveDate  Long     离开时间戳（0 表示未知）
 *   days       Long     停留天数
 *   tag        String   到访标签
 *   note       String   备注
 *   updatedAt  Long     最后修改时间（用于冲突时"取新"）
 *   deleted    Long     软删除标记
 */
class VisitRecordCloud extends cloudDatabase.DatabaseObject {
  recordId: string = '';
  userOpenId: string = '';
  adcode: string = '';
  visitDate: number = 0;
  leaveDate: number = 0;
  days: number = 0;
  tag: string = '';
  note: string = '';
  updatedAt: number = 0;
  deleted: number = 0;

  naturalbase_ClassName(): string {
    return OBJECT_TYPE;
  }
}

/**
 * 云同步（端云一体化 · 云数据库）。
 *
 * 前置条件（AGC 控制台，一次即可）：
 *  1. 在 AGC 项目里开通「云开发 / 端云一体化」；
 *  2. 在「云数据库」里按上面的说明创建对象类型 visit_record；
 *  3. 应用侧无需新增权限（云数据库只需要 ohos.permission.INTERNET，已在 module.json5 声明）。
 *
 * 未开通时所有调用都会抛错（典型错误码 1008230002 Schema config error），
 * 这里统一转成可读文案，界面上提示"云同步未开通"，不影响本地功能。
 */
export class CloudSyncService {
  private static zone: cloudDatabase.DatabaseZone | undefined = undefined;

  private static getZone(): cloudDatabase.DatabaseZone {
    if (CloudSyncService.zone === undefined) {
      CloudSyncService.zone = cloudDatabase.zone(ZONE_NAME);
    }
    return CloudSyncService.zone;
  }

  /** 把本地记录推到云端（按 recordId 覆盖写） */
  static async push(openId: string, records: VisitRecord[]): Promise<number> {
    if (records.length === 0) {
      return 0;
    }
    const payload: VisitRecordCloud[] = [];
    for (const record of records) {
      const item: VisitRecordCloud = new VisitRecordCloud();
      item.recordId = record.id;
      item.userOpenId = openId;
      item.adcode = record.adcode;
      item.visitDate = record.visitDate;
      item.leaveDate = record.leaveDate;
      item.days = record.days;
      item.tag = record.tag;
      item.note = record.note;
      item.updatedAt = record.updatedAt;
      item.deleted = record.deleted;
      payload.push(item);
    }
    try {
      const affected: number = await CloudSyncService.getZone().upsert(payload);
      hilog.info(DOMAIN, TAG, 'cloud push ok: %{public}d', affected);
      return affected;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'cloud push failed: %{public}s', JSON.stringify(err));
      throw new Error(CloudSyncService.friendlyError(err));
    }
  }

  /** 拉取当前账号在云端的全部记录 */
  static async pull(openId: string): Promise<VisitRecord[]> {
    const all: VisitRecord[] = [];
    try {
      let offset: number = 0;
      while (true) {
        const query: cloudDatabase.DatabaseQuery<VisitRecordCloud> =
          new cloudDatabase.DatabaseQuery(VisitRecordCloud);
        query.equalTo('userOpenId', openId);
        query.limit(PAGE_SIZE, offset);
        const page: VisitRecordCloud[] = await CloudSyncService.getZone().query(query);
        for (const item of page) {
          all.push({
            id: item.recordId,
            adcode: item.adcode,
            visitDate: item.visitDate,
            leaveDate: item.leaveDate,
            days: item.days,
            tag: item.tag,
            note: item.note,
            createdAt: item.visitDate,
            updatedAt: item.updatedAt,
            deleted: item.deleted
          });
        }
        if (page.length < PAGE_SIZE) {
          break;
        }
        offset = offset + PAGE_SIZE;
      }
      hilog.info(DOMAIN, TAG, 'cloud pull ok: %{public}d', all.length);
      return all;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'cloud pull failed: %{public}s', JSON.stringify(err));
      throw new Error(CloudSyncService.friendlyError(err));
    }
  }

  /** 把云数据库的错误码翻成人话 */
  private static friendlyError(err: Object): string {
    const code: number = (err as Record<string, Object>)['code'] as number;
    if (code === 1008230002) {
      return '云同步还没开通：请先在 AGC 创建对象类型 visit_record';
    }
    if (code === 1008230001) {
      return '网络异常，请检查网络后重试';
    }
    if (code === 201) {
      return '缺少网络权限';
    }
    return '云同步失败，请稍后重试';
  }
}
