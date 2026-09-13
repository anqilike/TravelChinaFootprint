/** 到访标签 */
export enum VisitTag {
  BUSINESS = 'business',
  TRAVEL = 'travel',
  FAMILY = 'family',
  TRANSIT = 'transit',
  LIVE = 'live',
  OTHER = 'other'
}

/** 一条到访记录 */
export interface VisitRecord {
  id: string;
  adcode: string;
  visitDate: number;
  leaveDate: number;
  days: number;
  tag: string;
  note: string;
  createdAt: number;
  updatedAt: number;
  deleted: number;
}

/** 单个城市的到访汇总 */
export interface CityVisitStat {
  adcode: string;
  count: number;
  firstVisit: number;
  lastVisit: number;
}

/** 标签的中文名 */
export function tagLabel(tag: string): string {
  switch (tag) {
    case VisitTag.BUSINESS:
      return '出差';
    case VisitTag.TRAVEL:
      return '旅行';
    case VisitTag.FAMILY:
      return '探亲';
    case VisitTag.TRANSIT:
      return '路过';
    case VisitTag.LIVE:
      return '居住';
    default:
      return '其他';
  }
}
