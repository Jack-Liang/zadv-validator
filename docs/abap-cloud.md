# ABAP Cloud 适配可行性调研

结论先行：**v2.x 维持 on-prem 定位，不做 ABAP Cloud（Steampunk/Embedded
Steam）适配**。核心校验能力建立在「直接读 DDIC 元数据 + 对任意检查表动态
SQL」之上，这两点在 ABAP Cloud 运行时没有 released 的等价物；适配不是移植
而是重写。若未来出现需求，建议先走本文末尾的"元数据提供者接口化"演进，
那是通向 Cloud 的第一步。

## 现有实现对未 released 对象的依赖清单

| 依赖 | 用途 | ABAP Cloud 现状 |
|---|---|---|
| `DD07L` / `DD01L` 直读 | 域固定值、小写标志 | 未 released；无公开等价物 |
| `DD05S` 直读 | 外键映射（非同名/组合键） | 未 released |
| `DD02L` / `DD04L` 直读 | 对象存在性预检（防短转储） | 未 released |
| `TFDIR` 直读 | 转换出口存在性 | 未 released；Cloud 中转换出口机制整体不可用 |
| 动态 `SELECT ... FROM (tab)` | 任意检查表查值 | 动态表名仅允许已 released/自有对象；"任意表"语义不成立 |
| `CONVERSION_EXIT_xxx_INPUT` 动态调用 | 外部格式→内部格式 | 未 released |
| `cl_salv_table`（display_findings 回退路径） | ALV 展示 | 未 released（Cloud 走 RAP/Fiori 展示层） |
| BAL 函数组（log_findings） | 应用日志 | 经典 BAL 未 released（Cloud 用应用日志 API 另有体系） |
| 自建 SE91 消息类 | finding 文本 | 消息类本身在 Cloud 可建，但 `MESSAGE ... INTO` 用法受限 |

另有两个非对象层面的差异：DDIC 定制表（ZADV_RULES 为定制传输类 C）在
Cloud 侧需重建为 managed 表/场景化配置；abapGit 本身也不面向 Cloud 开发流
（Cloud 用 abapGit 的 successor：Embrace/ADT 原生传输）。

## Cloud 中"校验"问题的正确解法

ABAP Cloud 的数据入口校验职责由框架承担，这正是本库**明确不做**的
"替代 RAP 校验"：

- 结构/字段级：CDS view entity 的类型系统 + `@Validation`/BO behavior
  validation（RAP），值帮助关联（value help association）承担"检查表"语义
- 领域固定值：值帮助/固定值注释在 CDS 元数据层表达
- 上传场景：CAP/REST 入口 + RAP action 内联校验，错误回传走框架消息机制

即：Cloud 上"上传内表批量校验"这个场景本身被架构性替代，而非缺一个
可移植的库。

## 若仍要向 Cloud 演进：建议路径

1. **元数据读取接口化**（收益独立于 Cloud）：把 `get_domain` /
   `check_table` / `resolve_foreign_keys` / `conv_exit_exists` 背后的直读
   收敛为 `ZIF_ADV_METADATA_PROVIDER` 之类的注入接口，默认实现仍是 DDIC
   直读——测试替身、CDS 视图实现、未来 Cloud 实现都可在此挂载
2. **检查表语义降级**：Cloud 实现里"任意检查表查值"退化为"声明式值清单"
   （配置表提供允许值集合），放弃 DD05S 组合外键的通用性
3. **展示/日志层替换**：display/log 两 helper 已是纯便利层，Cloud 侧留空
   实现即可，不影响 validate 核心
4. 届时再评估收益是否值得维护第二套 provider

## 记录

- 调研时间：2026-10（v2.0 规划）
- 决定：不进入 v2.x 范围；重新评估触发条件为出现真实的 Cloud 部署需求，
  或 SAP released 上述 DDIC 读取的公开等价物
