CLASS zcl_adv_validator DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    " library metadata (version, author, repository, ...) lives in a
    " constants-only interface so that it stays usable without the class
    " and other projects can adopt the same convention
    INTERFACES zif_adv_metadata.

    ALIASES:
      c_version     FOR zif_adv_metadata~c_version,
      c_author      FOR zif_adv_metadata~c_author,
      c_repository  FOR zif_adv_metadata~c_repository,
      c_license     FOR zif_adv_metadata~c_license,
      c_description FOR zif_adv_metadata~c_description.

    TYPES:
      "! finding severity: E = error (default), W = warning, I = info.
      "! Used as the type of ty_rule-severity / ty_finding-severity.
      ty_severity TYPE c LENGTH 1,

      "! One error found by the validator. Row 0 is used for structural
      "! problems (bad table type, rule references unknown field, ...).
      "! severity is never initial ('E' default); rule_id is only filled
      "! when the finding originates from an explicit rule that carries
      "! one - DDIC derived findings stay initial there.
      BEGIN OF ty_finding,
        row        TYPE i,
        fieldname  TYPE fieldname,
        value      TYPE string,
        check_type TYPE c LENGTH 12,
        object     TYPE c LENGTH 60,
        message    TYPE string,
        severity   TYPE ty_severity,
        rule_id    TYPE c LENGTH 30,
      END OF ty_finding,
      ty_findings TYPE STANDARD TABLE OF ty_finding WITH EMPTY KEY,

      "! Explicit rule that adds to or overrides the DDIC derived checks.
      "! All attributes are optional. severity defaults to 'E',
      "! rule_id is echoed into the findings of this rule.
      BEGIN OF ty_rule,
        fieldname  TYPE fieldname,
        required   TYPE abap_bool,
        checktable TYPE tabname,
        checkfield TYPE fieldname,
        domname    TYPE c LENGTH 30,
        regex      TYPE string,
        severity   TYPE ty_severity,
        rule_id    TYPE c LENGTH 30,
      END OF ty_rule,
      ty_rules TYPE STANDARD TABLE OF ty_rule WITH EMPTY KEY,

      "! column filter lists for only_fields( ) / exclude_fields( ).
      "! Elementary row types demand constructor values COMPATIBLE with
      "! the row type: 'BUKRS' (C literal) fits neither C(30) nor string,
      "! so callers must use backtick string literals:
      "! only_fields( VALUE #( ( `BUKRS` ) ) ).
      ty_fieldnames TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line,

      "! operators of a declarative comparison rule: EQ NE LT LE GT GE
      ty_operator TYPE c LENGTH 2,

      "! Declarative cross field comparison of one row, e.g.
      "! DATE_FROM <= DATE_TO. The comparison is skipped whenever one of
      "! the operands is initial (mark the fields required instead).
      "! 'field' is the left operand and carries the finding, 'other' is
      "! the right operand of the same row.
      BEGIN OF ty_compare_rule,
        rule_id  TYPE c LENGTH 30,
        severity TYPE ty_severity,
        field    TYPE fieldname,
        operator TYPE ty_operator,
        other    TYPE fieldname,
      END OF ty_compare_rule,
      ty_compare_rules TYPE STANDARD TABLE OF ty_compare_rule WITH EMPTY KEY,

      "! Declarative duplicate check across the whole table (file level
      "! uniqueness): the combination of 'fields' must not repeat - the
      "! first occurrence passes, every later one is reported. An empty
      "! fields list means just the anchor field. Rows in which all
      "! fields of the rule are initial are exempt (initial passes).
      "! The combination is evaluated in field name order (sorted), so
      "! finding-value/object are deterministic regardless of the order
      "! the fields were registered in.
      BEGIN OF ty_unique_rule,
        rule_id  TYPE c LENGTH 30,
        severity TYPE ty_severity,
        field    TYPE fieldname,
        fields   TYPE ty_fieldnames,
      END OF ty_unique_rule,
      ty_unique_rules TYPE STANDARD TABLE OF ty_unique_rule WITH EMPTY KEY.

    CONSTANTS:
      "! Categories reported in ty_finding-check_type
      BEGIN OF c_check,
        structure  TYPE c LENGTH 12 VALUE 'STRUCTURE',
        required   TYPE c LENGTH 12 VALUE 'REQUIRED',
        domain     TYPE c LENGTH 12 VALUE 'DOMAIN',
        checktable TYPE c LENGTH 12 VALUE 'CHECKTABLE',
        date       TYPE c LENGTH 12 VALUE 'DATE',
        time       TYPE c LENGTH 12 VALUE 'TIME',
        numc       TYPE c LENGTH 12 VALUE 'NUMC',
        regex      TYPE c LENGTH 12 VALUE 'REGEX',
        plugin     TYPE c LENGTH 12 VALUE 'PLUGIN',
        compare    TYPE c LENGTH 12 VALUE 'COMPARE',
        unique     TYPE c LENGTH 12 VALUE 'UNIQUE',
        truncation TYPE c LENGTH 12 VALUE 'TRUNCATION',
      END OF c_check,

      "! severities reported in ty_finding-severity
      BEGIN OF c_severity,
        error   TYPE ty_severity VALUE 'E',
        warning TYPE ty_severity VALUE 'W',
        info    TYPE ty_severity VALUE 'I',
      END OF c_severity.

    METHODS:
      "! Validate any internal table against DDIC metadata and added
      "! rules. The row structure must be DDIC based (or a mixed
      "! structure whose components are DDIC typed) for automatic
      "! checks; string/numeric helper fields are simply skipped unless
      "! covered by a rule. Initial values pass all checks unless a rule
      "! marks them required. The method never raises: unusable
      "! metadata is reported leniently. iv_row_offset is added to the
      "! row number of every finding: call it on slices of a big table
      "! with the running offset to keep global row numbers (structural
      "! findings stay row 0).
      validate
        IMPORTING it_data            TYPE ANY TABLE
                  iv_row_offset      TYPE i OPTIONAL
        RETURNING VALUE(rt_findings) TYPE ty_findings,

      add_rule
        IMPORTING is_rule TYPE ty_rule,

      add_rules
        IMPORTING it_rules TYPE ty_rules,

      clear_rules,

      "! register a custom single column check (plugin, see interface
      "! ZIF_ADV_COLUMN_CHECK) for one field. It runs for every row in
      "! which the field is non-initial and has passed the built-in
      "! checks; the field does not need DDIC metadata. Unknown field
      "! names are reported as STRUCTURE findings by validate( ).
      add_column_check
        IMPORTING iv_fieldname TYPE fieldname
                  io_check     TYPE REF TO zif_adv_column_check,

      "! discard all column check registrations (add_column_check)
      clear_column_checks,

      "! register a declarative cross field comparison (row level, e.g.
      "! DATE_FROM <= DATE_TO). Runs for every row regardless of the
      "! column filters; operands that are initial are skipped. Field
      "! names and the operator are normalized to upper case. Unknown
      "! fields and unknown operators are reported as STRUCTURE findings
      "! by validate( ). severity defaults to 'E', rule_id is echoed.
      add_compare_rule
        IMPORTING is_rule TYPE ty_compare_rule,

      add_compare_rules
        IMPORTING it_rules TYPE ty_compare_rules,

      "! discard all comparison rule registrations
      clear_compare_rules,

      "! register a declarative duplicate check (file level uniqueness
      "! of a field combination). Runs on the whole table regardless of
      "! the column filters; rows whose rule fields are all initial are
      "! exempt. An empty fields list means just the anchor field.
      "! Unknown field names are reported as STRUCTURE findings.
      add_unique_rule
        IMPORTING is_rule TYPE ty_unique_rule,

      add_unique_rules
        IMPORTING it_rules TYPE ty_unique_rules,

      "! discard all uniqueness rule registrations
      clear_unique_rules,

      "! load validation rules of one scenario from the customizing
      "! table ZADV_RULES (override the table name with iv_tabname) and
      "! register them: RULE_TYPE COLUMN rows become column rules
      "! (required/regex/checktable+checkfield/domname), COMPARE rows
      "! become comparison rules (fieldname/operator/other_field),
      "! UNIQUE rows sharing a RULE_ID form one uniqueness rule (one
      "! row per key field, the alphabetically first is the anchor).
      "! Returns the number of registered rules; 0 without raising when
      "! the table does not exist or the scenario has no rows - the
      "! dynamic SELECT never creates an activation order dependency
      "! between the class and the table.
      add_rules_from_db
        IMPORTING iv_scenario       TYPE clike
                  iv_tabname        TYPE clike OPTIONAL
        RETURNING VALUE(rv_count)   TYPE i,

      "! Restrict validation to the given columns (initial = all columns).
      "! Rules on other columns are skipped as well. Unknown names are
      "! reported as STRUCTURE findings. Replaces the previous list,
      "! an empty list resets the restriction.
      only_fields
        IMPORTING it_fields TYPE ty_fieldnames,

      "! Remove the given columns from validation, applied within an
      "! only_fields restriction if both are set. Replaces the previous
      "! list, an empty list resets.
      exclude_fields
        IMPORTING it_fields TYPE ty_fieldnames,

      "! Discard cached domain fixed values, check-table lookups and
      "! conversion-exit existence checks. Call this when DDIC objects or
      "! customizing data may have changed during the lifetime of the
      "! validator instance.
      clear_caches.

    CLASS-METHODS:
      "! Check a single value against the DDIC definition (domain fixed
      "! values, check table, conversion exit, format) of a data element.
      "! rv_ok = abap_true means valid; if invalid, es_finding explains
      "! why (row = 1, fieldname = element name). Initial values are
      "! considered valid. The value may be passed in external format,
      "! the conversion exit is applied internally.
      check_value_by_element
        IMPORTING iv_value     TYPE clike
                  iv_rollname  TYPE clike
        EXPORTING es_finding   TYPE ty_finding
        RETURNING VALUE(rv_ok) TYPE abap_bool,

      "! Same as check_value_by_element, but the DDIC definition is taken
      "! from a field of a DDIC table or structure.
      check_value_by_field
        IMPORTING iv_value     TYPE clike
                  iv_tabname   TYPE clike
                  iv_fieldname TYPE clike
        EXPORTING es_finding   TYPE ty_finding
        RETURNING VALUE(rv_ok) TYPE abap_bool,

      "! show findings in a SALV grid with optimized columns and an
      "! optional list header; on systems without SALV the findings are
      "! written to the classic list instead. Pure convenience - the
      "! findings are plain data, the kind of display stays the
      "! caller's choice.
      display_findings
        IMPORTING it_findings TYPE ty_findings
                  iv_title    TYPE clike OPTIONAL,

      "! write findings into an application log (BAL) and save it: one
      "! message per finding, message type from severity, the finding
      "! text split over the four 50 char message variables. Returns
      "! the log handle, or initial when nothing was written (no
      "! findings, object not registered in SLG0, BAL error). Never
      "! raises - check SLG1 for the result. The save happens in the
      "! current LUW; iv_commit = abap_true adds a COMMIT WORK for
      "! callers that do not run inside a bigger transaction.
      log_findings
        IMPORTING it_findings    TYPE ty_findings
                  iv_object      TYPE balobj_d
                  iv_subobject   TYPE balsubobj OPTIONAL
                  iv_extnumber   TYPE balnrext OPTIONAL
                  iv_commit      TYPE abap_bool OPTIONAL
        RETURNING VALUE(rv_log_handle) TYPE balloghndl,

      "! staging pre-check: character-like columns of it_data (e.g. a
      "! string staging table of a file upload) are compared with the
      "! field lengths of the DDIC table/structure iv_typename - values
      "! that would be truncated by the assignment are reported as W
      "! findings (iv_severity overrides, E/W/I). Only columns that
      "! exist under the same name in both structures are checked,
      "! non character-like target types (amounts, raw) are skipped.
      precheck_truncation
        IMPORTING it_data            TYPE ANY TABLE
                  iv_typename        TYPE clike
                  iv_severity        TYPE ty_severity OPTIONAL
        RETURNING VALUE(rt_findings) TYPE ty_findings.

  PRIVATE SECTION.

    TYPES:
      "! method parameters cannot use inline LENGTH -> named type
      ty_domname TYPE c LENGTH 30,

      "! SE91 message class id and number for build_msg
      ty_msgid TYPE c LENGTH 20,
      ty_msgnr TYPE n LENGTH 3,

      "! DD05S foreign key mapping: one field of the validated structure
      "! to the check table field it refers to
      BEGIN OF ty_fkmap,
        fieldname TYPE fieldname,
        fortable  TYPE tabname,
        forkey    TYPE fieldname,
      END OF ty_fkmap,
      ty_fkmaps TYPE SORTED TABLE OF ty_fkmap
                  WITH NON-UNIQUE KEY fieldname fortable,

      BEGIN OF ty_struct_fk,
        tabname TYPE tabname,
        maps    TYPE ty_fkmaps,
      END OF ty_struct_fk,
      ty_struct_fks TYPE HASHED TABLE OF ty_struct_fk WITH UNIQUE KEY tabname,

      "! partner field of a composite foreign key: another field of the
      "! validated structure and the check table field it maps to
      BEGIN OF ty_fk_partner,
        fieldname  TYPE fieldname,
        checkfield TYPE fieldname,
      END OF ty_fk_partner,
      ty_fk_partners TYPE SORTED TABLE OF ty_fk_partner
                       WITH UNIQUE KEY fieldname,

      BEGIN OF ty_field,
        fieldname    TYPE fieldname,
        synthetic    TYPE abap_bool,
        domname      TYPE dfies-domname,
        datatype     TYPE dfies-datatype,
        convexit     TYPE dfies-convexit,
        checktable   TYPE dfies-checktable,
        required     TYPE abap_bool,
        regex        TYPE string,
        rule_ctab    TYPE dfies-checktable,
        rule_cfield  TYPE fieldname,
        rule_domname TYPE dfies-domname,
        fkey_checkfield TYPE fieldname,
        fkey_partners   TYPE ty_fk_partners,
        reffield     TYPE dfies-reffield,
        rule_severity TYPE ty_severity,
        rule_id       TYPE c LENGTH 30,
      END OF ty_field,
      ty_fields TYPE SORTED TABLE OF ty_field WITH UNIQUE KEY fieldname,

      BEGIN OF ty_domval,
        domvalue_l TYPE dd07l-domvalue_l,
        domvalue_h TYPE dd07l-domvalue_h,
      END OF ty_domval,
      ty_domvals TYPE STANDARD TABLE OF ty_domval WITH EMPTY KEY,

      BEGIN OF ty_domain,
        domname   TYPE ty_domname,
        lowercase TYPE abap_bool,
        values    TYPE ty_domvals,
      END OF ty_domain,
      ty_domains TYPE HASHED TABLE OF ty_domain WITH UNIQUE KEY domname,

      BEGIN OF ty_ctab_hit,
        tabname TYPE tabname,
        field   TYPE fieldname,
        value   TYPE string,
        found   TYPE abap_bool,
      END OF ty_ctab_hit,
      ty_ctab_hits TYPE HASHED TABLE OF ty_ctab_hit
                       WITH UNIQUE KEY tabname field value,

      BEGIN OF ty_convexit,
        name   TYPE convexit,
        exists TYPE abap_bool,
      END OF ty_convexit,
      ty_convexits TYPE HASHED TABLE OF ty_convexit WITH UNIQUE KEY name,

      "! registered custom column checks (plugins), see add_column_check
      BEGIN OF ty_plugin,
        fieldname TYPE fieldname,
        check     TYPE REF TO zif_adv_column_check,
      END OF ty_plugin,
      ty_plugins TYPE SORTED TABLE OF ty_plugin
                   WITH NON-UNIQUE KEY fieldname,

      "! one BAL message per finding, see build_bal_msgs
      ty_bal_msgs TYPE STANDARD TABLE OF bal_s_msg WITH EMPTY KEY,

      "! row of the ZADV_RULES customizing table (or any table with
      "! the same columns), see add_rules_from_db
      BEGIN OF ty_db_rule,
        scenario    TYPE c LENGTH 30,
        rule_id     TYPE c LENGTH 30,
        rule_type   TYPE c LENGTH 10,
        fieldname   TYPE fieldname,
        operator    TYPE c LENGTH 2,
        other_field TYPE fieldname,
        required    TYPE flag,
        severity    TYPE c LENGTH 1,
        regex       TYPE c LENGTH 255,
        checktable  TYPE tabname,
        checkfield  TYPE fieldname,
        domname     TYPE c LENGTH 30,
      END OF ty_db_rule,
      ty_db_rules TYPE STANDARD TABLE OF ty_db_rule WITH EMPTY KEY,

      "! duplicate detection: first row in which a key combination
      "! occurred (hashed lookup while the rows are scanned in order)
      BEGIN OF ty_dup_seen,
        key       TYPE string,
        first_row TYPE i,
      END OF ty_dup_seen,
      ty_dup_seens TYPE HASHED TABLE OF ty_dup_seen WITH UNIQUE KEY key,

      "! internal-format values to look up in one check table column,
      "! deduplicated (hashed) and as index table for chunked iteration
      ty_values    TYPE STANDARD TABLE OF string WITH EMPTY KEY,
      ty_value_set TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line,

      BEGIN OF ty_ctab_want,
        tabname TYPE tabname,
        field   TYPE fieldname,
        values  TYPE ty_value_set,
      END OF ty_ctab_want,
      ty_ctab_wants TYPE SORTED TABLE OF ty_ctab_want
                       WITH UNIQUE KEY tabname field,

      "! elementary target of the dynamic single column batch SELECT;
      "! C -> string strips trailing blanks so found values compare
      "! cleanly with the searched internal-format values
      ty_ctab_val  TYPE c LENGTH 1333,
      ty_ctab_vals TYPE STANDARD TABLE OF ty_ctab_val WITH EMPTY KEY,

      "! hit cache for composite foreign key lookups: keysig is the '+'
      "! joined list of check table field names, tuple the tab separated
      "! internal-format values in the same order
      BEGIN OF ty_ckey_hit,
        tabname TYPE tabname,
        keysig  TYPE string,
        tuple   TYPE string,
        found   TYPE abap_bool,
      END OF ty_ckey_hit,
      ty_ckey_hits TYPE HASHED TABLE OF ty_ckey_hit
                     WITH UNIQUE KEY tabname keysig tuple,

      ty_ckey_fields TYPE STANDARD TABLE OF fieldname WITH EMPTY KEY,

      BEGIN OF ty_ckey_group,
        tabname TYPE tabname,
        keysig  TYPE string,
        fields  TYPE ty_ckey_fields,
        tuples  TYPE ty_value_set,
      END OF ty_ckey_group,
      ty_ckey_groups TYPE SORTED TABLE OF ty_ckey_group
                       WITH UNIQUE KEY tabname keysig.

    CONSTANTS:
      "! SE91 message class carrying the finding texts (SE63 translatable)
      c_msgid TYPE ty_msgid VALUE 'ZADV_VALIDATOR',
      "! values per dynamic IN( ) batch: small enough for any database
      "! IN list and statement size limit
      c_in_chunk TYPE i VALUE 100,

      "! character-like DDIC datatypes whose values truncate silently
      "! (on the right) when assigned to a shorter target
      BEGIN OF c_charlike,
        char  TYPE dfies-datatype VALUE 'CHAR',
        numc  TYPE dfies-datatype VALUE 'NUMC',
        dats  TYPE dfies-datatype VALUE 'DATS',
        tims  TYPE dfies-datatype VALUE 'TIMS',
        accp  TYPE dfies-datatype VALUE 'ACCP',
        lang  TYPE dfies-datatype VALUE 'LANG',
        unit  TYPE dfies-datatype VALUE 'UNIT',
        cuky  TYPE dfies-datatype VALUE 'CUKY',
        clnt  TYPE dfies-datatype VALUE 'CLNT',
      END OF c_charlike,

      "! customizing table read by add_rules_from_db
      c_rulestab TYPE tabname VALUE 'ZADV_RULES',

      "! RULE_TYPE values of the customizing table
      BEGIN OF c_rule_type,
        column  TYPE c LENGTH 10 VALUE 'COLUMN',
        compare TYPE c LENGTH 10 VALUE 'COMPARE',
        unique  TYPE c LENGTH 10 VALUE 'UNIQUE',
      END OF c_rule_type.

    DATA:
      mt_rules          TYPE ty_rules,
      mt_plugins        TYPE ty_plugins,
      mt_compare_rules  TYPE ty_compare_rules,
      mt_unique_rules   TYPE ty_unique_rules,
      mt_only_fields    TYPE ty_fieldnames,
      mt_exclude_fields TYPE ty_fieldnames,
      mt_domains        TYPE ty_domains,
      mt_ctab_hits      TYPE ty_ctab_hits,
      mt_ckey_hits      TYPE ty_ckey_hits,
      mt_struct_fks     TYPE ty_struct_fks,
      mt_convexits      TYPE ty_convexits.

    METHODS:
      build_fields
        IMPORTING io_struct        TYPE REF TO cl_abap_structdescr
        RETURNING VALUE(rt_fields) TYPE ty_fields,

      "! resolve the DD05S foreign key mapping for every DDIC derived
      "! check table field of the (already column filtered) field list:
      "! the real check table field name and the partner fields of
      "! composite foreign keys. Purely additive: without a mapping row
      "! the same-name behaviour stays in effect. Called after the column
      "! filters on purpose: partners dropped by a filter degrade the
      "! composite check to the single field check.
      resolve_foreign_keys
        IMPORTING iv_structname TYPE tabname
        CHANGING  ct_fields     TYPE ty_fields,

      "! DD05S mapping rows of one structure, one SELECT per structure
      get_struct_fks
        IMPORTING iv_tabname   TYPE tabname
        RETURNING VALUE(rs_fk) TYPE ty_struct_fk,

      "! fill the check table of currency/unit code columns (e.g. WAERS,
      "! GEWEI) that are referenced by CURR/QUAN amount fields of the
      "! same structure but carry no own DDIC foreign key: TCURC/WAERS
      "! resp. T006/MSEHI. Must run after resolve_foreign_keys so that
      "! real DDIC foreign keys and explicit rules always win and the
      "! same problem is never reported twice.
      resolve_curr_quan
        CHANGING ct_fields TYPE ty_fields,

      "! ordered check table field list of a composite foreign key:
      "! own check field first, then the partners (sorted by field name)
      ckey_fields
        IMPORTING is_field        TYPE ty_field
        RETURNING VALUE(rt_fields) TYPE ty_ckey_fields,

      ckey_keysig
        IMPORTING is_field      TYPE ty_field
        RETURNING VALUE(rv_sig) TYPE string,

      "! tuple of a composite key for one data row: own internal-format
      "! value first, then the partner values. ev_complete = abap_false
      "! when a partner component is missing or initial
      build_fkey_tuple
        IMPORTING is_field     TYPE ty_field
                  it_fields    TYPE ty_fields
                  iv_struct    TYPE any
                  iv_value     TYPE string
        EXPORTING ev_tuple     TYPE string
                  ev_complete  TYPE abap_bool,

      get_domain
        IMPORTING iv_domname       TYPE ty_domname
        RETURNING VALUE(rs_domain) TYPE ty_domain,

      check_domain
        IMPORTING iv_domname       TYPE ty_domname
                  iv_value         TYPE string
        RETURNING VALUE(rv_ok)     TYPE abap_bool,

      check_table
        IMPORTING iv_table         TYPE tabname
                  iv_field         TYPE fieldname
                  iv_value         TYPE string
        RETURNING VALUE(rv_ok)     TYPE abap_bool,

      "! display value -> internal comparison format: conversion exit
      "! applied, upper case unless the effective domain allows lowercase
      internal_value
        IMPORTING is_field      TYPE ty_field
                  iv_disp       TYPE string
        RETURNING VALUE(rv_val) TYPE string,

      "! collect the distinct check-table lookups of all rows and fill
      "! the lookup cache with chunked IN( ) selects, so the row loop
      "! below fires no per-value SELECT COUNT( * )
      prefetch_checktables
        IMPORTING it_data   TYPE ANY TABLE
                  it_fields TYPE ty_fields,

      "! look up it_values of one check table column in chunks of
      "! c_in_chunk and cache hit/miss per value; on dynamic SQL errors
      "! nothing is cached and the per-value fallback applies
      prefetch_ctab_group
        IMPORTING iv_table  TYPE tabname
                  iv_field  TYPE fieldname
                  it_values TYPE ty_value_set,

      "! collect the distinct composite key tuples of all rows and fill
      "! the tuple cache with chunked OR-of-ANDs selects; rows with an
      "! incomplete tuple (initial partner) feed the single column batch
      "! prefetch instead
      prefetch_foreign_keys
        IMPORTING it_data   TYPE ANY TABLE
                  it_fields TYPE ty_fields,

      prefetch_ckey_group
        IMPORTING iv_table  TYPE tabname
                  iv_keysig TYPE string
                  it_fields TYPE ty_ckey_fields
                  it_tuples TYPE ty_value_set,

      "! cached existence check of one composite key tuple; on dynamic
      "! SQL errors the lenient hit is cached like check_table does
      check_foreign_key
        IMPORTING iv_table  TYPE tabname
                  iv_keysig TYPE string
                  iv_tuple  TYPE string
        RETURNING VALUE(rv_ok) TYPE abap_bool,

      check_date
        IMPORTING iv_date          TYPE string
        RETURNING VALUE(rv_ok)     TYPE abap_bool,

      check_time
        IMPORTING iv_time          TYPE string
        RETURNING VALUE(rv_ok)     TYPE abap_bool,

      check_numc
        IMPORTING iv_value         TYPE string
        RETURNING VALUE(rv_ok)     TYPE abap_bool,

      to_internal
        IMPORTING iv_convexit      TYPE convexit
                  iv_value         TYPE string
        RETURNING VALUE(rv_val)    TYPE string,

      conv_exit_exists
        IMPORTING iv_convexit      TYPE convexit
        RETURNING VALUE(rv_ok)     TYPE abap_bool,

      "! declarative cross field comparisons of one row. Unknown fields
      "! and unknown operators were reported as structural findings
      "! before the row loop and are skipped here; initial operands are
      "! exempt (mark the fields required instead)
      compare_findings
        IMPORTING iv_row             TYPE i
                  iv_struct          TYPE any
        RETURNING VALUE(rt_findings) TYPE ty_findings,

      "! duplicate findings of all uniqueness rules: rows are scanned
      "! in table order, the first occurrence of a combination passes,
      "! every later one is reported. iv_offset shifts the row numbers
      "! (slice validation) and replaces sy-tabix, which stays 0 for
      "! hashed tables
      unique_findings
        IMPORTING it_data            TYPE ANY TABLE
                  iv_offset          TYPE i
        RETURNING VALUE(rt_findings) TYPE ty_findings,

      "! map ZADV_RULES rows to the three registration APIs; rows with
      "! an unknown RULE_TYPE are skipped. Pure mapping without DB
      "! access, that is what the unit tests call. By value on purpose:
      "! the mapping sorts the rows
      apply_db_rules
        IMPORTING VALUE(it_rules)  TYPE ty_db_rules
        RETURNING VALUE(rv_count)  TYPE i,

      "! effective field combination of a uniqueness rule: the explicit
      "! fields list, or just the anchor field when no list was given;
      "! upper case, sorted and deduplicated for a deterministic key
      unique_fields
        IMPORTING is_rule           TYPE ty_unique_rule
        RETURNING VALUE(rt_fields)  TYPE ty_values.

    "! static on purpose: it is called via short form from the static
    "! check_value_* methods (instance methods cannot be called that
    "! way from a static context) and uses no instance state
    CLASS-METHODS:
      check_single
        IMPORTING iv_value     TYPE clike
                  iv_rollname  TYPE clike
        EXPORTING es_finding   TYPE ty_finding
        RETURNING VALUE(rv_ok) TYPE abap_bool,

      "! normalize a rule severity: initial and invalid values become
      "! c_severity-error, 'W' and 'I' pass through. Static on purpose:
      "! build_bal_msgs( ) runs in a static context
      normalize_severity
        IMPORTING iv_severity        TYPE clike
        RETURNING VALUE(rv_severity) TYPE ty_severity,

      "! findings as BAL messages: message type from severity, the
      "! finding text split into the four 50 char message variables of
      "! generic message 018. Pure mapping, no BAL calls - this is what
      "! log_findings( ) writes and what the unit tests check
      build_bal_msgs
        IMPORTING it_findings   TYPE ty_findings
        RETURNING VALUE(rt_msgs) TYPE ty_bal_msgs,

      "! finding message text from the SE91 message class; operands for
      "! unused placeholders are supplied blank. clike by reference on
      "! purpose: it accepts the C(30) metadata arguments (fieldname,
      "! domname, ...) as well as string values; a typed string
      "! parameter was rejected by the 7.40 SP08 syntax check even
      "! when passed by value
      build_msg
        IMPORTING iv_nr          TYPE ty_msgnr
                  iv_a           TYPE clike OPTIONAL
                  iv_b           TYPE clike OPTIONAL
                  iv_c           TYPE clike OPTIONAL
        RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.


