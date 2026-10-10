INTERFACE zif_adv_validator PUBLIC.

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
    "! All attributes are optional, an initial checktable suppresses the
    "! DDIC check table for that field (not implemented: use a different
    "! field or extend the class if you need suppression).
    BEGIN OF ty_rule,
      fieldname  TYPE fieldname,
      required   TYPE abap_bool,
      checktable TYPE tabname,
      checkfield TYPE fieldname,
      domname    TYPE domname_l,
      regex      TYPE string,
    END OF ty_rule,
    ty_rules TYPE STANDARD TABLE OF ty_rule WITH EMPTY KEY.

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
    "! Validate any internal table against DDIC metadata and added rules.
    "! The row structure must be DDIC based (or a mixed structure whose
    "! components are DDIC typed) for automatic checks; string/numeric
    "! helper fields are simply skipped unless covered by a rule.
    "! Initial values pass all checks unless a rule marks them required.
    "! The method never raises: unusable metadata is reported leniently.
    VALIDATE
      IMPORTING it_data             TYPE ANY TABLE
      RETURNING VALUE(rt_findings)  TYPE ty_findings,

    ADD_RULE
      IMPORTING is_rule TYPE ty_rule,

    ADD_RULES
      IMPORTING it_rules TYPE ty_rules,

    CLEAR_RULES.

ENDINTERFACE.
