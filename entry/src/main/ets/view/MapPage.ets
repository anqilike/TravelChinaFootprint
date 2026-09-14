import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { curves } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { CityItem, CountryItem, ProvinceItem } from '../model/CityDict';
import { CityRepository } from '../repository/CityRepository';
import { FootprintListener, footprintStore } from '../viewmodel/FootprintStore';
import { LocationService } from '../service/LocationService';
import { Dimens, MapDefaults, MapLabelStyle, Motion, Palette } from '../common/Theme';
import { WindowService } from '../common/WindowService';

const DOMAIN: number = 0x0000;
const TAG: string = 'MapPage';

/** 打卡标签选项 */
interface TagOption {
  value: string;
  label: string;
}

/** 地图上的城市名标注（由经纬度投影到屏幕坐标后绘制） */
interface CityLabel {
  code: string;
  name: string;
  /** 标签中心的屏幕坐标（vp）。城市标签的 y 已含下移偏移，不再是点位本身 */
  x: number;
  y: number;
  /** 该标签"本来应该在"的锚点位置（vp）：被挤开时用它画虚线牵引线指回去 */
  anchorX: number;
  anchorY: number;
  /** 是否被挤离锚点（true 时画一条虚线从锚点连到标签） */
  leader: boolean;
  visited: boolean;
  /** 'province' = 省名（大一号、无底色）；'city' = 地级市名 */
  kind: string;
  /** 标签尺寸（vp）：由字数与字号估算，用于避让排布和精确居中 */
  w: number;
  h: number;
  /** 排布优先级，数字越小越优先占位 */
  priority: number;
}

/** 城市标签相对点位的下移距离（vp），避免压住圆点 */
const CITY_LABEL_OFFSET: number = 9;
/** 标签之间的最小间隙（vp） */
const LABEL_GAP: number = 2;
/**
 * 省名允许的**字形**重叠比例（不是包围盒）。
 * 全国视野下东部省份挨得很近，若要求"零重叠"，山东、江西这些会被整片挤掉；
 * 放到 40% 后：山东(与河北≈11%)、江西(与湖南≈33%) 能显示，
 * 而天津(与北京≈49%)、香港/澳门(与广东≈48~52%) 仍会自动隐藏——
 * 正好符合"位置必须准确，挤不下的宁可不显示"的规则。
 */
const PROVINCE_OVERLAP_TOLERANCE: number = 0.25;
/** 与底图国名允许的字形重叠（几乎为 0，只是留一点像素级余量） */
const RESERVED_OVERLAP_TOLERANCE: number = 0.1;
/**
 * 汉字字形相对包围盒的收缩比例。
 * 包围盒 = 字形 + 安全留白，实际墨迹只有约 0.80 宽、0.53 高
 * （11.9vp 字号：字宽 11.9、字高约 10.5，而包围盒是 29.8×19.9）。
 * 之前取 0.62 偏高，把"其实没压上"的省份（河北 vs 北京）也判成冲突了。
 */
const INK_WIDTH_RATIO: number = 0.8;
const INK_HEIGHT_RATIO: number = 0.53;
/**
 * 标注字号（vp），**按底图实测值反推**：
 * 在真机截图里量底图国名"中华人民共和国"的"中"字，字形高 38px = 10.9vp，
 * CJK 字形约占 0.88em → 底图字号 ≈ 12.3vp。
 * 因此这里取省名 12、城市名 11（省名略大形成层级），字重统一 Medium，
 * 与底图笔画粗细一致，不再出现"我们的字又大又浅"的割裂感。
 */
const PROVINCE_FONT_SIZE: number = 11.9;
const CITY_FONT_SIZE: number = 11.9;

/**
 * 国家名（自绘）字号。
 * 底图自带的国家名已在 Petal Maps Studio 里整类隐藏——它固定画在中国正中央，
 * 会压住河北 / 山西 / 宁夏几个省名，而且我们挪不动它。
 * 改由自己绘制后，它和省市名一起参与避让，位置也由我们决定。
 */
const COUNTRY_FONT_SIZE: number = 11.9;

/**
 * 全国视野下不标的省级行政区（用户已确认可以隐藏）。
 * 天津被北京/河北夹住、香港澳门紧贴广东，在这个缩放级别它们的名字与邻省**必然重叠**
 * （实测：天津↔北京字形重叠 44%，香港/澳门↔广东 45%+），与其糊成一团不如不标。
 * 放大到 zoom≥4.5 进入省会层后，它们会以"省会/特别行政区"的身份自然出现。
 */
const NATIONAL_SKIP_CODES: string[] = ['120000', '810000', '820000'];

/**
 * 自定义地图样式（Petal Maps Studio 发布）。
 * 样式内容：隐藏「行政区划 → 主要城市」的标签要素，
 *          去掉底图自带的城市点位符号，避免与 App 自己绘制的 370 个城市点位重叠。
 * 样式 ID 为发布后的唯一 ID，在 Studio 中修改样式后所有使用该 ID 的应用自动生效。
 */
const MAP_STYLE_ID: string = '2038502036122762880';

/**
 * 34 个省级行政区的行政中心（省会 / 首府 / 直辖市 / 港澳台）行政区划代码。
 * 用于分级标注：【低缩放】只显示省会 + 底图的省份名；【放大后】再显示全部地级市。
 */
const CAPITAL_CODES: string[] = [
  '110000', '120000', '130100', '140100', '150100', '210100',
  '220100', '230100', '310000', '320100', '330100', '340100',
  '350100', '360100', '370100', '410100', '420100', '430100',
  '440100', '450100', '460100', '500000', '510100', '520100',
  '530100', '540100', '610100', '620100', '630100', '640100',
  '650100', '710000', '810000', '820000'
];

/**
 * 足迹地图（P-02）。
 * 实现路线：华为 Map Kit 底图 + 370 个城市点位（指导书附录 G "点位方案"）。
 * 合规要点：
 *  1) 底图使用华为地图服务，审图号通过 setApproveNumberEnabled 显示；
 *  2) 不自行绘制行政区边界几何，只做标注（属于法规允许的"增值服务—标注"）；
 *  3) 不遮挡地图 Logo。
 */
@ComponentV2
export struct MapPage {
  private mapOptions?: mapCommon.MapOptions;
  private callback?: AsyncCallback<map.MapComponentController>;
  private controller?: map.MapComponentController;
  private markers: Map<string, map.Marker> = new Map<string, map.Marker>();
  private listener: FootprintListener = (code: string, visited: boolean) => {
    this.syncMarker(code, visited);
    // 点亮状态变化会影响城市名的颜色，需要刷新标注
    this.updateCityLabels();
  };

  @Local mapReady: boolean = false;
  @Local hint: string = '地图加载中…';
  @Local sheetShown: boolean = false;
  @Local selectedCode: string = '';
  @Local locating: boolean = false;
  @Local showUnvisited: boolean = true;
  /** 当前是否处于"能看清细节"的缩放级别（用于点位疏密控制） */
  @Local detailZoom: boolean = false;
  /** 沉浸式布局下需要避开的状态栏 / 手势条高度（vp） */
  @Local safeTop: number = 0;
  @Local safeBottom: number = 0;
  /** 打卡表单：标签与备注 */
  @Local selectedTag: string = 'other';
  @Local noteInput: string = '';

