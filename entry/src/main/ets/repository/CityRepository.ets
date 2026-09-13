import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CityDictFile, CityItem, CountryItem, ProvinceItem } from '../model/CityDict';

const DOMAIN: number = 0x0000;
const TAG: string = 'CityRepository';
const RAW_FILE: string = 'city_dict_v1.json';

/**
 * 城市字典仓储：字典随包发布（rawfile），只读，不打数据库、不联网。
 * 数据来源：公开行政区划边界数据（GCJ-02）+ 民政部行政区划代码。
 */
export class CityRepository {
  private static cities: CityItem[] = [];
  private static byCode: Map<string, CityItem> = new Map<string, CityItem>();
  private static provinceList: string[] = [];
  private static provinceLabelItems: ProvinceItem[] = [];
  private static countryLabelItems: CountryItem[] = [];
  private static version: string = '';
  private static generatedAt: string = '';

  static async load(context: common.UIAbilityContext): Promise<void> {
    if (CityRepository.cities.length > 0) {
      return;
    }
    const bytes: Uint8Array = await context.resourceManager.getRawFileContent(RAW_FILE);
    const text: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
    const file: CityDictFile = JSON.parse(text) as CityDictFile;
    CityRepository.cities = file.cities;
    CityRepository.version = file.version;
    CityRepository.generatedAt = file.generatedAt;

    const index: Map<string, CityItem> = new Map<string, CityItem>();
    const provinces: string[] = [];
    for (const city of file.cities) {
      index.set(city.code, city);
      if (city.parent.length > 0 && !provinces.includes(city.parent)) {
        provinces.push(city.parent);
      }
    }
    CityRepository.byCode = index;
    CityRepository.provinceList = provinces;
    CityRepository.provinceLabelItems = file.provinces === undefined ? [] : file.provinces;
    CityRepository.countryLabelItems = file.countries === undefined ? [] : file.countries;
    hilog.info(DOMAIN, TAG, 'city dict loaded: %{public}d units, %{public}d provinces', file.cities.length,
      provinces.length);
  }

  static all(): CityItem[] {
    return CityRepository.cities;
  }

  static get(code: string): CityItem | undefined {
    return CityRepository.byCode.get(code);
  }

  static total(): number {
    return CityRepository.cities.length;
  }

  static provinces(): string[] {
    return CityRepository.provinceList;
  }

  /** 省级行政区列表（含标签坐标），用于在地图上绘制省份名 */
  static provinceItems(): ProvinceItem[] {
    return CityRepository.provinceLabelItems;
  }

  /** 国家 / 地区名列表（自绘，替代底图自带的国名） */
  static countryItems(): CountryItem[] {
    return CityRepository.countryLabelItems;
  }

  static dictVersion(): string {
    return CityRepository.version;
  }

  static dictGeneratedAt(): string {
    return CityRepository.generatedAt;
  }

  /** 模糊搜索：支持全称、简称、拼音首字母（暂用名称匹配） */
  static search(keyword: string): CityItem[] {
    const key: string = keyword.trim();
    if (key.length === 0) {
      return CityRepository.cities;
    }
    const result: CityItem[] = [];
    for (const city of CityRepository.cities) {
      if (city.name.includes(key) || city.short.includes(key) || city.parent.includes(key)) {
        result.push(city);
      }
    }
    return result;
  }

  /** 找到距离给定坐标最近的城市的（用于：点按地图 → 猜你想点亮哪座城市） */
  static nearest(lat: number, lng: number): CityItem | undefined {
    let best: CityItem | undefined = undefined;
    let bestDistance: number = Number.MAX_VALUE;
    for (const city of CityRepository.cities) {
      const d: number = CityRepository.distanceKm(lat, lng, city.lat, city.lng);
      if (d < bestDistance) {
        bestDistance = d;
        best = city;
      }
    }
    return best;
  }

  /** 两点球面距离（公里） */
  static distanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const rad: number = Math.PI / 180;
    const dLat: number = (lat2 - lat1) * rad;
    const dLng: number = (lng2 - lng1) * rad;
    const a: number = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
    return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }
}
