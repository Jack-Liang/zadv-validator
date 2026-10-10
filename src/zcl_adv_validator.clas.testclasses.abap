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
      only_field_unknown   FOR TESTING.
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
    lo_validator->only_fields( VALUE #( ( 'DATE' ) ) ).

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
    lo_validator->exclude_fields( VALUE #( ( 'DATE' ) ) ).

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
    lo_validator->only_fields( VALUE #( ( 'DOES_NOT_EXIST' ) ) ).

    DATA(lt_findings) = lo_validator->validate( VALUE ty_rows( ( ) ) ).

    cl_abap_unit_assert=>assert_equals(
        exp = 1 act = lines( lt_findings ) msg = 'unknown only field not reported' ).
    cl_abap_unit_assert=>assert_equals(
        exp = CONV string( zcl_adv_validator=>c_check-structure )
        act = CONV string( lt_findings[ 1 ]-check_type ) ).
  ENDMETHOD.

ENDCLASS.