  /** 记录每个点位当前的透明度，避免重复下发原生指令 */
  private markerAlpha: Map<string, number> = new Map<string, number>();
  /** 当前屏幕上的城市名标注 */
  @Local cityLabels: CityLabel[] = [];
  /** 地图容器尺寸（vp），用于判断标注是否在视野内 */
  private mapWidth: number = 0;
  private mapHeight: number = 0;
  /** 标签刷新重试计数（容器尺寸未就绪时用） */
  private labelRetry: number = 0;
  /** 上一次"跟随相机"刷新标注的时间戳（毫秒），用于节流 */
  private lastCameraTick: number = 0;
  /** 点位闪烁定时器句柄 */
  private blinkTimer: number = -1;
  /** 每座城市的闪烁周期与相位缓存（由行政区划代码派生，稳定不变） */
  private blinkParams: Map<string, number[]> = new Map<string, number[]>();
  /** 自己识别点按时，记录按下位置与时刻 */
  private touchDownX: number = 0;
  private touchDownY: number = 0;
  private touchDownAt: number = 0;
  /** 本次触摸是否已经移动超过容差（移动过就不算点击） */
  private touchMoved: boolean = false;
  /** 上一次处理点按的时刻：地图自己的 mapClick 与我们的 onTouch 会同时命中同一次点按，用它去重 */
  private lastPickAt: number = 0;
  /** TODO 临时诊断：被挤掉的省名（地图 SDK 日志刷爆配额，hilog 会被丢弃，只能画在屏幕上） */
  @Local debugDropped: string = '';
  /**
   * 由父组件传入：当前是否停留在本页。
   * 点位闪烁只在页面可见时跑，切走就停（省电），切回来接着闪。
   */
  @Param active: boolean = true;

  @Monitor('active')
  onActiveChanged(): void {
    if (this.active) {
      this.startBlinking();
    } else {
      this.stopBlinking();
    }
  }
  /**
   * 悬浮控件入场标记：地图就绪后置 true，
   * 让顶部胶囊 / 图例淡入并轻微下滑，而不是"啪"地一下出现。
   */
  @Local chromeIn: boolean = false;

  /**
   * 相机变化时的标注刷新（拖动地图时名字跟着走）。
   * 节流到约 60ms 一次：太频繁会拖慢地图渲染，太稀疏会看着"卡"。
   */
  private onCameraChanged(): void {
    const now: number = Date.now();
    if (now - this.lastCameraTick < 60) {
      return;
    }
    this.lastCameraTick = now;
    this.updateCityLabels();
  }

  aboutToAppear(): void {
    this.safeTop = WindowService.safeTop;
    this.safeBottom = WindowService.safeBottom;
    this.mapOptions = {
      position: {
        target: { latitude: MapDefaults.centerLat, longitude: MapDefaults.centerLng },
        zoom: MapDefaults.zoom
      }
    };
    this.callback = (err: BusinessError | undefined, controller: map.MapComponentController | undefined) => {
      if (err !== undefined && err !== null) {
        this.hint = `地图加载失败（错误码 ${err.code}）。请确认已在 AGC 开通"地图服务"并重新申请调试 Profile。`;
        hilog.error(DOMAIN, TAG, 'map init failed: %{public}s', JSON.stringify(err));
        return;
      }
      if (controller === undefined) {
        this.hint = '地图初始化失败';
        return;
      }
      this.controller = controller;
      this.setupMap(controller);
    };
    footprintStore.subscribe(this.listener);
    this.startBlinking();
  }

  aboutToDisappear(): void {
    footprintStore.unsubscribe(this.listener);
    this.stopBlinking();
  }

  /**
   * 启动"已点亮点位闪烁"。
   *
   * 做法：每 80ms 按 sine 曲线给每个已点亮 marker 下发一次透明度，
   * 周期和相位由城市代码派生 —— 每座城市都不一样，所以永远不会同步闪，
   * 远远一看就是一片"呼吸着的金点"，去过哪里一目了然。
   */
  private startBlinking(): void {
    if (this.blinkTimer !== -1) {
      return;
    }
    this.blinkTimer = setInterval(() => {
      this.tickBlink();
    }, MapDefaults.blinkIntervalMs);
  }

  private stopBlinking(): void {
    if (this.blinkTimer === -1) {
      return;
    }
    clearInterval(this.blinkTimer);
    this.blinkTimer = -1;
  }

  private tickBlink(): void {
    if (this.markers.size === 0) {
      return;
    }
    const now: number = Date.now();
    const span: number = MapDefaults.blinkBrightAlpha - MapDefaults.blinkDimAlpha;
    this.markers.forEach((marker: map.Marker, code: string) => {
      if (!footprintStore.isVisited(code)) {
        return;
      }
      const params: number[] = this.blinkParam(code);
      // sine 相位：0 → 暗，0.5 → 最亮
      const k: number = 0.5 + 0.5 * Math.sin(2 * Math.PI * (now / params[0] + params[1]));
      const alpha: number = MapDefaults.blinkDimAlpha + span * k;
      this.markerAlpha.set(code, alpha);
      marker.setAlpha(alpha);
    });
  }

  /** 由城市代码派生出 [周期ms, 相位0~1]，同一座城市每次都一样 */
  private blinkParam(code: string): number[] {
    const cached: number[] | undefined = this.blinkParams.get(code);
    if (cached !== undefined) {
      return cached;
    }
    let h1: number = 17;
    let h2: number = 31;
    for (let i = 0; i < code.length; i++) {
      const c: number = code.charCodeAt(i);
      h1 = (h1 * 31 + c) % 100000;
      h2 = (h2 * 37 + c) % 100000;
    }
    const period: number = MapDefaults.blinkMinPeriodMs + (h1 % MapDefaults.blinkPeriodRangeMs);
    const phase: number = (h2 % 1000) / 1000;
    const params: number[] = [period, phase];
    this.blinkParams.set(code, params);
    return params;
  }

  /**
   * 地图初始化顺序很重要：
   * setCustomMapStyle 会清空地图上的覆盖物，所以必须"先改样式、再画点位"，
   * 否则刚加好的 370 个 marker 会被样式清掉。
   */
  private async setupMap(controller: map.MapComponentController): Promise<void> {
    // 关键顺序：先应用自定义样式（会清空地图覆盖物），再画点位
    await this.applyCustomStyle(controller);
    this.bindMapEvents(controller);
    await this.renderAllMarkers();
    this.updateCityLabels();
    // 点位就绪即视为地图可用，清掉"加载中"提示（mapLoad 事件在改样式后可能不再触发）
    this.mapReady = true;
    this.hint = '';
    // 让悬浮控件跟着淡入（延迟一帧，保证初值先渲染出来）
    setTimeout(() => {
      this.chromeIn = true;
    }, 60);
  }

