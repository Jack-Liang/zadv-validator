# 更新日志

## 未发布（v0.3 进行中）

- 新增单值校验静态方法 `check_value_by_element` / `check_value_by_field`（复用 validate 全套 DDIC 校验，
  返回真假 + finding 原因；初始值视为合法）
- 修复：`ty_fieldnames` 行类型 fieldname → string（`VALUE #()` 字面量兼容性，上游反馈）


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
