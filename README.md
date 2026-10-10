# zadv-validator — 基于 DDIC 的 ABAP 内表通用校验器

[English](README_EN.md)

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
| 检查表 `CHECKTABLE` | 自动（DFIES-CHECKTABLE + DD05S 外键映射）或规则指定 | 外键字段经 DD05S 解析真实检查表字段（支持非同名，如 REGIO→T005A-BLAND）；组合外键按字段组合校验；行循环前批量预填缓存（单列每批 100 值 IN，组合键每批 100 元组 OR-of-ANDs） |
| 货币/单位参照 | 自动（DFIES-REFFIELD） | CURR/QUAN 金额字段引用的代码列（如 WAERS/GEWEI）若在上传结构中且无自有外键/规则，自动补 TCURC/WAERS、T006/MSEHI 检查（复用检查表全套机制，含 CUNIT 转换） |
| 日期格式 `DATE` | 自动（DATS） | YYYYMMDD，含月份天数与闰年 |
| 时间格式 `TIME` | 自动（TIMS） | HHMMSS |
| 数字串 `NUMC` | 自动（NUMC） | 只允许数字 |
| 转换出口 | 自动（CONVEXIT） | 比较前调用 `CONVERSION_EXIT_xxx_INPUT`（存在性查 TFDIR，失败回退原值） |
| 必填 `REQUIRED` | 规则 | 初始值默认放行，标记 required 后报错 |
| 插件 `PLUGIN` | 注册（`add_column_check`） | 实现接口 `ZIF_ADV_COLUMN_CHECK` 的自定义单列校验类，逐行收到 值+整行引用（可做简单跨字段）；自行决定 ok/文本/severity/rule_id |
| 比较 `COMPARE` | 规则（`add_compare_rule`） | 声明式跨字段比较：`field operator other`（EQ/NE/LT/LE/GT/GE），如 DATE_FROM <= DATE_TO；任一操作数为初始值时跳过（要拦截空值请配合 required）；行级规则，不受列过滤影响 |
| 查重 `UNIQUE` | 规则（`add_unique_rule`） | 声明式文件内查重：字段组合在整个表中必须唯一，首次出现放行、后续重复报错（消息注明首次所在行）；组合内字段全为初始值的行豁免 |
| 正则 `REGEX` | 规则 | 用于无 DDIC 类型的字段（如 string 邮箱）；按子串搜索匹配，需全串匹配请用 `^...$` 包裹 |
| 规则来源：配置表 | 自动（`ZADV_RULES`） | 三类规则按场景（SCENARIO）存定制表，`add_rules_from_db( )` 加载，顾问可维护、随定制请求传输，免改代码；语义与代码注册完全一致 |
| 大小写 | 自动 | 域非 lowercase 时按大写比较，兼容从小写来源导入的数据 |

初始值（空）不做任何检查（除 REQUIRED）——与 SAP 录入行为一致。

## 安装（abapGit）

1. SE80 / abapGit（`ZABAPGIT`）→ *Link abapGit Repository*，输入本仓库地址。
2. 包名建议 `ZADV_VALIDATOR`，拉取后激活。包内含 SE91 消息类
   `ZADV_VALIDATOR`（finding 文本来源），随包一起拉取，整包激活即可。
3. 依赖：ABAP 7.40 SP08+（on-prem；直接访问 DD07L/DD01L/TFDIR 并使用动态 SQL，
   不适用于 ABAP Cloud / Steampunk）。

## 快速开始

```abap
DATA(lo_validator) = NEW zcl_adv_validator( ).

" 可选：为非 DDIC 字段或额外约束追加显式规则
lo_validator->add_rules( VALUE #(
  ( fieldname = 'EMAIL'  regex = `^[\w\.\-]+@[\w\.\-]+\.\w{2,}$` )
  ( fieldname = 'REMARK' required = abap_true )
  ( fieldname = 'NOTIFY' regex = `^X?$` severity = 'W' rule_id = 'R01' )
  ( fieldname = 'WERKS'  checktable = 'T001W' ) ) ).  " 覆盖/补充 DDIC 检查表

" 可选：声明式跨字段比较与文件内查重（见下文专章）
lo_validator->add_compare_rule( VALUE #( field = 'DATE_FROM' operator = 'LE'
                                         other = 'DATE_TO' rule_id = 'R_PERIOD' ) ).
lo_validator->add_unique_rule(  VALUE #( field = 'REF_ID' rule_id = 'R_DUP_REF' ) ).

DATA(lt_findings) = lo_validator->validate( gt_upload ).

IF lt_findings IS INITIAL.
  " 全部通过，可入库
ELSE.
  " 直接展示：内置 SALV helper（无 SALV 系统自动回退经典列表）
  zcl_adv_validator=>display_findings(
      it_findings = lt_findings
      iv_title    = 'Upload validation' ).

  " 或落应用日志（SLG1 查看；对象需先在 SLG0 注册）：
  " zcl_adv_validator=>log_findings(
  "     it_findings = lt_findings
  "     iv_object   = 'ZUPLOAD' iv_commit = abap_true ).

  " 或自行处理，例如只拦截错误、放行警告：
  " LOOP AT lt_findings TRANSPORTING NO FIELDS
  "      WHERE severity = zcl_adv_validator=>c_severity-error.
  " ENDLOOP.
ENDIF.
```

