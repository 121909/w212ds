# ZTE 充电分离自动控制

针对 ZTE W210DS / W205DS（Android 13）等中兴设备的充电分离自动控制模块。基于 Magisk 参考模块（见下节）的节点/开关分析改写，适配 SukiSU / KernelSU，改为轮询复用、WebUI 可视化配置。

## Magisk 参考模块

本模块的**内核节点与 `Settings.Global` 开关分析**源自 Magisk 版「中兴充电分离自动控制」（制作者：尽欢/枕云归，针对 W205DS Android 13 实机验证）。当前 KernelSU 版与参考实现的主要区别：

| 项 | Magisk 参考版 | 本模块 (KernelSU/SukiSU) |
|---|---|---|
| 配置入口 | 音量键 + Action 按钮 | **模块页 WebUI**（全部可视化） |
| 轮询 | 每 15 秒读 `usb/online` | 每 3 秒检测插拔，每 ~30 秒电量阈值 |
| 连接分类 | 只有 USB 接入/未接 | **PC(SDP/CDP) / 充电器(DCP/PD) 分开处理** |
| PC USB | 与充电器同逻辑 | 独立开关「插入电脑 USB 自动分离」（动作一次） |
| 充电器模式 | 仅阈值 | 关闭 / 插入立即分离 / 电量阈值 |
| 电量阈值 | 50–90% | 50–90%（WebUI 步进） |
| 低于阈值 | 自动关分离 | 可选自动关闭或**闩锁保持到拔电** |
| 日志 | 64KiB 自动清空 | 同 |

## 功能

- 区分当前连接类型：**PC 数据口**（`usb_type` = SDP/CDP）与**充电器**（DCP/PD 等）。
- **PC USB**：插入瞬间按「插电脑 USB 自动分离」开关动作一次，不做持续监控。
- **充电器**：三种模式可选
  - `关闭`：插入充电器不操作（正常充电）。
  - `插入立即分离`：插入即开启分离。
  - `电量阈值`：充到设定阈值（50/60/70/80/90%）才开启分离。
- 阈值模式的 `自动关闭` 选项（AUTO_CLOSE）：
  - `0`（闩锁）：达到阈值开启分离后**保持到拔电**，不受电量回落影响。
  - `1`（迟滞）：低于阈值自动关分离，回到阈值再开。
- 仅写 `Settings.Global` 的 `charge_separation_switch`（1=分离 / 0=正常充电），**断电后系统自动关闭分离**，无需额外操作。
- 只在开关确实需要变化时写入，避免无效操作。

## 工作原理

以 Shell 轮询为主（因该设备 sysfs 电源节点 inotify 实测不可靠，参考模块使用轻量轮询）：

```
service.sh（开机自启，root）
├─ 每 3 秒：读 /sys/class/power_supply/usb/online，检测插拔
│   ├─ 0→1（插入）：调用 apply_once —— PC 走 SEP_ON_USB，充电器走 CHARGER_MODE
│   └─ 1→0（拔出）：复位闩锁（TH_LATCH=0）
└─ 每 10 次循环（~30 秒）：threshold_tick —— 电量阈值状态机
    ├─ 未接电：不再读电量，直接保持分离关闭
    └─ 充电器连接且 CHARGER_MODE=2：按电量/阈值/闩锁计算目标开关
```

连接分类逻辑（`common.sh: detect_conn`）：

1. `usb/online` ≠ 1 → `OFF`（未供电）
2. `charger_psy/usb_type` 当前值（`[...]` 括起）：
   - `SDP`/`CDP` → `PC`（电脑数据口）
   - `DCP`/`PD`/`PD_DRP`/`BrickID`/`C` → `CHARGER`（充电器）
3. 若无法判定且 UTG 状态为 `CONFIGURED` → `PC`；否则 `CHARGER`

监视服务在系统解冻期间运行；深睡（suspend）时整个 userspace 被冻结，
轮询不产生定时唤醒，不阻止系统休眠。

## WebUI 控制

模块页打开 WebUI 即可可视化调整，无需音量键：

- **插入电脑 USB 自动分离** 开关
- **充电器模式** 分段按钮：关 / 立即 / 阈值
- **开启阈值** 步进器：0、50、60、70、80、90（仅阈值模式显示）
- **低于阈值自动关闭** 开关（阈值模式生效时显示）
- **立即按当前连接应用**：手动让当前连接立刻套用配置结果
- **当前状态**：连接类型、电量、分离开关、硬件节点

> 注：SukiSU 内置 WebView 的 `addJavascriptInterface` 只暴露参数最多的
> `exec(cmd, options, callbackFunc)` 重载，WebUI 通过该回调形式收发命令
> （若直接调用 `exec(cmd)` 同步形式会被遮蔽而取不到输出）。已在
> `webroot/index.html` 中封装回调适配器。

## 配置

`config.conf`（模块目录，可在 WebUI 调整；重启后保留）：

| 键 | 可选值 | 说明 |
|---|---|---|
| `SEP_ON_USB` | `0`/`1` | 插电脑 USB 自动分离开关 |
| `CHARGER_MODE` | `0`/`1`/`2` | 充电器模式：关闭/插入立即分离/电量阈值 |
| `THRESHOLD` | `0`/`50`/`60`/`70`/`80`/`90` | 阈值（仅 `CHARGER_MODE=2`） |
| `AUTO_CLOSE` | `0`/`1` | 低于阈值行为：闩锁保持 / 自动关闭 |

无效值会被 `common.sh: read_config` 回退为默认值（`SEP_ON_USB=1, CHARGER_MODE=0, THRESHOLD=70, AUTO_CLOSE=0`）。

## 安装

- SukiSU / KernelSU 管理器安装 `zte-charge-separate.zip`。
- 安装后开机自启，无需手动启动。
- WebUI 入口：模块页 → 打开该模块的 WebUI。

## 卸载

卸载时 `uninstall.sh` 会自动把 `charge_separation_switch` 置回 `0`，恢复正常充电。

## 注意事项

- 只控制厂商原生充电分离开关（`battery_charging_enabled` 硬件节点由系统自身的分离状态驱动），不绕过电池温度、充电器等系统/硬件安全保护。
- 这里的「充电器」指 USB 口正在以 DCP/PD 等充电器类型供电；「PC」指 SDP/CDP 数据口供电。
- 阈值模式每 ~30 秒复核一次电量；拔电后系统自动关闭分离。
- 模块化改动请重新打包 zip：仓库内 `customize.sh` 仅包含安装权限设置，zip 顶层文件分布即模块最终布局（无 META-INF）。