REPORT zadv_demo.

"* Demo for ZCL_ADV_VALIDATOR: validates a (simulated) upload table
"* against DDIC domain fixed values, check tables and format rules,
"* then shows every invalid input in an ALV.
"*
"* Row 1 is built from values that are valid in the current system,
"* rows 2 and 3 contain deliberate errors.

TYPES: BEGIN OF ty_upload,
         bukrs  TYPE bukrs,     " check table T001
         land1  TYPE land1,     " check table T005
         waers  TYPE waers,     " check table TCURC
         spras  TYPE spras,     " check table T002
         budat  TYPE budat,     " DATS format check
         email  TYPE string,    " non DDIC field -> regex rule
         remark TYPE string,    " non DDIC field -> required rule
       END OF ty_upload.

DATA gt_upload TYPE STANDARD TABLE OF ty_upload WITH EMPTY KEY.


START-OF-SELECTION.

  " pick values that are valid in THIS system so row 1 stays clean
  SELECT SINGLE bukrs FROM t001  INTO @DATA(lv_bukrs).
  SELECT SINGLE land1 FROM t005  INTO @DATA(lv_land1).
  SELECT SINGLE waers FROM tcurc INTO @DATA(lv_waers).
  SELECT SINGLE sprsl FROM t002  INTO @DATA(lv_spras).

  gt_upload = VALUE #(
    ( bukrs = lv_bukrs land1 = lv_land1 waers = lv_waers spras = lv_spras
      budat = sy-datum email = 'dev@example.com' remark = 'perfect row' )

    ( bukrs = 'ZZZZ' land1 = 'ZZ' waers = 'ZZZ' spras = 'Q'
      budat = '20261301' email = 'not-an-email' remark = '' )

    ( bukrs = lv_bukrs land1 = lv_land1 waers = 'ZZZ' spras = lv_spras
      budat = sy-datum email = 'fine@example.com' remark = 'only currency wrong' ) ).

  DATA(lo_validator) = NEW zcl_adv_validator( ).

  " explicit rules for fields that have no DDIC type
  lo_validator->add_rules( VALUE #(
    ( fieldname = 'EMAIL'  regex = `^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$` )
    ( fieldname = 'REMARK' required = abap_true ) ) ).

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
