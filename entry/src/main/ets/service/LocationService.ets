import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CityItem } from '../model/CityDict';
import { CityRepository } from '../repository/CityRepository';

const DOMAIN: number = 0x0000;
const TAG: string = 'LocationService';

/**
 * 定位服务：只取一次当前位置，在本机换算成"最近的市州级城市"。
 * 隐私约定：原始经纬度不落库、不上传。
 */
export class LocationService {
  static async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    const permissions: Permissions[] = [
      'ohos.permission.APPROXIMATELY_LOCATION'
    ];
    try {
      const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(context, permissions);
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
      hilog.info(DOMAIN, TAG, 'permission granted: %{public}s', granted ? 'yes' : 'no');
      return granted;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'request permission failed');
      return false;
    }
  }

  /** 返回"当前所在城市"（按最近城市中心点判定） */
  static async detectCurrentCity(): Promise<CityItem | undefined> {
    try {
      const request: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        scenario: geoLocationManager.LocationRequestScenario.UNSET,
        timeoutMs: 5000
      };
      const location: geoLocationManager.Location = await geoLocationManager.getCurrentLocation(request);
      const city: CityItem | undefined = CityRepository.nearest(location.latitude, location.longitude);
      if (city !== undefined) {
        const distance: number = CityRepository.distanceKm(location.latitude, location.longitude, city.lat, city.lng);
        hilog.info(DOMAIN, TAG, 'nearest city %{public}s distance %{public}f km', city.name, distance);
      }
      return city;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'get current location failed');
      return undefined;
    }
  }
}
