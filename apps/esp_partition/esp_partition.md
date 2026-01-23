<!--
 Copyright 2025 Winford <winford@object.stream>

SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
-->

# esp_partition

The escript can be used to read and parse binary partitions as well as generate ESP32 partition table
binary files from csv template files.

## Build

From the root eee_tools project directory:

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

The escript will be available in `_build/default/bin`.

## `esp_partition` Escript Usage

After building the `esp_partition` escript, a partition table can be created with the following command:

```console
$ _build/default/bin/esp_partition partitions.csv partition_table.bin
Processed input file partitions.csv
Verifying table data...
Verification complete
Output written to: partition_table.bin
Success! Partition table written to partition_table.bin
```

## APIs

See the `esp_partition` module docs.
* `m:esp_partition`
* `m:esp_partition_csv`
