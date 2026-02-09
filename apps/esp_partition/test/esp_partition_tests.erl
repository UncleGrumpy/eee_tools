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

-module(esp_partition_tests).
-include("esp_partition.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-ifdef(TEST).
-compile(export_all).
-endif.

-define(TEST_PAD_LEN, ?PARTITION_TABLE_MAX - byte_size(?TEST_TABLE_DATA)).
-define(TEST_TABLE_DATA,
    <<170, 80, 1, 2, 0, 144, 0, 0, 0, 96, 0, 0, 110, 118, 115, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 170, 80, 1, 1, 0, 240, 0, 0, 0, 16, 0, 0, 112, 104, 121, 95, 105, 110, 105,
        116, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 170, 80, 0, 0, 0, 0, 1, 0, 0, 0, 28, 0, 102, 97,
        99, 116, 111, 114, 121, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 170, 80, 1, 1, 0, 0, 29, 0,
        0, 0, 4, 0, 98, 111, 111, 116, 46, 97, 118, 109, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 170,
        80, 1, 1, 0, 0, 33, 0, 0, 0, 16, 0, 109, 97, 105, 110, 46, 97, 118, 109, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 235, 235, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
        255, 33, 129, 163, 117, 129, 89, 112, 168, 204, 220, 70, 215, 193, 88, 2, 166>>
).
-define(PART1,
    <<170, 80, 1, 2, 0, 144, 0, 0, 0, 96, 0, 0, 110, 118, 115, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0>>
).
-define(PART2,
    <<170, 80, 1, 1, 0, 240, 0, 0, 0, 16, 0, 0, 112, 104, 121, 95, 105, 110, 105, 116, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0>>
).
-define(PART3,
    <<170, 80, 0, 0, 0, 0, 1, 0, 0, 0, 28, 0, 102, 97, 99, 116, 111, 114, 121, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0>>
).
-define(PART4,
    <<170, 80, 1, 1, 0, 0, 29, 0, 0, 0, 4, 0, 98, 111, 111, 116, 46, 97, 118, 109, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0>>
).
-define(PART5,
    <<170, 80, 1, 1, 0, 0, 33, 0, 0, 0, 16, 0, 109, 97, 105, 110, 46, 97, 118, 109, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0>>
).
-define(TABLE, [
    #partition{
        name = "nvs",
        type = 1,
        subtype = 2,
        offset = 36864,
        size = 24576,
        encrypted = false,
        readonly = false,
        entry_num = 1
    },
    #partition{
        name = "phy_init",
        type = 1,
        subtype = 1,
        offset = 61440,
        size = 4096,
        encrypted = false,
        readonly = false,
        entry_num = 2
    },
    #partition{
        name = "factory",
        type = 0,
        subtype = 0,
        offset = 65536,
        size = 1835008,
        encrypted = false,
        readonly = false,
        entry_num = 3
    },
    #partition{
        name = "boot.avm",
        type = 1,
        subtype = 1,
        offset = 1900544,
        size = 262144,
        encrypted = false,
        readonly = false,
        entry_num = 4
    },
    #partition{
        name = "main.avm",
        type = 1,
        subtype = 1,
        offset = 2162688,
        size = 1048576,
        encrypted = false,
        readonly = false,
        entry_num = 5
    }
]).

