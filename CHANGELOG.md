<!--
 Copyright 2025 Winford <winford@object.stream>

SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
-->

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 (Unreleased)

### Added

- esp_partition: library and escript for generating ESP32 partition tables
- esp_nvs: library and escript for creating provisioned NVS partitions for ESP32 platform
- eee_lib: library of utility modules
  * ecrc: library for generating CRC checksums compatible with the ESP32 ROM implementation,
  designed for compatibility with both AtomVM and OTP BEAM.
  * ecsv: library for reading and writing csv files
  * efile: library for reading and writing files designed for compatibility with OTP and AtomVM
  * eee_lib: miscellaneous helpers, including logging the output of external commands to file
