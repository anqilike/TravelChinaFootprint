/**
 * 已点亮城市的配色方案。
 *
 * 每种方案两件事：
 *  · dot   —— 地图上那个点的颜色（图标是预先烘好的 8 套 PNG，见 marker_lit_N.png）
 *  · label —— 城市名在地图上的颜色。名字是压在浅色底图上的小字，
 *             所以统一取同色系的**深色版**，保证可读；点可以亮，字不能糊。
 *
 * 在「我的 → 点亮颜色」里选择，落盘保存。
 */
export interface LitColorPreset {
  name: string;
  dot: string;
  label: string;
}

export class LitColors {
  static presets(): LitColorPreset[] {
    return [
      { name: '纯黄', dot: '#FFE500', label: '#A87900' },
      { name: '暖金', dot: '#F5C542', label: '#C8861A' },
      { name: '纯红', dot: '#FF3B30', label: '#C0271E' },
      { name: '橙红', dot: '#FF7A00', label: '#B45309' },
      { name: '青绿', dot: '#00D084', label: '#00754A' },
      { name: '天蓝', dot: '#00A8FF', label: '#00659E' },
      { name: '紫', dot: '#A855F7', label: '#6B2FB0' },
      { name: '玫红', dot: '#FF4D94', label: '#B81F5E' }
    ];
  }

  static count(): number {
    return LitColors.presets().length;
  }

  static get(index: number): LitColorPreset {
    const list: LitColorPreset[] = LitColors.presets();
    const safe: number = (index < 0 || index >= list.length) ? 0 : index;
    return list[safe];
  }
}
