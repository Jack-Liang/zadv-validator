"*"* use this source file for your ABAP unit test classes
CLASS ltcl_validate DEFINITION FINAL
  FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_row,
             status TYPE as4local,  " domain AS4LOCAL: fixed values A/N/I
             date   TYPE budat,     " DATS
             time   TYPE uzeit,     " TIMS
             mail   TYPE string,    " non DDIC -> only usable via rules
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


  METHOD build_ddic_table.
    " unknown type -> unbound ref, the caller skips the test. Existence
    " is pre-checked on dd02l: describe_by_name dumps (uncatchably) for
    " unknown names on some releases, a SELECT cannot raise
    DATA(lv_name) = to_upper( CONV string( iv_tabname ) ).

    SELECT SINGLE @abap_true FROM dd02l
           WHERE tabname = @lv_name AND as4local = 'A'
           INTO @DATA(lv_exists).
    IF lv_exists <> abap_true.
      RETURN.
    ENDIF.

    TRY.
        DATA(lo_descr) = cl_abap_typedescr=>describe_by_name( lv_name ).
        DATA(lo_tab) = cl_abap_tabledescr=>create(
                         CAST cl_abap_structdescr( lo_descr ) ).
        CREATE DATA rr_table TYPE HANDLE lo_tab.
      CATCH cx_root ##NO_TEXT.
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
