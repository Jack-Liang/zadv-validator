INTERFACE zif_adv_column_check PUBLIC.

  "! Custom single column check of ZCL_ADV_VALIDATOR (plugin). An
  "! implementation is registered per field name with
  "! zcl_adv_validator=>add_column_check( ) and runs for every row in
  "! which the field has a non-initial value that passed the built-in
  "! DDIC checks - the first failing check of a field wins, so a plugin
  "! only sees values the validator itself accepted.
  "! The interface is self contained on purpose (own result types, no
  "! reference to the validator class): it must activate before and
  "! independently of the class that uses it.

  TYPES:
    "! E = error (default), W = warning, I = info; invalid values are
    "! normalized to E by the validator
    ty_severity TYPE c LENGTH 1,

    "! result of one checked value: ok = abap_false produces a finding
    "! with the given text/severity/object/rule_id
    BEGIN OF ty_result,
      ok       TYPE abap_bool,
      severity TYPE ty_severity,
      message  TYPE string,
      object   TYPE c LENGTH 60,
      rule_id  TYPE c LENGTH 30,
    END OF ty_result.

  METHODS check
    IMPORTING iv_row        TYPE i
              iv_fieldname  TYPE fieldname
              iv_value      TYPE string
              ir_row        TYPE REF TO data
    RETURNING VALUE(rs_result) TYPE ty_result.

  "! iv_row: 1 based row number within the validated table
  "! iv_fieldname: field the check is registered for (upper case)
  "! iv_value: original external format value of that field
  "! ir_row: reference to the whole row structure - assign it to read
  "!         other columns, which makes simple cross field rules
  "!         possible without waiting for a declarative framework

ENDINTERFACE.
