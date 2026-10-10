"*"* use this source file for your ABAP unit test classes
CLASS ltcl_validate DEFINITION FINAL
  FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_row,
             status    TYPE as4local,  " domain AS4LOCAL: fixed values A/N/I
             date      TYPE budat,     " DATS
             time      TYPE uzeit,     " TIMS
             mail      TYPE string,    " non DDIC -> only usable via rules
             date_from TYPE budat,     " comparison rule demo operand
             date_to   TYPE budat,     " comparison rule demo operand
           END OF ty_row,
           ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    "! component/value pairs for the runtime built DDIC test tables: the
    "! include must not reference application tables (KNA1, MARA, VBAK)
    "! statically, or it does not even compile on systems without them
    TYPES: BEGIN OF ty_cell,
             comp  TYPE fieldname,
             value TYPE string,
           END OF ty_cell,
           ty_cells TYPE STANDARD TABLE OF ty_cell WITH EMPTY KEY.

    METHODS:
      non_structured_table FOR TESTING,
      clean_row_no_findings FOR TESTING,
      invalid_date         FOR TESTING,
      invalid_time         FOR TESTING,
      invalid_domain_value FOR TESTING,
      regex_rule           FOR TESTING,
      regex_rule_ok        FOR TESTING,
      required_rule        FOR TESTING,
      rule_field_missing   FOR TESTING,
      only_fields_restricts FOR TESTING,
      exclude_fields_skips FOR TESTING,
      only_field_unknown   FOR TESTING,
      element_value_valid  FOR TESTING,
      element_value_invalid_domain FOR TESTING,
      element_value_invalid_date   FOR TESTING,
      field_value_invalid_domain   FOR TESTING,
      field_value_unknown  FOR TESTING,
      checktable_rule_routes FOR TESTING,
      lenient_missing_ctab  FOR TESTING,
      cache_idempotent      FOR TESTING,
      alpha_element_valid   FOR TESTING,
      fkey_composite_valid     FOR TESTING,
      fkey_composite_invalid   FOR TESTING,
      fkey_partner_initial     FOR TESTING,
      fkey_cache_idempotent    FOR TESTING,
      curr_quan_unit_t006      FOR TESTING,
      curr_quan_currency_tcurc FOR TESTING,
      metadata_exposed         FOR TESTING,
      severity_warning_rule    FOR TESTING,
      severity_default_error   FOR TESTING,
      severity_invalid_value   FOR TESTING,
      ddic_finding_severity_e  FOR TESTING,
      plugin_custom_check      FOR TESTING,
      plugin_unknown_field     FOR TESTING,
      plugin_cross_field       FOR TESTING,
      compare_rule_violated    FOR TESTING,
      compare_rule_ok_initial  FOR TESTING,
      compare_rule_unknown_field FOR TESTING,
      compare_rule_bad_operator FOR TESTING,
      unique_rule_flags_duplicates FOR TESTING,
      unique_rule_initial_exempt  FOR TESTING,
      unique_rule_unknown_field   FOR TESTING,
      truncation_overlength   FOR TESTING,
      truncation_ok           FOR TESTING,
      lowercase_domain_internal FOR TESTING,
      interval_domain_values  FOR TESTING,
      bal_msg_mapping         FOR TESTING,
      bal_log_empty_findings  FOR TESTING,
      db_rules_mapping        FOR TESTING,
      db_rules_lenient        FOR TESTING,
      row_offset              FOR TESTING,

      "! builds a standard table of the named DDIC structure at runtime;
      "! an unbound result means the type does not exist on this system
      "! and the calling test passes without assertions
      build_ddic_table
        IMPORTING iv_tabname      TYPE clike
        RETURNING VALUE(rr_table) TYPE REF TO data,

      "! appends one row with the given component values to a table
      "! built by build_ddic_table
      append_row
        IMPORTING ir_table TYPE REF TO data
                  it_cells TYPE ty_cells.
ENDCLASS.

"* white box access for the tests that exercise private helpers
"* (internal_value case folding, build_bal_msgs message mapping);
"* local friends is the standard pattern for the test class include
CLASS zcl_adv_validator DEFINITION LOCAL FRIENDS ltcl_validate.


"* two reference implementations of the column check plugin interface:
"* one rejects values without an @ (string column without DDIC), the
"* other reads the whole row via ir_row and demands a mail address
"* whenever STATUS = 'A' (simple cross field rule)
CLASS lcl_plugin_mail DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES zif_adv_column_check.
ENDCLASS.

CLASS lcl_plugin_mail IMPLEMENTATION.
  METHOD zif_adv_column_check~check.
    rs_result-ok       = abap_false.
    rs_result-severity = 'W'.
    rs_result-message  = |custom check: no @ in { iv_value }|.
    rs_result-rule_id  = 'PLUGIN_MAIL'.

    IF iv_value CS '@'.
      rs_result-ok = abap_true.
      CLEAR rs_result-message.
    ENDIF.
  ENDMETHOD.
ENDCLASS.


CLASS lcl_plugin_cross DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES zif_adv_column_check.
ENDCLASS.

CLASS lcl_plugin_cross IMPLEMENTATION.
  METHOD zif_adv_column_check~check.
    " registered on STATUS: 'A' demands a non-initial MAIL in the row
    rs_result-ok = abap_true.
    CHECK ir_row IS BOUND.
    ASSIGN ir_row->* TO FIELD-SYMBOL(<ls_row>).
    ASSIGN COMPONENT 'MAIL' OF STRUCTURE <ls_row> TO FIELD-SYMBOL(<lv_mail>).
    IF sy-subrc = 0 AND iv_value = 'A' AND <lv_mail> IS INITIAL.
      rs_result-ok       = abap_false.
      rs_result-severity = 'E'.
      rs_result-message  = 'status A requires a mail address'.
      rs_result-rule_id  = 'PLUGIN_CROSS'.
    ENDIF.
  ENDMETHOD.
ENDCLASS.


