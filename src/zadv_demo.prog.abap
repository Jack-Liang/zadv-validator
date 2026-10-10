REPORT zadv_demo.

"* Demo for ZCL_ADV_VALIDATOR: validates a (simulated) upload table
"* against DDIC domain fixed values, check tables and format rules,
"* then shows every invalid input in an ALV.
"*
"* The demo deliberately avoids SELECTs on customizing tables so it
"* activates on every system (trial/developer editions often lack T001
"* etc.). Check-table findings appear only where the check table is
"* actually present; on systems without it the lenient mode lets the
"* value pass instead of raising an error.

TYPES: BEGIN OF ty_upload,
         status TYPE as4local,  " domain AS4LOCAL: fixed values A/N/I
         budat  TYPE budat,     " DATS format check
         bukrs  TYPE bukrs,     " check table T001
         land1  TYPE land1,     " check table T005
         waers  TYPE waers,     " check table TCURC
         email  TYPE string,    " non DDIC field -> regex rule
         remark TYPE string,    " non DDIC field -> required rule
       END OF ty_upload.

DATA gt_upload TYPE STANDARD TABLE OF ty_upload WITH EMPTY KEY.


START-OF-SELECTION.

  " an invalid date cannot be written as a literal: the syntax check
  " rejects literals that do not match type D -> build it at runtime
  DATA(lv_invalid_date) = `20261301`.

  gt_upload = VALUE #(
    " row 1: values that are valid on most systems
    ( status = 'A' budat = sy-datum bukrs = '1000' land1 = 'DE'
      waers = 'EUR' email = 'dev@example.com' remark = 'typical valid row' )

    " row 2: wrong domain value, wrong date, unknown check-table values,
    "        failing regex, missing required remark
    ( status = 'Z' budat = lv_invalid_date bukrs = 'ZZZZ' land1 = 'ZZ'
      waers = 'ZZZ' email = 'not-an-email' remark = '' )

    " row 3: everything fine except the domain value
    ( status = 'Z' budat = sy-datum bukrs = '1000' land1 = 'DE'
      waers = 'EUR' email = 'fine@example.com' remark = 'only flag wrong' ) ).

  DATA(lo_validator) = NEW zcl_adv_validator( ).

  " explicit rules for fields that have no DDIC type
  lo_validator->add_rules( VALUE #(
    ( fieldname = 'EMAIL'  regex = `^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$` )
    ( fieldname = 'REMARK' required = abap_true ) ) ).

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

  TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = DATA(lo_alv)
        CHANGING  t_table      = lt_findings ).

      lo_alv->get_columns( )->set_optimize( abap_true ).
      lo_alv->display( ).

    CATCH cx_salv_msg.
      LOOP AT lt_findings INTO DATA(ls_finding).
        WRITE: / ls_finding-row, ls_finding-fieldname, ls_finding-value,
                 ls_finding-check_type, ls_finding-message.
      ENDLOOP.
  ENDTRY.
