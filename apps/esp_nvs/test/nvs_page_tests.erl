%% unit tests for nvs_page module
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

-module(nvs_page_tests).
-include_lib("eunit/include/eunit.hrl").
-include("esp_nvs.hrl").

-ifdef(TEST).
-compile(export_all).
-endif.

nvs_page_encode_entry_test() ->
    Key = <<"test">>,
    Type = data,
    Encoding = binary,
    Value = <<"-42">>,
    NsIdx = 1,
    Padding = binary:copy(<<16#ff>>, 29),
    PaddedVal = <<Value:3/binary, Padding:29/binary>>,
    {Bin, NsIdx} = nvs_entry:encode(Key, Type, Encoding, Value, NsIdx),
    ?assertEqual(96, byte_size(Bin)),
    <<NsIdx:1/unsigned-integer-unit:8, TypeCode:1/unsigned-integer-unit:8, _Span:1/binary,
        _ChunkIdx:1/binary, _CRC:4/binary, KeyField:16/binary, _ValueField:8/binary,
        WrittenVal:32/binary, _Footer:32/binary>> = Bin,
    ?assertEqual(16#42, TypeCode),
    KeyPadding = binary:copy(<<16#00>>, 16 - byte_size(Key)),
    ?assertEqual(<<Key:4/binary, KeyPadding:12/binary>>, KeyField),
    ?assertEqual(PaddedVal, WrittenVal).

nvs_page_crc32_test() ->
    HeadBegin = <<16#01, 16#42, 16#02, 16#00, 16#00, 16#00, 16#00, 16#00>>,
    Key =
        <<16#70, 16#73, 16#6b, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00,
            16#00, 16#00, 16#00>>,
    HeadData = <<16#08, 16#00, 16#ff, 16#ff, 16#0f, 16#fa, 16#2c, 16#69>>,
    CRC = nvs_entry:compute_crc32_for_header(
        <<HeadBegin:8/binary, Key:16/binary, HeadData:8/binary>>
    ),
    ?assert(is_integer(CRC)),
    ?assertEqual(binary:decode_unsigned(<<16#82, 16#1c, 16#a2, 16#91>>, little), CRC).

nvs_page_insert_test() ->
    {ok, {Page, _}} = nvs_page:init(16#6000),
    Key = <<"foo">>,
    Value = <<"AtomVM NVS TEST">>,
    NsIdx = 1,
    {Bin, NsIdx} = nvs_entry:encode(Key, data, binary, Value, NsIdx),
    {ok, Page2} = nvs_page:insert_entry(Bin, Page),
    %% Check buffer content and entry_num
    ?assertEqual(160, Page2#page.offset),
    EntryOffset = 64,
    <<_Pre:EntryOffset/binary, Written:96/binary, _Rest/binary>> = Page2#page.page_buf,
    ?assertEqual(Bin, Written).
