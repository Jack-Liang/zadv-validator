REPORT zadv_demo.

"* Demo for ZCL_ADV_VALIDATOR: validates a (simulated) upload table
"* against DDIC domain fixed values, check tables and format rules,
"* then shows every invalid input in an ALV.
"*
"* A second section demonstrates the v1.0 features (composite foreign
"* keys via DD05S, currency/unit code references) on real DDIC tables
"* (KNA1, MARA, VBAK). Those tables are resolved at RUNTIME so the
"* demo still activates on minimal systems - the sections are skipped
"* with a note when the object does not exist.
"*
"* v1.1 features ride along on the upload table: declarative cross
"* field comparison (BUDAT <= DATE_TO), file level duplicate check
"* (REF_ID), application log (BAL) and the string staging truncation
"* pre-check (against DD01L, which exists on every system).
"*
"* The demo deliberately avoids SELECTs on customizing tables so it
"* activates on every system (trial/developer editions often lack T001
"* etc.). Check-table findings appear only where the check table is
"* actually present; on systems without it the lenient mode lets the
"* value pass instead of raising an error.

TYPES: BEGIN OF ty_upload,
         status  TYPE as4local,  " domain AS4LOCAL: fixed values A/N/I
         budat   TYPE budat,     " DATS format check
         date_to TYPE budat,     " comparison rule operand
         bukrs   TYPE bukrs,     " check table T001
         land1   TYPE land1,     " check table T005
         waers   TYPE waers,     " check table TCURC
         email   TYPE string,    " non DDIC field -> regex rule
         remark  TYPE string,    " non DDIC field -> required rule
         ref_id  TYPE string,    " non DDIC field -> unique rule
       END OF ty_upload.

DATA gt_upload TYPE STANDARD TABLE OF ty_upload WITH EMPTY KEY.


"* row model of the runtime DDIC demos: a row is a list of
"* fieldname/value cells assigned to the dynamically created DDIC row
TYPES: BEGIN OF ty_cell,
         fieldname TYPE fieldname,
         value     TYPE string,
       END OF ty_cell,
       ty_cells TYPE STANDARD TABLE OF ty_cell WITH EMPTY KEY,
       BEGIN OF ty_demo_row,
         cells TYPE ty_cells,
       END OF ty_demo_row,
       ty_demo_rows TYPE STANDARD TABLE OF ty_demo_row WITH EMPTY KEY.


CLASS lcl_ddic_demo DEFINITION FINAL CREATE PRIVATE.
  PUBLIC SECTION.
    CLASS-METHODS run
      IMPORTING iv_tabname TYPE clike
                iv_title   TYPE clike
                it_rows    TYPE ty_demo_rows.
ENDCLASS.


CLASS lcl_ddic_demo IMPLEMENTATION.

  METHOD run.
    WRITE: / iv_title.
    ULINE.

    DATA: lr_tab  TYPE REF TO data,
          lr_line TYPE REF TO data.

    DATA(lv_tabname) = to_upper( CONV string( iv_tabname ) ).

    " runtime resolution on purpose: a static TYPE reference to KNA1/
    " MARA/VBAK would block the activation on minimal systems.
    " Existence pre-check on dd02l first: describe_by_name dumps
    " (uncatchably) for unknown names on some releases
    SELECT SINGLE @abap_true FROM dd02l
           WHERE tabname = @lv_tabname AND as4local = 'A'
           INTO @DATA(lv_tab_exists).

    IF lv_tab_exists <> abap_true.
      WRITE: / `  skipped:`, lv_tabname, `is not on this system`.
      SKIP.
      RETURN.
    ENDIF.

    " TYPE STANDARD TABLE OF (name) on purpose, same reason as the
    " build_ddic_table helper in the unit tests: a table rebuilt from
    " descriptors loses the DDIC row type and validate( ) would then
    " degrade to the lenient mixed structure fallback
    TRY.
        CREATE DATA lr_tab TYPE STANDARD TABLE OF (lv_tabname).
      CATCH cx_sy_create_data_error ##NO_TEXT.
        WRITE: / `  skipped:`, lv_tabname, `cannot be created`.
        SKIP.
        RETURN.
    ENDTRY.

    FIELD-SYMBOLS: <lt_rows> TYPE ANY TABLE,
                   <ls_row>  TYPE any,
                   <lv_val>  TYPE any.
    ASSIGN lr_tab->* TO <lt_rows>.

    DATA(lo_line) = CAST cl_abap_structdescr(
                      CAST cl_abap_tabledescr(
                        cl_abap_typedescr=>describe_by_data( <lt_rows> )
                      )->get_table_line_type( ) ).

    CREATE DATA lr_line TYPE HANDLE lo_line.
    ASSIGN lr_line->* TO <ls_row>.

    LOOP AT it_rows INTO DATA(ls_row).
      LOOP AT ls_row-cells INTO DATA(ls_cell).
        ASSIGN COMPONENT ls_cell-fieldname OF STRUCTURE <ls_row> TO <lv_val>.
        IF sy-subrc = 0.
          <lv_val> = ls_cell-value.
        ENDIF.
      ENDLOOP.
      INSERT <ls_row> INTO TABLE <lt_rows>.
    ENDLOOP.

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( <lt_rows> ).

    IF lt_findings IS INITIAL.
      WRITE: / `  all rows valid`.
    ELSE.
      LOOP AT lt_findings INTO DATA(ls_finding).
        WRITE: / `  row`, ls_finding-row, ls_finding-fieldname,
                 ls_finding-value, ls_finding-severity,
                 ls_finding-check_type, ls_finding-object.
      ENDLOOP.
    ENDIF.
    SKIP.
  ENDMETHOD.