  /** 应用 Petal Maps Studio 发布的地图样式 */
  private async applyCustomStyle(controller: map.MapComponentController): Promise<void> {
    const options: mapCommon.CustomMapStyleOptions = { styleId: MAP_STYLE_ID };
    try {
      await controller.setCustomMapStyle(options);
      hilog.info(DOMAIN, TAG, 'custom map style applied: %{public}s', MAP_STYLE_ID);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'setCustomMapStyle failed: %{public}d %{public}s', error.code, error.message);
    }
  }

  private bindMapEvents(controller: map.MapComponentController): void {
    // 合规：显示审图号（仅在境内显示），这是"在地图显著位置标明审图号"要求的标准做法
    try {
      controller.setApproveNumberEnabled(true);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setApproveNumberEnabled not available');
    }

    // 关闭底图自带控件：缩放按钮 / 指南针 / 比例尺 / 定位按钮。
    // 原因有二：
    //  1) 它们会和 App 自绘的悬浮控件叠在一起（"按钮打架"）；
    //  2) 自带控件是浅色实心样式，和暗色玻璃 UI 不统一。
    // 关闭后由 this.controlStack() 提供一套同风格控件。
    try {
      controller.setZoomControlsEnabled(false);
      controller.setCompassControlsEnabled(false);
      controller.setScaleControlsEnabled(false);
      controller.setMyLocationControlsEnabled(false);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'disable built-in map controls failed');
    }

    // 花瓣地图 Logo 与审图号必须常驻可见（合规要求），
    // 这里把它从屏幕最底部往上抬，避免被悬浮导航条压住。
    try {
      controller.setLogoPadding({ bottom: vp2px(96 + this.safeBottom) });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setLogoPadding failed');
    }

    const manager: map.MapEventManager = controller.getEventManager();
    manager.on('mapLoad', () => {
      this.mapReady = true;
      this.hint = '';
      this.renderAllMarkers();
    });
    manager.on('cameraIdle', () => {
      this.applyDeclutter();
      // 相机停下后重算城市名标注
      this.updateCityLabels();
    });
    // 地图移动过程中也要跟着刷新标注。
    // 之前只在 cameraIdle 重算，导致"拖动地图时名字钉在原地、停下才重画"——
    // 这里监听 cameraChange（相机变化即回调），配合节流让名字跟着地图一起走。
    manager.on('cameraChange', () => {
      this.onCameraChanged();
    });
    // 手势被取消时不会触发 cameraIdle，如果不补一次，标注会一直空着
    manager.on('cameraMoveCancel', () => {
      this.updateCityLabels();
    });
    manager.on('mapClick', (latLng: mapCommon.LatLng) => {
      this.handleMapClick(latLng);
    });
    manager.on('cameraMoveStart', () => {
      // 不再清空标注：现在由 cameraChange 逐帧跟随，清空反而会闪一下
      this.onCameraChanged();
    });
    manager.on('markerClick', (marker: map.Marker) => {
      const code: string = marker.getTitle();
      if (code !== undefined && code.length > 0) {
        this.openCity(code);
      }
    });
    manager.on('error', (error: BusinessError) => {
      this.hint = `地图服务异常（${error.code}）：请检查地图服务是否已开通`;
      hilog.error(DOMAIN, TAG, 'map error: %{public}s', JSON.stringify(error));
    });
  }

  /**
   * 计算当前视野内需要显示的标注，并在自绘标签之间做避让。
   *
   * 职责边界（与 Petal Maps Studio 样式的约定，实测结论）：
   *  · 道路、国界、地形、国家名 → 由华为底图提供（样式里已把"道路""国家"设为展示）；
   *  · **省名 → 由 App 自绘**。实测底图在 z3.6~z6.6 这些常用级别根本不画省名，
   *    只靠底图会导致"全国视野看不到省份"，所以省名必须自己标；
   *  · 地级市名 → 由 App 自绘（底图的城市要素已关闭，避免"空心圈 + 实心点"两套点位重叠）。
   *
   * 分级策略：
   *  · 缩放 < nameZoom：省名 + 34 个省会/首府；
   *  · 缩放 ≥ nameZoom：铺开全部 370 个地级市名，省名退场，避免和密集城市名打架。
   * 优先级：已点亮 > 省会 > 省名 > 其他地级市。
   *
   * 为什么省会优先于省名：在全国视野下，一个 15vp 的汉字约等于 200 公里，
   * 省名标签的包围盒会盖住大半个省，而省会几乎总在省名附近（几何重心≈省会）。
   * 若省名优先，省会会被整片挤掉（实测 34 个省会全部消失）。
   * 因此这里让省会先占位，省名去填西部那些空旷区域，两边都不至于没有名字。
   */
  private updateCityLabels(): void {
    const controller: map.MapComponentController | undefined = this.controller;
    if (controller === undefined || this.mapWidth <= 0 || this.mapHeight <= 0) {
      this.cityLabels = [];
      // 容器尺寸还没测量出来时（启动瞬间 MapKit 回调可能先于 onAreaChange），
      // 有限次重试，避免"标注算不出来又没人再触发"的空窗
      if (this.labelRetry < 6) {
        this.labelRetry = this.labelRetry + 1;
        setTimeout(() => {
          this.updateCityLabels();
        }, 300);
      }
      return;
    }
    this.labelRetry = 0;
    let zoom: number = MapDefaults.zoom;
    try {
      zoom = controller.getCameraPosition().zoom;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getCameraPosition failed');
    }
    // 三段式分级：省名 → 省会 → 地级市，任何时刻只出现其中一层，避免同屏"两种名字"打架
    const provincesOnly: boolean = zoom < MapDefaults.capitalZoom;
    const capitalsOnly: boolean = zoom < MapDefaults.nameZoom;
    const projection: map.Projection = controller.getProjection();

    // ① 收集候选标签
    const pool: CityLabel[] = [];

    // ⓪ 国家 / 地区名：自绘（底图的国名已整类隐藏）。
    //    它们先占位，并作为"保留区"供省名 / 市名避让，保证国名不被压。
    const countryItems: CountryItem[] = CityRepository.countryItems();
    for (const country of countryItems) {
      const cp: mapCommon.MapPoint =
        projection.toScreenLocation({ latitude: country.lat, longitude: country.lng });
      const cx: number = px2vp(cp.positionX);
      const cy: number = px2vp(cp.positionY);
      // 国家名要求"整条都在屏幕内"，否则边缘会出现被切掉半截的国名（很难看）
      const halfW: number = (country.name.length * COUNTRY_FONT_SIZE + 6) / 2;
      if (cx - halfW < 8 || cx + halfW > this.mapWidth - 8 ||
        cy < this.safeTop + 60 || cy > this.mapHeight - 110) {
        continue;
      }
      pool.push({
        code: `C_${country.name}`,
        name: country.name,
        x: cx,
        y: cy,
        anchorX: cx,
        anchorY: cy,
        leader: false,
        w: country.name.length * COUNTRY_FONT_SIZE + 6,
        h: COUNTRY_FONT_SIZE + 8,
        visited: false,
        kind: 'country',
        priority: 0
      });
    }

    // 第一级：省名（底图自带的国家名同屏显示，正好构成"国家 + 省"的全国视野）
    if (provincesOnly) {
      const provinceItems: ProvinceItem[] = CityRepository.provinceItems();
      for (const province of provinceItems) {
        if (NATIONAL_SKIP_CODES.includes(province.code)) {
          continue;
        }
        // 这一层不画任何城市名，所以直辖市 / 特别行政区 / 台湾也按"省级"一起标出来，
        // 保证全国视野下 34 个省级行政区都能看到名字。
        const provincePoint: mapCommon.MapPoint =
          projection.toScreenLocation({ latitude: province.lat, longitude: province.lng });
        const px: number = px2vp(provincePoint.positionX);
        const py: number = px2vp(provincePoint.positionY);
        if (px < -60 || py < -60 || px > this.mapWidth + 60 || py > this.mapHeight + 60) {
          continue;
        }
        pool.push({
          code: province.code,
          name: province.short,
          x: px,
          y: py,
          anchorX: px,
          anchorY: py,
          leader: false,
          w: province.short.length * PROVINCE_FONT_SIZE + 6,
          h: PROVINCE_FONT_SIZE + 8,
          visited: false,
          kind: 'province',
          priority: 1
        });
      }
    }

    // 第二 / 三级：省会 → 全部地级市（省名退场，不同时显示）
    if (!provincesOnly) {
      const cities: CityItem[] = CityRepository.all();
      for (const city of cities) {
        const isCapital: boolean = CAPITAL_CODES.includes(city.code);
        if (capitalsOnly && !isCapital) {
          continue;
        }
        const position: mapCommon.LatLng = { latitude: city.lat, longitude: city.lng };
        const point: mapCommon.MapPoint = projection.toScreenLocation(position);
        const x: number = px2vp(point.positionX);
        const y: number = px2vp(point.positionY);
        if (x < -40 || y < -40 || x > this.mapWidth + 40 || y > this.mapHeight + 40) {
          continue;
        }
        const visited: boolean = footprintStore.isVisited(city.code);
        pool.push({
          code: city.code,
          name: city.short,
          x: x,
          y: y + CITY_LABEL_OFFSET,
          anchorX: x,
          anchorY: y + CITY_LABEL_OFFSET,
          leader: false,
          w: city.short.length * CITY_FONT_SIZE + 6,
          h: CITY_FONT_SIZE + 7,
          visited: visited,
          kind: 'city',
          priority: visited ? 1 : (isCapital ? 3 : 4)
        });
      }
    }
    pool.sort((a: CityLabel, b: CityLabel) => a.priority - b.priority);

    // ② 按优先级贪心占位：与本屏已放置的标签冲突就跳过，保证屏幕上的名字不互相压字
    const placed: CityLabel[] = [];
    const boxes: number[] = [];
    /** 国家名单独留一份，作为"硬保留区"给省市名避让 */
    const reserved: number[] = [];
    for (const label of pool) {
      if (placed.length >= MapDefaults.maxLabels) {
        break;
      }
      const spot: CityLabel | undefined = this.findSpot(label, boxes, reserved);
      if (spot === undefined) {
        continue;
      }
      placed.push(spot);
      boxes.push(spot.x - spot.w / 2, spot.y - spot.h / 2,
        spot.x + spot.w / 2, spot.y + spot.h / 2);
      if (spot.kind === 'country') {
        reserved.push(spot.x - spot.w / 2, spot.y - spot.h / 2,
          spot.x + spot.w / 2, spot.y + spot.h / 2);
      }
    }
    this.cityLabels = placed;
    hilog.info(DOMAIN, TAG, 'labels zoom=%{public}d placed=%{public}d', Math.round(zoom), placed.length);
    // 把"被挤掉的省名"打进日志，方便用数据调排版，不用靠肉眼数截图
    let dropped: string = '';
    for (const label of pool) {
      if (label.kind !== 'province') {
        continue;
      }
      let found: boolean = false;
      for (const item of placed) {
        if (item.code === label.code) {
          found = true;
          break;
        }
      }
      if (!found) {
        dropped = dropped.length === 0 ? label.name : `${dropped},${label.name}`;
      }
    }
    hilog.info(DOMAIN, TAG, 'dropped=%{public}s', dropped);
    this.debugDropped = dropped;
  }

  /**
   * 给标签找位置。核心原则：**名字必须落在它自己的位置上，位置准确优先于"全都显示"**。
   *
   *  1) 底图国名（保留区）：硬约束，一点都不许压；
   *  2) 城市名：与已有标签冲突就放弃（放大后自然出现，符合真实地图的标注抽稀）；
   *  3) 省名：**锚点固定、绝不平移**。允许包围盒有小幅重叠（≤25%），
   *     这样东部密集省份（山东、江西…）能显示出来；重叠过大的（天津、香港、澳门）
   *     直接不显示——"宁可少标，也不把名字挪到别人家门口"。
   *
   * 注：`anchorX/anchorY` 与 `leader` 字段保留给后续可能启用的虚线牵引方案，目前不使用。
   */
  private findSpot(label: CityLabel, boxes: number[],
    reserved: number[]): CityLabel | undefined {
    // 底图国名：按"字形重叠"判断，留一点余量（≤10%），基本等于绝不压上去
    if (this.inkOverlapRatio(label, reserved) > RESERVED_OVERLAP_TOLERANCE) {
      return undefined;
    }
    if (label.kind !== 'province') {
      // 城市名：一格都不让
      return this.boxFree(label.x, label.y, label.w, label.h, boxes) ? label : undefined;
    }
    // 省名：原地放置，但允许小面积重叠（密集区要靠这一点才显示得出来）
    if (this.inkOverlapRatio(label, boxes) <= PROVINCE_OVERLAP_TOLERANCE) {
      return label;
    }
    return undefined;
  }

  /**
   * 两个标签"实际字形"（去掉包围盒留白）的重叠比例。
   *
   * 为什么不能直接用包围盒：包围盒是"字形 + 安全留白"，比字形本身大一圈，
   * 用它判重叠会把大量只是"挨得近"的省名误杀（实测河北、山东、江西都被误杀）。
   * 这里按汉字的实际墨迹比例收缩后再算：宽 ×0.82、高 ×0.62。
   */
  private inkOverlapRatio(label: CityLabel, boxes: number[]): number {
    const w: number = label.w * INK_WIDTH_RATIO;
    const h: number = label.h * INK_HEIGHT_RATIO;
    const x1: number = label.x - w / 2;
    const x2: number = label.x + w / 2;
    const y1: number = label.y - h / 2;
    const y2: number = label.y + h / 2;
    let total: number = 0;
    for (let i: number = 0; i + 3 < boxes.length; i += 4) {
      const bw: number = (boxes[i + 2] - boxes[i]) * INK_WIDTH_RATIO;
      const bh: number = (boxes[i + 3] - boxes[i + 1]) * INK_HEIGHT_RATIO;
      const bcx: number = (boxes[i] + boxes[i + 2]) / 2;
      const bcy: number = (boxes[i + 1] + boxes[i + 3]) / 2;
      const ox: number = Math.min(x2, bcx + bw / 2) - Math.max(x1, bcx - bw / 2);
      const oy: number = Math.min(y2, bcy + bh / 2) - Math.max(y1, bcy - bh / 2);
      if (ox > 0 && oy > 0) {
        total = total + ox * oy;
      }
    }
    return total / (w * h);
  }

  /** 标签框与已放置标签的总重叠面积（vp²），用于省名的"允许少量重叠"判断 */
  private overlapArea(x: number, y: number, w: number, h: number, boxes: number[]): number {
    const x1: number = x - w / 2;
    const x2: number = x + w / 2;
    const y1: number = y - h / 2;
    const y2: number = y + h / 2;
    let total: number = 0;
    for (let i: number = 0; i + 3 < boxes.length; i += 4) {
      const ox: number = Math.min(x2, boxes[i + 2]) - Math.max(x1, boxes[i]);
      const oy: number = Math.min(y2, boxes[i + 3]) - Math.max(y1, boxes[i + 1]);
      if (ox > 0 && oy > 0) {
        total = total + ox * oy;
      }
    }
    return total;
  }

  /** 判断以 (x,y) 为中心的标签框是否与 boxes/reserved 中的矩形相交 */
  private boxFree(x: number, y: number, w: number, h: number, boxes: number[]): boolean {
    const x1: number = x - w / 2 - LABEL_GAP;
    const x2: number = x + w / 2 + LABEL_GAP;
    const y1: number = y - h / 2 - LABEL_GAP;
    const y2: number = y + h / 2 + LABEL_GAP;
    for (let i: number = 0; i + 3 < boxes.length; i += 4) {
      if (x1 < boxes[i + 2] && x2 > boxes[i] && y1 < boxes[i + 3] && y2 > boxes[i + 1]) {
        return false;
      }
    }
    return true;
  }

  private async renderAllMarkers(): Promise<void> {
    // 可重复调用：先清掉已有点位（样式变更会清空覆盖物，这里做兜底重建）
    this.markers.forEach((marker: map.Marker) => {
      try {
        marker.remove();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'remove marker failed');
      }
    });
    this.markers.clear();
    this.markerAlpha.clear();

    const cities: CityItem[] = CityRepository.all();
    const batchSize: number = 40;
    for (let i = 0; i < cities.length; i += batchSize) {
      const slice: CityItem[] = cities.slice(i, i + batchSize);
      const tasks: Promise<void>[] = [];
      for (const city of slice) {
        tasks.push(this.addMarkerFor(city));
      }
      await Promise.all(tasks);
    }
    this.applyDeclutter();
    hilog.info(DOMAIN, TAG, 'markers rendered: %{public}d', this.markers.size);
  }

  private async addMarkerFor(city: CityItem): Promise<void> {
    const controller: map.MapComponentController | undefined = this.controller;
    if (controller === undefined) {
      return;
    }
    const visited: boolean = footprintStore.isVisited(city.code);
    const alpha: number = visited ? 1.0 : this.unlitAlpha();
    const options: mapCommon.MarkerOptions = {
      position: { latitude: city.lat, longitude: city.lng },
      icon: visited ? $r('app.media.marker_visited') : $r('app.media.marker_dim'),
      alpha: alpha,
      anchorU: 0.5,
      anchorV: 0.5,
      clickable: true,
      title: city.code
    };
    try {
      const marker: map.Marker = await controller.addMarker(options);
      this.markers.set(city.code, marker);
      this.markerAlpha.set(city.code, alpha);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'addMarker failed: %{public}s', city.code);
    }
  }

  /** 单个城市状态变化 → 只更新这一个点位（增量刷新） */
  private syncMarker(code: string, visited: boolean): void {
    const marker: map.Marker | undefined = this.markers.get(code);
    if (marker === undefined) {
      return;
    }
    marker.setIcon(visited ? $r('app.media.marker_visited') : $r('app.media.marker_dim'))
      .then(() => {
        this.setMarkerAlpha(code, visited ? 1.0 : this.unlitAlpha());
      })
      .catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'setIcon failed: %{public}s', JSON.stringify(err));
      });
  }

  /**
   * 未点亮城市的当前透明度：
   * 全国视野（缩放 < 4.5）时压暗到 0.38，避免 370 个点糊成一片；放大后提到 0.85；
   * 用户选择"只看已点亮"时完全隐藏。
   */
  private unlitAlpha(): number {
    if (!this.showUnvisited) {
      return 0.0;
    }
    return this.detailZoom ? 0.85 : 0.38;
  }

  /** 只对透明度真正变化的点位下发指令，避免缩放时全量调用原生接口 */
  private setMarkerAlpha(code: string, alpha: number): void {
    const previous: number | undefined = this.markerAlpha.get(code);
    if (previous !== undefined && Math.abs(previous - alpha) < 0.01) {
      return;
    }
    const marker: map.Marker | undefined = this.markers.get(code);
    if (marker === undefined) {
      return;
    }
    this.markerAlpha.set(code, alpha);
    marker.setAlpha(alpha);
  }

  /** 根据当前缩放级别调整未点亮城市的可见度 */
  private applyDeclutter(): void {
    const controller: map.MapComponentController | undefined = this.controller;
    let zoom: number = MapDefaults.zoom;
    if (controller !== undefined) {
      try {
        zoom = controller.getCameraPosition().zoom;
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'getCameraPosition failed');
      }
    }
    this.detailZoom = zoom >= 4.5;
    const unlit: number = this.unlitAlpha();
    this.markers.forEach((marker: map.Marker, code: string) => {
      this.setMarkerAlpha(code, footprintStore.isVisited(code) ? 1.0 : unlit);
    });
  }

  /**
   * 地图 SDK 的点击回调。只做一件事：把经纬度换算成屏幕坐标，交给统一的命中逻辑。
   */
  private handleMapClick(latLng: mapCommon.LatLng): void {
    const controller: map.MapComponentController | undefined = this.controller;
    if (controller === undefined) {
      return;
    }
    const point: mapCommon.MapPoint = controller.getProjection().toScreenLocation(latLng);
    hilog.info(DOMAIN, TAG, 'tap path=sdkClick');
    this.pickCityAtScreen(px2vp(point.positionX), px2vp(point.positionY));
  }

  /**
   * 自己识别点按。
   *
   * 为什么需要它：手指点一下通常会有几像素抖动，地图 SDK 会把这种抖动当成拖拽，
   * 于是 `mapClick` 根本不回调；点在地图点位上时也可能被点位消费掉。
   * 结果就是"一个城市要点好几次才弹窗"。这里直接在 MapComponent 上收触摸事件：
   * 按下 → 抬起，位移小于 16vp 且时长小于 500ms，就按一次点击处理，
   * 用 `fromScreenLocation` 反查经纬度，完全绕开 SDK 的手势判定。
   */
  private onMapTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      const touch: TouchObject = event.touches[0];
      this.touchDownX = touch.x;
      this.touchDownY = touch.y;
      this.touchDownAt = Date.now();
      this.touchMoved = false;
      return;
    }
    if (event.type === TouchType.Move) {
      const touch: TouchObject = event.touches[0];
      const dx: number = touch.x - this.touchDownX;
      const dy: number = touch.y - this.touchDownY;
      if (Math.sqrt(dx * dx + dy * dy) > MapDefaults.tapSlopVp) {
        this.touchMoved = true;
      }
      return;
    }
    if (event.type !== TouchType.Up) {
      return;
    }
    if (this.touchMoved || Date.now() - this.touchDownAt > MapDefaults.tapMaxMs) {
      return;
    }
    // 诊断日志：能区分"我们自己识别到点按"和"地图 SDK 回调"两条通路，
    // 排查"点了没反应"时先看这条有没有打出来。
    hilog.info(DOMAIN, TAG, 'tap path=ownTouch x=%{public}d y=%{public}d',
      Math.round(this.touchDownX), Math.round(this.touchDownY));
    this.pickCityAtScreen(this.touchDownX, this.touchDownY);
  }

  /**
   * 按**屏幕距离**找手指落点附近最近的城市，直接给出"点亮 / 查看"入口。
   *
   * 为什么不用公里阈值：同一段屏幕距离，在不同缩放级别对应的公里数差几十倍。
   * 全国视野下 60 公里只有约 20 物理像素，而点位本身也只有二十几像素宽，
   * 等于要求用户把指尖精确压在圆点上。
   * 屏幕距离则是"所见即所得"：圆点周围一个指尖的范围内都能命中，
   * 放大之后命中范围自动收窄，不会把隔壁城市抢过来。
   */
  private pickCityAtScreen(xVp: number, yVp: number): void {
    const controller: map.MapComponentController | undefined = this.controller;
    if (controller === undefined) {
      return;
    }
    // 同一次点按会被 mapClick 和 onTouch 各触发一次，这里去重
    const now: number = Date.now();
    if (now - this.lastPickAt < 600) {
      return;
    }
    this.lastPickAt = now;

    const projection: map.Projection = controller.getProjection();
    let best: CityItem | undefined = undefined;
    let bestDistance: number = MapDefaults.tapRadiusVp;
    for (const city of CityRepository.all()) {
      const point: mapCommon.MapPoint =
        projection.toScreenLocation({ latitude: city.lat, longitude: city.lng });
      const dx: number = px2vp(point.positionX) - xVp;
      const dy: number = px2vp(point.positionY) - yVp;
      const distance: number = Math.sqrt(dx * dx + dy * dy);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = city;
      }
    }
    if (best === undefined) {
      this.flashHint('附近没有可点亮的城市，放大后再试');
      return;
    }
    this.hint = '';
    this.openCity(best.code);
  }

  /**
   * 点在地图名称上：直接按"这个标签所在的位置"走同一个命中逻辑。
   *
   *  · 城市 / 省会标签 → 命中的必然是它自己（名字就画在它的圆点下方）；
   *  · 省名标签 → 命中该位置最近的城市（省名一般画在省会位置）；
   *  · 国家 / 地区名 → 附近没有可点亮城市时给一次提示，不会静默失败。
   */
  private onLabelTap(item: CityLabel): void {
    this.pickCityAtScreen(item.x, item.y);
  }

  /**
   * 短暂提示：地图上这类"操作反馈"不需要常驻，
   * 2.6 秒后自动消失，避免像标签一样一直糊在屏幕上。
   */
  private flashHint(text: string): void {
    this.hint = text;
    setTimeout(() => {
      if (this.hint === text) {
        this.hint = '';
      }
    }, 2600);
  }

  private openCity(code: string): void {
    this.selectedCode = code;
    this.selectedTag = 'other';
    this.noteInput = '';
    this.sheetShown = true;
  }

  private selectedCity(): CityItem | undefined {
    return CityRepository.get(this.selectedCode);
  }

  /** 定位到我的位置，并把镜头移过去 */
  private async locateMe(): Promise<void> {
    if (this.locating) {
      return;
    }
    this.locating = true;
    this.hint = '正在定位…';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const granted: boolean = await LocationService.requestPermission(context);
      if (!granted) {
        this.hint = '未获得定位权限，可在地图上手动选择城市';
        return;
      }
      const city: CityItem | undefined = await LocationService.detectCurrentCity();
      if (city === undefined) {
        this.hint = '定位失败，可在地图上手动选择城市';
        return;
      }
      this.hint = '';
      this.moveCamera(city.lng, city.lat, 9);
      this.openCity(city.code);
    } finally {
      this.locating = false;
    }
  }

  /** 回到中国全图 */
  private resetView(): void {
    this.moveCamera(MapDefaults.centerLng, MapDefaults.centerLat, MapDefaults.zoom);
  }

  private moveCamera(lng: number, lat: number, zoom: number): void {
    const controller: map.MapComponentController | undefined = this.controller;
    if (controller === undefined) {
      return;
    }
    const position: mapCommon.CameraPosition = {
      target: { latitude: lat, longitude: lng },
      zoom: zoom
    };
    controller.animateCamera(map.newCameraPosition(position), 600);
  }

  /** 自绘缩放控件：底图自带的 +/− 已关闭，这里用相机 API 自己实现 */
  private zoomBy(delta: number): void {
    const controller: map.MapComponentController | undefined = this.controller;
    if (controller === undefined) {
      return;
    }
    try {
      const current: number = controller.getCameraPosition().zoom;
      const target: number = Math.min(20, Math.max(2, current + delta));
      controller.animateCamera(map.zoomTo(target), 260);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'zoomBy failed');
    }
  }

  /** 切换"未点亮城市是否显示"，用于"只看已点亮"的分享/自我激励场景 */
  private toggleUnvisited(): void {
    this.showUnvisited = !this.showUnvisited;
    this.applyDeclutter();
    promptAction.showToast({ message: this.showUnvisited ? '显示全部城市' : '只看已点亮' });
  }

  @Builder
  citySheet() {
    Column() {
      if (this.selectedCity() !== undefined) {
        Row() {
          Column() {
            Text(this.selectedCity()!.name)
              .fontSize(20)
              .fontColor(Palette.text)
              .fontWeight(FontWeight.Medium)
            Text(`${this.selectedCity()!.parent} · ${this.levelLabel(this.selectedCity()!.level)}`)
              .fontSize(12)
              .fontColor(Palette.textDim)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(footprintStore.isVisited(this.selectedCity()!.code) ? '★ 已点亮' : '○ 未点亮')
            .fontSize(12)
            .fontColor(footprintStore.isVisited(this.selectedCity()!.code) ? Palette.gold : Palette.textDim)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        // 让开右上角的系统关闭按钮（SheetSize.MEDIUM/LARGE 会画一个圆形 X），
        // 否则"○ 未点亮"会和它叠在一起
        .padding({ right: 44 })

        Divider().color(Palette.line).margin({ top: 12, bottom: 12 })

        Row() {
          Column() {
            Text(this.selectedCity()!.code)
              .fontSize(15)
              .fontColor(Palette.text)
            Text('行政区划代码')
              .fontSize(11)
              .fontColor(Palette.textDim)
              .margin({ top: 2 })
          }
          .layoutWeight(1)

          Column() {
            Text(`${this.selectedCity()!.lng.toFixed(3)}, ${this.selectedCity()!.lat.toFixed(3)}`)
              .fontSize(15)
              .fontColor(Palette.text)
            Text('中心点坐标（GCJ-02）')
              .fontSize(11)
              .fontColor(Palette.textDim)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
        }
        .width('100%')

        Blank().height(20)

        // 打卡表单：仅在未点亮时出现；默认值即可直接保存，不增加操作负担
        if (!footprintStore.isVisited(this.selectedCity()!.code)) {
          Text('这次是…')
            .fontSize(12)
            .fontColor(Palette.textDim)
            .margin({ bottom: 8 })

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.tagOptions(), (item: TagOption) => {
              Text(item.label)
                .fontSize(13)
                .fontColor(this.selectedTag === item.value ? '#1A1405' : Palette.text)
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .borderRadius(999)
                .backgroundColor(this.selectedTag === item.value ? Palette.gold : Palette.surfaceSoft)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.selectedTag = item.value;
                })
            }, (item: TagOption) => item.value)
          }
          .width('100%')

          TextInput({ placeholder: '留一句备注（可跳过）', text: this.noteInput })
            .height(40)
            .borderRadius(12)
            .backgroundColor(Palette.surfaceSoft)
            .placeholderColor(Palette.textDim)
            .fontColor(Palette.text)
            .fontSize(14)
            .margin({ top: 4, bottom: 16 })
            .onChange((value: string) => {
              this.noteInput = value;
            })
        }

        Button(footprintStore.isVisited(this.selectedCity()!.code) ? '取消点亮（移除全部到访记录）' : '保存并点亮')
          .width('100%')
          .height(44)
          .borderRadius(Dimens.pillRadius)
          .backgroundColor(footprintStore.isVisited(this.selectedCity()!.code) ? Palette.surfaceSoft : Palette.gold)
          .fontColor(footprintStore.isVisited(this.selectedCity()!.code) ? Palette.text : '#1A1405')
          .fontSize(15)
          .onClick(() => {
            this.toggleSelected();
          })

        Blank().height(8)

        Button('定位到这里')
          .width('100%')
          .height(44)
          .borderRadius(Dimens.pillRadius)
          .backgroundColor(Palette.surfaceSoft)
          .fontColor(Palette.text)
          .fontSize(15)
          .onClick(() => {
            const city: CityItem | undefined = this.selectedCity();
            if (city !== undefined) {
              this.moveCamera(city.lng, city.lat, 8);
            }
          })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  private async toggleSelected(): Promise<void> {
    const city: CityItem | undefined = this.selectedCity();
    if (city === undefined) {
      return;
    }
    if (footprintStore.isVisited(city.code)) {
      await footprintStore.unlight(city.code);
      promptAction.showToast({ message: `已取消点亮 ${city.name}` });
    } else {
      await footprintStore.lightUp(city.code, this.selectedTag, this.noteInput);
      promptAction.showToast({ message: `已点亮 ${city.name}` });
    }
    // 操作完成后关闭卡片，让用户立刻看到点亮效果
    this.sheetShown = false;
  }

  /** 打卡标签选项（取值与 model/VisitRecord 的 VisitTag 对应） */
  private tagOptions(): TagOption[] {
    return [
      { value: 'business', label: '出差' },
      { value: 'travel', label: '旅行' },
      { value: 'family', label: '探亲' },
      { value: 'transit', label: '路过' },
      { value: 'live', label: '居住' },
      { value: 'other', label: '其他' }
    ];
  }

  private levelLabel(level: string): string {
    if (level === 'municipality') {
      return '直辖市';
    }
    if (level === 'sar') {
      return '特别行政区';
    }
    if (level === 'province') {
      return '省级行政区';
    }
    return '市州级行政区';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 地图本体（占满全部空间）
      MapComponent({ mapOptions: this.mapOptions, mapCallback: this.callback })
        .width('100%')
        .height('100%')
        // 官方《开发应用沉浸式效果》：背景类元素用 expandSafeArea 把绘制延伸到状态栏 / 导航条
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        // 自己识别"点按"：手指的微小抖动会被地图 SDK 当成拖拽从而不回调 mapClick，
        // 这里补一条通路，保证"点一下就能弹出来"（详见 onMapTouch 的注释）。
        .onTouch((event: TouchEvent) => {
          this.onMapTouch(event);
        })

      // 透明触摸层：只用来"看"用户的点按，不参与任何绘制。
      //
      // 为什么需要它：地图组件的原生手势可能会把触摸事件吃掉（尤其是手指点在地图点位上时），
      // 那样我们在 MapComponent 上注册的 onTouch 也收不到。
      // 这一层用 HitTestMode.Transparent —— 官方语义是"自身响应触摸，且不阻塞兄弟节点"，
      // 也就是：我们收到点按的同时，地图照样能拖动、能双指缩放。
      // 两条通路（这里 + 地图的 mapClick）都指向同一个命中函数，用时间戳去重。
      Column()
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        .onTouch((event: TouchEvent) => {
          this.onMapTouch(event);
        })

      // 名称标注层。
      // 视觉规范与华为底图自带标注保持一致：无底色、白描边（halo）、近黑字；
      // 已点亮城市改用金色系，靠色相区分状态，而不是靠"深色胶囊"。
      ForEach(this.cityLabels, (item: CityLabel) => {
        Row() {
          Text(item.name)
            .fontSize(item.kind === 'province' ? PROVINCE_FONT_SIZE :
              (item.kind === 'country' ? COUNTRY_FONT_SIZE : CITY_FONT_SIZE))
            // 未点亮统一用底图标签色；只有"已点亮"用金色，这是本 App 的语义色（图例里有说明）
            .fontColor(item.visited ? MapLabelStyle.visitedText : MapLabelStyle.labelText)
            // 字重：实测底图国名"蒙古"字形宽 39.5px/字、平均笔画 9.3px（≈0.24em）；
            // Bold 只有 ≈0.18em，所以再提一档用 Bolder，让笔画密度和底图一致。
            // 省名 / 省会名 / 地级市名三层统一用同一套字号与字重。
            .fontWeight(FontWeight.Bolder)
            .textShadow({
              radius: 2.5,
              color: MapLabelStyle.halo,
              offsetX: 0,
              offsetY: 0
            })
            // 关键：文字也必须声明不参与命中。
            // HitTestMode.None 的语义是"自身不响应，子节点和兄弟节点继续"——
            // 之前只给外面的 Row 设了 None，里面的 Text 仍然会被命中，
            // 于是点在名字上时这个节点就把触摸吃掉了，地图层根本收不到，
            // 表现就是"点名字没反应、必须点在空地或圆点上"。现在整棵标签子树都不拦触摸。
            .hitTestBehavior(HitTestMode.None)
        }
        .width(item.w)
        .height(item.h)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        // 整块标签都不参与命中：点名字的判定交给地图层的"最近城市"逻辑，
        // 这样"点名字能点亮"和"从名字上开始拖动地图"两件事可以同时成立。
        .hitTestBehavior(HitTestMode.None)
        .position({ x: item.x - item.w / 2, y: item.y - item.h / 2 })
      }, (item: CityLabel) =>
      `${item.kind}_${item.code}_${item.visited}_${Math.round(item.x)}_${Math.round(item.y)}`)

      // 顶部进度胶囊。
      // 注意：这里必须用"外层 Column 加左右 padding"来留边，不能写成
      // `width('100%') + margin({left,right})`——那样元素宽度是 100% 再加两侧外边距，
      // 右侧会直接溢出屏幕（页面顶栏之前就是这么被切掉的）。
      Column() {
        // 同样用 Button 承载，才能拿到沉浸光感材质（容器类在非标题栏区域不生效）
        Button() {
          Column() {
            Row() {
              Row() {
                Text('已点亮 ')
                  .fontSize(13)
                  .fontColor(Palette.text)
                Text(`${footprintStore.visitedCount}`)
                  .fontSize(19)
                  .fontColor(Palette.goldLight)
                  .fontWeight(FontWeight.Medium)
                Text(` / ${footprintStore.totalUnits}`)
                  .fontSize(13)
                  .fontColor(Palette.text)
              }
              Blank()
              Text(`覆盖 ${footprintStore.provinceCount} 省`)
                .fontSize(13)
                .fontColor(Palette.text)
                .maxLines(1)
            }
            .width('100%')

            Progress({ value: footprintStore.visitedCount, total: footprintStore.totalUnits,
              type: ProgressType.Linear })
              .width('100%')
              .height(4)
              .color(Palette.gold)
              .backgroundColor(Palette.line)
              .margin({ top: 8 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        }
        .width('100%')
        .padding(0)
        .borderRadius(Dimens.pillRadius)
        // 地图上的悬浮控件不在沉浸光感的生效范围内（官方 FAQ：Material inactive: out of scope），
        // 所以这里用系统组件级模糊 backgroundBlurStyle 来做真模糊，
        // 底色保持半透明，压住底图的同时还能看见地形透出来。
        .backgroundColor('#990C1320')
        // 用 COMPONENT_THIN 这一档：ArkUI 的 BlurStyle 预设自带一层"材质底色"，
        // ULTRA_THICK 几乎不透光（面板会变成实心块），THIN 才是"能看见背后内容被糊掉"的玻璃。
        .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: ThemeColorMode.DARK })
        .border({ width: 0.5, color: '#1FFFFFFF' })
        .shadow({ radius: 20, color: '#8C000000', offsetX: 0, offsetY: 8 })
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .margin({ top: 8 + this.safeTop })
      // 入场：地图就绪后淡入 + 轻微下滑，避免"啪"地一下出现
      .opacity(this.chromeIn ? 1 : 0)
      .translate({ y: this.chromeIn ? 0 : -12 })
      .animation({ duration: 380, curve: curves.springMotion(0.42, 0.9) })

      // 右侧悬浮控件：缩放 / 定位 / 全国 / 过滤。
      // 底图自带的缩放、指南针、比例尺、定位按钮已在 bindMapEvents 中关闭，
      // 所以这里不会出现两套按钮叠在一起的情况。
      Column({ space: 10 }) {
        this.zoomGroup()
        this.roundButton('locate', () => {
          this.locateMe();
        }, false)
        this.roundButton('reset', () => {
          this.resetView();
        }, false)
        // 过滤按钮的高亮跟着 showUnvisited 变，所以单独写一个**不带参数**的 @Builder：
        // 按值传参的 @Builder 不参与刷新（官方文档明确），参数化的写法点完不会变色。
        this.filterButton()
      }
      .alignItems(HorizontalAlign.End)
      .position({ right: 14, bottom: 92 + this.safeBottom })

      // 图例：解释"金色 = 去过"。
      // 放在顶部信息卡下方，而不是左下角——左下角是花瓣地图 Logo 与审图号的固定位置，
      // 图例压上去会遮挡合规信息。
      Button() {
        Row({ space: 12 }) {
          Row({ space: 5 }) {
            Circle()
              .width(7)
              .height(7)
              .fill(Palette.gold)
            Text('已点亮')
              .fontSize(10)
              .fontColor(Palette.text)
          }

          Row({ space: 5 }) {
            Circle()
              .width(7)
              .height(7)
              .fill('#54637D')
            Text('未点亮')
              .fontSize(10)
              .fontColor(Palette.text)
          }
        }
        .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      }
      .padding(0)
      .borderRadius(16)
      .backgroundColor('#990C1320')
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: ThemeColorMode.DARK })
      .border({ width: 0.5, color: '#1FFFFFFF' })
      .position({ left: 14, top: this.safeTop + 80 })
      .opacity(this.chromeIn ? 1 : 0)
      .translate({ y: this.chromeIn ? 0 : -8 })
      .animation({ duration: 420, curve: curves.springMotion(0.42, 0.9) })

      // 提示条（加载中 / 失败 / 操作反馈）
      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(12)
          .fontColor(Palette.text)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(12)
          .backgroundColor(Palette.surface)
          .border({ width: 1, color: Palette.line })
          .margin({ left: 20, right: 20, top: this.safeTop + 124 })
      }


    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldValue: Area, newValue: Area) => {
      // 记录地图容器尺寸（vp），城市名投影时需要用来判断是否在视野内
      this.mapWidth = Number(newValue.width);
      this.mapHeight = Number(newValue.height);
      this.updateCityLabels();
    })
    .bindSheet(this.sheetShown, this.citySheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      backgroundColor: Palette.surface,
      onDisappear: () => {
        this.sheetShown = false;
      }
    })
  }

  @Builder
  roundButton(kind: string, action: () => void, active: boolean) {
    Button() {
      this.controlIcon(kind, active ? Palette.gold : Palette.text, 20)
    }
    .width(Dimens.fabSize)
    .height(Dimens.fabSize)
    .borderRadius(Dimens.fabSize / 2)
    .backgroundColor(active ? '#3DF5C542' : '#99101828')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: ThemeColorMode.DARK })
    .border({ width: 0.5, color: active ? '#73F5C542' : '#1FFFFFFF' })
    .shadow({ radius: 16, color: '#73000000', offsetX: 0, offsetY: 6 })
    .stateStyles({ normal: this.normalFeedback, pressed: this.pressedFeedback })
    .onClick(action)
  }

  /**
   * "只看已点亮"按钮。
   * 和 roundButton 的区别：它 **不带参数**，直接读 this.showUnvisited，
   * 这样点完立刻能变色（参数化的 @Builder 不参与刷新）。
   */
  @Builder
  filterButton() {
    Button() {
      // 图标也直接写在这里：controlIcon 是"带参数的 @Builder"，同样不参与刷新，
      // 会把旧的白色图标一直留在按钮上（只变底色不变图标，实测踩过）。
      Image(MapPage.iconRes('filter'))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .fillColor(this.showUnvisited ? Palette.text : Palette.gold)
    }
    .width(Dimens.fabSize)
    .height(Dimens.fabSize)
    .borderRadius(Dimens.fabSize / 2)
    .backgroundColor(this.showUnvisited ? '#99101828' : '#3DF5C542')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: ThemeColorMode.DARK })
    .border({ width: 0.5, color: this.showUnvisited ? '#1FFFFFFF' : '#73F5C542' })
    .shadow({ radius: 16, color: '#73000000', offsetX: 0, offsetY: 6 })
    .stateStyles({ normal: this.normalFeedback, pressed: this.pressedFeedback })
    .onClick(() => {
      this.toggleUnvisited();
    })
  }

  /** 缩放控件组：上下两个按钮合成一根"药丸"，和单个圆按钮区分开 */
  @Builder
  zoomGroup() {
    Button() {
      Column() {
        this.zoomButton('plus', 1)
        Divider()
          .width(20)
          .color('#26FFFFFF')
        this.zoomButton('minus', -1)
      }
    }
    .padding(0)
    .borderRadius(Dimens.fabSize / 2)
    .backgroundColor('#99101828')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: ThemeColorMode.DARK })
    .border({ width: 0.5, color: '#1FFFFFFF' })
    .shadow({ radius: 16, color: '#73000000', offsetX: 0, offsetY: 6 })
  }

  @Builder
  zoomButton(kind: string, delta: number) {
    Button() {
      this.controlIcon(kind, Palette.text, 20)
    }
    .width(Dimens.fabSize)
    .height(Dimens.fabSize)
    .backgroundColor(Color.Transparent)
    .borderRadius(Dimens.fabSize / 2)
    .stateStyles({ normal: this.normalFeedback, pressed: this.pressedFeedback })
    .onClick(() => {
      this.zoomBy(delta);
    })
  }

  /** 按压反馈：和底部页签保持同一套手感（轻微缩小 + 变暗） */
  @Styles
  pressedFeedback() {
    .scale({ x: Motion.pressScale, y: Motion.pressScale })
    .opacity(0.82)
  }

  @Styles
  normalFeedback() {
    .scale({ x: 1.0, y: 1.0 })
    .opacity(1.0)
  }

  /** 控件图标：与底部导航同源的描边风格，24×24 视图缩放 */
  @Builder
  controlIcon(kind: string, color: string, size: number) {
    Image(MapPage.iconRes(kind))
      .width(size)
      .height(size)
      .objectFit(ImageFit.Contain)
      .fillColor(color)
  }

  private static iconRes(kind: string): Resource {
    if (kind === 'plus') {
      return $r('app.media.ic_plus');
    }
    if (kind === 'minus') {
      return $r('app.media.ic_minus');
    }
    if (kind === 'locate') {
      return $r('app.media.ic_locate');
    }
    if (kind === 'reset') {
      return $r('app.media.ic_globe');
    }
    return $r('app.media.ic_eye');
  }
}