演示程序：运行报表 `ZADV_DEMO`（SA38），构造一个典型合法行和两个含错行，
以 ALV 输出全部 findings；另有 v1.0 特性演示段（组合外键 KNA1、单位参照
MARA、货币参照 VBAK），DDIC 表在**运行期解析**，缺对象的系统自动跳过该段，
不阻塞激活，finding 输出在经典列表上（ALV 返回后可见）。演示**不 SELECT
任何定制表**，可在任何系统上激活；检查表类 finding 只在对应检查表
（T001/T005/TCURC/T005A/T006）存在且可读的系统上出现，否则按宽容模式放行
（不报错、不崩溃）。确定性的校验（域固定值 AS4LOCAL、日期格式、正则、必填）
在任何系统上都能看到效果。

## 用法总览（API）

一个校验器实例 = 一次导入场景。注册规则/插件/过滤 → `validate( )` 一次 →
按 `severity` 分流处理 findings；四个静态 helper 不需要实例，随取随用。

**实例方法（`NEW zcl_adv_validator( )` 之后链式配置）**

| 方法 | 用途 |
|---|---|
| `validate( it_data iv_row_offset )` | 校验任意内表，返回 `ty_findings`（每条含行号/字段/原值/类别/消息/severity/rule_id）；`iv_row_offset` 供大表分批时保持全局行号 |
| `add_rule( )` / `add_rules( )` / `clear_rules( )` | 列级显式规则：required / regex / checktable+checkfield / domname / severity / rule_id（无 DDIC 类型的字段靠它接管） |
| `add_compare_rule( )` / `add_compare_rules( )` / `clear_compare_rules( )` | 行级跨字段比较：`field operator other`（EQ/NE/LT/LE/GT/GE），如 DATE_FROM <= DATE_TO；初始操作数跳过 |
| `add_unique_rule( )` / `add_unique_rules( )` / `clear_unique_rules( )` | 表级查重：字段组合全表唯一（`fields` 空 = 仅 `field` 单字段）；首次放行、后续报错并注明首次行号 |
| `add_rules_from_db( )` | 从配置表 `ZADV_RULES` 按场景（SCENARIO）加载三类规则；返回加载数，表缺失/场景无记录返回 0 不抛异常 |
| `add_column_check( )` / `clear_column_checks( )` | 注册插件（实现 `ZIF_ADV_COLUMN_CHECK` 的类），自带 ok/文本/severity/rule_id，收到整行引用 |
| `only_fields( )` / `exclude_fields( )` | 列过滤（白名单优先，整体替换，传空重置） |
| `clear_caches( )` | 清空域值/检查表/转换出口缓存（定制数据变更后用） |

**静态方法（无需实例）**

| 方法 | 用途 |
|---|---|
| `check_value_by_element( )` / `check_value_by_field( )` | 单值校验：按数据元素或表字段取 DDIC 定义，返回真假 + finding 原因 |
| `precheck_truncation( )` | 截断预检：string 暂存表 vs 目标 DDIC 结构同名列长度，超长预警（缺省 W） |
| `display_findings( )` | findings 进 SALV（优化列宽 + 标题；无 SALV 回退经典列表） |
| `log_findings( )` | findings 写 BAL 应用日志（SLG1 查看；对象先在 SLG0 注册） |

**关键类型与常量**：`ty_finding` / `ty_rule` / `ty_compare_rule` /
`ty_unique_rule`（结构见上文各章节与 SE11 风格注释）；类别常量
`c_check-*`（STRUCTURE/REQUIRED/DOMAIN/CHECKTABLE/DATE/TIME/NUMC/
REGEX/PLUGIN/COMPARE/UNIQUE/TRUNCATION）；严重度常量 `c_severity-error/
warning/info`；字段名列表 `ty_fieldnames`（string 行类型，构造用反引号
字面量）。库版本等元数据在 `ZIF_ADV_METADATA`（`c_version` 等）。


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

