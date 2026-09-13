import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'DatabaseHelper';

const DDL_VISIT: string = 'CREATE TABLE IF NOT EXISTS visit_record (' +
  'id TEXT PRIMARY KEY, ' +
  'adcode TEXT NOT NULL, ' +
  'visit_date INTEGER, ' +
  'leave_date INTEGER, ' +
  'days INTEGER, ' +
  'tag TEXT, ' +
  'note TEXT, ' +
  'companions TEXT, ' +
  'created_at INTEGER NOT NULL, ' +
  'updated_at INTEGER NOT NULL, ' +
  'deleted INTEGER DEFAULT 0)';

const DDL_INDEX_ADCODE: string = 'CREATE INDEX IF NOT EXISTS idx_visit_adcode ON visit_record(adcode)';
const DDL_INDEX_DATE: string = 'CREATE INDEX IF NOT EXISTS idx_visit_date ON visit_record(visit_date DESC)';
const DDL_INDEX_DIRTY: string = 'CREATE INDEX IF NOT EXISTS idx_visit_dirty ON visit_record(updated_at)';

/**
 * 关系型数据库初始化与迁移。
 * 说明：全部数据仅保存在本机沙箱；首版不做云端同步。
 */
export class DatabaseHelper {
  private static store: relationalStore.RdbStore | undefined = undefined;

  static async init(context: common.UIAbilityContext): Promise<void> {
    if (DatabaseHelper.store !== undefined) {
      return;
    }
    try {
      const config: relationalStore.StoreConfig = {
        name: 'footprint.db',
        securityLevel: relationalStore.SecurityLevel.S1
      };
      const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
      await store.executeSql(DDL_VISIT);
      await store.executeSql(DDL_INDEX_ADCODE);
      await store.executeSql(DDL_INDEX_DATE);
      await store.executeSql(DDL_INDEX_DIRTY);
      DatabaseHelper.store = store;
      hilog.info(DOMAIN, TAG, 'database ready');
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'init database failed: %{public}s', error.message);
      throw new Error(`数据库初始化失败：${error.message}`);
    }
  }

  static requireStore(): relationalStore.RdbStore {
    const store: relationalStore.RdbStore | undefined = DatabaseHelper.store;
    if (store === undefined) {
      throw new Error('database is not initialized');
    }
    return store;
  }
}
