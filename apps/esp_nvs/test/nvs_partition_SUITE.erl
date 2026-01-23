%% nvs_partition_SUITE
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

-module(nvs_partition_SUITE).
-include("esp_nvs.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-ifdef(TEST).
-compile(export_all).
-endif.

all() ->
    [
        nvs_page_encode_insert,
        nvs_page_crc32,
        nvs_page_encode_entry_binary,
        nvs_csv_read_entries,
        nvs_page_verify_entry_bitmap,
        nvs_cli_functions,
        run_eunits
    ].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.
init_per_testcase(_TestCase, Config) -> Config.
end_per_testcase(_TestCase, _Config) -> ok.

run_eunits(_Config) ->
    ok = eunit:test({nvs_csv_tests, nvs_csv_read_entries_test}),
    ok = eunit:test({nvs_page_tests, nvs_page_crc32_test}),
    ok = eunit:test({nvs_page_tests, nvs_page_encode_entry_test}),
    ok = eunit:test({nvs_page_tests, nvs_page_insert_test}).

nvs_page_encode_insert(_Config) ->
    {ok, {readonly, {Page, NumPages}}} = nvs_page:init(16#2000),
    ?assertMatch(2, NumPages),
    {NameSpace, Idx} = nvs_entry:encode(<<"namespace">>, namespace, undefined, undefined, 0),
    {Entry, _} = nvs_entry:encode(<<"test">>, data, binary, <<"42">>, Idx),
    [Page0] = nvs_page:insert_entries([NameSpace, Entry], Page, []),
    ?assertEqual(192, Page0#page.offset),
    HeaderOffset = 64,
    <<_Pre:HeaderOffset/binary, Written:128/binary, _Rest/binary>> = Page0#page.page_buf,
    ?assertEqual(<<NameSpace:32/binary, Entry:96/binary>>, Written).

nvs_page_crc32(_Config) ->
    NullCrc = 0,
    BinKey = nvs_entry:pad_key(<<"ssid">>),
    Value = <<"NETWORK_NAME">>,
    ValCrc = ecrc:crc32_le(Value),
    ?assertEqual(binary:decode_unsigned(<<16#f5, 16#e2, 16#a7, 16#f5>>, little), ValCrc),
    CrcBin = binary:encode_unsigned(ValCrc, little),
    Data =
        <<16#01, 16#42, 16#02, 16#00, NullCrc:1/unsigned-integer-unit:32, BinKey:16/binary, 16#0c,
            16#00, 16#ff, 16#ff, CrcBin:4/binary>>,
    CRC = nvs_entry:compute_crc32_for_header(Data),
    ?assert(is_integer(CRC)),
    ExpectedCRC = binary:decode_unsigned(<<16#a6, 16#84, 16#56, 16#c8>>, little),
    ?assertEqual(ExpectedCRC, CRC).

nvs_page_encode_entry_binary(_Config) ->
    Key = <<"bar">>,
    Type = data,
    Encoding = binary,
    Value = <<"baz">>,
    NsIdx = 1,
    {Bin, NsIdx} = nvs_entry:encode(Key, Type, Encoding, Value, NsIdx),
    %% Correct slice:
    <<_NS:8, _T:8, _Span:8, _Chunk:8, _CRC:1/unsigned-integer-unit:32, KeyField:16/binary,
        _ValueField:8/binary, ValueBin:32/binary, _FooterHead:4/binary,
        _CRCfoot:1/unsigned-integer-unit:32, KeyField:16/binary,
        _Val:8/binary>> =
        Bin,
    Pad = binary:copy(<<16#ff>>, 29),
    ?assertEqual(<<"baz", Pad/binary>>, ValueBin).

nvs_csv_read_entries(Config) ->
    CsvContent =
        <<"#test file\r\nkey,type,encoding,value\r\nfoo,data,binary,21\r\nbar,data,binary,-792351273460494631\r\nbaz,data,binary,127\r\n">>,
    Filename = filename:join(?config(priv_dir, Config), "test_nvs.csv"),
    ok = file:write_file(Filename, CsvContent),
    try
        {ok, [E1, E2, E3]} = nvs_csv:read_file(Filename),
        ?assertEqual(foo, maps:get(key, E1)),
        ?assertEqual(data, maps:get(type, E1)),
        ?assertEqual(binary, maps:get(encoding, E1)),
        ?assertEqual(bar, maps:get(key, E2)),
        ?assertEqual(<<"127">>, maps:get(value, E3))
    after
        file:delete(Filename)
    end.

nvs_page_verify_entry_bitmap(_Config) ->
    {ok, {Page0, _}} = nvs_page:init(16#4000),
    {Bin1, 1} = nvs_entry:encode(<<"test">>, namespace, undefined, <<>>, 0),
    {ok, Page1} = nvs_page:insert_entry(Bin1, Page0),
    {Bin2, 1} = nvs_entry:encode(<<"key1">>, data, binary, <<"Hello ">>, 1),
    {ok, Page2} = nvs_page:insert_entry(Bin2, Page1),
    {Bin3, 1} = nvs_entry:encode(<<"key2">>, data, binary, <<"world.">>, 1),
    {ok, Page3} = nvs_page:insert_entry(Bin3, Page2),
    <<_Head:32/binary, Bitmap:32/little-binary, _Entries/binary>> =
        Page3#page.page_buf,
    Pad = binary:copy(<<16#ff>>, 30),
    ExpectBitmap = <<16#aa, 16#ea, Pad/binary>>,
    ?assertEqual(ExpectBitmap, Bitmap).

-record(config, {
    size = ?NVS_PARTITION_SIZE_DEFAULT :: pos_integer(),
    input_type :: file | device | undefined,
    input_path :: file:name_all(),
    verbosity = 0 :: 0..3,
    output_file :: file:name_all()
}).

nvs_cli_functions(Config) ->
    Out = filename:join(?config(priv_dir, Config), "nvs.bin"),
    CsvFile = filename:join(?config(priv_dir, Config), "nvs_partition.csv"),
    CsvContent =
        "key,type,encoding,value\ntest,namespace,,\nfoo,data,binary,21\nbar,data,binary,AtomVM NVS Test",
    try
        ?assertEqual(ok, efile:write(CsvFile, CsvContent, text)),

        Args = ["-q", "generate", CsvFile, Out, "0x6000"],
        {Cmd, Cfg} = nvs_cli:parse_cli_args(Args),
        ?assertEqual(generate, Cmd),
        ?assertEqual(true, is_record(Cfg, config)),
        ExpectCfg = #config{
            size = 24576, input_type = file, input_path = CsvFile, verbosity = 0, output_file = Out
        },
        ?assertEqual(ExpectCfg, Cfg),
        ?assertEqual(ok, nvs_cli:Cmd(Cfg)),
        {ok, NVS} = efile:read(Out),
        Sha1 = crypto:hash(sha, NVS),
        %% Expected sha1 calculated from nvs.bin generated with ESP-IDF nvs_partition_gen.py from same csv contents.
        Expected =
            <<26, 125, 59, 136, 86, 31, 228, 148, 232, 183, 28, 165, 60, 188, 126, 217, 61, 24, 238,
                29>>,
        ?assertEqual(Expected, Sha1)
    after
        file:delete(CsvFile),
        file:delete(Out)
    end.
