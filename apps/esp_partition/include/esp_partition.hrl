%% esp_partition partition records
%% This is part of eee_tools
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
%%
%% SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
%%

%%-------------------------------------------------------------------
%% Definitions taken from ESP-IDF docs and sources.
%% References:
%% https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/partition-tables.html
%%
%%-------------------------------------------------------------------
-ifndef(ESP_PARTITION_HRL).
-define(ESP_PARTITION_HRL, true).

-define(PARTITION_TABLE_MAX, 16#C00).
-define(PARTITION_TABLE_ENTRY_SIZE, 32).

%% Record definitions
-record(partition, {
    name :: string(),
    type :: byte() | undefined,
    subtype :: byte() | undefined,
    offset :: non_neg_integer() | undefined,
    size :: non_neg_integer() | undefined,
    encrypted = false :: boolean(),
    readonly = false :: boolean(),
    entry_num = 0 :: 0..255
}).

-record(partmap_config, {
    quiet = false :: boolean(),
    md5sum = true :: boolean(),
    secure = none :: none | v1 | v2,
    table_offset = 16#8000 :: non_neg_integer(),
    verify = true :: boolean(),
    flash_size = 16#400000 :: non_neg_integer()
}).

%% ESP_PARTITION_HRL
-endif.
