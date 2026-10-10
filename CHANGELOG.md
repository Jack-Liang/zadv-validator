# 更新日志

## 未发布

- 校验插件化（v1.1）：新增自包含接口 `ZIF_ADV_COLUMN_CHECK`（自带 ty_result
  类型，不引用主类，无激活顺序依赖）与 `add_column_check( )` /
  `clear_column_checks( )` 注册 API；插件在内置校验之后逐行执行（首错即止），
  收到 行号/字段名/外部格式值/**整行引用 ir_row**——简单跨字段规则即刻可做；
  finding 走新类别 `PLUGIN`（c_check-plugin），severity 经 normalize、
  rule_id/文本由插件给出；注册到无 DDIC 元数据的列自动合成字段，未知字段名
  走既有 003 STRUCTURE 报告。内置校验保留在类内：与批量预取/缓存紧耦合、
  组合外键本身跨字段，拆出损失大于收益
- 单测 32 → 35：插件自定义校验（string 列 + W + rule_id 回显）、未知字段
  STRUCTURE、跨字段插件（STATUS='A' 需 MAIL，经 ir_row 读同行）；demo 增加
  example.com 域名 I 级插件演示
- finding 增强（v1.1）：`ty_finding` 新增 `severity`（E/W/I，**永不为空**——DDIC 类
  检查恒为 E，规则类检查取规则值）与 `rule_id`（仅规则来源回显，便于调用方
  分支/统计）；`ty_rule` 新增 `severity`（初始/非法值经 normalize_severity 归一
  为 E）与 `rule_id`。结构追加在尾部，既有按名赋值的代码不受影响
- 新增 ALV 输出 helper 静态方法 `display_findings( it_findings iv_title )`：
  SALV 优化列宽 + 可选标题，无 SALV 系统回退经典列表输出，不再抛出；
  ZADV_DEMO 的 ALV 段改用该 helper（dogfooding）
- 单测 28 → 32：规则 severity=W + rule_id 回显且同行 DDIC finding 恒 E 无
  rule_id、规则缺省 severity 归一 E、非法 severity 回退 E、纯 DDIC finding
  的 severity/rule_id 断言
- 修复：ddic_finding_severity_e 误写静态调用 `NEW ...( )=>validate`（实为
  实例方法，716 行激活报 RETURNING 参数错），改 `->`


## v1.0.0（2026-10）

- demo：ZADV_DEMO 补 v1.0 特性演示段——组合外键（KNA1 LAND1+REGIO → T005A）、
  单位参照（MARA NTGEW → GEWEI → T006）、货币参照（VBAK NETWR → WAERS →
  TCURC），各一段有效行+含错行；DDIC 表经 RTTS 运行期解析，缺对象系统自动
  跳过不阻塞激活（与测试类动态建表同一策略），finding 输出在经典列表
- 修复：`describe_by_name` 对未知类型在部分版本抛出**无法捕获**的异常（精简版
  开发系统上单测 TYPE_NOT_FOUND 短转储，`CATCH cx_root` 拦不住）；所有可收到
  未知名字的入口先以 `dd02l`/`dd04l` SELECT 预检存在性——测试辅助
  `build_ddic_table`、ALPHA 用例守卫、以及主类 `check_single` /
  `check_value_by_field`（未知名字走原有 STRUCTURE finding 宽容路径，不再有
  短转储风险）
- 修复：7.40 SP08 激活再报两处——`build_msg` 参数改 `TYPE clike`（按值
  `TYPE string` 在该版本同样拒绝 C(30) 实参，实测确认）；组合键批量预取的
  `INTO TABLE <lt_found>` 字段符号目标补 `@` 转义（普通变量目标才可免转义，
  单列预取的 `lt_found` 不受影响），且 `@` 形式要求 `INTO` 子句置于语句末尾
- 修复：7.40 SP08 激活失败三处（上一轮 KNA1 修复后才暴露）——测试类
  `assert_matches` 在旧 Basis 不存在，改用 `assert_text_matches`；
  `build_msg` 的 iv_a/iv_b/iv_c 改按值传递（按引用的 string 参数收到
  fieldname/domname 等 C(30) 实参不兼容，即 "not compatible with the
  type STRING" 报错）；`prefetch_ckey_group` 去掉独立类型名
  `abap_componentdescr_tab`（旧版本不可见，改由 create( ) 参数位的
  VALUE # 推断组件表类型）
- 修复：测试类静态引用 KNA1/MARA/VBAK，无对应应用 DDIC 的系统上整个类无法激活
  （Local Test Classes 报 Type "KNA1" is unknown）；改为运行时 RTTI 动态建表 +
  逐组件赋值，表不存在的系统上相关用例自动空跑跳过（VBELN ALPHA 用例同步加
  存在性保护），有表系统上断言不变
- 新增库元数据常量接口 `ZIF_ADV_METADATA`（`zif_adv_metadata.intf.abap`）：
  `c_version`/`c_author`/`c_repository`/`c_license`/`c_description` 集中维护，
  `ZCL_ADV_VALIDATOR` 经 `INTERFACES` + `ALIASES` 同名暴露（`zcl_adv_validator=>c_version`
  等），依赖方可直接读取库信息（关于页、升级诊断等）；接口仅含常量、自包含，
  不引入额外激活依赖（v0.2 移除 ZIF_ADV_VALIDATOR 的教训）
- 单测 27 → 28：元数据完整性（版本为语义化格式、仓库为 GitHub 地址、
  类别名与接口常量一致）
- CURR/QUAN 参照校验（v1.0）：金额字段（DFIES-DATATYPE = CURR/QUAN）经
  REFFIELD 找到同结构的货币/单位代码列，代码列无自有外键/规则时自动补
  TCURC/WAERS、T006/MSEHI 检查表（在 resolve_foreign_keys 之后执行，真
  外键与规则永远优先，同一问题不重复报错）；完全复用检查表机制——批量
  预取、缓存、宽容回退、CUNIT 转换出口全部继承，无新消息号
- 单测 25 → 27：MARA GEWEI→T006/MSEHI（含 CUNIT）、VBAK WAERS→TCURC/WAERS，
  有效值通过 + 未知代码拦截 + finding 对象断言
- 完整外键映射（v1.0）：DDIC 检查表字段的真实映射改读 DD05S——非同名检查
  字段自动生效（如 KNA1-REGIO → T005A-BLAND），组合外键（LAND1+REGIO →
  T005A 的 LAND1+BLAND）按字段组合校验；映射按结构名缓存（一次 SELECT）
- 组合键批量预取：按"检查表/键字段组"收集去重内部格式元组，每批 100 个
  元组 OR-of-ANDs 一次查库（`SELECT DISTINCT f1,f2 ... WHERE (f1='..' AND
  f2='..') OR (...)`）；伙伴字段为空的稀疏行回退单列 IN 批量预取
- 宽容语义：伙伴字段不在结构/被列过滤排除 → 单字段语义；伙伴值为空 →
  宽容回退单字段检查（与旧版一致）；MANDT 不参与组合键；规则指定的
  检查表不查 DD05S（checkfield 即完整映射）；混合/本地结构无 DD05S
  上下文，仍按同名字段处理
- 新增消息 015（组合键 finding 文本），消息类扩至 001–015
- 单测 21 → 25：KNA1 组合外键四例（DE/BY 有效、DE/ZZ 拦截并断言 DD05S
  映射 REGIO→BLAND、伙伴空宽容回退、缓存幂等）


## v0.3（2026-10）

- 性能：检查表校验由"每个不同值一次 `SELECT COUNT(*)`"改为行循环前按
  检查表/字段分组收集去重内部格式值、每批 100 值 `WHERE field IN (...)`
  批量预填缓存；动态 SQL 失败（不可读检查表）不缓存，逐值回退宽容模式，
  行为与原先一致
- 重构：转换出口 + 大小写归一抽取为 `internal_value`（行循环与批量预取
  共用同一套键变换，保证缓存键一致）
- 消息类化（SE91）：新增消息类 `ZADV_VALIDATOR`（`zadv_validator.msag.xml`，
  001–014），全部 finding 文本经 `build_msg` 取自消息类，可 SE63 翻译；
  注意占位符上限 50 字符，超长 value 在 message 中截断（finding-value 仍为全值）
- 单测 17 → 21：检查表规则路由（checktable/checkfield 覆盖，以 DD07L/DOMNAME
  为检查表，同时覆盖批量 IN 预取与大小写归一键）、缺失检查表宽容回退
  （批量与逐值两层均不崩溃）、缓存幂等（重复 validate 与 clear_caches 后
  结果一致）、ALPHA 转换出口（VBELN 外部格式）；域值 finding 增加外部原值断言
- 工程：abaplint 基础规则（`abaplint.json`）+ GitHub Actions CI
  （`.github/workflows/abaplint.yml`，push/PR 触发）
- 新增单值校验静态方法 `check_value_by_element` / `check_value_by_field`（复用 validate 全套 DDIC 校验，
  返回真假 + finding 原因；初始值视为合法）
- 修复：`ty_fieldnames` 行类型 fieldname → string（`VALUE #()` 字面量兼容性，上游反馈）
- 修复：abaplint `obsolete_statement` 关闭 `regex` 子项（`FIND REGEX` 为旧内核
  兼容写法，见源码注释，`matches()` 在老 support package 不可用）
- 修复：CI 工作流补传 `GITHUB_TOKEN` 并声明 `checks: write` 权限（新仓库默认
  token 只读，Checks API 上报 403，0 issue 也判失败）


## v0.2（2026-10）

- 新增列过滤 `only_fields` / `exclude_fields`（白名单优先、整体替换、白名单字段名纠错）
- 修复：混合结构回退路径 dfies-fieldname 为空，导致日期/时间/域值检查被静默跳过
- 修复：动态 WHERE 括号内空格导致激活失败（*Boolean expression was expected*），改为紧凑写法
- 修复：非法日期/时间字面量被 D/T 静态校验拒绝，demo 与单测改为运行期构造
- 修复：移除 DOMNAME_L / DOMVALUE_L / DOMVALUE_H 数据元素依赖，域名改用命名类型，
  域值区间直接引用 DD07L 字段（旧版本字典兼容）
- 修复：方法参数与内表构造中的内联 LENGTH 不合法，改为命名类型
- 修复：`matches()` 谓词函数不能与 `=` 比较，正则改用 `FIND REGEX`（子串语义，全串匹配加 `^...$`）
- 重构：取消独立接口 ZIF_ADV_VALIDATOR，类型/常量/方法并入 ZCL_ADV_VALIDATOR（消除激活顺序依赖）
- demo 去除对 T001/T005/TCURC/T002 的 SELECT（精简系统激活兼容），域值演示改用 AS4LOCAL
- ABAP Unit 扩至 12 个用例；README 增加列过滤章节、排错表、路线图

## v0.1（2026-10）

- 初版：域固定值（DD07L/DD01L）、检查表（动态 SQL + 缓存）、DATS/TIMS/NUMC 格式、
  转换出口自动校验；required/regex/checktable/checkfield/domname 显式规则；
  行级错误定位（行号/字段/原值/类别/消息）；实例级缓存；宽容模式兜底
