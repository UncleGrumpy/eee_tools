%% unit tests for esp_partition_csv module
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
%% SPDX-FileCopyrightText: 2025 Winford (Uncle Grumpy) <winford@object.stream>
%% SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later

-module(esp_partition_csv_tests).
-include("esp_partition.hrl").
-include_lib("eunit/include/eunit.hrl").

-ifdef(TEST).
-compile(export_all).
-endif.

csv_string_from_csv_data_test() ->
    NVS = #{
        name => "nvs",
        type => "data",
        subtype => "nvs",
        offset => "0x9000",
        size => "0x6000",
        flags => ""
    },
    PHY = #{
        name => "phy_init",
        type => "data",
        subtype => "phy",
        offset => "0xf000",
        size => "0x1000",
        flags => ""
    },
    APP = #{
        name => "factory",
        type => "app",
        subtype => "factory",
        offset => "0x10000",
        size => "0x1C0000",
        flags => ""
    },
    BOOT = #{
        name => "boot.avm",
        type => "data",
        subtype => "phy",
        offset => "0x1D0000",
        size => "0x40000",
        flags => ""
    },
    MAIN = #{
        name => "main.avm",
        type => "data",
        subtype => "phy",
        offset => "0x210000",
        size => "0x100000",
        flags => ""
    },
    {ok, Lines} = esp_partition_csv:table_from_csv_data(
        [NVS, PHY, APP, BOOT, MAIN], #partmap_config{quiet = true}
    ),
    assert_partition_record_lines(Lines),

    {ok, Csv} = esp_partition_csv:encode_csv_table(Lines),
    ?assertEqual(
        lists:flatten(
            "# ESP-IDF Partition Table generated with eee_tools\n# Name, Type, SubType, Offset, Size, Flags\n" ++
                "nvs,data,nvs,0x9000,0x6000,\nphy_init,data,phy,0xF000,0x1000,\nfactory,app,factory,0x10000,0x1C0000,\n" ++
                "boot.avm,data,phy,0x1D0000,0x40000,\nmain.avm,data,phy,0x210000,0x100000,"
        ),
        Csv
    ).

csv_implied_offsets_test() ->
    FileString =
        lists:flatten(
            "# ESP-IDF Partition Table generated with eee_tools\n# Name, Type, SubType, Offset, Size, Flags\n" ++
                "nvs,data,nvs,,0x6000,\nphy_init,data,phy,,0x1000,\nfactory,app,factory,,0x1C0000,\n" ++
                "boot.avm,data,phy,,0x40000,\nmain.avm,data,phy,,0x100000,"
        ),
    Config = #partmap_config{quiet = true},
    Rows = ecsv:decode_iolist(FileString, [name, type, subtype, offset, size, flags]),
    {ok, Lines} = esp_partition_csv:table_from_csv_data(Rows, Config),
    assert_partition_record_lines(Lines).

assert_partition_record_lines([NVS_rec, PHY_rec, APP_rec, BOOT_rec, MAIN_rec]) ->
    ?assertMatch(
        #partition{
            name = "nvs",
            type = 16#01,
            subtype = 16#02,
            offset = 16#9000,
            size = 16#6000,
            encrypted = false,
            readonly = false,
            entry_num = 1
        },
        NVS_rec
    ),
    ?assertMatch(
        #partition{
            name = "phy_init",
            type = 16#01,
            subtype = 16#01,
            offset = 16#f000,
            size = 16#1000,
            encrypted = false,
            readonly = false,
            entry_num = 2
        },
        PHY_rec
    ),
    ?assertMatch(
        #partition{
            name = "factory",
            type = 16#00,
            subtype = 16#00,
            offset = 16#10000,
            size = 16#1C0000,
            encrypted = false,
            readonly = false,
            entry_num = 3
        },
        APP_rec
    ),
    ?assertMatch(
        #partition{
            name = "boot.avm",
            type = 16#01,
            subtype = 16#01,
            offset = 16#1D0000,
            size = 16#40000,
            encrypted = false,
            readonly = false,
            entry_num = 4
        },
        BOOT_rec
    ),
    ?assertMatch(
        #partition{
            name = "main.avm",
            type = 16#01,
            subtype = 16#01,
            offset = 16#210000,
            size = 16#100000,
            encrypted = false,
            readonly = false,
            entry_num = 5
        },
        MAIN_rec
    ).