is_partition_or_table_test() ->
    {Data, Pad} = {?TEST_TABLE_DATA, binary:copy(<<16#ff>>, ?TEST_PAD_LEN)},
    ?assertEqual({true, table}, esp_partition:is_partition_or_table(<<Data/binary, Pad/binary>>)),
    ?assertEqual({false, invalid}, esp_partition:is_partition_or_table(<<Data/binary>>)),
    ?assertEqual({false, invalid}, esp_partition:is_partition_or_table(binary:copy(<<16#00>>, 32))),
    ?assertEqual({true, partition}, esp_partition:is_partition_or_table(?PART1)),
    ?assertEqual({false, invalid}, esp_partition:is_partition_or_table(binary:part(?PART1, 0, 31))),
    ?assertEqual({true, partition}, esp_partition:is_partition_or_table(?PART2)),
    ?assertEqual({true, partition}, esp_partition:is_partition_or_table(?PART3)),
    ?assertEqual({true, partition}, esp_partition:is_partition_or_table(?PART4)),
    ?assertEqual({true, partition}, esp_partition:is_partition_or_table(?PART5)).

binary_to_table_test() ->
    {Data, Pad} = {?TEST_TABLE_DATA, binary:copy(<<16#ff>>, ?TEST_PAD_LEN)},
    ?assertEqual({ok, ?TABLE}, esp_partition:binary_to_table(<<Data/binary, Pad/binary>>)).

table_to_binary_test() ->
    {Data, Pad} = {?TEST_TABLE_DATA, binary:copy(<<16#ff>>, ?TEST_PAD_LEN)},
    {ok, Result} = esp_partition:table_to_binary(?TABLE, #partmap_config{}),
    ?assertEqual(byte_size(<<Data/binary, Pad/binary>>), byte_size(Result)),
    ?assertEqual(<<Data/binary, Pad/binary>>, Result),
    ?assertError(
        {flash_overflow, {_Size, 16#200000 = _Max}},
        esp_partition:table_to_binary(?TABLE, #partmap_config{flash_size = 16#200000})
    ).

get_info_test() ->
    {Data, Pad} = {?TEST_TABLE_DATA, binary:copy(<<16#ff>>, ?TEST_PAD_LEN)},
    ?assertEqual(
        {"nvs", nvs, 16#9000, 16#6000, []},
        esp_partition:get_info("nvs", <<Data/binary, Pad/binary>>)
    ),
    ?assertEqual(
        {"factory", {firmware, factory}, 16#10000, 16#1C0000, []},
        esp_partition:get_info("factory", <<Data/binary, Pad/binary>>)
    ),
    ?assertEqual(
        {"main.avm", phy, 16#210000, 16#100000, []},
        esp_partition:get_info("main.avm", <<Data/binary, Pad/binary>>)
    ),
    ?assertError(
        {no_partition, {name, "foo"}}, esp_partition:get_info("foo", <<Data/binary, Pad/binary>>)
    ).

partition_at_offset_test() ->
    {Data, Pad} = {?TEST_TABLE_DATA, binary:copy(<<16#ff>>, ?TEST_PAD_LEN)},
    ?assertEqual(
        {"main.avm", phy, 16#210000, 16#100000, []},
        esp_partition:partition_at_offset(16#210000, <<Data/binary, Pad/binary>>)
    ),
    ?assertEqual(
        {"nvs", nvs, 16#9000, 16#6000, []},
        esp_partition:partition_at_offset(16#9000, <<Data/binary, Pad/binary>>)
    ),
    ?assertError(
        {no_partition, {offset, 16#12000}},
        esp_partition:partition_at_offset(16#12000, <<Data/binary, Pad/binary>>)
    ).

verify_table_test() ->
    ?assertEqual(ok, esp_partition:verify_table(?TABLE, #partmap_config{})),
    ?assertMatch(
        {error, {flash_overflow, _PartInfo}},
        esp_partition:verify_table(?TABLE, #partmap_config{flash_size = 16#200000})
    ).

-dialyzer({nowarn_function, verify_table_error_test/0}).
verify_table_error_test() ->
    ?assertMatch(
        {error, {invalid_partition_table, {not_records_list, _Offender}}},
        esp_partition:verify_table(?TEST_TABLE_DATA, #partmap_config{})
    ).

list_test() ->
    {Data, Pad} = {?TEST_TABLE_DATA, binary:copy(<<16#ff>>, ?TEST_PAD_LEN)},
    ExpectResult = [
        {"nvs", nvs, 36864, 24576, []},
        {"phy_init", phy, 61440, 4096, []},
        {"factory", {firmware, factory}, 65536, 1835008, []},
        {"boot.avm", phy, 1900544, 262144, []},
        {"main.avm", phy, 2162688, 1048576, []}
    ],
    ?assertEqual(ExpectResult, esp_partition:list(<<Data/binary, Pad/binary>>)).
