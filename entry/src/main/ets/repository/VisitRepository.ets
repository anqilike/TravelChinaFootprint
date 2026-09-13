import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper } from './DatabaseHelper';
import { CityVisitStat, VisitRecord } from '../model/VisitRecord';

const TABLE: string = 'visit_record';

/** 到访记录读写 */
export class VisitRepository {
  /** 新增一条到访记录（点亮城市） */
  static async addVisit(adcode: string, visitDate: number, tag: string, note: string, days: number): Promise<void> {
    const store: relationalStore.RdbStore = DatabaseHelper.requireStore();
    const now: number = Date.now();
    const values: relationalStore.ValuesBucket = {
      'id': `${adcode}_${now}_${Math.floor(Math.random() * 10000)}`,
      'adcode': adcode,
      'visit_date': visitDate,
      'leave_date': 0,
      'days': days,
      'tag': tag,
      'note': note,
      'companions': '',
      'created_at': now,
      'updated_at': now,
      'deleted': 0
    };
    await store.insert(TABLE, values);
  }

  /** 批量点亮：单事务，保证原子性 */
  static async addVisitsBatch(adcodes: string[]): Promise<void> {
    const store: relationalStore.RdbStore = DatabaseHelper.requireStore();
    const now: number = Date.now();
    store.beginTransaction();
    try {
      for (const adcode of adcodes) {
        const values: relationalStore.ValuesBucket = {
          'id': `${adcode}_${now}_${Math.floor(Math.random() * 10000)}`,
          'adcode': adcode,
          'visit_date': now,
          'leave_date': 0,
          'days': 0,
          'tag': 'other',
          'note': '',
          'companions': '',
          'created_at': now,
          'updated_at': now,
          'deleted': 0
        };
        await store.insert(TABLE, values);
      }
      store.commit();
    } catch (err) {
      store.rollBack();
      throw err as Error;
    }
  }

  /** 取消点亮：软删除该城市全部到访记录 */
  static async removeCity(adcode: string): Promise<void> {
    const store: relationalStore.RdbStore = DatabaseHelper.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('adcode', adcode);
    const values: relationalStore.ValuesBucket = {
      'deleted': 1,
      'updated_at': Date.now()
    };
    await store.update(values, predicates);
  }

  /**
   * 清除本机全部足迹记录（「我的 → 清除本机足迹数据」）。
   *
   * 用软删除而不是 DELETE：与本仓库其它写操作保持一致，
   * 云同步的合并逻辑靠 deleted 标记判断"这条记录被删过"，
   * 直接物理删除会让下次全量同步把旧记录当成新增又拉回来。
   */
  static async clearAll(): Promise<void> {
    const store: relationalStore.RdbStore = DatabaseHelper.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.notEqualTo('deleted', 1);
    const values: relationalStore.ValuesBucket = {
      'deleted': 1,
      'updated_at': Date.now()
    };
    await store.update(values, predicates);
  }

  /** 读取全部已点亮的城市编码 */
  static async loadVisitedCodes(): Promise<string[]> {
    const store: relationalStore.RdbStore = DatabaseHelper.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('deleted', 0);
    const resultSet: relationalStore.ResultSet = await store.query(predicates, ['adcode']);
    const codes: string[] = [];
    const column: number = resultSet.getColumnIndex('adcode');
    while (resultSet.goToNextRow()) {
      const code: string = resultSet.getString(column);
      if (!codes.includes(code)) {
        codes.push(code);
      }
    }
    resultSet.close();
    return codes;
  }

