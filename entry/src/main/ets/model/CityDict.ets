/** 点亮单元层级 */
export enum CityLevel {
  /** 直辖市 */
  MUNICIPALITY = 'municipality',
  /** 地级市 / 自治州 / 地区 / 盟 / 省直辖县级 */
  CITY = 'city',
  /** 特别行政区 */
  SAR = 'sar',
  /** 省级整体（台湾省） */
  PROVINCE = 'province'
}

/** 城市字典条目（一个可点亮的市州级单元） */
export interface CityItem {
  /** 行政区划代码，唯一主键 */
  code: string;
  /** 全称，如"杭州市" */
  name: string;
  /** 简称，如"杭州" */
  short: string;
  /** 层级，取值见 CityLevel */
  level: string;
  /** 所属省级行政区名称 */
  parent: string;
  /** 所属省级行政区代码 */
  parentCode: string;
  /** 中心点经度（GCJ-02） */
  lng: number;
  /** 中心点纬度（GCJ-02） */
  lat: number;
}

/** 省级行政区（用于地图上的省份名标注） */
export interface ProvinceItem {
  /** 省级行政区划代码 */
  code: string;
  /** 全称 */
  name: string;
  /** 简称：内蒙古自治区 → 内蒙古 */
  short: string;
  /** 标签位置（几何重心，GCJ-02） */
  lng: number;
  lat: number;
  /** 该省行政中心的行政区划代码（省会） */
  capitalCode: string;
}

/**
 * 国家 / 地区名（自绘）。
 * 底图自带的国名会被画在中国正中央、压住河北/山西/宁夏几个省名，
 * 且位置不可控；因此改为在样式里把「国家」整类隐藏，由 App 自己绘制。
 */
export interface CountryItem {
  /** 显示名，如"蒙古" */
  name: string;
  /** 标签锚点经度（GCJ-02） */
  lng: number;
  lat: number;
}

/** 城市字典文件结构 */
export interface CityDictFile {
  version: string;
  generatedAt: string;
  source: string;
  total: number;
  countries?: CountryItem[];
  provinces: ProvinceItem[];
  cities: CityItem[];
}
