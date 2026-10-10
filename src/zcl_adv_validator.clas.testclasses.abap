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
      curr_quan_currency_tcurc FOR TESTING.
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
    " or check table apply
    cl_abap_unit_assert=>assert_equals(
        exp = abap_true
        act = zcl_adv_validator=>check_value_by_element(
                  iv_value = '123' iv_rollname = 'VBELN' )
        msg = 'external VBELN form should pass ALPHA' ).
  ENDMETHOD.


  METHOD fkey_composite_valid.
    " KNA1-REGIO has the composite foreign key LAND1+REGIO -> T005A
    " (LAND1+BLAND): the shipped combination DE/BY (Bavaria) must pass
    " the combination check without any finding
    DATA lt_rows TYPE STANDARD TABLE OF kna1 WITH EMPTY KEY.
    APPEND VALUE #( land1 = 'DE' regio = 'BY' ) TO lt_rows.

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( lt_rows ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0 act = lines( lt_findings )
        msg = 'valid region combination reported' ).
  ENDMETHOD.


  METHOD fkey_composite_invalid.
    " DE/ZZ does not exist in T005A: the combination must be rejected,
    " and the DD05S mapping must show up as BLAND (not the same-name
    " REGIO) together with the partner field LAND1
    DATA lt_rows TYPE STANDARD TABLE OF kna1 WITH EMPTY KEY.
    APPEND VALUE #( land1 = 'DE' regio = 'ZZ' ) TO lt_rows.

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( lt_rows ).

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
    DATA lt_rows TYPE STANDARD TABLE OF kna1 WITH EMPTY KEY.
    APPEND VALUE #( regio = 'BY' ) TO lt_rows.

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( lt_rows ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0 act = lines( lt_findings )
        msg = 'initial partner must degrade to the lenient single check' ).
  ENDMETHOD.


  METHOD fkey_cache_idempotent.
    " repeated validate( ) (tuple cache hits) and a run after
    " clear_caches( ) (fresh lookups) must return identical findings
    DATA lt_rows TYPE STANDARD TABLE OF kna1 WITH EMPTY KEY.
    APPEND VALUE #( land1 = 'DE' regio = 'ZZ' ) TO lt_rows.
    APPEND VALUE #( land1 = 'DE' regio = 'ZZ' ) TO lt_rows.

    DATA(lo_validator) = NEW zcl_adv_validator( ).

    DATA(lt_first)  = lo_validator->validate( lt_rows ).
    DATA(lt_second) = lo_validator->validate( lt_rows ).

    cl_abap_unit_assert=>assert_equals(
        exp = 2 act = lines( lt_first )
        msg = 'both rows must be reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = lines( lt_first ) act = lines( lt_second )
        msg = 'second validate must return identical findings' ).

    lo_validator->clear_caches( ).

    cl_abap_unit_assert=>assert_equals(
        exp = lines( lt_first ) act = lines( lo_validator->validate( lt_rows ) )
        msg = 'validate after clear_caches must return identical findings' ).
  ENDMETHOD.


  METHOD curr_quan_unit_t006.
    " MARA-NTGEW (QUAN) references the unit column MARA-GEWEI: the unit
    " code is validated against T006/MSEHI (with the CUNIT conversion
    " exit of GEWEI applied). An existing own foreign key on GEWEI
    " produces the very same lookup, both paths are fine here.
    DATA lt_rows TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    APPEND VALUE #( ntgew = '1' gewei = 'KG' ) TO lt_rows.
    APPEND VALUE #( ntgew = '1' gewei = 'ZZX' ) TO lt_rows.

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( lt_rows ).

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
    DATA lt_rows TYPE STANDARD TABLE OF vbak WITH EMPTY KEY.
    APPEND VALUE #( netwr = '1' waers = 'EUR' ) TO lt_rows.
    APPEND VALUE #( netwr = '1' waers = 'ZZZ9' ) TO lt_rows.

    DATA(lt_findings) = NEW zcl_adv_validator( )->validate( lt_rows ).

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

ENDCLASS.
