%% unit tests for ecrc module
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

-module(ecrc_tests).
-include_lib("eunit/include/eunit.hrl").

-ifdef(TEST).
-compile(export_all).
-endif.

-define(TEST_DATA, <<
    16#01,
    16#42,
    16#02,
    16#00,
    16#66,
    16#6f,
    16#6f,
    16#00,
    16#00,
    16#00,
    16#00,
    16#00,
    16#00,
    16#00,
    16#00,
    16#00,
    16#00,
    16#00,
    16#00,
    16#00,
    16#02,
    16#00,
    16#ff,
    16#ff,
    16#b4,
    16#ab,
    16#51,
    16#43
>>).

crc32_le_test() ->
    Data = ?TEST_DATA,
    CRC = ecrc:crc32_le(Data),
    ?assertEqual(binary:decode_unsigned(<<16#af, 16#99, 16#25, 16#74>>, little), CRC).

eee_crc32_le_test() ->
    Data = ?TEST_DATA,
    CRC = ecrc:eee_crc32_le(Data, 16#00000000),
    ?assertEqual(binary:decode_unsigned(<<16#af, 16#99, 16#25, 16#74>>, little), CRC).
