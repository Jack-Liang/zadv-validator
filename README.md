# zadv-validator — 基于 DDIC 的 ABAP 内表通用校验器

传入任意内表，自动根据 DDIC 元数据（域固定值、检查表、转换出口、数据类型）
校验每个字段的每个值，逐行逐字段指出不合法的输入。适合文件上传/批量导入
（Excel、CSV）入库前的合法性检查。

灵感与互补：[hhelibeb/abap-data-validator](https://github.com/hhelibeb/abap-data-validator)
（格式/正则类校验）与
[Nagaraj121999/Dynamic-Validation](https://github.com/Nagaraj121999/Dynamic-Validation)
（检查表校验思路），本库把两类能力合并成一个通用校验器，并补齐了
域固定值校验与错误定位（行号 + 字段 + 原值 + 消息）。

## 校验能力

| 检查 | 来源 | 说明 |
|---|---|---|
| 域固定值 `DOMAIN` | 自动（DD07L/DD01L） | 支持单值与区间；尊重域的小写标志 |
| 检查表 `CHECKTABLE` | 自动（DFIES-CHECKTABLE）或规则指定 | 动态 `SELECT COUNT(*)`，结果缓存；检查表字段同名假设可用 `checkfield` 覆盖 |
| 日期格式 `DATE` | 自动（DATS） | YYYYMMDD，含月份天数与闰年 |
| 时间格式 `TIME` | 自动（TIMS） | HHMMSS |
| 数字串 `NUMC` | 自动（NUMC） | 只允许数字 |
| 转换出口 | 自动（CONVEXIT） | 比较前调用 `CONVERSION_EXIT_xxx_INPUT`（存在性查 TFDIR，失败回退原值） |
| 必填 `REQUIRED` | 规则 | 初始值默认放行，标记 required 后报错 |
| 正则 `REGEX` | 规则 | 用于无 DDIC 类型的字段（如 string 邮箱）；按子串搜索匹配，需全串匹配请用 `^...$` 包裹 |
| 大小写 | 自动 | 域非 lowercase 时按大写比较，兼容从小写来源导入的数据 |

初始值（空）不做任何检查（除 REQUIRED）——与 SAP 录入行为一致。

## 安装（abapGit）

1. SE80 / abapGit（`ZABAPGIT`）→ *Link abapGit Repository*，输入本仓库地址。
2. 包名建议 `ZADV_VALIDATOR`，拉取后激活。
3. 依赖：ABAP 7.40 SP08+（on-prem；直接访问 DD07L/DD01L/TFDIR 并使用动态 SQL，
   不适用于 ABAP Cloud / Steampunk）。

## 快速开始

```abap
DATA(lo_validator) = NEW zcl_adv_validator( ).

" 可选：为非 DDIC 字段或额外约束追加显式规则
lo_validator->add_rules( VALUE #(
  ( fieldname = 'EMAIL'  regex = `^[\w\.\-]+@[\w\.\-]+\.\w{2,}$` )
  ( fieldname = 'REMARK' required = abap_true )
  ( fieldname = 'WERKS'  checktable = 'T001W' ) ) ).  " 覆盖/补充 DDIC 检查表

DATA(lt_findings) = lo_validator->validate( gt_upload ).

IF lt_findings IS INITIAL.
  " 全部通过，可入库
ELSE.
  LOOP AT lt_findings ASSIGNING FIELD-SYMBOL(<fs_f>).
    WRITE: / <fs_f>-row, <fs_f>-fieldname, <fs_f>-value,
             <fs_f>-check_type, <fs_f>-message.
  ENDLOOP.
ENDIF.
```

演示程序：运行报表 `ZADV_DEMO`（SA38），构造一个典型合法行和两个含错行，
以 ALV 输出全部 findings。演示**不 SELECT 任何定制表**，可在任何系统上
激活；检查表类 finding 只在对应检查表（T001/T005/TCURC）存在且可读的系统
上出现，否则按宽容模式放行（不报错、不崩溃）。确定性的校验（域固定值
AS4LOCAL、日期格式、正则、必填）在任何系统上都能看到效果。

## 列过滤

默认校验 DDIC 能推导出的全部列。可以限定范围：

```abap
" 只检查指定列（规则也只对这些列生效；写错字段名会在 findings 里报 STRUCTURE）
lo_validator->only_fields( VALUE #( ( 'BUKRS' ) ( 'WAERS' ) ) ).

" 或排除指定列（与 only_fields 同时设置时，在其范围内排除）
lo_validator->exclude_fields( VALUE #( ( 'REMARK' ) ) ).

" 两个方法均整体替换各自列表；传空表 VALUE #( ) 重置
```

## 单值校验

不构造内表，直接校验一个值（静态方法，内部复用同一套 DDIC 校验逻辑）：

```abap
" 按数据元素
IF zcl_adv_validator=>check_value_by_element(
       iv_value    = lv_bukrs
       iv_rollname = 'BUKRS' ) = abap_false.
  " 非法：需要原因时接 es_finding
ENDIF.

" 或按表字段取 DDIC 定义（域/检查表/转换出口随该字段）
DATA ls_finding TYPE zcl_adv_validator=>ty_finding.
DATA(lv_ok) = zcl_adv_validator=>check_value_by_field(
                  EXPORTING iv_value     = 'Z'
                            iv_tabname   = 'DD07L'
                            iv_fieldname = 'AS4LOCAL'
                  IMPORTING es_finding   = ls_finding ).
```

- 值可按外部格式传入，转换出口在内部执行（如 ALPHA 自动补零）
- 初始值视为合法（与整表校验口径一致，必填请用规则）
- 元素/字段/表不存在 → 返回 `abap_false` 且 `es_finding-check_type = STRUCTURE`

## 返回结构 ty_finding

| 字段 | 含义 |
|---|---|
| `row` | 行号（表内顺序计数）；0 表示结构性问题（表行非结构、规则字段不存在） |
| `fieldname` | 字段名 |
| `value` | 原始输入值（外部格式，直接可读） |
| `check_type` | STRUCTURE / REQUIRED / DOMAIN / CHECKTABLE / DATE / TIME / NUMC / REGEX |
| `object` | 涉及对象：域名 或 `检查表/字段` 或 正则 |
| `message` | 英文消息文本（调用方可用前 5 个字段自建中文消息） |

## 工作原理

1. RTTI 解析内表行结构，`GET_DDIC_FIELD_LIST( )` 取 DFIES 元数据
   （域名、检查表、转换出口、数据类型）；混合结构（含 string 等非 DDIC
   字段）自动回退为逐组件解析，非 DDIC 字段跳过（可用规则接管）。
2. 逐行逐字段：required → 初始值放行 → 转换出口 → 格式检查 → 域固定值
   → 检查表 → 正则；每个字段每行只报第一个错误，避免错误级联噪音。
3. 缓存：域固定值（按域）、检查表命中（按 表+字段+值）、转换出口存在性
   （按出口名）均为实例级缓存；同一实例反复校验大批量数据时，
   同检查表字段的不同取值仍会逐个查库（每个不同值一次 `SELECT COUNT`）。

## 设计取舍与限制

- **检查表字段同名假设**：外键对应字段默认与本字段同名，非同名时用规则
  `checkfield` 指定（完整外键映射在 DD05S，v1 未解析）。
- **元数据错误宽容处理**：检查表无法读取（生成表/视图等）时按"通过"处理，
  不阻塞数据流也不报错——避免误杀合法数据；如需严格模式请自行扩展。
- **域固定值长度**：DD07L 的 DOMVALUE_L/H 上限 10 字符（SAP 限制），
  长值域本库无能为力（与 SE11 行为一致）。
- **自引用跳过**：字段检查表 = 上传结构本身（如基于 T001 的结构校验 BUKRS）
  会被跳过，避免自己查自己。
- **性能**：值基数高的大批量数据建议先 `SORT + DELETE ADJACENT DUPLICATES`
  预去重，或分批调用；域值与转换出口检查无此问题（纯内存）。
- **不走 `DDUT_INPUT_CHECK`**：直接读 DD07L + 动态 SQL 可控性更好、可缓存、
  无 FM 签名依赖；需要其外键级语义时可替换 `check_table` 实现。

## 仓库结构

```
CHANGELOG.md                             更新日志
src/
  package.devc.xml                        包 ZADV_VALIDATOR
  zcl_adv_validator.clas.abap             校验器（类型、常量、方法全部在类中，无接口依赖）
  zcl_adv_validator.clas.testclasses.abap ABAP Unit 测试（17 个用例）
  zadv_demo.prog.abap                     演示报表
```

## 测试

类 `ZCL_ADV_VALIDATOR` 自带 ABAP Unit（SE80 → 类 → 运行，或 ADT），
覆盖：合法行零误报、非法日期/时间/域值、正则与必填规则、规则字段缺失、
非结构化表拒绝、列过滤（only/exclude 及白名单字段名纠错）、单值校验
（check_value_by_element/by_field）。检查表类用例依赖系统主数据，
故在 demo 中演示而非单测。

## 路线图

### v0.3（近期：性能与工程化）
- [ ] **检查表批量查询**：按列收集去重值后 `WHERE field IN (...)` 分批查询，替代逐值 `SELECT COUNT(*)`——大表导入的主要性能瓶颈
- [ ] **消息类化（SE91）**：错误文本迁入消息类，支持 SE63 翻译（当前硬编码英文）
- [ ] 单测补强：转换出口（ALPHA）、小写域、区间型域值、缓存幂等、规则覆盖 DDIC
- [ ] abaplint 基础配置（CI 静态检查）

### v1.0（功能完整版）
- [ ] **完整外键映射**：读 DD05S，支持非同名检查表字段与组合键（多字段外键）
- [ ] **校验插件化**：抽出单列校验器接口（域值/检查表/格式/正则各自实现类），开放注册自定义校验
- [ ] 跨字段与行间规则：如 DATE_FROM <= DATE_TO、文件内查重（依赖插件化）
- [ ] finding 增强：severity（E/W/I）、规则 ID；BAL 应用日志与 ALV 输出 helper
- [ ] CURR/QUAN 参照校验：货币列参照 TCURC、单位列参照 T006（DFIES-REFTABLE/REFFIELD 自动识别）
- [ ] 暂存 STRING 字段截断预检（超长值入库前预警）
- [ ] README 英文版

### v2.0+（生态与场景）
- [ ] 规则配置表：校验规则存自定义表，顾问可维护、可传输，免改代码
- [ ] Excel 上传端到端示例（abap2xlsx → 暂存表 → 校验 → ALV）
- [ ] ABAP Cloud 适配可行性调研（以 released 对象替代 DD07L/DD01L/TFDIR 直读与动态 SQL）
- [ ] GitHub Actions：abaplint + abapGit trial 系统自动激活与单测
- [ ] 大表分批/并行校验

明确不做：7.02 及以下语法降级（维护成本大于收益）、多包拆分、替代 RAP 校验。

## License

MIT