ENDCLASS.


"* plugin demo: a custom single column check (ZIF_ADV_COLUMN_CHECK)
"* that flags e-mail addresses of the reserved example.com domain as
"* informational - any check class can be registered per column, the
"* row reference even allows simple cross field checks
CLASS lcl_check_example_domain DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES zif_adv_column_check.
ENDCLASS.

CLASS lcl_check_example_domain IMPLEMENTATION.
  METHOD zif_adv_column_check~check.
    rs_result-ok = abap_true.
    IF iv_value CS '@example.com'.
      rs_result-ok       = abap_false.
      rs_result-severity = 'I'.
      rs_result-message  = |demo plugin: { iv_value } uses a reserved domain|.
      rs_result-rule_id  = 'DEMO_RESERVED_DOMAIN'.
    ENDIF.
  ENDMETHOD.
ENDCLASS.


START-OF-SELECTION.

  " an invalid date cannot be written as a literal: the syntax check
  " rejects literals that do not match type D -> build it at runtime
  DATA(lv_invalid_date) = `20261301`.

  gt_upload = VALUE #(
    " row 1: values that are valid on most systems; REF_ID first use
    ( status = 'A' budat = sy-datum date_to = sy-datum bukrs = '1000'
      land1 = 'DE' waers = 'EUR' email = 'dev@example.com'
      remark = 'typical valid row' ref_id = 'R-001' )

    " row 2: wrong domain value, wrong date, unknown check-table values,
    "        failing regex, missing required remark, BUDAT > DATE_TO
    "        (comparison rule), REF_ID reuse of row 1 (unique rule)
    ( status = 'Z' budat = lv_invalid_date date_to = '20260101'
      bukrs = 'ZZZZ' land1 = 'ZZ' waers = 'ZZZ' email = 'not-an-email'
      remark = '' ref_id = 'R-001' )

    " row 3: everything fine except the domain value; DATE_TO initial
    "        -> comparison skipped (mark required to catch that)
    ( status = 'Z' budat = sy-datum bukrs = '1000' land1 = 'DE'
      waers = 'EUR' email = 'fine@example.com' remark = 'only flag wrong'
      ref_id = 'R-002' ) ).

  DATA(lo_validator) = NEW zcl_adv_validator( ).

  " explicit rules for fields that have no DDIC type
  lo_validator->add_rules( VALUE #(
    ( fieldname = 'EMAIL'  regex = `^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$` )
    ( fieldname = 'REMARK' required = abap_true ) ) ).

  " declarative cross field comparison: BUDAT must not be after
  " DATE_TO; initial operands are skipped, severity W
  lo_validator->add_compare_rule( VALUE #( field    = 'BUDAT'
                                           operator = 'LE'
                                           other    = 'DATE_TO'
                                           severity = 'W'
                                           rule_id  = 'R_PERIOD' ) ).

  " declarative file level duplicate check on REF_ID
  lo_validator->add_unique_rule( VALUE #( field   = 'REF_ID'
                                          rule_id = 'R_DUP_REF' ) ).

  " register a custom column check (plugin) for EMAIL, see the local
  " class lcl_check_example_domain above
  lo_validator->add_column_check(
      iv_fieldname = 'EMAIL'
      io_check     = NEW lcl_check_example_domain( ) ).

  " restrict validation to specific columns (optional, example):
  " backtick literals on purpose - 'C' literals do not fit the
  " elementary string row type of the constructor
  " lo_validator->only_fields( VALUE #( ( `BUKRS` ) ( `WAERS` ) ) ).
  " lo_validator->exclude_fields( VALUE #( ( `STATUS` ) ) ).

  " single value check without a table (static method):
  " zcl_adv_validator=>check_value_by_element(
  "     iv_value = '1000' iv_rollname = 'BUKRS' ).

  " example of an explicit check-table rule overriding DDIC:
  " ( fieldname = 'BUKRS' checktable = 'T001' checkfield = 'BUKRS' )

  DATA(lt_findings) = lo_validator->validate( gt_upload ).

  " ---------------------------------------------------------------------
  " v1.0 feature demos on real DDIC tables (runtime resolved, skipped
  " with a note where the objects do not exist); their findings go to
  " the classic list output below, the upload findings to the ALV
  " ---------------------------------------------------------------------
  lcl_ddic_demo=>run(
    iv_tabname = 'KNA1'
    iv_title   = 'composite foreign key via DD05S: KNA1 LAND1+REGIO -> T005A'
    it_rows    = VALUE ty_demo_rows(
      ( cells = VALUE #( ( fieldname = 'LAND1' value = 'DE' )
                         ( fieldname = 'REGIO' value = 'BY' ) ) )
      ( cells = VALUE #( ( fieldname = 'LAND1' value = 'DE' )
                         ( fieldname = 'REGIO' value = 'ZZ' ) ) ) ) ).

  lcl_ddic_demo=>run(
    iv_tabname = 'MARA'
    iv_title   = 'unit reference: MARA NTGEW (QUAN) -> GEWEI checked against T006'
    it_rows    = VALUE ty_demo_rows(
      ( cells = VALUE #( ( fieldname = 'NTGEW' value = '1' )
                         ( fieldname = 'GEWEI' value = 'KG' ) ) )
      ( cells = VALUE #( ( fieldname = 'NTGEW' value = '1' )
                         ( fieldname = 'GEWEI' value = 'ZZX' ) ) ) ) ).

  lcl_ddic_demo=>run(
    iv_tabname = 'VBAK'
    iv_title   = 'currency reference: VBAK NETWR (CURR) -> WAERS checked against TCURC'
    it_rows    = VALUE ty_demo_rows(
      ( cells = VALUE #( ( fieldname = 'NETWR' value = '1' )
                         ( fieldname = 'WAERS' value = 'EUR' ) ) )
      ( cells = VALUE #( ( fieldname = 'NETWR' value = '1' )
                         ( fieldname = 'WAERS' value = 'ZZZ9' ) ) ) ) ).

  " ---------------------------------------------------------------------
  " staging pre-check: string values vs. the field lengths of a target
  " DDIC structure (DD01L exists everywhere: DOMNAME CHAR30, AS4LOCAL
  " CHAR1). Values that a MOVE to the target would truncate silently
  " are reported as warnings before they reach the database
  " ---------------------------------------------------------------------
  TYPES: BEGIN OF ty_stage,
           domname  TYPE string,
           as4local TYPE string,
         END OF ty_stage,
         ty_stages TYPE STANDARD TABLE OF ty_stage WITH EMPTY KEY.

  DATA(lv_overlength) = `ABCDEFGHIJKLMNOPQRSTUVWXYZ01234`.

  WRITE: / `string staging truncation pre-check (target DD01L)`.
  ULINE.
  LOOP AT zcl_adv_validator=>precheck_truncation(
             it_data     = VALUE ty_stages(
                             ( domname = `AS4LOCAL` as4local = `A` )
                             ( domname = lv_overlength as4local = `AB` ) )
             iv_typename = 'DD01L' )
       INTO DATA(ls_trunc).
    WRITE: / `  row`, ls_trunc-row, ls_trunc-fieldname, ls_trunc-value,
             ls_trunc-severity, ls_trunc-check_type.
  ENDLOOP.
  SKIP.

  " ---------------------------------------------------------------------
  " application log (BAL): the upload findings as a persistent log,
  " one message per finding, message type from the severity. View it
  " with SLG1; the object must be registered in SLG0 first (or pass
  " an object of your own)
  " ---------------------------------------------------------------------
  DATA(lv_log_handle) = zcl_adv_validator=>log_findings(
      it_findings = lt_findings
      iv_object   = 'ZADV_DEMO'
      iv_commit   = abap_true ).

  IF lv_log_handle IS INITIAL.
    WRITE: / `application log: nothing written (empty findings or object`,
           `ZADV_DEMO not registered in SLG0)`.
  ELSE.
    WRITE: / `application log written, see SLG1 (object ZADV_DEMO)`.
  ENDIF.
  SKIP.

  " findings of the upload demo -> SALV via the built-in helper
  " (classic list fallback is part of the helper)
  zcl_adv_validator=>display_findings(
      it_findings = lt_findings
      iv_title    = |zadv-validator demo: { lines( lt_findings ) } findings| ).
