CLASS zcl_adv_validator DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      "! One error found by the validator. Row 0 is used for structural
      "! problems (bad table type, rule references unknown field, ...).
      BEGIN OF ty_finding,
        row        TYPE i,
        fieldname  TYPE fieldname,
        value      TYPE string,
        check_type TYPE c LENGTH 12,
        object     TYPE c LENGTH 60,
        message    TYPE string,
      END OF ty_finding,
      ty_findings TYPE STANDARD TABLE OF ty_finding WITH EMPTY KEY,

      "! Explicit rule that adds to or overrides the DDIC derived checks.
      "! All attributes are optional.
      BEGIN OF ty_rule,
        fieldname  TYPE fieldname,
        required   TYPE abap_bool,
        checktable TYPE tabname,
        checkfield TYPE fieldname,
        domname    TYPE c LENGTH 30,
        regex      TYPE string,
      END OF ty_rule,
      ty_rules TYPE STANDARD TABLE OF ty_rule WITH EMPTY KEY,

      "! column filter lists for only_fields( ) / exclude_fields( ).
      "! Elementary row types demand constructor values COMPATIBLE with
      "! the row type: 'BUKRS' (C literal) fits neither C(30) nor string,
      "! so callers must use backtick string literals:
      "! only_fields( VALUE #( ( `BUKRS` ) ) ).
      ty_fieldnames TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.

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
      END OF c_check.

    METHODS:
      "! Validate any internal table against DDIC metadata and added
      "! rules. The row structure must be DDIC based (or a mixed
      "! structure whose components are DDIC typed) for automatic
      "! checks; string/numeric helper fields are simply skipped unless
      "! covered by a rule. Initial values pass all checks unless a rule
      "! marks them required. The method never raises: unusable
      "! metadata is reported leniently.
      validate
        IMPORTING it_data            TYPE ANY TABLE
        RETURNING VALUE(rt_findings) TYPE ty_findings,

      add_rule
        IMPORTING is_rule TYPE ty_rule,

      add_rules
        IMPORTING it_rules TYPE ty_rules,

      clear_rules,

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
        RETURNING VALUE(rv_ok) TYPE abap_bool.

  PRIVATE SECTION.

    TYPES:
      "! method parameters cannot use inline LENGTH -> named type
      ty_domname TYPE c LENGTH 30,

      "! SE91 message class id and number for build_msg
      ty_msgid TYPE c LENGTH 20,
      ty_msgnr TYPE n LENGTH 3,

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
      ty_ctab_vals TYPE STANDARD TABLE OF ty_ctab_val WITH EMPTY KEY.

    CONSTANTS:
      "! SE91 message class carrying the finding texts (SE63 translatable)
      c_msgid TYPE ty_msgid VALUE 'ZADV_VALIDATOR',
      "! values per dynamic IN( ) batch: small enough for any database
      "! IN list and statement size limit
      c_in_chunk TYPE i VALUE 100.

    DATA:
      mt_rules          TYPE ty_rules,
      mt_only_fields    TYPE ty_fieldnames,
      mt_exclude_fields TYPE ty_fieldnames,
      mt_domains        TYPE ty_domains,
      mt_ctab_hits      TYPE ty_ctab_hits,
      mt_convexits      TYPE ty_convexits.

    METHODS:
      build_fields
        IMPORTING io_struct        TYPE REF TO cl_abap_structdescr
        RETURNING VALUE(rt_fields) TYPE ty_fields,

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
        RETURNING VALUE(rv_ok)     TYPE abap_bool.

    "! static on purpose: it is called via short form from the static
    "! check_value_* methods (instance methods cannot be called that
    "! way from a static context) and uses no instance state
    CLASS-METHODS:
      check_single
        IMPORTING iv_value     TYPE clike
                  iv_rollname  TYPE clike
        EXPORTING es_finding   TYPE ty_finding
        RETURNING VALUE(rv_ok) TYPE abap_bool,

      "! finding message text from the SE91 message class; operands for
      "! unused placeholders are supplied blank
      build_msg
        IMPORTING iv_nr          TYPE ty_msgnr
                  iv_a           TYPE string OPTIONAL
                  iv_b           TYPE string OPTIONAL
                  iv_c           TYPE string OPTIONAL
        RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.