## 版本元数据

库的版本、作者、仓库地址等信息集中在常量接口 `ZIF_ADV_METADATA`，
`ZCL_ADV_VALIDATOR` 实现该接口并以同名别名暴露，两种访问方式等价：

```abap
DATA(lv_version) = zif_adv_metadata=>c_version.   " 直接走接口
WRITE: / zcl_adv_validator=>c_repository.          " 走类别名
```

| 常量 | 内容 |
|---|---|
| `c_version` | 语义化版本 `MAJOR.MINOR.PATCH`（与 CHANGELOG 同步） |
| `c_author` | 维护者 |
| `c_repository` | 仓库与 issue 跟踪地址 |
| `c_license` | SPDX 许可标识（MIT） |
| `c_description` | 一句话描述 |

依赖本库的项目可直接读取（"关于"页、升级诊断输出等）；其他开源库也
可以照搬这个模式——建一个自包含的常量接口，实现类用 `ALIASES` 暴露，
消费方即可统一按 `zif_xxx=>c_version` 的约定获取库信息。

## 校验插件（自定义单列校验）

实现接口 `ZIF_ADV_COLUMN_CHECK` 并按字段注册，即可插入任意自定义校验——
无需修改校验器本身。插件在**内置校验之后**执行（每字段每行只报第一个错误，
所以插件只看到校验器自己放行的值），并拿到整行引用，简单跨字段规则立即可做：

```abap
CLASS lcl_check_shipment DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES zif_adv_column_check.
ENDCLASS.

CLASS lcl_check_shipment IMPLEMENTATION.
  METHOD zif_adv_column_check~check.
    " 注册在 DELIV_MODE 上：值 = 'EXPRESS' 时要求同一行的 PRIORITY 非空
    rs_result-ok = abap_true.
    ASSIGN ir_row->* TO FIELD-SYMBOL(<ls_row>).
    ASSIGN COMPONENT 'PRIORITY' OF STRUCTURE <ls_row> TO FIELD-SYMBOL(<lv_prio>).
    IF sy-subrc = 0 AND iv_value = 'EXPRESS' AND <lv_prio> IS INITIAL.
      rs_result-ok       = abap_false.
      rs_result-severity = 'E'.                       " 初始/非法值归一为 E
      rs_result-message  = |express delivery needs a priority|.
      rs_result-rule_id  = 'R_EXPRESS_PRIO'.          " 回显到 finding-rule_id
    ENDIF.
  ENDMETHOD.
ENDCLASS.

lo_validator->add_column_check(
    iv_fieldname = 'DELIV_MODE'
    io_check     = NEW lcl_check_shipment( ) ).
```

- 接口**自包含**（自带 ty_result 类型，不引用主类），无激活顺序问题
- 注册到无 DDIC 元数据的列（如 string）也有效；未知字段名在 validate 时报
  STRUCTURE finding（与规则同一条 003 消息）
- finding 的 `check_type = 'PLUGIN'`（常量 `c_check-plugin`），文本由插件
  直接给出（不经 SE91 消息类）
- `clear_column_checks( )` 清空全部注册

## 跨字段与行间规则（声明式）

插件适合带自定义逻辑的校验；如果只是"字段之间比大小"、"文件里不许有重复"，
不用写类，直接声明规则即可：

```abap
" 跨字段比较：BUDAT <= DATE_TO（操作符 EQ/NE/LT/LE/GT/GE）
" finding 定位在左操作数字段上，object 为 'BUDAT <= DATE_TO'
lo_validator->add_compare_rule( VALUE #(
    field    = 'BUDAT'
    operator = 'LE'
    other    = 'DATE_TO'
    severity = 'W'
    rule_id  = 'R_PERIOD' ) ).

" 文件内查重：REF_ID+WERKS 组合全表唯一
" 首次出现放行，后续重复报错并注明首次所在行
lo_validator->add_unique_rule( VALUE #(
    field    = 'REF_ID'            " finding 定位字段（锚点）
    fields   = VALUE #( ( `REF_ID` ) ( `WERKS` ) )
    rule_id  = 'R_DUP_KEY' ) ).
```

- **比较规则**逐行执行，在列级检查之后、与列过滤无关（行级规则）；任一
  操作数为**初始值时跳过**比较——要拦截空值请给字段加 `required` 规则。
  两个无法比较的值（如数字串与文本）按违反处理
