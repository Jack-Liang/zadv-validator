INTERFACE zif_adv_metadata PUBLIC.

  "! Metadata of the zadv-validator library, kept in a constants-only
  "! interface of its own so that consumers can read it without the
  "! class and other projects can copy the same convention. Self
  "! contained on purpose (no types, no methods): the implementing
  "! class compiles against it, so it must never depend on anything.
  CONSTANTS:
    "! semantic version (MAJOR.MINOR.PATCH), kept in sync with CHANGELOG.md
    c_version     TYPE string VALUE '2.0.0',
    "! maintainer of the library
    c_author      TYPE string VALUE 'Jack-Liang',
    "! repository and issue tracker
    c_repository  TYPE string VALUE 'https://github.com/Jack-Liang/zadv-validator',
    "! SPDX license identifier
    c_license     TYPE string VALUE 'MIT',
    "! one line purpose of the library
    c_description TYPE string VALUE 'DDIC based generic data validator'.

ENDINTERFACE.
