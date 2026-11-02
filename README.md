# 易灵思实时图像边缘检测系统

基于易灵思 Titanium Ti60F225 FPGA 和 VF-Ti60F225 V4.1 开发板，实现 SC2210 相机采集、自适应中值降噪、全分辨率 Canny 边缘检测、RGB565 彩色预览和 HDMI 显示。

## 最终工程

```text
proj/dbg_261019_2_rgb565_neutral_edge_median/dbg_261019_2_rgb565_neutral_edge_median/
```

顶层模块为 `system_dbg_top`。最终码流位于该工程的 `outflow/` 目录：

```text
dbg_rgb565_neutral_edge_median.bit
dbg_rgb565_neutral_edge_median.hex
```

## 总体数据流

```text
SC2210 RAW8 相机
  -> MIPI D-PHY / CSI-2 接收
  -> 64 位 beat 行解包
  -> 彩色预览支路与全分辨率边缘支路
  -> 显示模式选择
  -> 640x480 VGA 时序与 HDMI TMDS 输出
```

## 主要模块

### 顶层与相机链路

- `system_dbg_top.v`：系统顶层，连接相机、图像算法、彩色与边缘缓存、显示模式、按键、LED 和测量接口。彩色、灰度、边缘、左右分屏、彩色叠红边五种模式均在此选择。
- `I2C_SC2210_640x480_4Lanes_Config.v`：通过 I2C 配置 SC2210 的 640x480、4-lane、RAW8 工作模式及曝光、帧长等寄存器。
- `csi_rx/csi_rx.sv`：易灵思 MIPI CSI-2 接收 IP，将四路 D-PHY 数据转换为 64 位像素 beat，并通过跨时钟 FIFO 把数据送入 25 MHz 像素时钟域。
- `camera_line_unpack.v`：将每行 80 个 64 位 beat 解包为 640 个 RAW8 像素。两个行 bank 共用一个 160x64 同步双口 RAM，降低 LUT 和触发器占用。
- `camera_pixel_unpack.v` 和 `data_unpack.v`：保留的像素/数据解包实现，用于模块验证和不同数据组织方式。

### 图像算法

- `alg_top.v`：图像算法顶层，完成 RAW Bayer 去马赛克、亮度提取、自适应中值降噪、Canny 边缘检测以及有效信号和坐标延迟对齐。
- `debayer.v`、`grayscale.v`：从 3x3 Bayer 窗口恢复 RGB888，并使用 77/150/29 权重计算 8 位亮度。
- `median3x3.v`、`sort3.v`：灰度中值和自适应中值。最终算法只替换孤立噪点，尽量保留单像素细线，并将其结果送入 Canny 前级。
- `gaussian5x5.v`：使用 5x5 高斯核进行平滑，核权值按可分离移位加法实现，降低乘法器和 DSP 占用。
- `sobel.v`：计算水平和垂直梯度 Gx、Gy 及梯度幅值；`scharr.v` 为可选的梯度实现。
- `canny_nms.v`：沿梯度方向执行非极大值抑制，保留局部极大值；`canny_nms_interp.v` 为可选插值版本。
- `canny_hysteresis.v`：双阈值滞后连接。高阈值可调，低阈值取高阈值的一半，弱边只有在与已确认边缘连通时才保留。
- `edge_link3x3.v`：根据梯度方向补齐单像素断点，不进行整体膨胀，因此不会明显加粗边缘。
- `shape_detect.v`、`shape_overlay.v`、`cn_font_rom.v`：早期形状识别与中文字符资源。最终版本不启用形状识别，也不在有效数据通路中。

### 缓存与显示

- `rgb565_preview_store.v`：将去马赛克后的彩色画面水平和垂直抽样为 320x240，使用 R5/G6/B5 编码，每四个像素打包成一个 64 位字；显示端按固定 640x480 时序读出并 2x2 放大，节省片上 RAM。
- `edge_frame_store.v`：保存 640x480 单比特边缘图，每行 80 字节。写侧使用算法输出的真实坐标，并默认减去 x-3、y-4，修正算法延迟造成的空间偏差。
- `vga_timing.v`：产生 25 MHz、640x480、总时序 800x525、约 59.52 Hz 的显示同步信号。
- `rgb2dvi.v`、`tmds_channel.v`：将 RGB 数据编码为 TMDS，并转换为 HDMI 所需的差分串行输出。
- `pattern_gen.v`：相机未连接或数据流中断时产生彩条，便于先验证显示链路。
- `split_mux.v`、`rgb_video_delay.v`、`video_delay.v`：显示分屏和时序信号对齐所需的辅助模块。
- `video_frame_store.v`、`rgb332_preview_store.v`：早期灰度与 RGB332 预览方案，保留用于版本比较。

### 控制、诊断与测量

- `key_debounce.v`：按键 20 ms 消抖。短按模式键切换画面，长按切换 LED 诊断面板，阈值键每次将高阈值提高 4。
- `threshold_reg.v`：保存 Canny 高阈值，低阈值在算法内部自动取半。
- `dbg_led_bank.v`：集中检测 PLL、I2C、CSI、像素有效、缓存写入和断流状态，将故障映射到八位 LED。
- `measurement_timing.v`：输出帧同步脉冲、帧长脉冲、帧周期和帧行数，便于示波器、逻辑分析仪或外部计数。
- `dual_clock_fifo.v`、`async_fifo.v`、`simple_dual_port_ram.v`：跨时钟传输和双口存储辅助模块。

## 关键实现思路

- 彩色预览与边缘检测分为两条支路。彩色支路使用 320x240 RGB565 缓存以控制片上 RAM；Canny 支路直接处理 640x480 原始像素，不经过预览缓存。
- 算法采用逐像素流水结构，当前完整 Canny 路径为 17 拍。所有模块通过 `valid`、`de`、`hs`、`vs` 和坐标信号对齐。
- 红边对齐同时处理时间延迟和空间坐标，避免仅靠固定像素偏移处理缺失 beat 造成的累计漂移。
- 相机与显示使用各自时序，通过帧缓存消除相机帧率与显示刷新率不完全一致造成的滚动。
- 最终工程已完成 Efinity 综合、布局布线、时序检查和码流生成；13 项仿真全部通过，日志位于工程 `sim/logs/final-20261027/`。

## 目录说明

- `proj/`：最终 Efinity 工程、RTL、CSI IP、约束、仿真和构建结果。
- `rtl/`：共享 RTL 源码。
- `sim/`：共享模块测试平台与激励数据。
- `scripts/`：Efinity 构建和仿真脚本。
- `py/refmodel.py`：算法 Python 黄金模型。
- `build_repo/rtl/video/`、`proj/rtl/`：为兼容工程和仿真脚本原有相对路径而保留的共享 RTL 副本。
- `FILE_SHA256.txt`：文件完整性校验清单。

## 编译

需安装 Efinity 2026.1。在代码包根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 `
  proj\dbg_261019_2_rgb565_neutral_edge_median\dbg_261019_2_rgb565_neutral_edge_median\dbg_261019_2.xml
```