- **查重规则**在整表扫描后执行，与列过滤无关；`fields` 为空时退化为仅
  `field` 单字段查重；组合按字段名**排序**后求值，finding 的
  `value/object` 顺序确定（`WERKS+REF_ID`）与注册顺序无关；组合内字段
  **全为初始值**的行豁免（与"初始值放行"的整体口径一致）
- 未知字段名、非法操作符（非 EQ/NE/LT/LE/GT/GE）在 validate 时报
  STRUCTURE finding（消息 003/020），不会静默失效
- finding 类别：`c_check-compare` / `c_check-unique`；severity 缺省 E，
  `rule_id` 回显，与列级规则一致
- `clear_compare_rules( )` / `clear_unique_rules( )` 清空各自注册；
  复杂逻辑（跨行聚合、条件依赖）仍建议走插件或调用方自处理

## 暂存 STRING 截断预检

文件上传常先进 string 暂存表再 MOVE 到 DDIC 目标结构——超长值会被
**静默截断**。入库前用静态方法预先预警：

```abap
" it_data：string 暂存表；iv_typename：目标 DDIC 表/结构名
DATA(lt_findings) = zcl_adv_validator=>precheck_truncation(
    it_data     = lt_staging
    iv_typename = 'ZTARGET' ).        " 缺省 severity = W（预警）
```

- 只比较**两边同名**的列；目标侧仅字符类类型（CHAR/NUMC/DATS/TIMS/ACCP/
  LANG/UNIT/CUKY/CLNT）参与——金额/数量类赋值报错而非截断，无需预警
- 值长度（string 转换去尾部空格后）> 目标字段长度 → `TRUNCATION` finding
  （`c_check-truncation`），`object` 为 `目标/字段`，severity 可用
  `iv_severity` 覆盖（缺省 W）
- 目标不存在/非 DDIC 结构 → STRUCTURE finding（消息 012），不抛异常
- 暂存侧的 raw/xstring 列无文本长度概念，自动跳过

## Excel 上传端到端示例

