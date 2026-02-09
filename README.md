<!--
 Copyright 2025 Winford <winford@object.stream>

SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
-->
# eee_tools

_Erlang escripts for ESP32 devices_

A set of escripts and OTP libraries for working with ESP32 devices.

## Tools:

- [`esp_partition`](apps/esp_partition/esp_partition.md) for editing partition tables.
- [`esp_nvs`](apps/esp_nvs/eee_nvs.md) for editing ESP32 Non-Volatile Storage (NVS) partitions.

## Utility libraries:

* [`eee_lib`](apps/eee_lib/eee_lib.md) Common utility functions.

## Build an individual tool

The escripts utilize modules from several of the umbrella project applications, so they must be
built from the root directory of the project. Individual escripts must be built one at a time.
Without an `-a` or `--main-app` option given the default is to build `esp_partition`.

<!-- TODO: create release profile(s) and update build and install instructions -->

To build the `esp_partition` tool use `-a` or `--main-app` to select the `esp_partition` build
target as follows:

```console
$ rebar3 escriptize -a esp_partition
===> Verifying dependencies...
===> Analyzing applications...
===> Compiling eee_lib
===> Compiling esp_partition
===> Compiling esp_nvs
===> Compiling eee_tools
===> Building escript for esp_partition...
```

To build the `esp_nvs` tool use `-a` or `--main-app` to select the `esp_nvs` build target as
follows:

```console
$ rebar3 escriptize -a esp_nvs
===> Verifying dependencies...
===> Analyzing applications...
===> Compiling eee_lib
===> Compiling esp_partition
===> Compiling esp_nvs
===> Compiling eee_tools
===> Building escript for esp_nvs...
```

The escripts will be compiled into `_build/default/bin/`.

## [esp_partition](apps/esp_partition/esp_partition.md)

This tool can be used to read and parse binary partitions as well as generate ESP32 partition table
binary files from csv template files. This replicates the functionality of Espressif's python based
[gen_esp32part.py](https://github.com/espressif/esp-idf/blob/master/components/partition_table/gen_esp32part.py)
used by ESP-IDF to build binary partition tables.

## [esp_nvs](apps/esp_nvs/eee_nvs.md)

This tool can create nvs partitions with key-value pairs from an ESP-IDF compatible
[NVS](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/storage/nvs_flash.html)
(non-volatile storage) description file in [csv](https://en.wikipedia.org/wiki/Comma-separated_values)
(comma-separated values) format. This tool is a BEAM replacement for Espressif's python based
[nvs_partition_gen.py](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/storage/nvs_partition_gen.html)
tool, but with extra functionality. In addition to generating NVS partition binaries the NVS
partition of an attached device can be read and a csv file of the currently stored key values will
be generated, just use the path to an attached device as the input and provide the csv filename for
the output.

## [eee_lib](apps/eee_lib/eee_lib.md)

This library contains several modules targeting Esp-IDF compatibility, but also flexible enough to
be useful in other situations. Several of the included modules provide compatibility for both BEAM
and AtomVM functionality, including `ecrc` (for generating esp32-rom compatible crc32 checksums)
and `efile` (providing file read and write functions that work on both OTP and AtomVM). The module
`ecsv` is mostly intended for working with ESP-IDF-compatible csv files, but may be useful when a
lightweight csv library is needed for constrained environments.