CLASS zcl_adv_validator IMPLEMENTATION.

  METHOD validate.

    DATA: lv_row  TYPE i,
          lr_line TYPE REF TO data.

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
                      message   = build_msg( iv_nr = '001' ) )
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
                                                  iv_a  = lv_only ) )
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
                                                iv_a  = <fs_chk>-fieldname ) )
               TO rt_findings.
      ENDIF.
    ENDLOOP.

    " ---------------------------------------------------------------------
    " 4) prefill the check-table lookup cache in chunked batches
    " ---------------------------------------------------------------------
    prefetch_checktables( it_data = it_data it_fields = lt_fields ).

    " ---------------------------------------------------------------------
    " 5) row loop
    " ---------------------------------------------------------------------
    LOOP AT it_data ASSIGNING <row>.
      lv_row = lv_row + 1.

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
                                               iv_a  = <fs_field>-fieldname ) )
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
                                                   iv_a  = lv_disp ) )
                     TO rt_findings.
              CONTINUE.
            ENDIF.
          WHEN 'TIMS'.
            IF check_time( lv_disp ) = abap_false.
              APPEND VALUE #( row = lv_row fieldname = <fs_field>-fieldname
                              value = lv_disp
                              check_type = c_check-time
                              message = build_msg( iv_nr = '006'
                                                   iv_a  = lv_disp ) )
                     TO rt_findings.
              CONTINUE.
            ENDIF.
          WHEN 'NUMC'.
            IF check_numc( lv_disp ) = abap_false.
              APPEND VALUE #( row = lv_row fieldname = <fs_field>-fieldname
                              value = lv_disp
                              check_type = c_check-numc
                              message = build_msg( iv_nr = '007'
                                                   iv_a  = lv_disp ) )
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
                                               iv_b  = lv_dom ) )
                 TO rt_findings.
          CONTINUE.
        ENDIF.

        " check table (rule overrides DDIC) ...............................
        DATA(lv_ctab) = COND #( WHEN <fs_field>-rule_ctab IS NOT INITIAL
                                THEN <fs_field>-rule_ctab
                                ELSE <fs_field>-checktable ).
        DATA(lv_cfld) = COND #( WHEN <fs_field>-rule_cfield IS NOT INITIAL
                                THEN <fs_field>-rule_cfield
                                ELSE <fs_field>-fieldname ).

        IF lv_ctab IS NOT INITIAL AND
           check_table( iv_table = lv_ctab iv_field = lv_cfld iv_value = lv_int ) = abap_false.
          APPEND VALUE #( row = lv_row fieldname = <fs_field>-fieldname
                          value = lv_disp object = |{ lv_ctab }/{ lv_cfld }|
                          check_type = c_check-checktable
                          message = build_msg( iv_nr = '009'
                                               iv_a  = lv_disp
                                               iv_b  = lv_ctab
                                               iv_c  = lv_cfld ) )
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
                                                 iv_a  = lv_disp ) )
                   TO rt_findings.
            CONTINUE.
          ENDIF.
        ENDIF.

      ENDLOOP.
    ENDLOOP.

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
    CLEAR: mt_domains, mt_ctab_hits, mt_convexits.
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

    DATA lo_struct TYPE REF TO cl_abap_structdescr.
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

    IF lo_struct IS INITIAL OR lo_struct->is_ddic_type( ) = abap_false.
      es_finding-row        = 0.
      es_finding-fieldname  = CONV fieldname( lv_field ).
      es_finding-check_type = c_check-structure.
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
      es_finding-message    = build_msg( iv_nr = '013'
                                         iv_a  = lv_field
                                         iv_b  = lv_tabname ).
      RETURN.
    ENDIF.

    IF ls_dfies-rollname IS INITIAL.
      es_finding-row        = 0.
      es_finding-fieldname  = CONV fieldname( lv_field ).
      es_finding-check_type = c_check-structure.
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

    DATA lo_descr TYPE REF TO cl_abap_typedescr.
    TRY.
        lo_descr = cl_abap_typedescr=>describe_by_name( lv_rollname ).
      CATCH cx_root ##NO_TEXT.
        CLEAR lo_descr.
    ENDTRY.

    IF lo_descr IS INITIAL
       OR lo_descr->kind <> cl_abap_typedescr=>kind_elem
       OR CAST cl_abap_elemdescr( lo_descr )->is_ddic_type( ) = abap_false.
      es_finding-row        = 0.
      es_finding-fieldname  = CONV fieldname( lv_rollname ).
      es_finding-check_type = c_check-structure.
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
                      checktable = <ls_dfies>-checktable )
             INTO TABLE rt_fields.
    ENDLOOP.

    " merge explicit rules on top
    LOOP AT mt_rules ASSIGNING FIELD-SYMBOL(<ls_rule>).

      INSERT VALUE #( fieldname    = <ls_rule>-fieldname
                      synthetic    = abap_true
                      datatype     = 'CHAR'
                      required     = <ls_rule>-required
                      regex        = <ls_rule>-regex
                      rule_ctab    = <ls_rule>-checktable
                      rule_cfield  = <ls_rule>-checkfield
                      rule_domname = <ls_rule>-domname )
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


  METHOD prefetch_checktables.

    DATA lt_wants TYPE ty_ctab_wants.

    LOOP AT it_fields ASSIGNING FIELD-SYMBOL(<fs_pfield>).

      DATA(lv_ctab) = COND #( WHEN <fs_pfield>-rule_ctab IS NOT INITIAL
                              THEN <fs_pfield>-rule_ctab
                              ELSE <fs_pfield>-checktable ).
      CHECK lv_ctab IS NOT INITIAL.
      DATA(lv_cfld) = COND #( WHEN <fs_pfield>-rule_cfield IS NOT INITIAL
                              THEN <fs_pfield>-rule_cfield
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


  METHOD build_msg.
    " TYPE 'S' with INTO only builds the text, nothing is displayed or
    " logged; surplus WITH operands are allowed, missing ones would fail
    MESSAGE ID c_msgid TYPE 'S' NUMBER iv_nr
            WITH iv_a iv_b iv_c
            INTO rv_text.
  ENDMETHOD.

ENDCLASS.