CLASS ltcl_validate IMPLEMENTATION.

  METHOD clean_row_no_findings.
    DATA(lt_rows) = VALUE ty_rows(
      ( status = 'A' date = '20261010' time = '235959' mail = 'a@b.de' ) ).

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( lt_rows ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0
        act = lines( lt_findings )
        msg = 'valid row produced findings' ).
  ENDMETHOD.


  METHOD invalid_date.
    " invalid D literals are rejected by the syntax check -> build at runtime
    DATA(lv_invalid) = `20261301`.

    DATA(lt_rows) = VALUE ty_rows( ( date = lv_invalid ) ).

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( lt_rows ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings ) msg = 'invalid date not detected' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-date )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
  ENDMETHOD.


  METHOD invalid_time.
    " invalid T literals are rejected by the syntax check -> build at runtime
    DATA(lv_invalid) = `246000`.

    DATA(lt_rows) = VALUE ty_rows( ( time = lv_invalid ) ).

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( lt_rows ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings ) msg = 'invalid time not detected' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-time )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
  ENDMETHOD.


  METHOD invalid_domain_value.
    " 'Z' is outside the fixed values of domain AS4LOCAL (A/N/I)
    DATA(lt_rows) = VALUE ty_rows( ( status = 'Z' ) ).

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( lt_rows ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings ) msg = 'invalid domain value not detected' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-domain )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'Z' act = CONV string( lt_findings[ 1 ]-value )
        msg = 'finding must carry the original external value' ).
  ENDMETHOD.


  METHOD regex_rule.
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_rule( VALUE #( fieldname = 'MAIL'
                                     regex     = `^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$` ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( mail = 'not-an-email' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings ) msg = 'regex mismatch not detected' ).
  ENDMETHOD.


  METHOD regex_rule_ok.
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_rule( VALUE #( fieldname = 'MAIL'
                                     regex     = `^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$` ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( mail = 'dev@example.com' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0 act = lines( lt_findings ) msg = 'matching value reported' ).
  ENDMETHOD.


  METHOD required_rule.
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_rule( VALUE #( fieldname = 'MAIL' required = abap_true ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( mail = '' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings ) msg = 'missing required value not detected' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-required )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
  ENDMETHOD.


  METHOD rule_field_missing.
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_rule( VALUE #( fieldname = 'DOES_NOT_EXIST' required = abap_true ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings ) msg = 'unknown rule field not reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-structure )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
  ENDMETHOD.


  METHOD non_structured_table.
    DATA lt_strings TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( lt_strings ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings ) msg = 'unstructured table not rejected' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-structure )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
  ENDMETHOD.


  METHOD only_fields_restricts.
    DATA(lv_invalid) = `20261301`.

    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->only_fields( VALUE #( ( `DATE` ) ) ).

    DATA(lt_findings) = lo_validator->validate(
        VALUE ty_rows( ( status = 'Z' date = lv_invalid mail = 'x' ) ) ).

    " status 'Z' is invalid as well but the column filter must skip it
    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings ) msg = 'only_fields not applied' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-date )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
  ENDMETHOD.


  METHOD exclude_fields_skips.
    DATA(lv_invalid) = `20261301`.

    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->exclude_fields( VALUE #( ( `DATE` ) ) ).

    DATA(lt_findings) = lo_validator->validate(
        VALUE ty_rows( ( status = 'Z' date = lv_invalid mail = 'x' ) ) ).

    " the invalid date must be skipped, only the domain finding remains
    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings ) msg = 'exclude_fields not applied' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-domain )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
  ENDMETHOD.


  METHOD only_field_unknown.
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->only_fields( VALUE #( ( `DOES_NOT_EXIST` ) ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings ) msg = 'unknown only field not reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-structure )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
  ENDMETHOD.


  METHOD element_value_valid.
    DATA ls_finding TYPE zcl_adv_validator=>ty_finding.

    DATA(lv_ok) = zcl_adv_validator=>check_value_by_element(
                      EXPORTING iv_value    = 'A'
                                iv_rollname = 'AS4LOCAL'
                      IMPORTING es_finding  = ls_finding ).

    cl_abap_unit_assert=>assert_equals(
        exp = abap_true act = lv_ok msg = 'A should be valid for AS4LOCAL' ).
    cl_abap_unit_assert=>assert_initial(
        act = ls_finding msg = 'no finding expected for valid value' ).
  ENDMETHOD.


  METHOD element_value_invalid_domain.
    DATA ls_finding TYPE zcl_adv_validator=>ty_finding.

    DATA(lv_ok) = zcl_adv_validator=>check_value_by_element(
                      EXPORTING iv_value    = 'Z'
                                iv_rollname = 'AS4LOCAL'
                      IMPORTING es_finding  = ls_finding ).

    cl_abap_unit_assert=>assert_equals(
        exp = abap_false act = lv_ok msg = 'Z should be invalid for AS4LOCAL' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-domain )
        act = CONV string( ls_finding-check_type ) ).
  ENDMETHOD.


  METHOD element_value_invalid_date.
    DATA lv_invalid TYPE string.
    lv_invalid = `20261301`.

    DATA ls_finding TYPE zcl_adv_validator=>ty_finding.

    DATA(lv_ok) = zcl_adv_validator=>check_value_by_element(
                      EXPORTING iv_value    = lv_invalid
                                iv_rollname = 'BUDAT'
                      IMPORTING es_finding  = ls_finding ).

    cl_abap_unit_assert=>assert_equals(
        exp = abap_false act = lv_ok msg = '20261301 should be invalid for BUDAT' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-date )
        act = CONV string( ls_finding-check_type ) ).
  ENDMETHOD.


  METHOD field_value_invalid_domain.
    DATA ls_finding TYPE zcl_adv_validator=>ty_finding.

    DATA(lv_ok) = zcl_adv_validator=>check_value_by_field(
                      EXPORTING iv_value     = 'Z'
                                iv_tabname   = 'DD07L'
                                iv_fieldname = 'AS4LOCAL'
                      IMPORTING es_finding   = ls_finding ).

    cl_abap_unit_assert=>assert_equals(
        exp = abap_false act = lv_ok msg = 'Z should be invalid for DD07L-AS4LOCAL' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-domain )
        act = CONV string( ls_finding-check_type ) ).
  ENDMETHOD.


  METHOD field_value_unknown.
    DATA ls_finding TYPE zcl_adv_validator=>ty_finding.

    DATA(lv_ok) = zcl_adv_validator=>check_value_by_field(
                      EXPORTING iv_value     = 'X'
                                iv_tabname   = 'DD01L'
                                iv_fieldname = 'DOES_NOT_EXIST'
                      IMPORTING es_finding   = ls_finding ).

    cl_abap_unit_assert=>assert_equals(
        exp = abap_false act = lv_ok msg = 'unknown field must fail' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-structure )
        act = CONV string( ls_finding-check_type ) ).
  ENDMETHOD.


  METHOD checktable_rule_routes.
    " rule routes the lookup to DD07L/DOMNAME instead of the DDIC default:
    " 'AS4LOCAL' is a domain name present in DD07L (it has fixed values),
    " 'ZZ_...' is not. Both rows are covered by one batched IN( ) select
    " and the lowercase input proves the case folding of the search key
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_rule( VALUE #( fieldname  = 'MAIL'
                                     checktable = 'DD07L'
                                     checkfield = 'DOMNAME' ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows(
      ( mail = 'as4local' )
      ( mail = 'zz_not_a_domain_9' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings )
        msg = 'only the unknown domain name must be reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-checktable )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = |DD07L/DOMNAME|
        act = CONV string( lt_findings[ 1 ]-object )
        msg = 'rule checkfield must be used for the lookup' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lt_findings[ 1 ]-row ).
  ENDMETHOD.


  METHOD lenient_missing_ctab.
    " an unreadable check table must never block the data flow: neither
    " the batched select nor the per-value fallback may raise
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_rule( VALUE #( fieldname  = 'MAIL'
                                     checktable = 'ZADV_NO_SUCH_TABLE' ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( mail = 'X' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0 act = lines( lt_findings )
        msg = 'missing check table must pass leniently' ).
  ENDMETHOD.


  METHOD cache_idempotent.
    " repeated validate( ) on the same instance (cache hits) and after
    " clear_caches( ) (fresh lookups) must return identical findings
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_rule( VALUE #( fieldname  = 'MAIL'
                                     checktable = 'DD07L'
                                     checkfield = 'DOMNAME' ) ).

    DATA(lt_rows) = VALUE ty_rows( ( status = 'Z' mail = 'zz_not_a_domain_9' )
                                   ( status = 'Z' mail = 'zz_not_a_domain_9' ) ).

    DATA(lt_first)  = lo_validator->validate( lt_rows ).
    DATA(lt_second) = lo_validator->validate( lt_rows ).

    cl_abap_unit_assert=>assert_equals(
        exp = 4 act = lines( lt_first )
        msg = 'expected one domain and one checktable finding per row' ).
    cl_abap_unit_assert=>assert_equals(
        exp = lines( lt_first ) act = lines( lt_second )
        msg = 'second validate must return identical findings' ).

    lo_validator->clear_caches( ).

    cl_abap_unit_assert=>assert_equals(
        exp = lines( lt_first ) act = lines( lo_validator->validate( lt_rows ) )
        msg = 'validate after clear_caches must return identical findings' ).
  ENDMETHOD.


  METHOD alpha_element_valid.
    " VBELN carries conversion exit ALPHA: the external form passes with
    " the exit executed (padded to the internal form), no fixed values
    " or check table apply. VBELN is SD metadata: skip on systems
    " without it, existence via dd04l because describe_by_name dumps
    " (uncatchably) for unknown names on some releases
    SELECT SINGLE @abap_true FROM dd04l
           WHERE rollname = 'VBELN' AND as4local = 'A'
           INTO @DATA(lv_vbeln).
    IF lv_vbeln <> abap_true.
      RETURN.
    ENDIF.

    cl_abap_unit_assert=>assert_equals(
        exp = abap_true
        act = zcl_adv_validator=>check_value_by_element(
                  iv_value = '123' iv_rollname = 'VBELN' )
        msg = 'external VBELN form should pass ALPHA' ).
  ENDMETHOD.


  METHOD fkey_composite_valid.
    " KNA1-REGIO has the composite foreign key LAND1+REGIO -> T005A
    " (LAND1+BLAND): the shipped combination DE/BY (Bavaria) must pass
    " the combination check without any finding. The table is built at
    " runtime: systems without KNA1 skip this test instead of failing
    " to compile
    DATA(lr_rows) = build_ddic_table( 'KNA1' ).
    IF lr_rows IS NOT BOUND.
      RETURN.
    ENDIF.
    FIELD-SYMBOLS <lt_rows> TYPE ANY TABLE.
    ASSIGN lr_rows->* TO <lt_rows>.

    append_row( ir_table = lr_rows
                it_cells = VALUE #( ( comp = 'LAND1' value = 'DE' )
                                    ( comp = 'REGIO'  value = 'BY' ) ) ).

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( <lt_rows> ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0 act = lines( lt_findings )
        msg = 'valid region combination reported' ).
  ENDMETHOD.


  METHOD fkey_composite_invalid.
    " DE/ZZ does not exist in T005A: the combination must be rejected,
    " and the DD05S mapping must show up as BLAND (not the same-name
    " REGIO) together with the partner field LAND1
    DATA(lr_rows) = build_ddic_table( 'KNA1' ).
    IF lr_rows IS NOT BOUND.
      RETURN.
    ENDIF.
    FIELD-SYMBOLS <lt_rows> TYPE ANY TABLE.
    ASSIGN lr_rows->* TO <lt_rows>.

    append_row( ir_table = lr_rows
                it_cells = VALUE #( ( comp = 'LAND1' value = 'DE' )
                                    ( comp = 'REGIO'  value = 'ZZ' ) ) ).

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( <lt_rows> ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings )
        msg = 'unknown region combination not detected' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-checktable )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'REGIO' act = CONV string( lt_findings[ 1 ]-fieldname ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = |T005A/BLAND+LAND1| act = CONV string( lt_findings[ 1 ]-object )
        msg = 'DD05S must map REGIO to the check table field BLAND' ).
  ENDMETHOD.


  METHOD fkey_partner_initial.
    " with an initial partner (LAND1 empty) the composite key cannot be
    " evaluated: the lenient single field fallback applies, 'BY' exists
    " as a region in T005A somewhere -> no finding
    DATA(lr_rows) = build_ddic_table( 'KNA1' ).
    IF lr_rows IS NOT BOUND.
      RETURN.
    ENDIF.
    FIELD-SYMBOLS <lt_rows> TYPE ANY TABLE.
    ASSIGN lr_rows->* TO <lt_rows>.

    append_row( ir_table = lr_rows
                it_cells = VALUE #( ( comp = 'REGIO' value = 'BY' ) ) ).

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( <lt_rows> ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0 act = lines( lt_findings )
        msg = 'initial partner must degrade to the lenient single check' ).
  ENDMETHOD.


  METHOD fkey_cache_idempotent.
    " repeated validate( ) (tuple cache hits) and a run after
    " clear_caches( ) (fresh lookups) must return identical findings
    DATA(lr_rows) = build_ddic_table( 'KNA1' ).
    IF lr_rows IS NOT BOUND.
      RETURN.
    ENDIF.
    FIELD-SYMBOLS <lt_rows> TYPE ANY TABLE.
    ASSIGN lr_rows->* TO <lt_rows>.

    append_row( ir_table = lr_rows
                it_cells = VALUE #( ( comp = 'LAND1' value = 'DE' )
                                    ( comp = 'REGIO'  value = 'ZZ' ) ) ).
    append_row( ir_table = lr_rows
                it_cells = VALUE #( ( comp = 'LAND1' value = 'DE' )
                                    ( comp = 'REGIO'  value = 'ZZ' ) ) ).

    DATA(lo_validator) = NEW zcl_adv_validator( ).

    DATA(lt_first)  = lo_validator->validate( <lt_rows> ).
    DATA(lt_second) = lo_validator->validate( <lt_rows> ).

    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lines( lt_first )
        msg = 'both rows must be reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = lines( lt_first ) act = lines( lt_second )
        msg = 'second validate must return identical findings' ).

    lo_validator->clear_caches( ).

    cl_abap_unit_assert=>assert_equals(
        exp = lines( lt_first ) act = lines( lo_validator->validate( <lt_rows> ) )
        msg = 'validate after clear_caches must return identical findings' ).
  ENDMETHOD.


  METHOD curr_quan_unit_t006.
    " MARA-NTGEW (QUAN) references the unit column MARA-GEWEI: the unit
    " code is validated against T006/MSEHI (with the CUNIT conversion
    " exit of GEWEI applied). An existing own foreign key on GEWEI
    " produces the very same lookup, both paths are fine here.
    DATA(lr_rows) = build_ddic_table( 'MARA' ).
    IF lr_rows IS NOT BOUND.
      RETURN.
    ENDIF.
    FIELD-SYMBOLS <lt_rows> TYPE ANY TABLE.
    ASSIGN lr_rows->* TO <lt_rows>.

    append_row( ir_table = lr_rows
                it_cells = VALUE #( ( comp = 'NTGEW' value = '1' )
                                    ( comp = 'GEWEI' value = 'KG' ) ) ).
    append_row( ir_table = lr_rows
                it_cells = VALUE #( ( comp = 'NTGEW' value = '1' )
                                    ( comp = 'GEWEI' value = 'ZZX' ) ) ).

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( <lt_rows> ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings )
        msg = 'unknown unit must be reported, valid unit must pass' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-checktable )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = |T006/MSEHI| act = CONV string( lt_findings[ 1 ]-object )
        msg = 'unit code column must be checked against T006/MSEHI' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lt_findings[ 1 ]-row ).
  ENDMETHOD.


  METHOD curr_quan_currency_tcurc.
    " VBAK-NETWR (CURR) references the currency column VBAK-WAERS: the
    " currency code is validated against TCURC/WAERS. 'EUR' exists on
    " every system, 'ZZZ9' does not exist anywhere
    DATA(lr_rows) = build_ddic_table( 'VBAK' ).
    IF lr_rows IS NOT BOUND.
      RETURN.
    ENDIF.
    FIELD-SYMBOLS <lt_rows> TYPE ANY TABLE.
    ASSIGN lr_rows->* TO <lt_rows>.

    append_row( ir_table = lr_rows
                it_cells = VALUE #( ( comp = 'NETWR' value = '1' )
                                    ( comp = 'WAERS' value = 'EUR' ) ) ).
    append_row( ir_table = lr_rows
                it_cells = VALUE #( ( comp = 'NETWR' value = '1' )
                                    ( comp = 'WAERS' value = 'ZZZ9' ) ) ).

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( <lt_rows> ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings )
        msg = 'unknown currency must be reported, EUR must pass' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-checktable )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = |TCURC/WAERS| act = CONV string( lt_findings[ 1 ]-object )
        msg = 'currency code column must be checked against TCURC/WAERS' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lt_findings[ 1 ]-row ).
  ENDMETHOD.


  METHOD metadata_exposed.
    " the constants must stay consumable both via the interface and via
    " the class aliases, and the version must be plain semver so that
    " consumers can display or compare it
    cl_abap_unit_assert=>assert_text_matches(
        pattern = '^[0-9]+\.[0-9]+\.[0-9]+$'
        text    = zif_adv_metadata=>c_version
        msg     = 'c_version is not MAJOR.MINOR.PATCH' ).

    cl_abap_unit_assert=>assert_not_initial(
        act = zif_adv_metadata=>c_author      msg = 'c_author is initial' ).
    cl_abap_unit_assert=>assert_text_matches(
        pattern = '^https://github[.]com/[^/]+/[^/]+'
        text    = zif_adv_metadata=>c_repository
        msg     = 'c_repository is not a github url' ).
    cl_abap_unit_assert=>assert_not_initial(
        act = zif_adv_metadata=>c_license      msg = 'c_license is initial' ).
    cl_abap_unit_assert=>assert_not_initial(
        act = zif_adv_metadata=>c_description  msg = 'c_description is initial' ).

    cl_abap_unit_assert=>assert_equals(
        exp = zif_adv_metadata=>c_version
        act = zcl_adv_validator=>c_version
        msg = 'class alias diverges from interface constant' ).
    cl_abap_unit_assert=>assert_equals(
        exp = zif_adv_metadata=>c_repository
        act = zcl_adv_validator=>c_repository
        msg = 'class alias diverges from interface constant' ).
  ENDMETHOD.


  METHOD severity_warning_rule.
    " a rule with severity W marks only its own findings: the regex
    " finding carries W and the rule id, the DDIC domain finding of the
    " same row stays E without rule id
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_rule( VALUE #( fieldname = 'MAIL'
                                     regex     = `^a+b*$`
                                     severity  = zcl_adv_validator=>c_severity-warning
                                     rule_id   = 'R_MAIL_FMT' ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( status = 'Z'
                                                                 mail  = 'x' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lines( lt_findings )
        msg = 'domain and regex findings expected' ).

    READ TABLE lt_findings INTO DATA(ls_domain)
         WITH KEY check_type = zcl_adv_validator=>c_check-domain.
    cl_abap_unit_assert=>assert_subrc( ).

    READ TABLE lt_findings INTO DATA(ls_regex)
         WITH KEY check_type = zcl_adv_validator=>c_check-regex.
    cl_abap_unit_assert=>assert_subrc( ).

    cl_abap_unit_assert=>assert_equals(
        exp = 'W' act = CONV string( ls_regex-severity )
        msg = 'rule severity W must reach the rule finding' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'R_MAIL_FMT' act = CONV string( ls_regex-rule_id )
        msg = 'rule id must be echoed into the finding' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'E' act = CONV string( ls_domain-severity )
        msg = 'DDIC findings stay error severity' ).
    cl_abap_unit_assert=>assert_initial(
        act = ls_domain-rule_id
        msg = 'DDIC findings carry no rule id' ).
  ENDMETHOD.


  METHOD severity_default_error.
    " no severity in the rule -> normalized to E
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_rule( VALUE #( fieldname = 'MAIL' required = abap_true ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( mail = '' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 'E' act = CONV string( lt_findings[ 1 ]-severity )
        msg = 'initial rule severity must default to E' ).
  ENDMETHOD.


  METHOD severity_invalid_value.
    " anything but W/I is normalized to E - never propagate garbage
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_rule( VALUE #( fieldname = 'MAIL'
                                     regex    = `^a+$`
                                     severity = 'X' ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( mail = 'b' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 'E' act = CONV string( lt_findings[ 1 ]-severity )
        msg = 'invalid severity must fall back to E' ).
  ENDMETHOD.


  METHOD ddic_finding_severity_e.
    " pure DDIC findings always carry a non-initial severity E
    DATA(lt_findings) = NEW zcl_adv_validator( )->validate(
                            VALUE ty_rows( ( status = 'Z' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 'E' act = CONV string( lt_findings[ 1 ]-severity )
        msg = 'DDIC finding severity must be E' ).
    cl_abap_unit_assert=>assert_initial(
        act = lt_findings[ 1 ]-rule_id
        msg = 'DDIC finding must not carry a rule id' ).
  ENDMETHOD.


  METHOD plugin_custom_check.
    " a plugin on a plain string column (no DDIC metadata): the check
    " class decides ok/text/severity/rule_id, the validator normalizes
    " the severity before it reaches the finding
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_column_check(
        iv_fieldname = 'MAIL'
        io_check     = NEW lcl_plugin_mail( ) ).

    DATA(lt_findings) = lo_validator->validate(
        VALUE ty_rows( ( mail = 'abc@de' )
                       ( mail = 'no-at-sign' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings )
        msg = 'only the failing plugin value must be reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-plugin )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'W' act = CONV string( lt_findings[ 1 ]-severity )
        msg = 'plugin severity W must reach the finding' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'PLUGIN_MAIL' act = CONV string( lt_findings[ 1 ]-rule_id )
        msg = 'plugin rule id must be echoed' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lt_findings[ 1 ]-row ).
  ENDMETHOD.


  METHOD plugin_unknown_field.
    " registrations for fields that do not exist are structural
    " findings, same 003 path as rules
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_column_check(
        iv_fieldname = 'DOES_NOT_EXIST'
        io_check     = NEW lcl_plugin_mail( ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings )
        msg = 'unknown plugin field not reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-structure )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
  ENDMETHOD.


  METHOD plugin_cross_field.
    " ir_row gives the plugin the whole row: STATUS = 'A' demands a
    " mail address, a simple cross field rule without any framework
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_column_check(
        iv_fieldname = 'STATUS'
        io_check     = NEW lcl_plugin_cross( ) ).

    DATA(lt_findings) = lo_validator->validate(
        VALUE ty_rows( ( status = 'A' mail = '' )
                       ( status = 'A' mail = 'x@y' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings )
        msg = 'status A without mail must be reported, with mail passes' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'PLUGIN_CROSS' act = CONV string( lt_findings[ 1 ]-rule_id )
        msg = 'cross field plugin finding expected' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lt_findings[ 1 ]-row ).
  ENDMETHOD.


  METHOD compare_rule_violated.
    " DATE_FROM <= DATE_TO as a declarative cross field rule: only the
    " violated row is reported, on the left operand field, with the
    " rule severity and rule id echoed
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_compare_rule( VALUE #( field    = 'DATE_FROM'
                                             operator = 'LE'
                                             other    = 'DATE_TO'
                                             severity = 'W'
                                             rule_id  = 'R_PERIOD' ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows(
      ( date_from = '20261010' date_to = '20261001' )
      ( date_from = '20261010' date_to = '20261011' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings )
        msg = 'only the violated comparison must be reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-compare )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'DATE_FROM' act = CONV string( lt_findings[ 1 ]-fieldname ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = |DATE_FROM <= DATE_TO|
        act = CONV string( lt_findings[ 1 ]-object ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'W' act = CONV string( lt_findings[ 1 ]-severity )
        msg = 'rule severity W must reach the finding' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'R_PERIOD' act = CONV string( lt_findings[ 1 ]-rule_id ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lt_findings[ 1 ]-row ).
  ENDMETHOD.


  METHOD compare_rule_ok_initial.
    " initial operands are exempt (mark them required instead) and a
    " satisfied comparison passes - no finding either way
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_compare_rule( VALUE #( field    = 'DATE_FROM'
                                             operator = 'LE'
                                             other    = 'DATE_TO' ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows(
      ( date_from = '20261010' )
      ( date_from = '20261001' date_to = '20261010' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0 act = lines( lt_findings )
        msg = 'initial operand and satisfied comparison must both pass' ).
  ENDMETHOD.


  METHOD compare_rule_unknown_field.
    " operands that do not exist are structural findings, same 003
    " path as column rules
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_compare_rule( VALUE #( field    = 'DATE_FROM'
                                             operator = 'LE'
                                             other    = 'DOES_NOT_EXIST' ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings )
        msg = 'unknown comparison operand not reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-structure )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'DOES_NOT_EXIST' act = CONV string( lt_findings[ 1 ]-fieldname ) ).
  ENDMETHOD.


  METHOD compare_rule_bad_operator.
    " an operator outside EQ NE LT LE GT GE is a structural finding
    " (message 020), not a silent skip
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_compare_rule( VALUE #( field    = 'DATE_FROM'
                                             operator = 'XX'
                                             other    = 'DATE_TO' ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings )
        msg = 'invalid operator not reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-structure )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'DATE_FROM' act = CONV string( lt_findings[ 1 ]-fieldname ) ).
  ENDMETHOD.


  METHOD unique_rule_flags_duplicates.
    " STATUS+MAIL must stay unique across the table: first occurrence
    " passes, the repeat is reported on the anchor field; the
    " combination is reported in sorted field order
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_unique_rule( VALUE #(
        field   = 'STATUS'
        fields  = VALUE #( ( `STATUS` ) ( `MAIL` ) )
        rule_id = 'R_DUP_KEY' ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows(
      ( status = 'A' mail = 'x@y' )
      ( status = 'A' mail = 'x@y' )
      ( status = 'N' mail = 'x@y' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings )
        msg = 'only the repeated combination must be reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-unique )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'STATUS' act = CONV string( lt_findings[ 1 ]-fieldname )
        msg = 'finding anchors on the declared field' ).
    cl_abap_unit_assert=>assert_equals(
        exp = |MAIL+STATUS| act = CONV string( lt_findings[ 1 ]-object )
        msg = 'combination is reported in sorted field order' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'x@y/A' act = CONV string( lt_findings[ 1 ]-value )
        msg = 'value shows the combination, sorted field order' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lt_findings[ 1 ]-row ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'R_DUP_KEY' act = CONV string( lt_findings[ 1 ]-rule_id ) ).
  ENDMETHOD.


  METHOD unique_rule_initial_exempt.
    " rows in which all fields of the rule are initial are exempt, in
    " line with "initial values pass" everywhere else; single anchor
    " field without an explicit fields list works as well
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_unique_rule( VALUE #( field = 'STATUS' ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows(
      ( mail = 'a' )
      ( mail = 'b' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0 act = lines( lt_findings )
        msg = 'all-initial key rows must be exempt from duplicate checks' ).
  ENDMETHOD.


  METHOD unique_rule_unknown_field.
    " field names that do not exist are structural findings, same 003
    " path as everywhere else
    DATA(lo_validator) = NEW zcl_adv_validator( ).
    lo_validator->add_unique_rule( VALUE #( field = 'DOES_NOT_EXIST' ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings )
        msg = 'unknown uniqueness field not reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-structure )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
  ENDMETHOD.


  METHOD truncation_overlength.
    " string staging rows against DD01L (DOMNAME CHAR30, AS4LOCAL
    " CHAR1): overlength values are reported as W before they are
    " silently truncated by the assignment; raw staging columns have
    " no text length and are skipped
    TYPES: BEGIN OF ty_stage,
             domname  TYPE string,
             as4local TYPE string,
             raw_blob TYPE xstring,
           END OF ty_stage,
           ty_stages TYPE STANDARD TABLE OF ty_stage WITH EMPTY KEY.

    DATA(lv31) = `ABCDEFGHIJKLMNOPQRSTUVWXYZ01234`.

    DATA(lt_findings) = zcl_adv_validator=>precheck_truncation(
        it_data     = VALUE ty_stages(
                        ( domname = `AS4LOCAL` as4local = `A`
                          raw_blob = 'FF' )
                        ( domname = lv31 as4local = `AB` ) )
        iv_typename = 'DD01L' ).

    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lines( lt_findings )
        msg = 'DOMNAME (31>30) and AS4LOCAL (2>1) of row 2 must be found' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lt_findings[ 1 ]-row ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-truncation )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'W' act = CONV string( lt_findings[ 1 ]-severity )
        msg = 'truncation pre-check defaults to warning severity' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'DOMNAME' act = CONV string( lt_findings[ 1 ]-fieldname ) ).
  ENDMETHOD.


  METHOD truncation_ok.
    " values that fit and staging columns the target does not have are
    " never reported
    TYPES: BEGIN OF ty_stage,
             domname  TYPE string,
             as4local TYPE string,
             extra    TYPE string,
           END OF ty_stage,
           ty_stages TYPE STANDARD TABLE OF ty_stage WITH EMPTY KEY.

    DATA(lv30) = `ABCDEFGHIJKLMNOPQRSTUVWXYZ0123`.

    DATA(lt_findings) = zcl_adv_validator=>precheck_truncation(
        it_data     = VALUE ty_stages(
                        ( domname = lv30 as4local = `A` extra = lv30 ) )
        iv_typename = 'DD01L' ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0 act = lines( lt_findings )
        msg = 'fitting values and extra staging columns must pass' ).
  ENDMETHOD.


  METHOD lowercase_domain_internal.
    " white box test of the case folding rule: with a lowercase domain
    " the comparison value stays as entered, with a regular domain it
    " is folded to upper case (this is what check table lookups and
    " domain fixed values compare with). No hardcoded domain: any
    " active lowercase domain of this system is discovered at runtime,
    " systems without one skip the test
    SELECT SINGLE domname FROM dd01l
           WHERE as4local = 'A' AND lowercase = 'X'
           INTO @DATA(lv_lower_dom).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(lo_validator) = NEW zcl_adv_validator( ).

    DATA ls_field TYPE zcl_adv_validator=>ty_field.
    ls_field-domname = lv_lower_dom.

    cl_abap_unit_assert=>assert_equals(
        exp = `MixedCase`
        act = lo_validator->internal_value( is_field = ls_field
                                            iv_disp  = `MixedCase` )
        msg = |domain { lv_lower_dom } is lowercase and must keep the case| ).

    CLEAR ls_field.
    ls_field-domname = 'AS4LOCAL'.

    cl_abap_unit_assert=>assert_equals(
        exp = `MIXEDCASE`
        act = lo_validator->internal_value( is_field = ls_field
                                            iv_disp  = `MixedCase` )
        msg = 'regular domains fold the value to upper case' ).
  ENDMETHOD.


  METHOD interval_domain_values.
    " fixed value intervals (DOMVALUE_H filled): a value equal to the
    " upper bound is only accepted when the interval logic works -
    " single value logic would reject it, because it is not the start
    " of its own row. The sample domain is discovered at runtime from
    " dd07l, systems without any interval domain skip the test.
    " dd07l~domvalue_h qualified on purpose: on 7.40 SP08 a bare name
    " on the RIGHT side of a WHERE comparison parses as a host variable
    " ("has to be escaped using @ or qualified by a table name"), only
    " the qualified form reads as a column
    TYPES: BEGIN OF ty_domrow,
             domname    TYPE dd07l-domname,
             domvalue_l TYPE dd07l-domvalue_l,
             domvalue_h TYPE dd07l-domvalue_h,
           END OF ty_domrow.
    DATA ls_interval TYPE ty_domrow.

    SELECT SINGLE domname, domvalue_l, domvalue_h
      FROM dd07l
      WHERE as4local = 'A'
        AND domvalue_h <> ' '
        AND domvalue_l <> dd07l~domvalue_h
      INTO CORRESPONDING FIELDS OF @ls_interval.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " white box on purpose: check_domain( ) is exactly the interval
    " logic, without the data element side effects (conversion exits,
    " element check tables) a randomly discovered element might carry
    DATA(lo_validator) = NEW zcl_adv_validator( ).

    cl_abap_unit_assert=>assert_equals(
        exp = abap_true
        act = lo_validator->check_domain(
                  iv_domname = ls_interval-domname
                  iv_value    = CONV #( ls_interval-domvalue_l ) )
        msg = |{ ls_interval-domvalue_l } must be valid for { ls_interval-domname }| ).

    cl_abap_unit_assert=>assert_equals(
        exp = abap_true
        act = lo_validator->check_domain(
                  iv_domname = ls_interval-domname
                  iv_value    = CONV #( ls_interval-domvalue_h ) )
        msg = |{ ls_interval-domvalue_h } is the interval end and must be valid| ).
  ENDMETHOD.


  METHOD bal_msg_mapping.
    " white box test of the BAL message mapping: message type from the
    " severity, generic message 018, text chunked over the four 50
    " character message variables (SE91 placeholders hold 50 chars)
    DATA(lv_long) = repeat( val = 'x' occ = 160 ).

    DATA(lt_findings) = VALUE zcl_adv_validator=>ty_findings(
      ( severity = 'E' message = 'short text' )
      ( severity = 'W' message = lv_long ) ).

    DATA(lt_msgs) = zcl_adv_validator=>build_bal_msgs( lt_findings ).

    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lines( lt_msgs )
        msg = 'one BAL message per finding' ).

    READ TABLE lt_msgs INTO DATA(ls_msg1) INDEX 1.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'E' act = CONV string( ls_msg1-msgty ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = '018' act = CONV string( ls_msg1-msgno ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'short text' act = CONV string( ls_msg1-msgv1 ) ).

    READ TABLE lt_msgs INTO DATA(ls_msg2) INDEX 2.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'W' act = CONV string( ls_msg2-msgty ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 50 act = strlen( CONV string( ls_msg2-msgv1 ) ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 50 act = strlen( CONV string( ls_msg2-msgv2 ) ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 50 act = strlen( CONV string( ls_msg2-msgv3 ) ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 10 act = strlen( CONV string( ls_msg2-msgv4 ) )
        msg = '160 characters split into 50/50/50/10' ).
  ENDMETHOD.


  METHOD bal_log_empty_findings.
    " no findings -> no log at all, and no database activity the unit
    " test would have to clean up (the writing path itself needs a
    " registered BAL object and is demoed in ZADV_DEMO instead)
    cl_abap_unit_assert=>assert_initial(
        act = zcl_adv_validator=>log_findings(
                  it_findings = VALUE #( )
                  iv_object   = 'ZADV_UNIT_TEST' )
        msg = 'empty findings must not create a log' ).
  ENDMETHOD.


  METHOD db_rules_mapping.
    " ZADV_RULES rows -> the three registration APIs: COLUMN/COMPARE
    " take one row each, UNIQUE rows sharing a rule id form ONE rule
    " (the alphabetically first field is the anchor), unknown rule
    " types are skipped. White box on purpose: the mapping is pure and
    " needs no database, add_rules_from_db only adds the SELECT
    DATA lt_rows TYPE zcl_adv_validator=>ty_db_rules.
    lt_rows = VALUE #(
      ( scenario = 'T' rule_id = 'R1' rule_type = 'COLUMN'
        fieldname = 'MAIL' regex = `^a+$` severity = 'W' )
      ( scenario = 'T' rule_id = 'R2' rule_type = 'COLUMN'
        fieldname = 'DATE' required = 'X' )
      ( scenario = 'T' rule_id = 'R3' rule_type = 'COMPARE'
        fieldname = 'DATE_FROM' operator = 'LE' other_field = 'DATE_TO' )
      ( scenario = 'T' rule_id = 'R4' rule_type = 'UNIQUE'
        fieldname = 'STATUS' severity = 'W' )
      ( scenario = 'T' rule_id = 'R4' rule_type = 'UNIQUE'
        fieldname = 'MAIL' )
      ( scenario = 'T' rule_id = 'R5' rule_type = 'SOMETHING'
        fieldname = 'MAIL' ) ).

    DATA(lo_validator) = NEW zcl_adv_validator( ).

    DATA(lv_count) = lo_validator->apply_db_rules( lt_rows ).

    cl_abap_unit_assert=>assert_equals(
        exp = 4 act = lv_count
        msg = 'two column, one compare, one unique rule expected' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lines( lo_validator->mt_rules )
        msg = 'unknown rule type must be skipped' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lo_validator->mt_compare_rules ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lo_validator->mt_unique_rules ) ).

    READ TABLE lo_validator->mt_unique_rules INDEX 1 INTO DATA(ls_unique).
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'MAIL' act = CONV string( ls_unique-field )
        msg = 'alphabetically first row of the group is the anchor' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lines( ls_unique-fields )
        msg = 'both rows of the rule id contribute a key field' ).

    " end to end: the mapped rules validate exactly like registered
    " ones (regex W + rule id echo, required, violated comparison);
    " row 1 carries a valid DATE so only the comparison fires, row 2
    " leaves DATE initial -> the required rule from the table fires
    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows(
      ( date = '20261010' date_from = '20261010' date_to = '20261001' )
      ( mail = 'b' ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 3 act = lines( lt_findings )
        msg = 'compare violation + regex + required findings expected' ).

    READ TABLE lt_findings INTO DATA(ls_regex)
         WITH KEY check_type = zcl_adv_validator=>c_check-regex.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'W' act = CONV string( ls_regex-severity )
        msg = 'severity from the customizing row must reach the finding' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'R1' act = CONV string( ls_regex-rule_id )
        msg = 'rule id from the customizing row must be echoed' ).
  ENDMETHOD.


  METHOD db_rules_lenient.
    " a missing customizing table and a scenario without rows load
    " nothing: the SELECT raises internally, the catch keeps the rule
    " set empty - never an exception, never a broken activation
    DATA(lo_validator) = NEW zcl_adv_validator( ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0
        act = lo_validator->add_rules_from_db(
                  iv_scenario = 'X'
                  iv_tabname  = 'ZADV_NO_SUCH_TABLE' )
        msg = 'missing table must load zero rules without raising' ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0
        act = lo_validator->add_rules_from_db( iv_scenario = 'ZADV_NO_SCENARIO_9' )
        msg = 'scenario without rows must load zero rules' ).
  ENDMETHOD.


  METHOD row_offset.
    " iv_row_offset shifts finding row numbers: validate slices of a
    " big table with the running offset to keep global row numbers,
    " for column level and file level findings alike
    DATA(lo_validator) = NEW zcl_adv_validator( ).

    DATA(lt_findings) = lo_validator->validate(
        it_data       = VALUE ty_rows( ( status = 'Z' ) )
        iv_row_offset = 99 ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings ) ).
    cl_abap_unit_assert=>assert_equals(
        exp = 100 act = lt_findings[ 1 ]-row
        msg = 'offset 99 plus position 1' ).

    lo_validator->add_unique_rule( VALUE #( field = 'STATUS' ) ).

    DATA(lt_dup) = lo_validator->validate(
        it_data       = VALUE ty_rows( ( status = 'A' ) ( status = 'A' ) )
        iv_row_offset = 9 ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_dup )
        msg = 'only the duplicate row is reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 11 act = lt_dup[ 1 ]-row
        msg = 'uniqueness findings carry the offset too' ).
  ENDMETHOD.


  METHOD build_ddic_table.
    " unknown type -> unbound ref, the caller skips the test. Existence
    " is pre-checked on dd02l: CREATE DATA with an unknown dynamic type
    " name raises, and a SELECT cannot
    DATA(lv_name) = to_upper( CONV string( iv_tabname ) ).

    SELECT SINGLE @abap_true FROM dd02l
           WHERE tabname = @lv_name AND as4local = 'A'
           INTO @DATA(lv_exists).
    IF lv_exists <> abap_true.
      RETURN.
    ENDIF.

    " TYPE STANDARD TABLE OF (name) on purpose: a table rebuilt from a
    " struct descriptor (cl_abap_tabledescr=>create) loses the DDIC
    " name of the row type, and validate( ) would then degrade to the
    " mixed structure fallback - without foreign keys, currency and
    " unit references (only element level metadata survives there)
    TRY.
        CREATE DATA rr_table TYPE STANDARD TABLE OF (lv_name).
      CATCH cx_sy_create_data_error ##NO_TEXT.
        CLEAR rr_table.
    ENDTRY.
  ENDMETHOD.


  METHOD append_row.
    FIELD-SYMBOLS: <lt_rows> TYPE ANY TABLE,
                   <ls_row>  TYPE any.

    ASSIGN ir_table->* TO <lt_rows>.

    DATA(lo_struct) = CAST cl_abap_structdescr(
                        CAST cl_abap_tabledescr(
                          cl_abap_typedescr=>describe_by_data( <lt_rows> )
                        )->get_table_line_type( ) ).

    DATA lr_row TYPE REF TO data.
    CREATE DATA lr_row TYPE HANDLE lo_struct.
    ASSIGN lr_row->* TO <ls_row>.

    LOOP AT it_cells INTO DATA(ls_cell).
      ASSIGN COMPONENT ls_cell-comp OF STRUCTURE <ls_row> TO FIELD-SYMBOL(<lv_val>).
      IF sy-subrc = 0.
        <lv_val> = ls_cell-value.
      ENDIF.
    ENDLOOP.

    " <ls_row> points at lr_row->* already: a generic reference must
    " not be dereferenced (->) directly inside INSERT
    INSERT <ls_row> INTO TABLE <lt_rows>.
  ENDMETHOD.

ENDCLASS.


"*"* round trip through the real ZADV_RULES table. The unit tests of
"* ltcl_validate cover the rule MAPPING against in-memory rows and the
"* lenient zero-rules paths; what only the real table proves is the
"* SELECT column list of add_rules_from_db( ) - a wrong column name
"* raises inside the dynamic SELECT and the lenient catch turns it into
"* "0 rules", which the empty-scenario test cannot tell apart. This
"* class writes two rows of a dedicated scenario, loads and validates
"* them, then rolls the LUW back. Own risk level on purpose: it
"* modifies customizing data transiently (ROLLBACK WORK runs BEFORE
"* the assertions, so the LUW is cleaned even when one of them aborts)
CLASS ltcl_db_rules DEFINITION FINAL
  FOR TESTING
  RISK LEVEL DANGEROUS
  DURATION SHORT.

  PRIVATE SECTION.
    METHODS db_rules_roundtrip FOR TESTING.
ENDCLASS.


CLASS ltcl_db_rules IMPLEMENTATION.

  METHOD db_rules_roundtrip.
    CONSTANTS lc_scenario TYPE c LENGTH 30 VALUE 'ZADV_UNIT_TEST'.

    " component order of the real table row (minus MANDT, which the
    " INSERT fills automatically): INSERT dbtab matches positionally,
    " and ty_db_rule of the main class has a different field order
    TYPES: BEGIN OF ty_tabl_row,
             scenario    TYPE c LENGTH 30,
             rule_id     TYPE c LENGTH 30,
             fieldname   TYPE fieldname,
             rule_type   TYPE c LENGTH 10,
             operator    TYPE c LENGTH 2,
             other_field TYPE fieldname,
             required    TYPE flag,
             severity    TYPE c LENGTH 1,
             regex       TYPE c LENGTH 255,
             checktable  TYPE tabname,
             checkfield  TYPE fieldname,
             domname     TYPE c LENGTH 30,
           END OF ty_tabl_row,
           ty_tabl_rows TYPE STANDARD TABLE OF ty_tabl_row WITH EMPTY KEY.

    TYPES: BEGIN OF ty_row,
             mail      TYPE string,
             date_from TYPE budat,
             date_to   TYPE budat,
           END OF ty_row,
           ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    " guard like everywhere: no table object on this system -> skip
    SELECT SINGLE @abap_true FROM dd02l
           WHERE tabname = 'ZADV_RULES' AND as4local = 'A'
           INTO @DATA(lv_exists).
    IF lv_exists <> abap_true.
      RETURN.
    ENDIF.

    DATA(lv_count) = 0.
    DATA lt_findings TYPE zcl_adv_validator=>ty_findings.

    " transient customizing content of this LUW; dynamic table name in
    " a variable on purpose (no literal in the dynamic position, no
    " inline VALUE at the FROM TABLE operand - neither is accepted by
    " the 7.40 SP08 syntax check), and the test class must not create
    " an activation dependency either
    DATA(lv_tab) = CONV string( 'ZADV_RULES' ).

    DATA lt_insert TYPE ty_tabl_rows.
    lt_insert = VALUE #(
      ( scenario = lc_scenario rule_id = 'R1' rule_type = 'COLUMN'
        fieldname = 'MAIL' regex = `^a+$` severity = 'W' )
      ( scenario = lc_scenario rule_id = 'R2' rule_type = 'COMPARE'
        fieldname = 'DATE_FROM' operator = 'LE' other_field = 'DATE_TO' ) ).

    DELETE FROM (lv_tab) WHERE scenario = lc_scenario.

    INSERT (lv_tab) FROM TABLE lt_insert.

    " own LUW, the SELECT of add_rules_from_db( ) sees the uncommitted
    " rows; load and validate BEFORE any assertion can abort the test
    DATA(lo_validator) = NEW zcl_adv_validator( ).

    lv_count = lo_validator->add_rules_from_db( iv_scenario = lc_scenario ).

    " mail 'b' violates the regex rule (W, R1), row 1 violates the
    " comparison rule - both must come from the real table rows
    lt_findings = lo_validator->validate( VALUE ty_rows(
      ( mail = 'b' )
      ( date_from = '20261010' date_to = '20261001' ) ) ).

    ROLLBACK WORK.

    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lv_count
        msg = 'both customizing rows must load from the real table' ).

    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lines( lt_findings )
        msg = 'regex and comparison findings from the loaded rules' ).

    READ TABLE lt_findings INTO DATA(ls_regex)
         WITH KEY check_type = zcl_adv_validator=>c_check-regex.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'W' act = CONV string( ls_regex-severity )
        msg = 'severity of the customizing row must reach the finding' ).
    cl_abap_unit_assert=>assert_equals(
        exp = 'R1' act = CONV string( ls_regex-rule_id )
        msg = 'rule id of the customizing row must be echoed' ).
  ENDMETHOD.

ENDCLASS.