文件上传的完整管线（abap2xlsx 读文件 → string 暂存 → 截断预检 → 校验 →
展示/留档）。abap2xlsx 是独立第三方库（[abap2xlsx](https://github.com/abap2xlsx/abap2xlsx)），
需单独安装，本库**不依赖它**——管线从第 2 步起与文件来源无关，CSV/应用服务器
文件同样适用：

```abap
" 1) abap2xlsx 读工作表（reader API 以所用版本为准）
DATA(lo_excel) = CAST zif_excel_reader( NEW zcl_excel_reader_2007( )
                   )->load_file( i_excel2007 = lv_xstring ).
DATA(lo_sheet) = lo_excel->get_worksheet_by_name( 'Sheet1' ).

" 2) 写入 string 暂存表：列名与目标 DDIC 结构同名（此处以 ZSDI_UPLOAD 为例）
DATA lt_stage TYPE STANDARD TABLE OF ty_stage WITH EMPTY KEY.  " 全 string 列
" LOOP AT lo_sheet->... INTO lt_stage.  " 或按行读单元格

" 3) 截断预检：超长值在 MOVE 到目标结构之前预警
DATA(lt_trunc) = zcl_adv_validator=>precheck_truncation(
                     it_data = lt_stage iv_typename = 'ZSDI_UPLOAD' ).
" lt_trunc 非空时按 severity 分流：E 回退修正 / W 提示确认

" 4) MOVE 到目标类型并校验（规则从配置表按场景加载，免改代码）
DATA lt_upload TYPE STANDARD TABLE OF zsdi_upload WITH EMPTY KEY.
LOOP AT lt_stage ASSIGNING FIELD-SYMBOL(<ls_stage>).
  APPEND INITIAL LINE TO lt_upload ASSIGNING FIELD-SYMBOL(<ls_upload>).
  MOVE-CORRESPONDING <ls_stage> TO <ls_upload>.
ENDLOOP.

DATA(lo_validator) = NEW zcl_adv_validator( ).
lo_validator->add_rules_from_db( iv_scenario = 'ZSDI_UPLOAD' ).
DATA(lt_findings) = lo_validator->validate( lt_upload ).

" 5) 展示（ALV）+ 留档（BAL，SLG1 查看）
zcl_adv_validator=>display_findings(
    it_findings = lt_findings iv_title = 'Upload validation' ).
zcl_adv_validator=>log_findings(
    it_findings = lt_findings iv_object = 'ZSDI_UPLOAD' iv_commit = abap_true ).
```

## 应用日志（BAL）

把 findings 写成 SLG1 可查的应用日志（每条 finding 一条消息，消息类型 =
severity，finding 文本经通用消息 018 分装到 4×50 字符占位符）：

```abap
DATA(lv_log_handle) = zcl_adv_validator=>log_findings(
    it_findings = lt_findings
    iv_object   = 'ZUPLOAD'          " 需先在 SLG0 注册（或用自有对象）
    iv_subobject = 'VALIDATE'
    iv_extnumber = |upload { sy-datum }|
    iv_commit   = abap_true ).       " 可选：helper 内直接 COMMIT WORK
```

- 返回日志句柄；findings 为空、对象未注册或 BAL 出错时返回初始值，
  **从不抛异常**（结果请看 SLG1）
- 保存在当前 LUW，提交由调用方控制；不在更大事务里时可用
  `iv_commit = abap_true` 让 helper 直接提交

## 规则配置表（ZADV_RULES）

规则可以不改代码、由顾问维护并随传输发布：包内自带客户端相关定制表
`ZADV_RULES`（定制传输类 C + 数据类 APPL2），每行一条规则或查重键字段，按**场景**加载：

```abap
DATA(lo_validator) = NEW zcl_adv_validator( ).
DATA(lv_count) = lo_validator->add_rules_from_db( iv_scenario = 'ZSDI_UPLOAD' ).
" lv_count = 实际加载数；0 = 表缺失或场景无记录（不抛异常）

DATA(lt_findings) = lo_validator->validate( gt_upload ).
```

表结构（键：SCENARIO / RULE_ID / FIELDNAME）：

| RULE_TYPE | 映射到 | 用到的列 |
|---|---|---|
| `COLUMN` | `add_rule( )` 列级规则 | FIELDNAME + REQUIRED / REGEX / CHECKTABLE + CHECKFIELD / DOMNAME |
| `COMPARE` | `add_compare_rule( )` 行级比较 | FIELDNAME（左操作数）+ OPERATOR（EQ/NE/LT/LE/GT/GE）+ OTHER_FIELD（右操作数） |
| `UNIQUE` | `add_unique_rule( )` 表级查重 | 同一 RULE_ID 的多行各贡献一个键字段（FIELDNAME），按字段名排序最前者为锚点；单行即单字段查重 |

SEVERITY、RULE_ID 三类通用（语义与代码注册一致）。要点：

- **维护**：SE16N 直接维护，或 SE11 里为表生成维护界面（SM30）；
  随定制请求传输（无需改代码、无需重新发布程序）
- **宽容**：未知 RULE_TYPE 跳过；表对象不存在或场景无记录返回 0——
  SELECT 走动态表名，类与表之间**没有激活顺序依赖**
- 未知字段名/非法操作符不会被跳过：validate 照常报 STRUCTURE
  finding（003/020），配置错误在第一次运行就可见
- 同一实例可与代码注册（`add_rule` 等）混用，加载只追加不清空；
  REGEX 列为 CHAR255，超长正则请在代码里注册
- DEMO：`ZADV_DEMO` 开头即按场景 `DEMO` 加载（无记录时打印说明）

## 返回结构 ty_finding

| 字段 | 含义 |
|---|---|
| `row` | 行号（表内顺序计数）；0 表示结构性问题（表行非结构、规则字段不存在） |
| `fieldname` | 字段名 |
| `value` | 原始输入值（外部格式，直接可读）；查重 finding 为组合值（`值1/值2`，按字段名排序） |
| `check_type` | STRUCTURE / REQUIRED / DOMAIN / CHECKTABLE / DATE / TIME / NUMC / REGEX / PLUGIN / COMPARE / UNIQUE / TRUNCATION |
| `object` | 涉及对象：域名、`检查表/字段`（组合外键为 `检查表/字段1+字段2`）、正则、比较表达式（`字段1 <= 字段2`）、查重字段组合（`字段1+字段2`）或 截断预检的 `目标/字段` |
| `message` | 消息文本，取自 SE91 消息类 `ZADV_VALIDATOR`（001–020），可 SE63 翻译；调用方也可用前 5 个字段自建消息。注意占位符最长 50 字符，超长 `value` 会被截断，完整值请看 `value` 字段 |
| `severity` | `E` / `W` / `I`（`c_severity-error/warning/info`），**永不为空**：DDIC 类检查恒为 `E`；规则类检查取规则 `severity`（缺省/非法值归一为 `E`）；截断预检缺省 `W` |
| `rule_id` | 仅规则来源的 finding 填充（回显规则里的 `rule_id`，便于程序分支/统计）；DDIC 类 finding 保持空 |

## 工作原理

1. RTTI 解析内表行结构，`GET_DDIC_FIELD_LIST( )` 取 DFIES 元数据
   （域名、检查表、转换出口、数据类型）；混合结构（含 string 等非 DDIC
   字段）自动回退为逐组件解析，非 DDIC 字段跳过（可用规则接管）。
2. 检查表批量预取：行循环前，按"检查表/字段"分组收集全表去重后的内部格式值，
   每批 100 个值用 `SELECT DISTINCT ... WHERE field IN (...)` 一次性查库并
   预填缓存——大表导入从"每个不同值一次往返"降为"每列每 100 个不同值一次"。
   组合外键（DD05S 多字段映射）按"检查表/键字段组"收集去重元组，每批 100 个
   元组用 OR-of-ANDs 一次查库；伙伴字段为空的行回退单列批量预取。
   动态 SQL 失败（生成表/视图等不可读）时不缓存，逐值回退到宽容模式。
3. 逐行逐字段：required → 初始值放行 → 转换出口+大小写归一 → 格式检查
   → 域固定值 → 检查表 → 正则 → 插件；每个字段每行只报第一个错误，
   避免错误级联噪音。每行的字段级检查之后执行声明式比较规则（行级，
   与列过滤无关）；行循环结束后整表执行查重规则。此时检查表查询几乎
   全部命中缓存，不再逐值查库。
4. 缓存：域固定值（按域）、检查表命中（按 表+字段+值）、转换出口存在性
   （按出口名）均为实例级缓存；`clear_caches( )` 可在定制数据变更后清空。

## 大表分批与并行校验

`validate( )` 支持分批：传 `iv_row_offset` 后 finding 行号 = 偏移 + 片内
位置（结构性 finding 恒为 0），各片结果可直接汇总：

```abap
DATA: lt_findings TYPE zcl_adv_validator=>ty_findings,
      lt_chunk    LIKE gt_upload,
      lv_off      TYPE i.

WHILE lv_off < lines( gt_upload ).
  CLEAR lt_chunk.
  APPEND LINES OF gt_upload
       FROM lv_off + 1
         TO nmin( val1 = lv_off + 50000 val2 = lines( gt_upload ) )
       TO lt_chunk.
  APPEND LINES OF lo_validator->validate( it_data       = lt_chunk
                                          iv_row_offset = lv_off )
       TO lt_findings.
  lv_off = lv_off + 50000.
ENDWHILE.
```

- 分批主要控制单次运行时长与内存；实例缓存跨片保留（同实例分批时
  检查表去重值只查一次库）
- **查重规则与分批互斥**：`UNIQUE` 在每次 `validate( )` 内独立求值，
  跨片重复检测不到——需要查重的场景不要分批，或先在库里预聚合
- 并行：每片一个**新实例**（校验器无共享状态，缓存独立），经 aRFC/
  后台任务并行执行，`iv_row_offset` 保证行号可合并；收益最大的是
  检查表 DB 往返占比高的场景，注意并行任务数与数据库连接配额

## 设计取舍与限制

- **外键映射（DD05S）**：DDIC 检查表字段的真实映射读自 DD05S——非同名检查
  字段自动生效，组合外键按字段组合校验（如 LAND1+REGIO → T005A）。
  伙伴字段不在上传结构中（或被列过滤排除）时按单字段语义校验；伙伴值为空
  的行宽容回退单字段检查（与旧版行为一致）。客户端字段（MANDT）不参与组合。
  规则指定的检查表不查 DD05S（`checkfield` 即完整映射）。
  混合/本地结构（非 DDIC 命名结构）无 DD05S 上下文，仍按同名字段处理。
- **元数据错误宽容处理**：检查表无法读取（生成表/视图等）时按"通过"处理，
  不阻塞数据流也不报错——避免误杀合法数据；如需严格模式请自行扩展。
- **域固定值长度**：DD07L 的 DOMVALUE_L/H 上限 10 字符（SAP 限制），
  长值域本库无能为力（与 SE11 行为一致）。
- **自引用跳过**：字段检查表 = 上传结构本身（如基于 T001 的结构校验 BUKRS）
  会被跳过，避免自己查自己。
- **性能**：检查表查询已按列分批（每批 100 个去重值）；值基数极高
  （单列不同值数以万计）时可再 `SORT + DELETE ADJACENT DUPLICATES`
  预去重或分批调用；域值与转换出口检查无此问题（纯内存）。
- **不走 `DDUT_INPUT_CHECK`**：直接读 DD07L + 动态 SQL 可控性更好、可缓存、
  无 FM 签名依赖；需要其外键级语义时可替换 `check_table` 实现。

## 仓库结构

```
CHANGELOG.md                             更新日志
abaplint.json                            abaplint 基础规则（CI 静态检查）
.github/workflows/abaplint.yml           GitHub Actions：push/PR 自动跑 abaplint
.github/workflows/abap-unit.yml          GitHub Actions：self-hosted ABAP 系统激活+单测（默认关闭）
docs/abap-cloud.md                       ABAP Cloud 适配可行性调研
src/
  package.devc.xml                        包 ZADV_VALIDATOR
  zadv_validator.msag.xml                 SE91 消息类 ZADV_VALIDATOR（001–020）
  zadv_rules.tabl.xml                     规则配置表 ZADV_RULES（定制传输类 C，随定制请求传输）
  zif_adv_metadata.intf.abap              元数据常量接口（版本/作者/仓库/许可/描述）
  zif_adv_column_check.intf.abap           校验插件接口（自定义单列校验）
  zcl_adv_validator.clas.abap             校验器（类型、常量、方法全部在类中，实现 ZIF_ADV_METADATA 暴露库元数据）
  zcl_adv_validator.clas.testclasses.abap ABAP Unit 测试（52 个用例，其中 1 例 DANGEROUS 级：真实 ZADV_RULES 往返，写后回滚）
  zadv_demo.prog.abap                     演示报表
```

## 测试

类 `ZCL_ADV_VALIDATOR` 自带 ABAP Unit（SE80 → 类 → 运行，或 ADT），
覆盖：合法行零误报、非法日期/时间/域值、正则与必填规则、规则字段缺失、
非结构化表拒绝、列过滤（only/exclude 及白名单字段名纠错）、单值校验
（check_value_by_element/by_field）、检查表规则路由与批量预取
（以 DD07L/DOMNAME 为检查表，不依赖系统主数据）、缺失检查表的宽容回退、
缓存幂等（重复 validate 与 clear_caches 后结果一致）、ALPHA 转换出口
（VBELN）、组合外键（KNA1 LAND1+REGIO → T005A：有效组合通过、无效组合
拦截并验证 DD05S 非同名映射 REGIO→BLAND、伙伴为空的宽容回退、缓存幂等）、
CURR/QUAN 参照（MARA GEWEI→T006/MSEHI 含 CUNIT 转换、VBAK WAERS→
TCURC/WAERS，有效值通过 + 未知代码拦截）、元数据接口完整性
（版本为语义化格式、仓库为 GitHub 地址、类别名与接口常量一致）、
插件（string 列自定义校验 + severity/rule_id 回显、未知字段、经 ir_row
的跨字段）、比较规则（违反定位在左操作数/满足与初始值跳过/未知字段与
非法操作符的 STRUCTURE 报告）、查重规则（组合重复报错并验证排序无关性、
全初始行豁免、未知字段）、截断预检（超长值 W 级报告、合规值与暂存特有
列放行）、BAL 消息映射（severity→消息类型、4×50 字符分块、空 findings
不建日志）、小写域与区间型域值（运行期从 DD01L/DD07L 发现样例对象，
不硬编码跨版本依赖；无样例的系统上自动跳过）、规则配置表映射
（COLUMN/COMPARE/UNIQUE 三类映射与锚点规则、未知类型跳过、表缺失/
空场景宽容返回 0）、行号偏移（列级与查重 finding 均随偏移）。
KNA1/MARA/VBAK/VBELN 等应用 DDIC 对象一律运行时解析（RTTI 动态建表、
逐组件赋值），测试类不含对应用表的静态类型引用——缺这些对象的系统
（如无 SD/MM 的精简安装）上相关用例自动空跑跳过，不再阻塞类激活；
依赖真实主数据的场景（真实检查表 T001 等）仍以 demo 演示为主。

## 路线图

### v0.3（性能与工程化）——已完成
- [x] **检查表批量查询**：按列收集去重值后 `WHERE field IN (...)` 分批查询（每批 100 值）预填缓存，替代逐值 `SELECT COUNT(*)`；动态 SQL 失败自动回退逐值宽容模式
- [x] **消息类化（SE91）**：错误文本迁入消息类 `ZADV_VALIDATOR`（001–014），支持 SE63 翻译
- [x] 单测补强：转换出口（ALPHA/VBELN）、缓存幂等、规则路由检查表（checktable/checkfield 覆盖）、缺失检查表宽容回退（小写域、区间型域值缺跨版本稳定样例域，挪至 v1.0）
- [x] abaplint 基础配置 + GitHub Actions CI（`.github/workflows/abaplint.yml`）

### v1.0（功能完整版）——已发布 1.0.0
- [x] **完整外键映射**：读 DD05S，支持非同名检查表字段与组合键（多字段外键）。
  伙伴字段缺失/被列过滤排除 → 单字段语义；伙伴值为空 → 宽容回退单字段检查；
  MANDT 不参与组合；规则指定检查表不受 DD05S 影响
- [x] CURR/QUAN 参照校验：货币列参照 TCURC、单位列参照 T006（DFIES-REFTABLE/REFFIELD 自动识别）。
  仅当代码列无自有外键/规则时补检查，绝不重复报错
- [x] 计划外交付：库元数据接口 `ZIF_ADV_METADATA`（c_version 等常量）、7.40 SP08
  真机激活兼容与短转储防护、demo v1.0 演示段（运行期解析 DDIC，最小系统可激活）

### v1.1（延续）——已完成
- [x] **校验插件化**：新增自包含接口 `ZIF_ADV_COLUMN_CHECK` + `add_column_check( )` 注册开放点，自定义单列校验（含经整行引用 ir_row 的简单跨字段）；内置校验保留在类内——与批量预取/缓存紧耦合，组合外键本身跨字段，拆出反而损失性能与行为兼容
- [x] **跨字段与行间规则（声明式）**：`add_compare_rule( )` 行级比较（field operator other，EQ/NE/LT/LE/GT/GE，初始操作数跳过）与 `add_unique_rule( )` 文件内查重（字段组合唯一，首次放行后续报错、全初始行豁免）；均为行级/表级规则，不受列过滤影响，未知字段/非法操作符报 STRUCTURE
- [x] finding 增强（severity/规则 ID）：`ty_finding` 新增 `severity`（E/W/I，永不为空；DDIC 类恒 E，规则类取规则值）与 `rule_id`（仅规则来源回显）；`ty_rule` 新增 `severity`（缺省/非法归一 E）与 `rule_id`
- [x] ALV 输出 helper：`display_findings( )` 静态方法（SALV 优化列宽 + 可选标题，无 SALV 回退经典列表）
- [x] BAL 应用日志 helper：`log_findings( )` 静态方法（每 finding 一条消息，severity→消息类型，文本 4×50 分块；SLG1 查看，宽容不抛异常，LUW 提交由调用方控制）
- [x] 暂存 STRING 截断预检：`precheck_truncation( )` 静态方法（string 暂存表 vs 目标 DDIC 结构同名列长度，超长预警 W，仅字符类目标参与）
- [x] 单测补遗：小写域、区间型域值——不再依赖硬编码样例域，运行期从 DD01L（lowercase）/DD07L（区间行）发现样例对象，无样例系统自动跳过
- [x] README 英文版（README_EN.md，与中文版同构）

### v2.0（生态与场景）——已发布 2.0.0
- [x] **规则配置表**：客户端相关定制表 `ZADV_RULES` 随包交付（SE16N/SM30 维护、
  随定制请求传输、免改代码），`add_rules_from_db( iv_scenario )` 场景化加载
  三类规则；动态 SELECT 无激活顺序依赖，表缺失/空场景宽容返回 0
- [x] **Excel 上传端到端示例**：README 文档化完整管线（abap2xlsx → string
  暂存 → 截断预检 → 校验 → ALV/BAL）；abap2xlsx 为独立第三方库，本库不引入
  依赖，管线自暂存表起与文件来源无关（CSV/AL11 同样适用）
- [x] **ABAP Cloud 适配可行性调研**：见 [docs/abap-cloud.md](docs/abap-cloud.md)——
  结论：v2.x 维持 on-prem（DDIC 直读、动态 SQL、SALV、BAL 均未 released，
  适配等于重写元数据层）；向 Cloud 演进的第一步（元数据读取接口化）已记录
- [x] **GitHub Actions 扩展**：`abap-unit.yml` 工作流就绪（abaplint 之后对
  self-hosted runner 执行 abapGit 拉取激活 + ABAP Unit），经仓库变量
  `ABAP_RUNNER` 控制启停，接入 runner 即生效；`abaplint.yml` 维持不变
- [x] **大表分批/并行校验**：`validate( iv_row_offset )` 分批保持全局行号
  （顺带修复哈希表输入时查重行号恒为 0 的问题），并行调用模式（每片独立
  实例 + 偏移合并）文档化；查重规则与分批互斥的语义已在文档注明

明确不做：7.02 及以下语法降级（维护成本大于收益）、多包拆分、替代 RAP 校验。

## License

MIT
