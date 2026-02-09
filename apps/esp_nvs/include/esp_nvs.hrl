%% Common definitions for nvs modules
%%
%% Copyright (c) 2025 Winford (Uncle Grumpy) <winford@object.stream>
%% All rights reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% SPDX-FileCopyrightText: 2025 Winford (Uncle Grumpy) <winford@object.stream>
%% SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later

%% References:
%% https://github.com/espressif/esp-idf/blob/v5.5.1/components/nvs_flash/include/nvs.h
%% https://github.com/espressif/esp-idf/blob/v5.5.1/components/nvs_flash/include/nvs_handle.hpp
%% https://github.com/espressif/esp-idf-nvs-partition-gen/blob/main/esp_idf_nvs_partition_gen/nvs_partition_gen.py

-ifndef(ESP_NVS_HRL).
-define(ESP_NVS_HRL, true).

-define(NVS_BLOCK_SIZE, 32).
-define(NVS_KEY_CHARS, 15).
-define(NVS_KEY_SIZE, 16).
-define(NVS_PARTITION_SIZE_DEFAULT, 16#6000).
-define(NVS_PAGE_SIZE, 4096).

-define(NVS_PAGE_BUF_LEN, 32768).

-record(page, {
    page_num = 1 :: pos_integer(),
    %% V2 NVS requires 1 empty page for swap.
    num_pages = 1 :: non_neg_integer(),
    %% Number of useable pages = (NVS_PARTITION_SIZE/4096) - 1
    version = 2 :: 1 | 2,
    %% Default to version 2 for AtomVM compatibility
    ns_idx = 0 :: 0..254,
    offset = 64 :: pos_integer(),
    %% Header and page entry table consume the first 64 bytes of each page
    page_buf = binary:copy(<<16#ff>>, (?NVS_PAGE_SIZE)) :: <<_:(?NVS_PAGE_BUF_LEN)>>
    %% 4096 bytes initialized to all 16#FF.
}).

%% ESP_NVS_HRL
-endif.
