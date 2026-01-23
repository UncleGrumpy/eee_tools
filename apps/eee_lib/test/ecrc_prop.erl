%% property tests for ecrc
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

-module(ecrc_prop).
-include_lib("proper/include/proper.hrl").

-ifdef(TEST).
-compile(export_all).
-endif.

%% --- Generators ---

binary_string() ->
    ?LET(
        S,
        proper_types:non_empty(latin1_string_gen()),
        list_to_binary(S)
    ).

latin1_string_gen() ->
    ?SIZED(Size, vector(Size, integer(33, 126))).

%% --- Properties ---
prop_crc32_le_string() ->
    ?FORALL(
        Data,
        binary_string(),
        begin
            Crc32 = ecrc:eee_crc32_le(Data, 16#00000000),
            erlang:crc32(16#ffffffff, Data) =:= Crc32
        end
    ).

prop_crc32_le_binary() ->
    ?FORALL(
        Data,
        binary(),
        begin
            Crc32 = ecrc:eee_crc32_le(Data, 16#00000000),
            erlang:crc32(16#ffffffff, Data) =:= Crc32
        end
    ).
