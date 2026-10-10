# zadv-validator — DDIC based generic ABAP internal table validator

[中文](README.md)

Pass in any internal table and every value of every field is validated
automatically against DDIC metadata (domain fixed values, check tables,
conversion exits, data types); every invalid input is reported with its
row and field. Built for the plausibility check before file
uploads/bulk imports (Excel, CSV) reach the database.

Inspiration and complementary work:
[hhelibeb/abap-data-validator](https://github.com/hhelibeb/abap-data-validator)
(format/regex style checks) and
[Nagaraj121999/Dynamic-Validation](https://github.com/Nagaraj121999/Dynamic-Validation)
(check table validation) — this library merges both into one generic
validator and adds domain fixed value checks plus error location
(row + field + original value + message).

## Validation capabilities

| Check | Source | Notes |
|---|---|---|
| Domain fixed values `DOMAIN` | automatic (DD07L/DD01L) | single values and intervals; the domain lowercase flag is respected |
| Check table `CHECKTABLE` | automatic (DFIES-CHECKTABLE + DD05S foreign key mapping) or rule | the real check table field is resolved via DD05S (non same-name mappings such as REGIO→T005A-BLAND work); composite foreign keys validate the value combination; the cache is prefilled before the row loop (single column: 100 values per IN batch, composite keys: 100 tuples per OR-of-ANDs batch) |
| Currency/unit reference | automatic (DFIES-REFFIELD) | code columns referenced by CURR/QUAN amount fields (e.g. WAERS/GEWEI) that are part of the upload structure and carry no own foreign key/rule are automatically checked against TCURC/WAERS resp. T006/MSEHI (reusing the full check table machinery incl. CUNIT conversion) |
| Date format `DATE` | automatic (DATS) | YYYYMMDD incl. days per month and leap years |
| Time format `TIME` | automatic (TIMS) | HHMMSS |
| Numeric text `NUMC` | automatic (NUMC) | digits only |
| Conversion exits | automatic (CONVEXIT) | `CONVERSION_EXIT_xxx_INPUT` is called before the comparison (existence checked in TFDIR, failures fall back to the raw value) |
| Required `REQUIRED` | rule | initial values pass by default; marking a field required reports them |
| Plugin `PLUGIN` | registration (`add_column_check`) | a custom single column check class implementing `ZIF_ADV_COLUMN_CHECK` receives the value plus a reference to the whole row (simple cross field rules possible) per row; decides ok/text/severity/rule_id itself |
| Comparison `COMPARE` | rule (`add_compare_rule`) | declarative cross field comparison: `field operator other` (EQ/NE/LT/LE/GT/GE), e.g. DATE_FROM <= DATE_TO; skipped when either operand is initial (combine with required to catch empties); row level rule, independent of the column filters |
| Uniqueness `UNIQUE` | rule (`add_unique_rule`) | declarative file level duplicate check: a field combination must stay unique across the table, the first occurrence passes, later repeats are reported (the message names the first row); rows whose combination is all initial are exempt |
| Regex `REGEX` | rule | for fields without a DDIC type (e.g. a string mail address); substring search semantics, wrap in `^...$` for a full match |
| Rule source: customizing | automatic (`ZADV_RULES`) | all three rule kinds stored per scenario (SCENARIO) in a customizing table, loaded with `add_rules_from_db( )` — consultant maintainable, transported as customizing, no code changes; semantics identical to code registration |
| Case handling | automatic | values are compared in upper case unless the domain allows lowercase, so data imported from case insensitive sources still validates |

Initial (empty) values pass every check except REQUIRED — consistent with
SAP data entry behaviour.

## Installation (abapGit)

1. SE80 / abapGit (`ZABAPGIT`) → *Link abapGit Repository*, enter the
   URL of this repository.
2. Suggested package name `ZADV_VALIDATOR`; pull and activate. The
   package contains the SE91 message class `ZADV_VALIDATOR` (the source
   of the finding texts); it is pulled with the package, activate
   everything together.
3. Requirements: ABAP 7.40 SP08+ (on-premise; reads DD07L/DD01L/TFDIR
   directly and uses dynamic SQL — not suitable for ABAP Cloud /
   Steampunk).

## Quick start

```abap
DATA(lo_validator) = NEW zcl_adv_validator( ).

" optional: explicit rules for non DDIC fields or extra constraints
lo_validator->add_rules( VALUE #(
  ( fieldname = 'EMAIL'  regex = `^[\w\.\-]+@[\w\.\-]+\.\w{2,}$` )
  ( fieldname = 'REMARK' required = abap_true )
  ( fieldname = 'NOTIFY' regex = `^X?$` severity = 'W' rule_id = 'R01' )
  ( fieldname = 'WERKS'  checktable = 'T001W' ) ) ).  " override/extend the DDIC check table

" optional: declarative cross field comparison and file level duplicate
" check (see the dedicated chapters below)
lo_validator->add_compare_rule( VALUE #( field = 'DATE_FROM' operator = 'LE'
                                         other = 'DATE_TO' rule_id = 'R_PERIOD' ) ).
lo_validator->add_unique_rule(  VALUE #( field = 'REF_ID' rule_id = 'R_DUP_REF' ) ).

DATA(lt_findings) = lo_validator->validate( gt_upload ).

IF lt_findings IS INITIAL.
  " everything passed, ready for the database
ELSE.
  " straight to the screen: built-in SALV helper (classic list fallback
  " on systems without SALV)
  zcl_adv_validator=>display_findings(
      it_findings = lt_findings
      iv_title    = 'Upload validation' ).

  " or into the application log (view with SLG1; the object must be
  " registered in SLG0 first):
  " zcl_adv_validator=>log_findings(
  "     it_findings = lt_findings
  "     iv_object   = 'ZUPLOAD' iv_commit = abap_true ).

  " or handle them yourself, e.g. block errors, let warnings pass:
  " LOOP AT lt_findings TRANSPORTING NO FIELDS
  "      WHERE severity = zcl_adv_validator=>c_severity-error.
  " ENDLOOP.
ENDIF.
```

Demo program: run report `ZADV_DEMO` (SA38). It builds one typical
valid row and two faulty rows and shows all findings in an ALV; v1.0
feature sections (composite foreign key KNA1, unit reference MARA,
currency reference VBAK) resolve their DDIC tables at RUNTIME and are
skipped with a note on systems without those objects, so activation is
never blocked (findings of those sections go to the classic list,
visible after the ALV is closed). The demo deliberately runs no SELECTs
on customizing tables and therefore activates on every system;
check-table findings only appear where the check table
(T001/T005/TCURC/T005A/T006) exists and is readable, otherwise the
lenient mode lets the value pass (no error, no crash). Deterministic
checks (domain fixed values AS4LOCAL, date format, regex, required)
show their effect on every system.

## Usage overview (API)

One validator instance = one import scenario. Register rules/plugins/
filters → one `validate( )` → branch on `severity`; the four static
helpers need no instance, use them where they fit.

**Instance methods (chain after `NEW zcl_adv_validator( )`)**

| Method | Purpose |
|---|---|
| `validate( it_data iv_row_offset )` | validate any internal table, returns `ty_findings` (each with row/field/value/check_type/message/severity/rule_id); `iv_row_offset` keeps global row numbers when validating slices of a big table |
| `add_rule( )` / `add_rules( )` / `clear_rules( )` | column level explicit rules: required / regex / checktable+checkfield / domname / severity / rule_id (how fields without DDIC types get covered) |
| `add_compare_rule( )` / `add_compare_rules( )` / `clear_compare_rules( )` | row level cross field comparison: `field operator other` (EQ/NE/LT/LE/GT/GE), e.g. DATE_FROM <= DATE_TO; initial operands are skipped |
| `add_unique_rule( )` / `add_unique_rules( )` / `clear_unique_rules( )` | table level duplicates: a field combination stays unique (empty `fields` = just `field`); first occurrence passes, later ones are reported with the first row |
| `add_rules_from_db( )` | load the three rule kinds per scenario (SCENARIO) from the `ZADV_RULES` customizing table; returns the number of rules, 0 without raising when the table or scenario is empty |
| `add_column_check( )` / `clear_column_checks( )` | register a plugin (class implementing `ZIF_ADV_COLUMN_CHECK`): decides ok/text/severity/rule_id itself, receives the whole row |
| `only_fields( )` / `exclude_fields( )` | column filters (whitelist wins, replaces the list as a whole, empty resets) |
| `clear_caches( )` | discard domain/check table/conversion exit caches (after customizing changes) |

**Static methods (no instance needed)**

| Method | Purpose |
|---|---|
| `check_value_by_element( )` / `check_value_by_field( )` | single value check by data element or table field, returns ok + a finding explaining why not |
| `precheck_truncation( )` | truncation pre-check: string staging table vs the same name columns of the target DDIC structure (defaults to W) |
| `display_findings( )` | findings in a SALV (optimized columns + header; classic list fallback without SALV) |
| `log_findings( )` | findings into a BAL application log (view with SLG1; register the object in SLG0 first) |

**Key types and constants**: `ty_finding` / `ty_rule` / `ty_compare_rule`
/ `ty_unique_rule` (structures shown in the chapters above and
documented as SE11 style comments); category constants `c_check-*`
(STRUCTURE/REQUIRED/DOMAIN/CHECKTABLE/DATE/TIME/NUMC/REGEX/PLUGIN/
COMPARE/UNIQUE/TRUNCATION); severity constants `c_severity-error/
warning/info`; the field name list `ty_fieldnames` (string row type,
populate with backtick literals). Library metadata lives in
`ZIF_ADV_METADATA` (`c_version` and friends).


## Column filters

By default every column the DDIC can describe is validated. Narrow it
down:

```abap
" validate only these columns (rules apply only to them as well;
" unknown names are reported as STRUCTURE findings)
lo_validator->only_fields( VALUE #( ( 'BUKRS' ) ( 'WAERS' ) ) ).

" or exclude columns (applied within an only_fields restriction)
lo_validator->exclude_fields( VALUE #( ( 'REMARK' ) ) ).

" both methods replace their list as a whole; pass VALUE #( ) to reset
```

## Single value checks

Without building a table — validate one value directly (static
methods, internally reusing the same DDIC validation logic):

```abap
" by data element
IF zcl_adv_validator=>check_value_by_element(
       iv_value    = lv_bukrs
       iv_rollname = 'BUKRS' ) = abap_false.
  " invalid: take the reason from es_finding
ENDIF.

" or take the DDIC definition from a table field (domain/check table/
" conversion exit as of that field)
DATA ls_finding TYPE zcl_adv_validator=>ty_finding.
DATA(lv_ok) = zcl_adv_validator=>check_value_by_field(
                  EXPORTING iv_value     = 'Z'
                            iv_tabname   = 'DD07L'
                            iv_fieldname = 'AS4LOCAL'
                  IMPORTING es_finding   = ls_finding ).
```

- values may be passed in external format; the conversion exit runs
  internally (e.g. ALPHA zero padding)
- initial values are considered valid (same convention as the table
  validation; use a rule for required fields)
- unknown element/table/field → `abap_false` and
  `es_finding-check_type = STRUCTURE`

## Version metadata

The library version, author, repository URL etc. live in the
constants-only interface `ZIF_ADV_METADATA`; `ZCL_ADV_VALIDATOR`
implements it and exposes the constants under the same names — both
access paths are equivalent:

```abap
DATA(lv_version) = zif_adv_metadata=>c_version.   " via the interface
WRITE: / zcl_adv_validator=>c_repository.          " via the class alias
```

| Constant | Content |
|---|---|
| `c_version` | semantic version `MAJOR.MINOR.PATCH` (kept in sync with the CHANGELOG) |
| `c_author` | maintainer |
| `c_repository` | repository and issue tracker URL |
| `c_license` | SPDX license identifier (MIT) |
| `c_description` | one line description |

Projects depending on this library can read it directly (about pages,
upgrade diagnostics output, ...); other open source libraries can copy
the pattern — a self contained constants interface, the implementing
class exposes it via `ALIASES`, consumers agree on `zif_xxx=>c_version`.

## Validation plugins (custom single column checks)

Implement `ZIF_ADV_COLUMN_CHECK` and register it per field to plug in
any custom validation — without touching the validator itself. Plugins
run **after** the built-in checks (each field reports only its first
error per row, so a plugin only sees values the validator itself
accepted) and receive a reference to the whole row, which makes simple
cross field rules possible right away:

```abap
CLASS lcl_check_shipment DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES zif_adv_column_check.
ENDCLASS.

CLASS lcl_check_shipment IMPLEMENTATION.
  METHOD zif_adv_column_check~check.
    " registered on DELIV_MODE: value = 'EXPRESS' demands a non-initial
    " PRIORITY in the same row
    rs_result-ok = abap_true.
    ASSIGN ir_row->* TO FIELD-SYMBOL(<ls_row>).
    ASSIGN COMPONENT 'PRIORITY' OF STRUCTURE <ls_row> TO FIELD-SYMBOL(<lv_prio>).
    IF sy-subrc = 0 AND iv_value = 'EXPRESS' AND <lv_prio> IS INITIAL.
      rs_result-ok       = abap_false.
      rs_result-severity = 'E'.                       " initial/invalid -> E
      rs_result-message  = |express delivery needs a priority|.
      rs_result-rule_id  = 'R_EXPRESS_PRIO'.          " echoed into finding-rule_id
    ENDIF.
  ENDMETHOD.
ENDCLASS.

lo_validator->add_column_check(
    iv_fieldname = 'DELIV_MODE'
    io_check     = NEW lcl_check_shipment( ) ).
```

- the interface is **self contained** (own ty_result type, no reference
  to the main class), no activation order dependencies
- works for columns without DDIC metadata (e.g. strings); unknown field
  names are reported as STRUCTURE findings by validate( ) (same 003
  message as rules)
- the finding carries `check_type = 'PLUGIN'` (constant
  `c_check-plugin`); the text comes straight from the plugin (not
  through the SE91 message class)
- `clear_column_checks( )` discards all registrations

## Cross field and inter-row rules (declarative)

Plugins are for checks that need custom logic; when it is really just
"compare two fields" or "no duplicates in the file", declare a rule
instead of writing a class:

```abap
" cross field comparison: BUDAT <= DATE_TO (operators EQ/NE/LT/LE/GT/GE)
" the finding is placed on the left operand, object = 'BUDAT <= DATE_TO'
lo_validator->add_compare_rule( VALUE #(
    field    = 'BUDAT'
    operator = 'LE'
    other    = 'DATE_TO'
    severity = 'W'
    rule_id  = 'R_PERIOD' ) ).

" file level uniqueness: REF_ID+WERKS must be unique in the whole table
" the first occurrence passes, later repeats are reported and the
" message names the row of the first occurrence
lo_validator->add_unique_rule( VALUE #(
    field    = 'REF_ID'            " finding anchor
    fields   = VALUE #( ( `REF_ID` ) ( `WERKS` ) )
    rule_id  = 'R_DUP_KEY' ) ).
```

- **comparison rules** run per row, after the column level checks and
  independent of the column filters (they are row level rules); a
  comparison is **skipped when either operand is initial** — combine
  with `required` to catch empty values. Operands that cannot be
  compared at all count as violated
- **uniqueness rules** run after the whole table has been scanned,
  independent of the column filters; an empty `fields` list degrades to
  a single field check on `field`; the combination is evaluated in
  **sorted** field name order, so finding `value/object` are
  deterministic (`WERKS+REF_ID`) regardless of registration order;
  rows whose combination is **all initial** are exempt (consistent with
  "initial passes" everywhere else)
- unknown field names and invalid operators (anything but
  EQ/NE/LT/LE/GT/GE) are reported as STRUCTURE findings by validate( )
  (messages 003/020) instead of failing silently
- finding categories: `c_check-compare` / `c_check-unique`; severity
  defaults to E, `rule_id` is echoed — same as column rules
- `clear_compare_rules( )` / `clear_unique_rules( )` discard their
  registrations; for complex logic (aggregation across rows,
  conditional dependencies) prefer a plugin or handle it yourself

## String staging truncation pre-check

File uploads often land in a string staging table first and are MOVE'd
into the DDIC target structure later — overlength values are
**silently truncated**. Pre-warn before the database write with the
static helper:

```abap
" it_data: the string staging table; iv_typename: target DDIC table/
" structure name
DATA(lt_findings) = zcl_adv_validator=>precheck_truncation(
    it_data     = lt_staging
    iv_typename = 'ZTARGET' ).        " severity defaults to W (a pre-warning)
```

- only columns that exist **under the same name on both sides** are
  compared; on the target side only character-like types (CHAR/NUMC/
  DATS/TIMS/ACCP/LANG/UNIT/CUKY/CLNT) participate — amounts and
  quantities refuse the assignment instead of truncating, no warning
  needed there
- value length (after the string conversion strips trailing blanks)
  > target field length → `TRUNCATION` finding
  (`c_check-truncation`), `object` = `target/field`; override the
  default W severity with `iv_severity`
- unknown target / not a DDIC structure → STRUCTURE finding (message
  012), never an exception
- raw/xstring staging columns have no meaningful text length and are
  skipped

## Excel upload end to end example

The complete pipeline of a file upload (abap2xlsx reads the file →
string staging → truncation pre-check → validation → display/archive).
abap2xlsx is a separate third party library
([abap2xlsx](https://github.com/abap2xlsx/abap2xlsx)) that must be
installed on its own — this library does **not** depend on it: from
step 2 on the pipeline is independent of the file source, CSV or
application server files work the same way:

```abap
" 1) abap2xlsx reads the worksheet (reader API as of your version)
DATA(lo_excel) = CAST zif_excel_reader( NEW zcl_excel_reader_2007( )
                   )->load_file( i_excel2007 = lv_xstring ).
DATA(lo_sheet) = lo_excel->get_worksheet_by_name( 'Sheet1' ).

" 2) into a string staging table: columns named like the target DDIC
"    structure (ZSDI_UPLOAD in this example)
DATA lt_stage TYPE STANDARD TABLE OF ty_stage WITH EMPTY KEY.  " all string columns
" LOOP AT lo_sheet->... INTO lt_stage.  " or read the cells row by row

" 3) truncation pre-check: warn about overlength values BEFORE the
"    MOVE into the target structure
DATA(lt_trunc) = zcl_adv_validator=>precheck_truncation(
                     it_data = lt_stage iv_typename = 'ZSDI_UPLOAD' ).
" branch on severity: E back to the user, W ask for confirmation

" 4) MOVE to the target type and validate (rules loaded per scenario
"    from the customizing table, no code changes)
DATA lt_upload TYPE STANDARD TABLE OF zsdi_upload WITH EMPTY KEY.
LOOP AT lt_stage ASSIGNING FIELD-SYMBOL(<ls_stage>).
  APPEND INITIAL LINE TO lt_upload ASSIGNING FIELD-SYMBOL(<ls_upload>).
  MOVE-CORRESPONDING <ls_stage> TO <ls_upload>.
ENDLOOP.

DATA(lo_validator) = NEW zcl_adv_validator( ).
lo_validator->add_rules_from_db( iv_scenario = 'ZSDI_UPLOAD' ).
DATA(lt_findings) = lo_validator->validate( lt_upload ).

" 5) display (ALV) + archive (BAL, view with SLG1)
zcl_adv_validator=>display_findings(
    it_findings = lt_findings iv_title = 'Upload validation' ).
zcl_adv_validator=>log_findings(
    it_findings = lt_findings iv_object = 'ZSDI_UPLOAD' iv_commit = abap_true ).
```

## Application log (BAL)

Write findings as an application log readable via SLG1 (one message
per finding, message type = severity, the finding text chunked into
the 4×50 character placeholders of generic message 018):

```abap
DATA(lv_log_handle) = zcl_adv_validator=>log_findings(
    it_findings  = lt_findings
    iv_object    = 'ZUPLOAD'          " register in SLG0 first (or pass your own)
    iv_subobject = 'VALIDATE'
    iv_extnumber = |upload { sy-datum }|
    iv_commit    = abap_true ).       " optional: COMMIT WORK inside the helper
```

- returns the log handle; initial when nothing was written (no
  findings, object not registered, BAL error) — it **never raises**,
  check SLG1 for the result
- the save happens in the current LUW, the commit stays with the
  caller; outside a bigger transaction `iv_commit = abap_true` lets
  the helper commit directly

## Rule customizing table (ZADV_RULES)

Rules without code changes, maintained by consultants and transported
like customizing: the package ships the client dependent customizing
table `ZADV_RULES` (delivery class C, data class APPL2), one row per rule or key
field, loaded per **scenario**:

```abap
DATA(lo_validator) = NEW zcl_adv_validator( ).
DATA(lv_count) = lo_validator->add_rules_from_db( iv_scenario = 'ZSDI_UPLOAD' ).
" lv_count = rules loaded; 0 = table missing or scenario empty (no exception)

DATA(lt_findings) = lo_validator->validate( gt_upload ).
```

Table layout (key: SCENARIO / RULE_ID / FIELDNAME):

| RULE_TYPE | maps to | columns used |
|---|---|---|
| `COLUMN` | `add_rule( )` column rule | FIELDNAME + REQUIRED / REGEX / CHECKTABLE + CHECKFIELD / DOMNAME |
| `COMPARE` | `add_compare_rule( )` row comparison | FIELDNAME (left operand) + OPERATOR (EQ/NE/LT/LE/GT/GE) + OTHER_FIELD (right operand) |
| `UNIQUE` | `add_unique_rule( )` duplicates | rows sharing a RULE_ID contribute one key field each (FIELDNAME); the alphabetically first is the anchor; a single row is a single field check |

SEVERITY and RULE_ID apply to all three kinds (same semantics as code
registration). Notes:

- **maintenance**: SE16N directly, or generate a maintenance view in
  SE11 (SM30); transported with customizing requests — no code
  changes, no transport of programs
- **lenient**: unknown RULE_TYPE rows are skipped; a missing table
  object or an empty scenario returns 0 — the SELECT uses a dynamic
  table name, so there is **no activation order dependency** between
  the class and the table
- unknown field names and invalid operators are NOT skipped:
  validate( ) reports the usual STRUCTURE findings (003/020), broken
  configuration shows up on the first run
- mixes freely with code registration on the same instance, loading
  only appends; REGEX is a CHAR255 column, longer patterns belong in
  code
- demo: `ZADV_DEMO` loads scenario `DEMO` at the start (with a note
  when there are no rows)

## The finding structure ty_finding

| Field | Meaning |
|---|---|
| `row` | row number (position in the table); 0 marks structural problems (non structure table type, rule references an unknown field) |
| `fieldname` | field name |
| `value` | the original input value (external format, human readable); for uniqueness findings the combination (`value1/value2`, sorted by field name) |
| `check_type` | STRUCTURE / REQUIRED / DOMAIN / CHECKTABLE / DATE / TIME / NUMC / REGEX / PLUGIN / COMPARE / UNIQUE / TRUNCATION |
| `object` | the object involved: domain name, `checktable/field` (composite foreign keys: `checktable/field1+field2`), the regex, the comparison expression (`field1 <= field2`), the uniqueness field combination (`field1+field2`) or `target/field` of the truncation pre-check |
| `message` | message text from SE91 message class `ZADV_VALIDATOR` (001–020), SE63 translatable; callers may build their own text from the first five fields instead. Placeholders hold at most 50 characters, overlength `value` is truncated in the message — the full value is in `value` |
| `severity` | `E` / `W` / `I` (`c_severity-error/warning/info`), **never initial**: DDIC derived checks are always `E`; rule derived findings take the rule severity (initial/invalid values normalize to `E`); the truncation pre-check defaults to `W` |
| `rule_id` | only filled for rule originated findings (echoes the `rule_id` of the rule, handy for branching/statistics); DDIC findings stay initial |

## How it works

1. RTTI resolves the row structure of the internal table,
   `GET_DDIC_FIELD_LIST( )` delivers the DFIES metadata (domain name,
   check table, conversion exit, data type); mixed structures (with
   string and other non DDIC fields) fall back to a per component
   resolution that skips non DDIC fields (rules can pick them up).
2. Check table batch prefetch: before the row loop, the distinct
   internal-format values are collected per check table column and the
   cache is prefilled with one `SELECT DISTINCT ... WHERE field IN (...)`
   per 100 values — a bulk import goes from "one round trip per
   distinct value" to "one per 100 distinct values per column".
   Composite foreign keys (multi field DD05S mappings) collect
   deduplicated tuples per check table/field group and fetch 100
   tuples per OR-of-ANDs select; rows with an initial partner fall
   back to the single column batch prefetch. When dynamic SQL fails
   (generated tables, unreadable views) nothing is cached and the
   per-value fallback keeps the lenient behaviour.
3. Row by row, field by field: required → initial passes → conversion
   exit + case normalization → format checks → domain fixed values →
   check table → regex → plugins; each field reports only its first
   error per row to avoid cascading noise. The declarative comparison
   rules of the row run after its field loop (row level, independent
   of the column filters); uniqueness rules run over the whole table
   after the row loop. By then nearly all check table lookups hit the
   cache — no per value selects anymore.
4. Caches: domain fixed values (per domain), check table hits (per
   table+field+value) and conversion exit existence (per exit) are
   instance level caches; `clear_caches( )` discards them after
   customizing changes.

## Slicing and parallel validation of big tables

`validate( )` is slice friendly: with `iv_row_offset` the finding row
number is offset + position in the slice (structural findings stay
0), so the results of all slices merge directly:

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

- slicing mainly bounds run time and memory per call; the instance
  caches survive between slices (one instance over slices queries
  every distinct check table value only once)
- **uniqueness rules and slices are mutually exclusive**: `UNIQUE` is
  evaluated within each `validate( )` call, duplicates across slices
  are invisible — do not slice when duplicates matter, or
  pre-aggregate in the database
- parallel: one **fresh instance** per slice (the validator keeps no
  shared state, caches are per instance), dispatched via aRFC or
  background tasks; `iv_row_offset` makes the row numbers mergeable.
  Gains are biggest where check table round trips dominate; mind the
  parallel task count and the database connection quota

## Design trade-offs and limits

- **Foreign key mapping (DD05S)**: the real mapping of DDIC check
  table fields is read from DD05S — non same-name check fields work
  automatically, composite foreign keys validate as a combination
  (e.g. LAND1+REGIO → T005A). A partner field missing from the upload
  structure (or dropped by a column filter) degrades to single field
  semantics; rows with an initial partner fall back leniently to the
  single field check (previous behaviour). The client field (MANDT)
  never participates. Rule specified check tables do not consult
  DD05S (`checkfield` is the complete mapping). Mixed/local structures
  have no DD05S context and keep same-name semantics.
- **Lenient metadata handling**: an unreadable check table (generated,
  view only, ...) counts as "passed" — the data flow is never blocked
  and nothing raises; build a strict mode yourself if you need one.
- **Domain fixed value length**: DD07L DOMVALUE_L/H hold at most 10
  characters (SAP limit), the library cannot check longer fixed
  values (same as SE11).
- **Self references skipped**: a field whose check table is the upload
  structure itself would validate the data against itself and is
  skipped.
- **Performance**: check table selects are batched per column (100
  deduplicated values each); for extreme cardinalities (tens of
  thousands of distinct values per column) pre-deduplicate with
  `SORT + DELETE ADJACENT DUPLICATES` or call validate( ) in slices;
  domain values and conversion exits are pure memory.
- **No `DDUT_INPUT_CHECK`**: reading DD07L plus controlled, cacheable
  dynamic SQL beats the FM signature dependency; replace
  `check_table` if you need its foreign key semantics.

## Repository layout

```
CHANGELOG.md                             change log
abaplint.json                            base abaplint rules (static CI checks)
.github/workflows/abaplint.yml           GitHub Actions: abaplint on push/PR
.github/workflows/abap-unit.yml          GitHub Actions: activation + ABAP Unit on a self-hosted system (off by default)
docs/abap-cloud.md                       ABAP Cloud feasibility study
src/
  package.devc.xml                        package ZADV_VALIDATOR
  zadv_validator.msag.xml                 SE91 message class ZADV_VALIDATOR (001–020)
  zadv_rules.tabl.xml                     rule customizing table ZADV_RULES (delivery class C, transported as customizing)
  zif_adv_metadata.intf.abap              metadata constants interface (version/author/repo/license/description)
  zif_adv_column_check.intf.abap           plugin interface (custom single column checks)
  zcl_adv_validator.clas.abap             the validator (types, constants, methods in one class, implements ZIF_ADV_METADATA)
  zcl_adv_validator.clas.testclasses.abap ABAP Unit tests (50 cases)
  zadv_demo.prog.abap                     demo report
```

## Tests

`ZCL_ADV_VALIDATOR` ships with ABAP Unit (SE80 → class → run, or ADT)
covering: zero false positives on valid rows, invalid date/time/domain
values, regex and required rules, unknown rule fields, rejection of
non structured tables, column filters (only/exclude and whitelist name
correction), single value checks (check_value_by_element/by_field),
rule routed check tables and the batch prefetch (using DD07L/DOMNAME
as the check table — no system master data needed), the lenient
fallback for missing check tables, cache idempotency (repeated
validate( ) and after clear_caches( )), the ALPHA conversion exit
(VBELN), composite foreign keys (KNA1 LAND1+REGIO → T005A: valid
combination passes, invalid is caught and the DD05S non same-name
mapping REGIO→BLAND verified, initial partner lenient fallback, cache
idempotency), CURR/QUAN references (MARA GEWEI→T006/MSEHI incl. CUNIT
conversion, VBAK WAERS→TCURC/WAERS, valid values pass + unknown codes
are caught), metadata interface integrity (semver version, GitHub
repository URL, class aliases equal the interface constants), plugins
(string column custom check + severity/rule_id echo, unknown field,
cross field via ir_row), comparison rules (violation anchored on the
left operand, satisfied and initial operands skipped, unknown fields
and invalid operators reported as STRUCTURE), uniqueness rules
(combination duplicates reported with registration order
independence, all initial rows exempt, unknown fields), the truncation
pre-check (overlength values reported as W, fitting values and staging
only columns pass), the BAL message mapping (severity → message type,
4×50 character chunking, no log without findings), lowercase domains
and interval fixed values (the sample objects are discovered at
runtime from DD01L/DD07L — no hardcoded cross release dependencies;
tests skip automatically on systems without a sample), the rule
customizing mapping (COLUMN/COMPARE/UNIQUE mapping incl. the anchor
rule, unknown types skipped, missing table/empty scenario return 0
leniently), and the row offset (column level and uniqueness findings
carry the offset). Application
DDIC objects (KNA1/MARA/VBAK/VBELN) are always resolved at runtime
(RTTI built tables, per component assignment) — the test class holds
no static type references, so minimal systems (no SD/MM) skip those
cases instead of failing activation; scenarios that need real master
data (real check tables such as T001) are covered by the demo.

## Roadmap

### v0.3 (performance and engineering) — done
- [x] **check table batching**: collect deduplicated values per column, `WHERE field IN (...)` in chunks of 100 to prefill the cache, replacing per value `SELECT COUNT(*)`; dynamic SQL failures fall back to the lenient per value mode
- [x] **SE91 message class**: finding texts moved to message class `ZADV_VALIDATOR` (001–014), SE63 translatable
- [x] test hardening: conversion exits (ALPHA/VBELN), cache idempotency, rule routed check tables (checktable/checkfield override), lenient fallback for missing check tables
- [x] abaplint base config + GitHub Actions CI (`.github/workflows/abaplint.yml`)

### v1.0 (feature complete) — released as 1.0.0
- [x] **complete foreign key mapping**: read DD05S, non same-name check table fields and composite (multi field) keys. Missing/filtered partner → single field semantics; initial partner value → lenient single field fallback; MANDT never participates; rule specified check tables unaffected
- [x] CURR/QUAN reference validation: currency columns against TCURC, unit columns against T006 (DFIES-REFTABLE/REFFIELD detection). Only when the code column has no own foreign key/rule — never double reported
- [x] unscheduled extras: library metadata interface `ZIF_ADV_METADATA` (constants such as c_version), 7.40 SP08 activation compatibility and shortdump guards, demo v1.0 sections (runtime resolved DDIC, activatable on minimal systems)

### v1.1 (continuation) — done
- [x] **validation plugins**: self contained interface `ZIF_ADV_COLUMN_CHECK` + `add_column_check( )` registration point for custom single column checks (incl. simple cross field via the whole row reference ir_row); the built-in checks stay inside the class — they are tightly coupled with the batch prefetch/caches and the composite foreign key is cross field by nature, extracting them would cost performance and compatibility
- [x] **declarative cross field and inter-row rules**: `add_compare_rule( )` row level comparisons (field operator other, EQ/NE/LT/LE/GT/GE, initial operands skipped) and `add_unique_rule( )` file level duplicates (unique field combination, first occurrence passes, all initial rows exempt); both are row/table level rules independent of the column filters, unknown fields/operators surface as STRUCTURE
- [x] finding enhancements (severity/rule id): `ty_finding` gained `severity` (E/W/I, never initial; DDIC always E, rules take their own) and `rule_id` (echoed for rule origins only); `ty_rule` gained `severity` (initial/invalid normalize to E) and `rule_id`
- [x] ALV output helper: `display_findings( )` static method (SALV optimized columns + optional header, classic list fallback without SALV)
- [x] BAL application log helper: `log_findings( )` static method (one message per finding, severity → message type, text chunked 4×50; view in SLG1, lenient without exceptions, the caller controls the LUW commit)
- [x] string staging truncation pre-check: `precheck_truncation( )` static method (string staging table vs the same name columns of the target DDIC structure, overlength pre-warning W, character like targets only)
- [x] test gap closing: lowercase domains, interval fixed values — no hardcoded sample domains, samples are discovered at runtime from DD01L (lowercase)/DD07L (interval rows), tests skip automatically where no sample exists
- [x] English README (README_EN.md, mirroring the Chinese one)

### v2.0 (ecosystem and scenarios) — released as 2.0.0
- [x] **rule customizing table**: the client dependent customizing table `ZADV_RULES` ships with the package (maintained via SE16N/SM30, transported as customizing, no code changes); `add_rules_from_db( iv_scenario )` loads all three rule kinds per scenario; dynamic SELECT without activation order dependency, missing table/empty scenario return 0 leniently
- [x] **end to end Excel upload example**: complete pipeline documented in the README (abap2xlsx → string staging → truncation pre-check → validation → ALV/BAL); abap2xlsx is a separate third party library this package does not depend on — from the staging table on, the pipeline is file source independent (CSV/AL11 alike)
- [x] **ABAP Cloud feasibility study**: see [docs/abap-cloud.md](docs/abap-cloud.md) — conclusion: v2.x stays on-premise (direct DDIC reads, dynamic SQL, SALV and BAL are not released; adapting would mean rewriting the metadata layer); the first step towards Cloud (a metadata provider interface) is recorded
- [x] **GitHub Actions extension**: the `abap-unit.yml` workflow is ready (after abaplint: abapGit pull + activation + ABAP Unit on a self-hosted runner), enabled via the repository variable `ABAP_RUNNER`; `abaplint.yml` unchanged
- [x] **sliced/parallel validation of big tables**: `validate( iv_row_offset )` keeps global row numbers across slices (also fixes uniqueness row numbers staying 0 for hashed input tables), the parallel call pattern (one instance per slice, merged via the offset) is documented; the mutual exclusiveness of uniqueness rules and slicing is called out

Explicitly not planned: syntax downport to 7.02 and below (maintenance
cost outweighs the benefit), multi package splits, replacing RAP
validations.

## License

MIT