  /** 读取每个城市的到访统计（次数、首次、最近） */
  static async loadCityStats(): Promise<CityVisitStat[]> {
    const store: relationalStore.RdbStore = DatabaseHelper.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('deleted', 0);
    const resultSet: relationalStore.ResultSet = await store.query(predicates, ['adcode', 'visit_date']);
    const index: Map<string, CityVisitStat> = new Map<string, CityVisitStat>();
    const colCode: number = resultSet.getColumnIndex('adcode');
    const colDate: number = resultSet.getColumnIndex('visit_date');
    while (resultSet.goToNextRow()) {
      const code: string = resultSet.getString(colCode);
      const date: number = resultSet.getLong(colDate);
      const exist: CityVisitStat | undefined = index.get(code);
      if (exist === undefined) {
        index.set(code, { adcode: code, count: 1, firstVisit: date, lastVisit: date });
      } else {
        exist.count = exist.count + 1;
        exist.lastVisit = date > exist.lastVisit ? date : exist.lastVisit;
        exist.firstVisit = date < exist.firstVisit ? date : exist.firstVisit;
      }
    }
    resultSet.close();
    const stats: CityVisitStat[] = [];
    index.forEach((value: CityVisitStat) => {
      stats.push(value);
    });
    return stats;
  }

  /** 读取全部记录（含软删除），用于云同步 */
  static async loadAllRecords(): Promise<VisitRecord[]> {
    const store: relationalStore.RdbStore = DatabaseHelper.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    const resultSet: relationalStore.ResultSet = await store.query(predicates,
      ['id', 'adcode', 'visit_date', 'leave_date', 'days', 'tag', 'note', 'created_at', 'updated_at', 'deleted']);
    const list: VisitRecord[] = [];
    const cId: number = resultSet.getColumnIndex('id');
    const cAdcode: number = resultSet.getColumnIndex('adcode');
    const cVisit: number = resultSet.getColumnIndex('visit_date');
    const cLeave: number = resultSet.getColumnIndex('leave_date');
    const cDays: number = resultSet.getColumnIndex('days');
    const cTag: number = resultSet.getColumnIndex('tag');
    const cNote: number = resultSet.getColumnIndex('note');
    const cCreated: number = resultSet.getColumnIndex('created_at');
    const cUpdated: number = resultSet.getColumnIndex('updated_at');
    const cDeleted: number = resultSet.getColumnIndex('deleted');
    while (resultSet.goToNextRow()) {
      list.push({
        id: resultSet.getString(cId),
        adcode: resultSet.getString(cAdcode),
        visitDate: resultSet.getLong(cVisit),
        leaveDate: resultSet.getLong(cLeave),
        days: resultSet.getLong(cDays),
        tag: resultSet.getString(cTag),
        note: resultSet.getString(cNote),
        createdAt: resultSet.getLong(cCreated),
        updatedAt: resultSet.getLong(cUpdated),
        deleted: resultSet.getLong(cDeleted)
      });
    }
    resultSet.close();
    return list;
  }

  /**
   * 云同步落库：按 id 覆盖写（本地更新的记录不被旧数据覆盖）。
   * 返回真正写入/更新的条数。
   */
  static async mergeFromCloud(records: VisitRecord[]): Promise<number> {
    if (records.length === 0) {
      return 0;
    }
    const store: relationalStore.RdbStore = DatabaseHelper.requireStore();
    let written: number = 0;
    store.beginTransaction();
    try {
      for (const record of records) {
        // 先看本地有没有这条、以及谁的 updatedAt 更新
        const probe: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
        probe.equalTo('id', record.id);
        const rs: relationalStore.ResultSet = await store.query(probe, ['updated_at']);
        let localUpdated: number = -1;
        if (rs.goToNextRow()) {
          localUpdated = rs.getLong(rs.getColumnIndex('updated_at'));
        }
        rs.close();
        if (localUpdated >= record.updatedAt) {
          continue; // 本地更新，保留本地
        }
        const values: relationalStore.ValuesBucket = {
          'id': record.id,
          'adcode': record.adcode,
          'visit_date': record.visitDate,
          'leave_date': record.leaveDate,
          'days': record.days,
          'tag': record.tag,
          'note': record.note,
          'companions': '',
          'created_at': record.createdAt,
          'updated_at': record.updatedAt,
          'deleted': record.deleted
        };
        await store.insert(TABLE, values,
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        written = written + 1;
      }
      store.commit();
    } catch (err) {
      store.rollBack();
      throw err as Error;
    }
    return written;
  }
}