CLASS zcl_adv_validator IMPLEMENTATION.

  METHOD validate.

    DATA: lv_row  TYPE i,
          lr_line TYPE REF TO data,
          lr_row  TYPE REF TO data.

    FIELD-SYMBOLS: <row> TYPE any,
                   <val> TYPE any.

    " ---------------------------------------------------------------------
    " 1) resolve the row structure
    " ---------------------------------------------------------------------
    DATA(lo_table) = CAST cl_abap_tabledescr(
                       cl_abap_typedescr=>describe_by_data( it_data ) ).
    DATA(lo_line)  = lo_table->get_table_line_type( ).

    IF lo_line->kind <> cl_abap_typedescr=>kind_struct.
      APPEND VALUE #( row = 0 fieldname = '-'
                      check_type = c_check-structure
                      message   = build_msg( iv_nr = '001' )
                      severity  = c_severity-error )
             TO rt_findings.
      RETURN.
    ENDIF.

    DATA(lo_struct) = CAST cl_abap_structdescr( lo_line ).
    DATA(lt_fields) = build_fields( lo_struct ).

    " ---------------------------------------------------------------------
    " 2) column filter: only_fields whitelist first, then exclude_fields
    " ---------------------------------------------------------------------
    IF mt_only_fields IS NOT INITIAL.
      DATA lt_filtered TYPE ty_fields.
      LOOP AT lt_fields ASSIGNING FIELD-SYMBOL(<fs_filter>).
        READ TABLE mt_only_fields TRANSPORTING NO FIELDS
             WITH TABLE KEY table_line = <fs_filter>-fieldname.
        IF sy-subrc = 0.
          INSERT <fs_filter> INTO TABLE lt_filtered.
        ENDIF.
      ENDLOOP.
      LOOP AT mt_only_fields INTO DATA(lv_only).
        READ TABLE lt_filtered TRANSPORTING NO FIELDS
             WITH TABLE KEY fieldname = lv_only.
        IF sy-subrc <> 0.
          APPEND VALUE #( row = 0 fieldname = lv_only
                          check_type = c_check-structure
                          message   = build_msg( iv_nr = '002'
                                                  iv_a  = lv_only )
                          severity  = c_severity-error )
                 TO rt_findings.
        ENDIF.
      ENDLOOP.
      lt_fields = lt_filtered.
    ENDIF.

    IF mt_exclude_fields IS NOT INITIAL.
      LOOP AT mt_exclude_fields INTO DATA(lv_exclude).
        DELETE lt_fields WHERE fieldname = lv_exclude.
      ENDLOOP.
    ENDIF.

    " ---------------------------------------------------------------------
    " 3.5) DD05S foreign key mapping for the DDIC derived check tables
    " ---------------------------------------------------------------------
    resolve_foreign_keys(
      EXPORTING iv_structname = CONV #( lo_struct->get_relative_name( ) )
      CHANGING  ct_fields     = lt_fields ).

    " ---------------------------------------------------------------------
    " 3.6) currency/unit code columns referenced by CURR/QUAN amounts
    " ---------------------------------------------------------------------
    resolve_curr_quan( CHANGING ct_fields = lt_fields ).

    " ---------------------------------------------------------------------
    " 3) rules referencing fields that do not exist -> structural findings
    " ---------------------------------------------------------------------
    CREATE DATA lr_line TYPE HANDLE lo_struct.
    ASSIGN lr_line->* TO <row>.

    LOOP AT lt_fields ASSIGNING FIELD-SYMBOL(<fs_chk>) WHERE synthetic = abap_true.
      ASSIGN COMPONENT <fs_chk>-fieldname OF STRUCTURE <row> TO <val>.
      IF sy-subrc <> 0.
        APPEND VALUE #( row = 0 fieldname = <fs_chk>-fieldname
                        check_type = c_check-structure
                        message   = build_msg( iv_nr = '003'
                                                iv_a  = <fs_chk>-fieldname )
                        severity  = c_severity-error )
               TO rt_findings.
      ENDIF.
    ENDLOOP.

    " ---------------------------------------------------------------------
    " 3.7) declarative comparison rules: operator must be known, both
    "      operands must exist; uniqueness rules: fields must exist
    " ---------------------------------------------------------------------
    LOOP AT mt_compare_rules ASSIGNING FIELD-SYMBOL(<fs_crchk>).
      IF <fs_crchk>-operator <> 'EQ' AND <fs_crchk>-operator <> 'NE'
         AND <fs_crchk>-operator <> 'LT' AND <fs_crchk>-operator <> 'LE'
         AND <fs_crchk>-operator <> 'GT' AND <fs_crchk>-operator <> 'GE'.
        APPEND VALUE #( row = 0 fieldname = <fs_crchk>-field
                        check_type = c_check-structure
                        message   = build_msg( iv_nr = '020'
                                                iv_a  = <fs_crchk>-operator )
                        severity  = c_severity-error )
               TO rt_findings.
      ENDIF.
      ASSIGN COMPONENT <fs_crchk>-field OF STRUCTURE <row> TO <val>.
      IF sy-subrc <> 0.
        APPEND VALUE #( row = 0 fieldname = <fs_crchk>-field
                        check_type = c_check-structure
                        message   = build_msg( iv_nr = '003'
                                                iv_a  = <fs_crchk>-field )
                        severity  = c_severity-error )
               TO rt_findings.
      ENDIF.
      ASSIGN COMPONENT <fs_crchk>-other OF STRUCTURE <row> TO <val>.
      IF sy-subrc <> 0.
        APPEND VALUE #( row = 0 fieldname = <fs_crchk>-other
                        check_type = c_check-structure
                        message   = build_msg( iv_nr = '003'
                                                iv_a  = <fs_crchk>-other )
                        severity  = c_severity-error )
               TO rt_findings.
      ENDIF.
    ENDLOOP.

    LOOP AT mt_unique_rules ASSIGNING FIELD-SYMBOL(<fs_urchk>).
      LOOP AT unique_fields( <fs_urchk> ) INTO DATA(lv_ufield).
        ASSIGN COMPONENT lv_ufield OF STRUCTURE <row> TO <val>.
        IF sy-subrc <> 0.
          APPEND VALUE #( row = 0 fieldname = lv_ufield
                          check_type = c_check-structure
                          message   = build_msg( iv_nr = '003'
                                                  iv_a  = lv_ufield )
                          severity  = c_severity-error )
                 TO rt_findings.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    " ---------------------------------------------------------------------
    " 4) prefill the check-table lookup cache in chunked batches
    " ---------------------------------------------------------------------
    prefetch_checktables( it_data = it_data it_fields = lt_fields ).
    prefetch_foreign_keys( it_data = it_data it_fields = lt_fields ).

    " ---------------------------------------------------------------------
    " 5) row loop
    " ---------------------------------------------------------------------
    " manual counter on purpose: sy-tabix is not filled for hashed
    " tables; the offset keeps global row numbers across slices
    lv_row = iv_row_offset.
    LOOP AT it_data ASSIGNING <row>.
      lv_row = lv_row + 1.
      GET REFERENCE OF <row> INTO lr_row.

      LOOP AT lt_fields ASSIGNING FIELD-SYMBOL(<fs_field>).

        ASSIGN COMPONENT <fs_field>-fieldname OF STRUCTURE <row> TO <val>.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.

        DATA(lv_disp) = CONV string( <val> ).

        " required ........................................................
        IF <fs_field>-required = abap_true AND <val> IS INITIAL.
          APPEND VALUE #( row = lv_row fieldname = <fs_field>-fieldname
                          value = lv_disp
                          check_type = c_check-required
                          message = build_msg( iv_nr = '004'
                                               iv_a  = <fs_field>-fieldname )
                          severity = <fs_field>-rule_severity
                          rule_id  = <fs_field>-rule_id )
                 TO rt_findings.
          CONTINUE.
        ENDIF.

        " initial values pass all other checks ............................
        IF <val> IS INITIAL.
          CONTINUE.
        ENDIF.

        " format checks ....................................................
        CASE <fs_field>-datatype.
          WHEN 'DATS'.
            IF check_date( lv_disp ) = abap_false.
              APPEND VALUE #( row = lv_row fieldname = <fs_field>-fieldname
                              value = lv_disp
                              check_type = c_check-date
                              message = build_msg( iv_nr = '005'
                                                   iv_a  = lv_disp )
                              severity  = c_severity-error )
                     TO rt_findings.
              CONTINUE.
            ENDIF.
          WHEN 'TIMS'.
            IF check_time( lv_disp ) = abap_false.
              APPEND VALUE #( row = lv_row fieldname = <fs_field>-fieldname
                              value = lv_disp
                              check_type = c_check-time
                              message = build_msg( iv_nr = '006'
                                                   iv_a  = lv_disp )
                              severity  = c_severity-error )
                     TO rt_findings.
              CONTINUE.
            ENDIF.
          WHEN 'NUMC'.
            IF check_numc( lv_disp ) = abap_false.
              APPEND VALUE #( row = lv_row fieldname = <fs_field>-fieldname
                              value = lv_disp
                              check_type = c_check-numc
                              message = build_msg( iv_nr = '007'
                                                   iv_a  = lv_disp )
                              severity  = c_severity-error )
                     TO rt_findings.
              CONTINUE.
            ENDIF.
        ENDCASE.

        " domain fixed values .............................................
        DATA(lv_dom) = COND #( WHEN <fs_field>-rule_domname IS NOT INITIAL
                              THEN <fs_field>-rule_domname
                              ELSE <fs_field>-domname ).

        " comparison value in internal format (conversion exit + case)
        DATA(lv_int) = internal_value( is_field = <fs_field>
                                       iv_disp  = lv_disp ).

        DATA lv_has_fixed_values TYPE abap_bool VALUE abap_false.
        IF lv_dom IS NOT INITIAL.
          DATA(ls_dom) = get_domain( lv_dom ).
          lv_has_fixed_values = xsdbool( ls_dom-values IS NOT INITIAL ).
        ENDIF.

        IF lv_has_fixed_values = abap_true AND
           check_domain( iv_domname = lv_dom iv_value = lv_int ) = abap_false.
          APPEND VALUE #( row = lv_row fieldname = <fs_field>-fieldname
                          value = lv_disp object = lv_dom
                          check_type = c_check-domain
                          message = build_msg( iv_nr = '008'
                                               iv_a  = lv_disp
                                               iv_b  = lv_dom )
                          severity = COND ty_severity(
                                       WHEN <fs_field>-rule_domname IS NOT INITIAL
                                       THEN <fs_field>-rule_severity
                                       ELSE c_severity-error )
                          rule_id  = COND #( WHEN <fs_field>-rule_domname IS NOT INITIAL
                                             THEN <fs_field>-rule_id ) )
                 TO rt_findings.
          CONTINUE.
        ENDIF.

        " check table (rule overrides DDIC) ...............................
        DATA(lv_ctab) = COND #( WHEN <fs_field>-rule_ctab IS NOT INITIAL
                                THEN <fs_field>-rule_ctab
                                ELSE <fs_field>-checktable ).
        DATA(lv_cfld) = COND #( WHEN <fs_field>-rule_cfield IS NOT INITIAL
                                THEN <fs_field>-rule_cfield
                                WHEN <fs_field>-fkey_checkfield IS NOT INITIAL
                                THEN <fs_field>-fkey_checkfield
                                ELSE <fs_field>-fieldname ).

        DATA: lv_keysig   TYPE string,
              lv_tuple    TYPE string,
              lv_complete TYPE abap_bool,
              lv_composed TYPE abap_bool.

        CLEAR: lv_tuple, lv_complete, lv_composed.

        IF lv_ctab IS NOT INITIAL AND
           <fs_field>-fkey_partners IS NOT INITIAL.

          " composite DDIC foreign key: validate the value combination;
          " an incomplete tuple (initial partner) degrades to the single
          " field check below
          build_fkey_tuple( EXPORTING is_field = <fs_field>
                                      it_fields = lt_fields
                                      iv_struct = <row>
                                      iv_value  = lv_int
                            IMPORTING ev_tuple    = lv_tuple
                                      ev_complete = lv_complete ).

          IF lv_complete = abap_true.
            lv_keysig = ckey_keysig( <fs_field> ).

            IF check_foreign_key( iv_table  = lv_ctab
                                  iv_keysig = lv_keysig
                                  iv_tuple  = lv_tuple ) = abap_false.
              APPEND VALUE #( row = lv_row fieldname = <fs_field>-fieldname
                              value = lv_disp object = |{ lv_ctab }/{ lv_keysig }|
                              check_type = c_check-checktable
                              message = build_msg( iv_nr = '015'
                                                   iv_a  = lv_disp
                                                   iv_b  = lv_ctab
                                                   iv_c  = lv_keysig )
                              severity  = c_severity-error )
                     TO rt_findings.
              CONTINUE.
            ENDIF.

            " composite check passed -> the single field check is skipped
            lv_composed = abap_true.
          ENDIF.

        ENDIF.

        IF lv_ctab IS NOT INITIAL AND lv_composed = abap_false AND
           check_table( iv_table = lv_ctab iv_field = lv_cfld iv_value = lv_int ) = abap_false.
          APPEND VALUE #( row = lv_row fieldname = <fs_field>-fieldname
                          value = lv_disp object = |{ lv_ctab }/{ lv_cfld }|
                          check_type = c_check-checktable
                          message = build_msg( iv_nr = '009'
                                               iv_a  = lv_disp
                                               iv_b  = lv_ctab
                                               iv_c  = lv_cfld )
                          severity = COND ty_severity(
                                       WHEN <fs_field>-rule_ctab IS NOT INITIAL
                                       THEN <fs_field>-rule_severity
                                       ELSE c_severity-error )
                          rule_id  = COND #( WHEN <fs_field>-rule_ctab IS NOT INITIAL
                                             THEN <fs_field>-rule_id ) )
                 TO rt_findings.
          CONTINUE.
        ENDIF.

        " regex rule ......................................................
        " FIND REGEX instead of predicate function matches( ) - predicate
        " functions cannot be compared with = and are not available on
        " older support packages
        IF <fs_field>-regex IS NOT INITIAL.
          FIND REGEX <fs_field>-regex IN lv_disp.
          IF sy-subrc <> 0.
            APPEND VALUE #( row = lv_row fieldname = <fs_field>-fieldname
                            value = lv_disp object = <fs_field>-regex
                            check_type = c_check-regex
                            message = build_msg( iv_nr = '010'
                                                 iv_a  = lv_disp )
                            severity = <fs_field>-rule_severity
                            rule_id  = <fs_field>-rule_id )
                   TO rt_findings.
            CONTINUE.
          ENDIF.
        ENDIF.

        " registered column checks (plugins) ..........................
        " they run last: only values the validator itself accepted reach
        " them, the first failing plugin finishes the field
        LOOP AT mt_plugins ASSIGNING FIELD-SYMBOL(<fs_plugin>)
             WHERE fieldname = <fs_field>-fieldname.

          DATA(ls_result) = <fs_plugin>-check->check(
                              iv_row       = lv_row
                              iv_fieldname = <fs_field>-fieldname
                              iv_value     = lv_disp
                              ir_row       = lr_row ).

          IF ls_result-ok <> abap_true.
            APPEND VALUE #( row = lv_row fieldname = <fs_field>-fieldname
                            value = lv_disp
                            object = ls_result-object
                            check_type = c_check-plugin
                            message = ls_result-message
                            severity = normalize_severity( ls_result-severity )
                            rule_id  = ls_result-rule_id )
                   TO rt_findings.
            EXIT.
          ENDIF.
        ENDLOOP.

      ENDLOOP.

      " declarative cross field comparisons of this row. They are row
      " level rules and run independently of the column filters and of
      " the per-field first-error-wins chain above
      APPEND LINES OF compare_findings( iv_row   = lv_row
                                        iv_struct = <row> ) TO rt_findings.
    ENDLOOP.

    " ---------------------------------------------------------------------
    " 6) file level duplicate rules (first occurrence passes)
    " ---------------------------------------------------------------------
    APPEND LINES OF unique_findings( it_data   = it_data
                                     iv_offset = iv_row_offset )
           TO rt_findings.

  ENDMETHOD.


  METHOD add_rule.
    APPEND is_rule TO mt_rules.
  ENDMETHOD.


  METHOD add_rules.
    APPEND LINES OF it_rules TO mt_rules.
  ENDMETHOD.


  METHOD clear_rules.
    CLEAR mt_rules.
  ENDMETHOD.


  METHOD add_column_check.
    INSERT VALUE #( fieldname = to_upper( CONV string( iv_fieldname ) )
                    check     = io_check )
           INTO TABLE mt_plugins.
  ENDMETHOD.


  METHOD clear_column_checks.
    CLEAR mt_plugins.
  ENDMETHOD.


  METHOD add_compare_rule.
    " upper case on purpose: structure components and the operator set
    " are upper case, callers may pass any case
    APPEND VALUE #( rule_id  = is_rule-rule_id
                    severity = is_rule-severity
                    field    = to_upper( CONV string( is_rule-field ) )
                    operator = to_upper( CONV string( is_rule-operator ) )
                    other    = to_upper( CONV string( is_rule-other ) ) )
           TO mt_compare_rules.
  ENDMETHOD.


  METHOD add_compare_rules.
    LOOP AT it_rules INTO DATA(ls_rule).
      add_compare_rule( ls_rule ).
    ENDLOOP.
  ENDMETHOD.


  METHOD clear_compare_rules.
    CLEAR mt_compare_rules.
  ENDMETHOD.


  METHOD add_unique_rule.
    DATA lt_fields TYPE ty_fieldnames.
    LOOP AT is_rule-fields INTO DATA(lv_field).
      INSERT to_upper( lv_field ) INTO TABLE lt_fields.
    ENDLOOP.

    APPEND VALUE #( rule_id  = is_rule-rule_id
                    severity = is_rule-severity
                    field    = to_upper( CONV string( is_rule-field ) )
                    fields   = lt_fields )
           TO mt_unique_rules.
  ENDMETHOD.


  METHOD add_unique_rules.
    LOOP AT it_rules INTO DATA(ls_rule).
      add_unique_rule( ls_rule ).
    ENDLOOP.
  ENDMETHOD.


  METHOD clear_unique_rules.
    CLEAR mt_unique_rules.
  ENDMETHOD.


  METHOD add_rules_from_db.
    DATA(lv_scenario) = to_upper( CONV string( iv_scenario ) ).
    DATA(lv_tabname) = COND string( WHEN iv_tabname IS INITIAL
                                    THEN CONV string( c_rulestab )
                                    ELSE to_upper( CONV string( iv_tabname ) ) ).

    DATA lt_rows TYPE ty_db_rules.

    " dynamic FROM on purpose: the class must activate without the
    " table object (no activation order dependency) and stay lenient on
    " systems where it is missing - the SELECT raises, the catch keeps
    " the rule set untouched
    TRY.
        SELECT scenario, rule_id, rule_type, fieldname,
               operator, other_field, required, severity,
               regex, checktable, checkfield, domname
          FROM (lv_tabname)
          WHERE scenario = @lv_scenario
          INTO CORRESPONDING FIELDS OF TABLE @lt_rows.
      CATCH cx_root ##NO_TEXT.
        CLEAR lt_rows.
    ENDTRY.

    rv_count = apply_db_rules( lt_rows ).
  ENDMETHOD.


  METHOD apply_db_rules.

    " stable order (BY on purpose, the table has an empty key): UNIQUE
    " rows of one rule id become adjacent, the alphabetically first
    " row of a group is the anchor
    SORT it_rules BY rule_type ASCENDING
                     rule_id ASCENDING
                     fieldname ASCENDING.

    LOOP AT it_rules ASSIGNING FIELD-SYMBOL(<ls_row>).
      CASE <ls_row>-rule_type.
        WHEN c_rule_type-column.
          add_rule( VALUE #( fieldname  = <ls_row>-fieldname
                             required   = xsdbool( <ls_row>-required = 'X' )
                             regex      = <ls_row>-regex
                             checktable = <ls_row>-checktable
                             checkfield = <ls_row>-checkfield
                             domname    = <ls_row>-domname
                             severity   = <ls_row>-severity
                             rule_id    = <ls_row>-rule_id ) ).
          rv_count = rv_count + 1.

        WHEN c_rule_type-compare.
          add_compare_rule( VALUE #( field    = <ls_row>-fieldname
                                     operator = <ls_row>-operator
                                     other    = <ls_row>-other_field
                                     severity = <ls_row>-severity
                                     rule_id  = <ls_row>-rule_id ) ).
          rv_count = rv_count + 1.

        WHEN c_rule_type-unique.
          " one row per key field, all rows of a rule id form ONE
          " rule - handled in the grouped loop below
          CONTINUE.

        WHEN OTHERS.
          CONTINUE.                " unknown rule type -> skip leniently
      ENDCASE.
    ENDLOOP.

    " UNIQUE groups: rows sharing a rule id form ONE rule, every row
    " contributes a key field; the sorted order makes the first row of
    " the group the anchor. Explicit grouping on purpose: control level
    " blocks (AT NEW/AT END OF) fill trailing components with '*' when
    " read, a classic source of garbage anchors
    DATA: lt_groups TYPE ty_unique_rules,
          lv_cur_id TYPE c LENGTH 30.

    CLEAR: lt_groups, lv_cur_id.
    LOOP AT it_rules ASSIGNING FIELD-SYMBOL(<ls_urow>)
         WHERE rule_type = c_rule_type-unique.

      IF <ls_urow>-rule_id <> lv_cur_id.
        DATA ls_unique TYPE ty_unique_rule.
        CLEAR ls_unique.
        ls_unique-rule_id  = <ls_urow>-rule_id.
        ls_unique-severity = <ls_urow>-severity.
        ls_unique-field    = <ls_urow>-fieldname.
        lv_cur_id = <ls_urow>-rule_id.
        APPEND ls_unique TO lt_groups ASSIGNING FIELD-SYMBOL(<ls_group>).
      ENDIF.

      " CONV on purpose: INSERT INTO TABLE demands a source compatible
      " with the string line type, C(30) of the db row is not
      INSERT CONV string( <ls_urow>-fieldname ) INTO TABLE <ls_group>-fields.
    ENDLOOP.

    LOOP AT lt_groups INTO DATA(ls_group).
      add_unique_rule( ls_group ).
      rv_count = rv_count + 1.
    ENDLOOP.

  ENDMETHOD.


  METHOD only_fields.
    CLEAR mt_only_fields.
    LOOP AT it_fields INTO DATA(lv_field).
      DATA(lv_upper) = to_upper( lv_field ).
      INSERT lv_upper INTO TABLE mt_only_fields.
    ENDLOOP.
  ENDMETHOD.


  METHOD exclude_fields.
    CLEAR mt_exclude_fields.
    LOOP AT it_fields INTO DATA(lv_field).
      DATA(lv_upper) = to_upper( lv_field ).
      INSERT lv_upper INTO TABLE mt_exclude_fields.
    ENDLOOP.
  ENDMETHOD.


  METHOD clear_caches.
    CLEAR: mt_domains, mt_ctab_hits, mt_ckey_hits, mt_struct_fks, mt_convexits.
  ENDMETHOD.


  METHOD check_value_by_element.
    rv_ok = check_single( EXPORTING iv_value    = iv_value
                                  iv_rollname = iv_rollname
                          IMPORTING es_finding = es_finding ).
  ENDMETHOD.


  METHOD check_value_by_field.
    CLEAR es_finding.
    rv_ok = abap_false.

    DATA(lv_tabname) = to_upper( CONV string( iv_tabname ) ).
    DATA(lv_field)   = to_upper( CONV string( iv_fieldname ) ).

    " existence pre-check on dd02l: describe_by_name dumps (uncatchably)
    " for unknown names on some releases, a SELECT cannot raise
    SELECT SINGLE @abap_true FROM dd02l
           WHERE tabname = @lv_tabname AND as4local = 'A'
           INTO @DATA(lv_tab_exists).

    DATA lo_struct TYPE REF TO cl_abap_structdescr.
    IF lv_tab_exists = abap_true.
      TRY.
          DATA(lo_descr) = cl_abap_typedescr=>describe_by_name( lv_tabname ).
          IF lo_descr->kind = cl_abap_typedescr=>kind_table.
            lo_descr = CAST cl_abap_tabledescr( lo_descr )->get_table_line_type( ).
          ENDIF.
          IF lo_descr->kind = cl_abap_typedescr=>kind_struct.
            lo_struct = CAST cl_abap_structdescr( lo_descr ).
          ENDIF.
        CATCH cx_root ##NO_TEXT.
          CLEAR lo_struct.
      ENDTRY.
    ENDIF.

    IF lo_struct IS INITIAL OR lo_struct->is_ddic_type( ) = abap_false.
      es_finding-row        = 0.
      es_finding-fieldname  = CONV fieldname( lv_field ).
      es_finding-check_type = c_check-structure.
      es_finding-severity   = c_severity-error.
      es_finding-message    = build_msg( iv_nr = '012' iv_a = lv_tabname ).
      RETURN.
    ENDIF.

    TRY.
        DATA(lt_dfies) = lo_struct->get_ddic_field_list( ).
      CATCH cx_root ##NO_TEXT.
        CLEAR lt_dfies.
    ENDTRY.

    READ TABLE lt_dfies INTO DATA(ls_dfies) WITH KEY fieldname = lv_field.
    IF sy-subrc <> 0.
      es_finding-row        = 0.
      es_finding-fieldname  = CONV fieldname( lv_field ).
      es_finding-check_type = c_check-structure.
      es_finding-severity   = c_severity-error.
      es_finding-message    = build_msg( iv_nr = '013'
                                         iv_a  = lv_field
                                         iv_b  = lv_tabname ).
      RETURN.
    ENDIF.

    IF ls_dfies-rollname IS INITIAL.
      es_finding-row        = 0.
      es_finding-fieldname  = CONV fieldname( lv_field ).
      es_finding-check_type = c_check-structure.
      es_finding-severity   = c_severity-error.
      es_finding-message    = build_msg( iv_nr = '014'
                                         iv_a  = lv_field
                                         iv_b  = lv_tabname ).
      RETURN.
    ENDIF.

    rv_ok = check_single( EXPORTING iv_value    = iv_value
                                  iv_rollname = ls_dfies-rollname
                          IMPORTING es_finding = es_finding ).
    es_finding-fieldname = CONV fieldname( lv_field ).
  ENDMETHOD.


  METHOD check_single.
    CLEAR es_finding.
    rv_ok = abap_false.

    DATA(lv_rollname) = to_upper( CONV string( iv_rollname ) ).

    " existence pre-check on dd04l, same reason as check_value_by_field
    SELECT SINGLE @abap_true FROM dd04l
           WHERE rollname = @lv_rollname AND as4local = 'A'
           INTO @DATA(lv_elem_exists).

    DATA lo_descr TYPE REF TO cl_abap_typedescr.
    IF lv_elem_exists = abap_true.
      TRY.
          lo_descr = cl_abap_typedescr=>describe_by_name( lv_rollname ).
        CATCH cx_root ##NO_TEXT.
          CLEAR lo_descr.
      ENDTRY.
    ENDIF.

    IF lo_descr IS INITIAL
       OR lo_descr->kind <> cl_abap_typedescr=>kind_elem
       OR CAST cl_abap_elemdescr( lo_descr )->is_ddic_type( ) = abap_false.
      es_finding-row        = 0.
      es_finding-fieldname  = CONV fieldname( lv_rollname ).
      es_finding-check_type = c_check-structure.
      es_finding-severity   = c_severity-error.
      es_finding-message    = build_msg( iv_nr = '011' iv_a = lv_rollname ).
      RETURN.
    ENDIF.

    " one-field anonymous structure, one row -> reuse validate( ) with a
    " fresh instance so column filters and rules of the caller cannot
    " interfere
    DATA(lo_elem)   = CAST cl_abap_elemdescr( lo_descr ).
    DATA(lo_struct) = cl_abap_structdescr=>create(
                        VALUE #( ( name = 'VAL' type = lo_elem ) ) ).
    DATA(lo_tab)    = cl_abap_tabledescr=>create( lo_struct ).

    DATA: lr_tab TYPE REF TO data,
          lr_row TYPE REF TO data.
    CREATE DATA: lr_tab TYPE HANDLE lo_tab,
                 lr_row TYPE HANDLE lo_struct.

    FIELD-SYMBOLS: <lt_values> TYPE ANY TABLE,
                   <ls_row>    TYPE any,
                   <lv_val>    TYPE any.
    ASSIGN: lr_tab->* TO <lt_values>,
            lr_row->* TO <ls_row>.
    ASSIGN COMPONENT 'VAL' OF STRUCTURE <ls_row> TO <lv_val>.
    <lv_val> = iv_value.
    INSERT <ls_row> INTO TABLE <lt_values>.

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( <lt_values> ).

    IF lt_findings IS INITIAL.
      rv_ok = abap_true.
      RETURN.
    ENDIF.

    READ TABLE lt_findings INTO es_finding INDEX 1.
    es_finding-row       = 1.
    es_finding-fieldname = CONV fieldname( lv_rollname ).
  ENDMETHOD.


  METHOD display_findings.
    " SALV factory wants CHANGING, the IMPORTING parameter must not be
    " modified -> hand it a local copy
    DATA(lt_findings) = it_findings.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = DATA(lo_alv)
          CHANGING  t_table      = lt_findings ).

        lo_alv->get_columns( )->set_optimize( abap_true ).

        IF iv_title IS NOT INITIAL.
          lo_alv->get_display_settings( )->set_list_header(
            CONV #( iv_title ) ).
        ENDIF.

        lo_alv->display( ).

      CATCH cx_salv_msg ##NO_TEXT.
        " no SALV on this system -> classic list instead, never raise
        LOOP AT it_findings INTO DATA(ls_finding).
          WRITE: / ls_finding-row, ls_finding-fieldname, ls_finding-value,
                   ls_finding-severity, ls_finding-check_type,
                   ls_finding-rule_id, ls_finding-message.
        ENDLOOP.
    ENDTRY.
  ENDMETHOD.


  METHOD log_findings.
    CHECK it_findings IS NOT INITIAL.

    DATA ls_log TYPE bal_s_log.
    ls_log-object    = iv_object.
    ls_log-subobject = iv_subobject.
    ls_log-extnumber = iv_extnumber.

    CALL FUNCTION 'BAL_LOG_CREATE'
      EXPORTING
        i_s_log      = ls_log
      IMPORTING
        e_log_handle = rv_log_handle
      EXCEPTIONS
        OTHERS       = 1.
    IF sy-subrc <> 0.
      " e.g. object not registered in SLG0 -> nothing we can do here
      CLEAR rv_log_handle.
      RETURN.
    ENDIF.

    LOOP AT build_bal_msgs( it_findings ) INTO DATA(ls_msg).
      CALL FUNCTION 'BAL_LOG_MSG_ADD'
        EXPORTING
          i_log_handle = rv_log_handle
          i_s_msg      = ls_msg
        EXCEPTIONS
          log_not_found = 1
          OTHERS        = 2.
      IF sy-subrc <> 0.
        CLEAR rv_log_handle.
        RETURN.
      ENDIF.
    ENDLOOP.

    DATA lt_handles TYPE bal_t_logh.
    APPEND rv_log_handle TO lt_handles.

    " save in the current LUW: the caller stays in charge of the commit
    CALL FUNCTION 'BAL_DB_SAVE'
      EXPORTING
        i_t_log_handle = lt_handles
      EXCEPTIONS
        log_not_found    = 1
        save_not_allowed = 2
        numbering_error  = 3
        OTHERS           = 4.
    IF sy-subrc <> 0.
      CLEAR rv_log_handle.
      RETURN.
    ENDIF.

    IF iv_commit = abap_true.
      COMMIT WORK.
    ENDIF.
  ENDMETHOD.


  METHOD precheck_truncation.
    DATA(lv_typename) = to_upper( CONV string( iv_typename ) ).

    " a pre-warning is the default of this helper, E only on request
    DATA(lv_severity) = COND ty_severity( WHEN iv_severity IS INITIAL
                                          THEN c_severity-warning
                                          ELSE normalize_severity( iv_severity ) ).

    " existence pre-check on dd02l: describe_by_name dumps (uncatchably)
    " for unknown names on some releases, a SELECT cannot raise
    SELECT SINGLE @abap_true FROM dd02l
           WHERE tabname = @lv_typename AND as4local = 'A'
           INTO @DATA(lv_exists).

    DATA: lt_dfies   TYPE ddfields,
          lv_badtype TYPE abap_bool VALUE abap_false.

    IF lv_exists = abap_true.
      TRY.
          DATA(lo_descr) = cl_abap_typedescr=>describe_by_name( lv_typename ).
          IF lo_descr->kind = cl_abap_typedescr=>kind_table.
            lo_descr = CAST cl_abap_tabledescr( lo_descr )->get_table_line_type( ).
          ENDIF.
          IF lo_descr->kind = cl_abap_typedescr=>kind_struct.
            lt_dfies = CAST cl_abap_structdescr( lo_descr )->get_ddic_field_list( ).
          ELSE.
            lv_badtype = abap_true.
          ENDIF.
        CATCH cx_root ##NO_TEXT.
          CLEAR lt_dfies.
      ENDTRY.
    ELSE.
      lv_badtype = abap_true.
    ENDIF.

    IF lv_badtype = abap_true OR lt_dfies IS INITIAL.
      APPEND VALUE #( row = 0 fieldname = '-'
                      check_type = c_check-structure
                      message = build_msg( iv_nr = '012' iv_a = lv_typename )
                      severity = c_severity-error )
             TO rt_findings.
      RETURN.
    ENDIF.

    DATA(lo_table) = CAST cl_abap_tabledescr(
                       cl_abap_typedescr=>describe_by_data( it_data ) ).
    DATA(lo_line)  = lo_table->get_table_line_type( ).

    IF lo_line->kind <> cl_abap_typedescr=>kind_struct.
      APPEND VALUE #( row = 0 fieldname = '-'
                      check_type = c_check-structure
                      message = build_msg( iv_nr = '001' )
                      severity = c_severity-error )
             TO rt_findings.
      RETURN.
    ENDIF.

    DATA(lo_struct) = CAST cl_abap_structdescr( lo_line ).

    " raw columns of the staging structure have no meaningful text
    " length -> skip them by name
    DATA lt_skip TYPE ty_fieldnames.
    LOOP AT lo_struct->get_components( ) ASSIGNING FIELD-SYMBOL(<ls_comp>).
      IF <ls_comp>-type->kind <> cl_abap_typedescr=>kind_elem.
        CONTINUE.
      ENDIF.
      DATA(lv_kind) = CAST cl_abap_elemdescr( <ls_comp>-type )->type_kind.
      IF lv_kind = cl_abap_typedescr=>typekind_xstring OR
         lv_kind = cl_abap_typedescr=>typekind_hex.
        INSERT to_upper( <ls_comp>-name ) INTO TABLE lt_skip.
      ENDIF.
    ENDLOOP.

    DATA lv_row TYPE i.
    LOOP AT it_data ASSIGNING FIELD-SYMBOL(<ls_row>).
      lv_row = lv_row + 1.

      LOOP AT lt_dfies ASSIGNING FIELD-SYMBOL(<ls_dtarget>).

        " only character-like target columns truncate text silently;
        " amounts and quantities refuse the assignment or convert
        CHECK <ls_dtarget>-datatype = c_charlike-char
           OR <ls_dtarget>-datatype = c_charlike-numc
           OR <ls_dtarget>-datatype = c_charlike-dats
           OR <ls_dtarget>-datatype = c_charlike-tims
           OR <ls_dtarget>-datatype = c_charlike-accp
           OR <ls_dtarget>-datatype = c_charlike-lang
           OR <ls_dtarget>-datatype = c_charlike-unit
           OR <ls_dtarget>-datatype = c_charlike-cuky
           OR <ls_dtarget>-datatype = c_charlike-clnt.

        READ TABLE lt_skip TRANSPORTING NO FIELDS
             WITH TABLE KEY table_line = <ls_dtarget>-fieldname.
        IF sy-subrc = 0.
          CONTINUE.
        ENDIF.

        " only columns that exist under the same name on both sides
        ASSIGN COMPONENT <ls_dtarget>-fieldname OF STRUCTURE <ls_row>
               TO FIELD-SYMBOL(<lv_src>).
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.

        DATA(lv_text) = CONV string( <lv_src> ).
        CHECK lv_text IS NOT INITIAL.

        " string conversion strips trailing blanks of CHAR columns, so
        " this is the length the assignment would really have to fit
        IF strlen( lv_text ) > <ls_dtarget>-leng.
          APPEND VALUE #( row = lv_row fieldname = <ls_dtarget>-fieldname
                          value = lv_text
                          object = |{ lv_typename }/{ <ls_dtarget>-fieldname }|
                          check_type = c_check-truncation
                          message = build_msg(
                              iv_nr = '019'
                              iv_a  = <ls_dtarget>-fieldname
                              iv_b  = |{ strlen( lv_text ) }|
                              iv_c  = |{ <ls_dtarget>-leng ALPHA = OUT }| )
                          severity = lv_severity )
                 TO rt_findings.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD build_bal_msgs.

    " one placeholder = 50 characters of SE91 message text: the whole
    " finding text is split into four of them via generic message 018
    CONSTANTS lc_chunk TYPE i VALUE 50.

    LOOP AT it_findings INTO DATA(ls_finding).

      DATA ls_msg TYPE bal_s_msg.
      CLEAR ls_msg.
      ls_msg-msgty = normalize_severity( ls_finding-severity ).
      ls_msg-msgid = c_msgid.
      ls_msg-msgno = '018'.

      DATA(lv_len) = strlen( ls_finding-message ).

      DO 4 TIMES.
        DATA(lv_off) = ( sy-index - 1 ) * lc_chunk.
        IF lv_off >= lv_len.
          EXIT.
        ENDIF.
        DATA(lv_chunk) = substring( val = ls_finding-message
                                    off  = lv_off
                                    len  = nmin( val1 = lc_chunk
                                                 val2 = lv_len - lv_off ) ).
        CASE sy-index.
          WHEN 1.
            ls_msg-msgv1 = lv_chunk.
          WHEN 2.
            ls_msg-msgv2 = lv_chunk.
          WHEN 3.
            ls_msg-msgv3 = lv_chunk.
          WHEN 4.
            ls_msg-msgv4 = lv_chunk.
        ENDCASE.
      ENDDO.

      APPEND ls_msg TO rt_msgs.
    ENDLOOP.
  ENDMETHOD.


  METHOD normalize_severity.
    IF iv_severity = c_severity-warning OR iv_severity = c_severity-info.
      rv_severity = iv_severity.
    ELSE.
      rv_severity = c_severity-error.
    ENDIF.
  ENDMETHOD.


  METHOD build_fields.

    DATA: lt_dfies  TYPE ddfields,
          lv_struct TYPE string.

    lv_struct = io_struct->get_relative_name( ).

    " primary path: structure itself is a DDIC type (includes flattened)
    IF io_struct->is_ddic_type( ) = abap_true.
      TRY.
          lt_dfies = io_struct->get_ddic_field_list( ).
        CATCH cx_root ##NO_TEXT.
          CLEAR lt_dfies.                     " metadata unreadable, use fallback
      ENDTRY.
    ENDIF.

    " fallback: mixed/local structures - take every DDIC typed element
    IF lt_dfies IS INITIAL.
      LOOP AT io_struct->get_components( ) ASSIGNING FIELD-SYMBOL(<ls_comp>).
        IF <ls_comp>-type->kind <> cl_abap_typedescr=>kind_elem.
          CONTINUE.
        ENDIF.
        DATA(lo_elem) = CAST cl_abap_elemdescr( <ls_comp>-type ).
        IF lo_elem->is_ddic_type( ) = abap_false.
          CONTINUE.
        ENDIF.
        TRY.
            DATA(ls_dfies) = lo_elem->get_ddic_field( ).
            " a standalone element description has no structure context,
            " its dfies-fieldname is initial -> use the component name
            ls_dfies-fieldname = <ls_comp>-name.
            APPEND ls_dfies TO lt_dfies.
          CATCH cx_root ##NO_TEXT.
            CONTINUE.
        ENDTRY.
      ENDLOOP.
    ENDIF.

    LOOP AT lt_dfies ASSIGNING FIELD-SYMBOL(<ls_dfies>).
      " self references (field checked against the table being loaded)
      " would validate every row against itself -> ignore
      IF <ls_dfies>-checktable IS NOT INITIAL AND
         <ls_dfies>-checktable = lv_struct.
        CLEAR <ls_dfies>-checktable.
      ENDIF.
      INSERT VALUE #( fieldname  = <ls_dfies>-fieldname
                      domname    = <ls_dfies>-domname
                      datatype   = <ls_dfies>-datatype
                      convexit   = <ls_dfies>-convexit
                      checktable = <ls_dfies>-checktable
                      reffield   = <ls_dfies>-reffield )
             INTO TABLE rt_fields.
    ENDLOOP.

    " merge explicit rules on top
    LOOP AT mt_rules ASSIGNING FIELD-SYMBOL(<ls_rule>).

      INSERT VALUE #( fieldname     = <ls_rule>-fieldname
                      synthetic     = abap_true
                      datatype      = 'CHAR'
                      required      = <ls_rule>-required
                      regex         = <ls_rule>-regex
                      rule_ctab     = <ls_rule>-checktable
                      rule_cfield   = <ls_rule>-checkfield
                      rule_domname  = <ls_rule>-domname
                      rule_severity = normalize_severity( <ls_rule>-severity )
                      rule_id       = <ls_rule>-rule_id )
             INTO TABLE rt_fields
             ASSIGNING FIELD-SYMBOL(<fs_field>).

      IF sy-subrc = 0.                           " new entry (synthetic field)
        CONTINUE.
      ENDIF.

      READ TABLE rt_fields ASSIGNING <fs_field>
           WITH TABLE KEY fieldname = <ls_rule>-fieldname.
      ASSERT sy-subrc = 0.

      IF <ls_rule>-required = abap_true.
        <fs_field>-required = abap_true.
      ENDIF.
      IF <ls_rule>-regex IS NOT INITIAL.
        <fs_field>-regex = <ls_rule>-regex.
      ENDIF.
      IF <ls_rule>-checktable IS NOT INITIAL.
        <fs_field>-rule_ctab   = <ls_rule>-checktable.
        <fs_field>-rule_cfield = <ls_rule>-checkfield.
      ENDIF.
      IF <ls_rule>-domname IS NOT INITIAL.
        <fs_field>-rule_domname = <ls_rule>-domname.
      ENDIF.
      IF <ls_rule>-rule_id IS NOT INITIAL.
        <fs_field>-rule_id = <ls_rule>-rule_id.
      ENDIF.

      " normalized on purpose: E when initial, last rule wins
      <fs_field>-rule_severity = normalize_severity( <ls_rule>-severity ).

    ENDLOOP.

    " plugin registrations for columns without DDIC metadata need a
    " synthetic field so the row loop visits them; the structural check
    " in validate( ) then reports unknown names the same way as rules
    LOOP AT mt_plugins INTO DATA(ls_plugin).
      INSERT VALUE #( fieldname = ls_plugin-fieldname
                      synthetic = abap_true
                      datatype  = 'CHAR' )
             INTO TABLE rt_fields.
    ENDLOOP.

  ENDMETHOD.


  METHOD resolve_foreign_keys.
    CHECK iv_structname IS NOT INITIAL.

    DATA(ls_fk) = get_struct_fks( iv_tabname = iv_structname ).

    LOOP AT ct_fields ASSIGNING FIELD-SYMBOL(<fs_fk>)
         WHERE checktable IS NOT INITIAL AND rule_ctab IS INITIAL.

      " own mapping row: field of the structure -> field of the check
      " table; without a row the same-name behaviour stays in effect
      READ TABLE ls_fk-maps INTO DATA(ls_map)
           WITH KEY fieldname = <fs_fk>-fieldname
                    fortable  = <fs_fk>-checktable.
      IF sy-subrc = 0.
        <fs_fk>-fkey_checkfield = ls_map-forkey.
      ENDIF.

      " partners of the composite foreign key: the other fields of the
      " same relationship whose components survived the column filters
      LOOP AT ls_fk-maps INTO DATA(ls_pmap)
           WHERE fortable = <fs_fk>-checktable.
        IF ls_pmap-fieldname = <fs_fk>-fieldname.
          CONTINUE.
        ENDIF.
        " the client assignment is part of the relationship but uploads
        " never carry the client -> it would permanently degrade the
        " composite check to the single field fallback
        IF ls_pmap-fieldname = 'MANDT' OR ls_pmap-forkey = 'MANDT'.
          CONTINUE.
        ENDIF.
        READ TABLE ct_fields TRANSPORTING NO FIELDS
             WITH TABLE KEY fieldname = ls_pmap-fieldname.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
        " a check table field must only appear once in the key: skip
        " partners of a second relationship to the same check table
        READ TABLE <fs_fk>-fkey_partners TRANSPORTING NO FIELDS
             WITH KEY checkfield = ls_pmap-forkey.
        IF sy-subrc = 0 OR ls_pmap-forkey = <fs_fk>-fkey_checkfield.
          CONTINUE.
        ENDIF.
        INSERT VALUE #( fieldname  = ls_pmap-fieldname
                        checkfield = ls_pmap-forkey )
               INTO TABLE <fs_fk>-fkey_partners.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_struct_fks.
    READ TABLE mt_struct_fks INTO rs_fk WITH TABLE KEY tabname = iv_tabname.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.

    rs_fk-tabname = iv_tabname.

    SELECT fieldname, fortable, forkey FROM dd05s
      WHERE tabname = @iv_tabname
      INTO CORRESPONDING FIELDS OF TABLE @rs_fk-maps.

    INSERT rs_fk INTO TABLE mt_struct_fks.
  ENDMETHOD.


  METHOD resolve_curr_quan.
    LOOP AT ct_fields ASSIGNING FIELD-SYMBOL(<fs_amt>)
         WHERE datatype = 'CURR' OR datatype = 'QUAN'.

      " CURR/QUAN amounts know their currency/unit code column by name
      CHECK <fs_amt>-reffield IS NOT INITIAL.
      CHECK <fs_amt>-reffield <> <fs_amt>-fieldname.

      READ TABLE ct_fields ASSIGNING FIELD-SYMBOL(<fs_code>)
           WITH TABLE KEY fieldname = <fs_amt>-reffield.
      IF sy-subrc <> 0.
        CONTINUE.                       " code column not part of the upload
      ENDIF.

      " an own DDIC foreign key or an explicit rule already validates
      " the code column -> never report the same problem twice
      CHECK <fs_code>-checktable IS INITIAL AND <fs_code>-rule_ctab IS INITIAL.

      " fkey_checkfield is the generic "resolved check table field" slot
      " read by the prefetch and the row loop alike; the code column
      " itself carries no conversion exit for currency keys, units keep
      " their CUNIT exit in internal_value( )
      IF <fs_amt>-datatype = 'CURR'.
        <fs_code>-checktable      = 'TCURC'.
        <fs_code>-fkey_checkfield = 'WAERS'.
      ELSE.
        <fs_code>-checktable      = 'T006'.
        <fs_code>-fkey_checkfield = 'MSEHI'.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD ckey_fields.
    APPEND COND fieldname( WHEN is_field-fkey_checkfield IS NOT INITIAL
                           THEN is_field-fkey_checkfield
                           ELSE is_field-fieldname )
           TO rt_fields.
    LOOP AT is_field-fkey_partners ASSIGNING FIELD-SYMBOL(<fs_cf>).
      APPEND <fs_cf>-checkfield TO rt_fields.
    ENDLOOP.
  ENDMETHOD.


  METHOD ckey_keysig.
    LOOP AT ckey_fields( is_field ) INTO DATA(lv_f).
      IF rv_sig IS NOT INITIAL.
        rv_sig = rv_sig && '+'.
      ENDIF.
      rv_sig = rv_sig && lv_f.
    ENDLOOP.
  ENDMETHOD.


  METHOD build_fkey_tuple.
    ev_complete = abap_true.
    ev_tuple    = iv_value.

    LOOP AT is_field-fkey_partners ASSIGNING FIELD-SYMBOL(<fs_bp>).

      ASSIGN COMPONENT <fs_bp>-fieldname OF STRUCTURE iv_struct
             TO FIELD-SYMBOL(<lv_bp>).
      IF sy-subrc <> 0 OR <lv_bp> IS INITIAL.
        ev_complete = abap_false.
        CLEAR ev_tuple.
        RETURN.
      ENDIF.

      READ TABLE it_fields ASSIGNING FIELD-SYMBOL(<fs_bmeta>)
           WITH TABLE KEY fieldname = <fs_bp>-fieldname.
      IF sy-subrc <> 0.
        ev_complete = abap_false.
        CLEAR ev_tuple.
        RETURN.
      ENDIF.

      ev_tuple = ev_tuple && cl_abap_char_utilities=>horizontal_tab
              && internal_value( is_field = <fs_bmeta>
                                 iv_disp  = CONV string( <lv_bp> ) ).
    ENDLOOP.
  ENDMETHOD.


  METHOD internal_value.
    " conversion exit first, then case folding: character values are
    " compared case-insensitively (upper) unless the effective domain
    " allows lowercase; digits pass through unchanged
    rv_val = to_internal( iv_convexit = is_field-convexit
                          iv_value    = iv_disp ).

    DATA(lv_dom) = COND #( WHEN is_field-rule_domname IS NOT INITIAL
                           THEN is_field-rule_domname
                           ELSE is_field-domname ).

    IF lv_dom IS INITIAL OR get_domain( lv_dom )-lowercase = abap_false.
      TRANSLATE rv_val TO UPPER CASE.
    ENDIF.
  ENDMETHOD.


  METHOD get_domain.
    READ TABLE mt_domains INTO rs_domain WITH TABLE KEY domname = iv_domname.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.

    rs_domain-domname = iv_domname.

    SELECT SINGLE lowercase FROM dd01l
           WHERE domname = @iv_domname AND as4local = 'A'
           INTO @rs_domain-lowercase.

    IF sy-subrc = 0.
      SELECT domvalue_l, domvalue_h FROM dd07l
        WHERE domname = @iv_domname AND as4local = 'A'
        INTO CORRESPONDING FIELDS OF TABLE @rs_domain-values.
    ENDIF.

    INSERT rs_domain INTO TABLE mt_domains.
  ENDMETHOD.


  METHOD check_domain.
    DATA(ls_dom) = get_domain( iv_domname ).

    rv_ok = abap_true.
    IF ls_dom-values IS INITIAL.
      RETURN.                                  " no fixed values -> all allowed
    ENDIF.

    rv_ok = abap_false.
    LOOP AT ls_dom-values ASSIGNING FIELD-SYMBOL(<ls_val>).
      IF <ls_val>-domvalue_h IS INITIAL.
        IF iv_value = <ls_val>-domvalue_l.
          rv_ok = abap_true.
          EXIT.
        ENDIF.
      ELSEIF iv_value >= <ls_val>-domvalue_l
         AND iv_value <= <ls_val>-domvalue_h.
        rv_ok = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD check_table.
    READ TABLE mt_ctab_hits INTO DATA(ls_hit)
         WITH TABLE KEY tabname = iv_table
                        field   = iv_field
                        value   = iv_value.
    IF sy-subrc = 0.
      rv_ok = ls_hit-found.
      RETURN.
    ENDIF.

    " lenient default: unreadable check-table metadata never blocks data
    rv_ok = abap_true.

    TRY.
        DATA(lv_where) = |{ to_upper( iv_field ) } = '|
                      && replace( val = iv_value sub = `'` with = `''` occ = 0 )
                      && |'|.

        " fully classic Open SQL on purpose: strict mode syntax (@) must
        " not be mixed with dynamic table/WHERE on older support packages.
        " No blanks inside the parentheses: WHERE( name ) must be one
        " compact token or the parser reads it as a static boolean
        " expression ("Boolean expression was expected")
        DATA lv_cnt TYPE i.

        SELECT COUNT(*) FROM (iv_table)
          INTO lv_cnt
          WHERE (lv_where).

        rv_ok = xsdbool( lv_cnt > 0 ).

      CATCH cx_sy_dynamic_osql_error ##NO_TEXT.
        " generated/view-only check tables etc. -> keep lenient default
    ENDTRY.

    INSERT VALUE #( tabname = iv_table field = iv_field value = iv_value
                    found   = rv_ok ) INTO TABLE mt_ctab_hits.
  ENDMETHOD.


  METHOD check_foreign_key.
    READ TABLE mt_ckey_hits INTO DATA(ls_hit)
         WITH TABLE KEY tabname = iv_table
                        keysig  = iv_keysig
                        tuple   = iv_tuple.
    IF sy-subrc = 0.
      rv_ok = ls_hit-found.
      RETURN.
    ENDIF.

    " lenient default: unreadable check-table metadata never blocks data
    rv_ok = abap_true.

    DATA: lt_fields TYPE ty_ckey_fields,
          lt_values TYPE ty_values,
          lv_where  TYPE string.

    SPLIT iv_keysig AT '+' INTO TABLE lt_fields.
    SPLIT iv_tuple  AT cl_abap_char_utilities=>horizontal_tab INTO TABLE lt_values.

    IF lines( lt_fields ) <> lines( lt_values ) OR lt_fields IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        LOOP AT lt_fields ASSIGNING FIELD-SYMBOL(<fs_kf>).
          READ TABLE lt_values INTO DATA(lv_val) INDEX sy-tabix.
          IF lv_where IS NOT INITIAL.
            lv_where = lv_where && ' AND '.
          ENDIF.
          lv_where = lv_where
                  && |{ <fs_kf> } = '|
                  && replace( val = lv_val sub = `'` with = `''` occ = 0 )
                  && |'|.
        ENDLOOP.

        " fully classic Open SQL on purpose, see check_table
        DATA lv_cnt TYPE i.

        SELECT COUNT(*) FROM (iv_table)
          INTO lv_cnt
          WHERE (lv_where).

        rv_ok = xsdbool( lv_cnt > 0 ).

      CATCH cx_sy_dynamic_osql_error ##NO_TEXT.
        " generated/view-only check tables etc. -> keep lenient default
    ENDTRY.

    INSERT VALUE #( tabname = iv_table keysig = iv_keysig tuple = iv_tuple
                    found   = rv_ok ) INTO TABLE mt_ckey_hits.
  ENDMETHOD.


  METHOD prefetch_checktables.

    DATA lt_wants TYPE ty_ctab_wants.

    LOOP AT it_fields ASSIGNING FIELD-SYMBOL(<fs_pfield>).

      " composite foreign keys are prefetched by prefetch_foreign_keys
      CHECK <fs_pfield>-fkey_partners IS INITIAL.

      DATA(lv_ctab) = COND #( WHEN <fs_pfield>-rule_ctab IS NOT INITIAL
                              THEN <fs_pfield>-rule_ctab
                              ELSE <fs_pfield>-checktable ).
      CHECK lv_ctab IS NOT INITIAL.
      DATA(lv_cfld) = COND #( WHEN <fs_pfield>-rule_cfield IS NOT INITIAL
                              THEN <fs_pfield>-rule_cfield
                              WHEN <fs_pfield>-fkey_checkfield IS NOT INITIAL
                              THEN <fs_pfield>-fkey_checkfield
                              ELSE <fs_pfield>-fieldname ).

      LOOP AT it_data ASSIGNING FIELD-SYMBOL(<fs_prow>).
        ASSIGN COMPONENT <fs_pfield>-fieldname OF STRUCTURE <fs_prow>
               TO FIELD-SYMBOL(<fs_pval>).
        IF sy-subrc <> 0 OR <fs_pval> IS INITIAL.
          CONTINUE.
        ENDIF.

        DATA(lv_int) = internal_value( is_field = <fs_pfield>
                                       iv_disp  = CONV string( <fs_pval> ) ).

        " already known from an earlier validate( ) on this instance?
        READ TABLE mt_ctab_hits TRANSPORTING NO FIELDS
             WITH TABLE KEY tabname = lv_ctab
                           field   = lv_cfld
                           value   = lv_int.
        IF sy-subrc = 0.
          CONTINUE.
        ENDIF.

        READ TABLE lt_wants ASSIGNING FIELD-SYMBOL(<fs_want>)
             WITH TABLE KEY tabname = lv_ctab field = lv_cfld.
        IF sy-subrc <> 0.
          INSERT VALUE #( tabname = lv_ctab field = lv_cfld )
                 INTO TABLE lt_wants ASSIGNING <fs_want>.
        ENDIF.
        INSERT lv_int INTO TABLE <fs_want>-values.
      ENDLOOP.
    ENDLOOP.

    LOOP AT lt_wants ASSIGNING <fs_want>.
      prefetch_ctab_group( iv_table  = <fs_want>-tabname
                           iv_field  = <fs_want>-field
                           it_values = <fs_want>-values ).
    ENDLOOP.
  ENDMETHOD.


  METHOD prefetch_ctab_group.

    DATA: lt_found     TYPE ty_ctab_vals,
          lt_found_set TYPE ty_value_set,
          lv_off       TYPE i,
          lv_from      TYPE i,
          lv_end       TYPE i,
          lv_in        TYPE string,
          lv_lit       TYPE string,
          lv_where     TYPE string.

    DATA(lv_fld)  = to_upper( iv_field ).
    DATA(lt_vals) = VALUE ty_values( ( LINES OF it_values ) ).

    WHILE lv_off < lines( lt_vals ).

      lv_from = lv_off + 1.
      lv_end  = nmin( val1 = lv_off + c_in_chunk
                      val2 = lines( lt_vals ) ).

      CLEAR lv_in.
      LOOP AT lt_vals FROM lv_from TO lv_end INTO DATA(lv_val).
        lv_lit = replace( val = lv_val sub = `'` with = `''` occ = 0 ).
        IF lv_in IS NOT INITIAL.
          lv_in = lv_in && ','.
        ENDIF.
        lv_in = lv_in && |'{ lv_lit }'|.
      ENDLOOP.
      lv_where = |{ lv_fld } IN ({ lv_in })|.

      TRY.
          CLEAR: lt_found, lt_found_set.

          " fully classic Open SQL on purpose, see check_table
          SELECT DISTINCT (lv_fld) FROM (iv_table)
            INTO TABLE lt_found
            WHERE (lv_where).

          LOOP AT lt_found INTO DATA(lv_hit).
            INSERT CONV string( lv_hit ) INTO TABLE lt_found_set.
          ENDLOOP.

          LOOP AT lt_vals FROM lv_from TO lv_end INTO lv_val.
            INSERT VALUE #( tabname = iv_table
                            field   = iv_field
                            value   = lv_val
                            found   = xsdbool( line_exists(
                                        lt_found_set[ table_line = lv_val ] ) ) )
                   INTO TABLE mt_ctab_hits.
          ENDLOOP.

        CATCH cx_sy_dynamic_osql_error.
          " unreadable check table (generated, view only, ...): cache
          " nothing here, the per-value fallback in the row loop keeps
          " the lenient behaviour
          RETURN.
      ENDTRY.

      lv_off = lv_end.
    ENDWHILE.
  ENDMETHOD.


  METHOD prefetch_foreign_keys.

    DATA: lt_groups TYPE ty_ckey_groups,
          lt_single TYPE ty_ctab_wants.

    LOOP AT it_fields ASSIGNING FIELD-SYMBOL(<fs_ffield>)
         WHERE checktable IS NOT INITIAL AND rule_ctab IS INITIAL.

      CHECK <fs_ffield>-fkey_partners IS NOT INITIAL.

      DATA(lv_ctab)   = <fs_ffield>-checktable.
      DATA(lv_keysig) = ckey_keysig( <fs_ffield> ).
      DATA(lt_cflds)  = ckey_fields( <fs_ffield> ).

      LOOP AT it_data ASSIGNING FIELD-SYMBOL(<fs_frow>).

        ASSIGN COMPONENT <fs_ffield>-fieldname OF STRUCTURE <fs_frow>
               TO FIELD-SYMBOL(<fs_fval>).
        IF sy-subrc <> 0 OR <fs_fval> IS INITIAL.
          CONTINUE.
        ENDIF.

        DATA(lv_int) = internal_value( is_field = <fs_ffield>
                                       iv_disp  = CONV string( <fs_fval> ) ).

        build_fkey_tuple( EXPORTING is_field = <fs_ffield>
                                    it_fields = it_fields
                                    iv_struct = <fs_frow>
                                    iv_value  = lv_int
                          IMPORTING ev_tuple    = DATA(lv_tuple)
                                    ev_complete = DATA(lv_complete) ).

        IF lv_complete = abap_true.

          READ TABLE mt_ckey_hits TRANSPORTING NO FIELDS
               WITH TABLE KEY tabname = lv_ctab
                              keysig  = lv_keysig
                              tuple   = lv_tuple.
          IF sy-subrc = 0.
            CONTINUE.
          ENDIF.

          READ TABLE lt_groups ASSIGNING FIELD-SYMBOL(<fs_fgrp>)
               WITH TABLE KEY tabname = lv_ctab keysig = lv_keysig.
          IF sy-subrc <> 0.
            INSERT VALUE #( tabname = lv_ctab keysig = lv_keysig
                            fields  = lt_cflds )
                   INTO TABLE lt_groups ASSIGNING <fs_fgrp>.
          ENDIF.
          INSERT lv_tuple INTO TABLE <fs_fgrp>-tuples.

        ELSE.

          " sparse row: the single field fallback of the row loop will
          " consult the single column cache -> prefetch the own value
          DATA(lv_sfld) = COND fieldname(
                            WHEN <fs_ffield>-fkey_checkfield IS NOT INITIAL
                            THEN <fs_ffield>-fkey_checkfield
                            ELSE <fs_ffield>-fieldname ).

          READ TABLE mt_ctab_hits TRANSPORTING NO FIELDS
               WITH TABLE KEY tabname = lv_ctab
                              field   = lv_sfld
                              value   = lv_int.
          IF sy-subrc = 0.
            CONTINUE.
          ENDIF.

          READ TABLE lt_single ASSIGNING FIELD-SYMBOL(<fs_swant>)
               WITH TABLE KEY tabname = lv_ctab field = lv_sfld.
          IF sy-subrc <> 0.
            INSERT VALUE #( tabname = lv_ctab field = lv_sfld )
                   INTO TABLE lt_single ASSIGNING <fs_swant>.
          ENDIF.
          INSERT lv_int INTO TABLE <fs_swant>-values.

        ENDIF.
      ENDLOOP.
    ENDLOOP.

    LOOP AT lt_groups ASSIGNING <fs_fgrp>.
      prefetch_ckey_group( iv_table  = <fs_fgrp>-tabname
                           iv_keysig = <fs_fgrp>-keysig
                           it_fields = <fs_fgrp>-fields
                           it_tuples = <fs_fgrp>-tuples ).
    ENDLOOP.

    LOOP AT lt_single ASSIGNING FIELD-SYMBOL(<fs_sgrp>).
      prefetch_ctab_group( iv_table  = <fs_sgrp>-tabname
                           iv_field  = <fs_sgrp>-field
                           it_values = <fs_sgrp>-values ).
    ENDLOOP.
  ENDMETHOD.


  METHOD prefetch_ckey_group.

    DATA: lt_tuples TYPE ty_values,
          lt_parts  TYPE ty_values,
          lt_found  TYPE ty_value_set,
          lv_off    TYPE i,
          lv_from   TYPE i,
          lv_end    TYPE i,
          lv_where  TYPE string,
          lv_cond   TYPE string,
          lv_cols   TYPE string,
          lv_ftuple TYPE string,
          lr_found  TYPE REF TO data.

    DATA(lv_tabs) = cl_abap_char_utilities=>horizontal_tab.

    " dynamic target: one character column per key field; C -> string
    " strips trailing blanks so found tuples compare cleanly with the
    " searched internal-format tuples
    TRY.
        " VALUE # at the parameter position infers the component table
        " type: the standalone name abap_componentdescr_tab is not
        " visible on older Basis releases
        DATA(lo_str) = cl_abap_structdescr=>create(
                         VALUE #( FOR lv_f IN it_fields
                                  ( name = lv_f
                                    type = cl_abap_elemdescr=>get_c( 1333 ) ) ) ).
        DATA(lo_tab) = cl_abap_tabledescr=>create( lo_str ).
      CATCH cx_root ##NO_TEXT.
        RETURN.                            " pathological field names
    ENDTRY.

    CREATE DATA lr_found TYPE HANDLE lo_tab.

    " typed on purpose: an inline FIELD-SYMBOL( ) declaration would
    " infer the generic type from REF TO data, and both
    " INTO TABLE @<lt_found> and LOOP AT <lt_found> then fail the
    " activation with "is not an internal table"
    FIELD-SYMBOLS <lt_found> TYPE STANDARD TABLE.
    ASSIGN lr_found->* TO <lt_found>.

    LOOP AT it_fields INTO DATA(lv_col).
      IF lv_cols IS NOT INITIAL.
        lv_cols = lv_cols && ','.
      ENDIF.
      lv_cols = lv_cols && lv_col.
    ENDLOOP.

    lt_tuples = VALUE ty_values( ( LINES OF it_tuples ) ).

    WHILE lv_off < lines( lt_tuples ).

      lv_from = lv_off + 1.
      lv_end  = nmin( val1 = lv_off + c_in_chunk
                      val2 = lines( lt_tuples ) ).

      CLEAR lv_where.
      LOOP AT lt_tuples FROM lv_from TO lv_end INTO DATA(lv_tuple).
        SPLIT lv_tuple AT lv_tabs INTO TABLE lt_parts.
        CLEAR lv_cond.
        LOOP AT it_fields ASSIGNING FIELD-SYMBOL(<fs_pf>).
          READ TABLE lt_parts INTO DATA(lv_pv) INDEX sy-tabix.
          IF lv_cond IS NOT INITIAL.
            lv_cond = lv_cond && ' AND '.
          ENDIF.
          lv_cond = lv_cond && |{ <fs_pf> } = '|
                  && replace( val = lv_pv sub = `'` with = `''` occ = 0 )
                  && |'|.
        ENDLOOP.
        IF lv_where IS NOT INITIAL.
          lv_where = lv_where && ' OR '.
        ENDIF.
        lv_where = lv_where && |( { lv_cond } )|.
      ENDLOOP.

      TRY.
          CLEAR lt_found.

          " classic dynamic SQL like check_table, but a field symbol as
          " INTO target needs the @ escape (plain variables do not) and
          " the @ form demands the INTO clause at the end of the statement
          SELECT DISTINCT (lv_cols) FROM (iv_table)
            WHERE (lv_where)
            INTO TABLE @<lt_found>.

          LOOP AT <lt_found> ASSIGNING FIELD-SYMBOL(<ls_found>).
            CLEAR lv_ftuple.
            LOOP AT it_fields ASSIGNING <fs_pf>.
              ASSIGN COMPONENT sy-tabix OF STRUCTURE <ls_found>
                     TO FIELD-SYMBOL(<lv_fv>).
              IF lv_ftuple IS NOT INITIAL.
                lv_ftuple = lv_ftuple && lv_tabs.
              ENDIF.
              lv_ftuple = lv_ftuple && CONV string( <lv_fv> ).
            ENDLOOP.
            INSERT lv_ftuple INTO TABLE lt_found.
          ENDLOOP.

          LOOP AT lt_tuples FROM lv_from TO lv_end INTO lv_tuple.
            INSERT VALUE #( tabname = iv_table
                            keysig  = iv_keysig
                            tuple   = lv_tuple
                            found   = xsdbool( line_exists(
                                        lt_found[ table_line = lv_tuple ] ) ) )
                   INTO TABLE mt_ckey_hits.
          ENDLOOP.

        CATCH cx_sy_dynamic_osql_error.
          " unreadable check table (generated, view only, ...): cache
          " nothing here, the per tuple fallback in the row loop keeps
          " the lenient behaviour
          RETURN.
      ENDTRY.

      lv_off = lv_end.
    ENDWHILE.
  ENDMETHOD.


  METHOD check_date.
    rv_ok = abap_false.
    CHECK iv_date IS NOT INITIAL
      AND strlen( iv_date ) = 8
      AND iv_date CO '0123456789'.

    DATA(lv_year)  = CONV i( iv_date(4) ).
    DATA(lv_month) = CONV i( iv_date+4(2) ).
    DATA(lv_day)   = CONV i( iv_date+6(2) ).

    CHECK lv_month BETWEEN 1 AND 12.

    DATA lv_max_day TYPE i.
    CASE lv_month.
      WHEN 1 OR 3 OR 5 OR 7 OR 8 OR 10 OR 12.
        lv_max_day = 31.
      WHEN 4 OR 6 OR 9 OR 11.
        lv_max_day = 30.
      WHEN 2.
        lv_max_day = COND i( WHEN lv_year MOD 4 = 0
                              AND ( lv_year MOD 100 <> 0 OR lv_year MOD 400 = 0 )
                             THEN 29 ELSE 28 ).
    ENDCASE.

    rv_ok = xsdbool( lv_day BETWEEN 1 AND lv_max_day ).
  ENDMETHOD.


  METHOD check_time.
    rv_ok = abap_false.
    CHECK iv_time IS NOT INITIAL
      AND strlen( iv_time ) = 6
      AND iv_time CO '0123456789'.

    rv_ok = xsdbool( CONV i( iv_time(2) )   < 24
                 AND CONV i( iv_time+2(2) ) < 60
                 AND CONV i( iv_time+4(2) ) < 60 ).
  ENDMETHOD.


  METHOD check_numc.
    rv_ok = xsdbool( iv_value CO '0123456789' ).
  ENDMETHOD.


  METHOD to_internal.
    rv_val = iv_value.
    CHECK iv_convexit IS NOT INITIAL.
    CHECK conv_exit_exists( iv_convexit ) = abap_true.

    DATA: lv_in  TYPE c LENGTH 256,
          lv_out TYPE c LENGTH 256.
    lv_in = iv_value.

    DATA(lv_fm) = |CONVERSION_EXIT_{ to_upper( iv_convexit ) }_INPUT|.

    TRY.
        CALL FUNCTION lv_fm
          EXPORTING
            input  = lv_in
          IMPORTING
            output = lv_out
          EXCEPTIONS
            OTHERS = 1.

        IF sy-subrc = 0.
          rv_val = lv_out.
        ENDIF.

      CATCH cx_sy_dyn_call_error ##NO_TEXT.
        " exotic exit with incompatible signature -> keep raw value
    ENDTRY.
  ENDMETHOD.


  METHOD conv_exit_exists.
    READ TABLE mt_convexits INTO DATA(ls_ce) WITH TABLE KEY name = iv_convexit.
    IF sy-subrc = 0.
      rv_ok = ls_ce-exists.
      RETURN.
    ENDIF.

    DATA(lv_fm) = |CONVERSION_EXIT_{ to_upper( iv_convexit ) }_INPUT|.

    SELECT SINGLE @abap_true FROM tfdir
           WHERE funcname = @lv_fm
           INTO @rv_ok.

    INSERT VALUE #( name = iv_convexit exists = rv_ok )
           INTO TABLE mt_convexits.
  ENDMETHOD.


  METHOD compare_findings.
    LOOP AT mt_compare_rules ASSIGNING FIELD-SYMBOL(<fs_cr>).

      ASSIGN COMPONENT <fs_cr>-field OF STRUCTURE iv_struct
             TO FIELD-SYMBOL(<lv_left>).
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      ASSIGN COMPONENT <fs_cr>-other OF STRUCTURE iv_struct
             TO FIELD-SYMBOL(<lv_right>).
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      " initial operands are exempt: mark the fields required instead
      " when an empty side must be reported
      IF <lv_left> IS INITIAL OR <lv_right> IS INITIAL.
        CONTINUE.
      ENDIF.

      " operator symbol in the finding text: 'DATE_FROM <= DATE_TO'
      " reads better than 'DATE_FROM LE DATE_TO'
      DATA(lv_op_sym) = SWITCH string( <fs_cr>-operator
                            WHEN 'EQ' THEN `=`
                            WHEN 'NE' THEN `<>`
                            WHEN 'LT' THEN `<`
                            WHEN 'LE' THEN `<=`
                            WHEN 'GT' THEN `>`
                            WHEN 'GE' THEN `>=`
                            ELSE <fs_cr>-operator ).

      DATA(lv_expr) = |{ <fs_cr>-field } { lv_op_sym } { <fs_cr>-other }|.

      DATA lv_ok TYPE abap_bool.
      lv_ok = abap_false.
      TRY.
          CASE <fs_cr>-operator.
            WHEN 'EQ'.
              IF <lv_left> = <lv_right>.
                lv_ok = abap_true.
              ENDIF.
            WHEN 'NE'.
              IF <lv_left> <> <lv_right>.
                lv_ok = abap_true.
              ENDIF.
            WHEN 'LT'.
              IF <lv_left> < <lv_right>.
                lv_ok = abap_true.
              ENDIF.
            WHEN 'LE'.
              IF <lv_left> <= <lv_right>.
                lv_ok = abap_true.
              ENDIF.
            WHEN 'GT'.
              IF <lv_left> > <lv_right>.
                lv_ok = abap_true.
              ENDIF.
            WHEN 'GE'.
              IF <lv_left> >= <lv_right>.
                lv_ok = abap_true.
              ENDIF.
            WHEN OTHERS.
              CONTINUE.                " reported as structure finding before
          ENDCASE.
        CATCH cx_root ##NO_TEXT.
          " operands that cannot be compared at all count as violated
          lv_ok = abap_false.
      ENDTRY.

      IF lv_ok = abap_false.
        APPEND VALUE #( row = iv_row fieldname = <fs_cr>-field
                        value = CONV string( <lv_left> )
                        object = lv_expr
                        check_type = c_check-compare
                        message = build_msg( iv_nr = '016'
                                             iv_a  = CONV string( <lv_left> )
                                             iv_b  = lv_expr )
                        severity = normalize_severity( <fs_cr>-severity )
                        rule_id  = <fs_cr>-rule_id )
               TO rt_findings.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD unique_findings.

    DATA: lt_seen  TYPE ty_dup_seens,
          lv_row   TYPE i,
          lv_key   TYPE string,
          lv_disp  TYPE string,
          lv_txt   TYPE string,
          lv_object TYPE string,
          lv_all_init TYPE abap_bool,
          lv_skip     TYPE abap_bool.

    LOOP AT mt_unique_rules ASSIGNING FIELD-SYMBOL(<fs_ur>).

      DATA(lt_fields) = unique_fields( <fs_ur> ).
      CHECK lt_fields IS NOT INITIAL.

      CLEAR lt_seen.

      " fields come back sorted and deduplicated: a stable key and a
      " stable finding object, whatever order they were registered in
      CLEAR lv_object.
      LOOP AT lt_fields INTO DATA(lv_uf0).
        IF lv_object IS NOT INITIAL.
          lv_object = lv_object && '+'.
        ENDIF.
        lv_object = lv_object && lv_uf0.
      ENDLOOP.

      " finding anchor: the declared field if present, else the first
      " field of the sorted combination
      DATA(lv_anchor) = COND fieldname( WHEN <fs_ur>-field IS NOT INITIAL
                                        THEN <fs_ur>-field
                                        ELSE CONV fieldname( lt_fields[ 1 ] ) ).

      " manual counter: sy-tabix stays 0 when it_data is hashed, the
      " offset keeps global row numbers across slices
      lv_row = iv_offset.
      LOOP AT it_data ASSIGNING FIELD-SYMBOL(<ls_urow>).
        lv_row = lv_row + 1.

        CLEAR: lv_key, lv_disp.
        lv_all_init = abap_true.
        lv_skip     = abap_false.

        LOOP AT lt_fields INTO DATA(lv_uf).
          ASSIGN COMPONENT lv_uf OF STRUCTURE <ls_urow> TO FIELD-SYMBOL(<lv_uv>).
          IF sy-subrc <> 0.
            lv_skip = abap_true.
            EXIT.
          ENDIF.
          IF <lv_uv> IS NOT INITIAL.
            lv_all_init = abap_false.
          ENDIF.
          lv_txt = CONV string( <lv_uv> ).
          lv_key = lv_key && cl_abap_char_utilities=>horizontal_tab && lv_txt.
          IF lv_disp IS NOT INITIAL.
            lv_disp = lv_disp && '/'.
          ENDIF.
          lv_disp = lv_disp && lv_txt.
        ENDLOOP.

        CHECK lv_skip = abap_false.

        " rows whose rule fields are all initial are exempt, in line
        " with "initial values pass" everywhere else
        CHECK lv_all_init = abap_false.

        READ TABLE lt_seen INTO DATA(ls_seen) WITH TABLE KEY key = lv_key.
        IF sy-subrc = 0.
          APPEND VALUE #( row = lv_row
                          fieldname = lv_anchor
                          value = lv_disp object = lv_object
                          check_type = c_check-unique
                          message = build_msg( iv_nr = '017'
                                               iv_a  = lv_disp
                                               iv_b  = lv_object
                                               iv_c  = CONV string( ls_seen-first_row ) )
                          severity = normalize_severity( <fs_ur>-severity )
                          rule_id  = <fs_ur>-rule_id )
                 TO rt_findings.
        ELSE.
          INSERT VALUE #( key = lv_key first_row = lv_row ) INTO TABLE lt_seen.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD unique_fields.
    " SORT BY table_line on purpose: without BY, SORT (like DELETE
    " ADJACENT DUPLICATES without COMPARING) uses the table key - and
    " ty_values has an EMPTY key, which turns both statements into
    " no-ops. DELETE is not needed at all: the hashed fields list of
    " the rule cannot contain duplicates, and the anchor fallback
    " appends a single entry
    IF is_rule-fields IS NOT INITIAL.
      LOOP AT is_rule-fields INTO DATA(lv_field).
        APPEND to_upper( lv_field ) TO rt_fields.
      ENDLOOP.
    ELSEIF is_rule-field IS NOT INITIAL.
      APPEND to_upper( CONV string( is_rule-field ) ) TO rt_fields.
    ENDIF.
    SORT rt_fields BY table_line ASCENDING.
  ENDMETHOD.


  METHOD build_msg.
    " TYPE 'S' with INTO only builds the text, nothing is displayed or
    " logged; surplus WITH operands are allowed, missing ones would fail
    MESSAGE ID c_msgid TYPE 'S' NUMBER iv_nr
            WITH iv_a iv_b iv_c
            INTO rv_text.
  ENDMETHOD.

ENDCLASS.
