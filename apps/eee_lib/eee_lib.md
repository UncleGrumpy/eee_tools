<!--
 Copyright 2025 Winford <winford@object.stream>

SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
-->

# eee_lib

An OTP library to support eee_tools

## Modules:

* `m:ecrc` crc32 checksum generator
* `m:ecsv` csv file parsing/creation utility
* `m:efile` file read and write functions compatible with standard OTP BEAM and AtomVM
* `m:eee_lib` miscellaneous helper functions, i.e. executing external commands and swapping endianness.
* `m:esp_device_flash` helper library for reading and writing to esp32 device flash - this relies on
the python based `esptool` until native Erlang modules can be created to replace its functionality.

## Build

```terminal
$ rebar3 compile
===> Verifying dependencies...
===> Analyzing applications...
===> Compiling eee_lib
===> Compiling esp_partition
===> Compiling esp_nvs
===> Compiling eee_tools
```

## APIs

See module's documentation:
* `m:ecrc`
* `m:ecsv`
* `m:eee_lib`
* `m:efile`
* `m:esp_device_flash`
