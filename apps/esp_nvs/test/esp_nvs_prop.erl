%% property tests for esp_nvs
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

-module(esp_nvs_prop).
-include_lib("proper/include/proper.hrl").

-ifdef(TEST).
-compile(export_all).
-endif.

%% --- Generators ---
entry() ->
    ?LET(
        {K, T, N},
        {nvs_key(), entry_type(), ns_idx()},
        {K, T, encoding(T), value(T), N}
    ).

nvs_key() ->
    ?LET(
        V,
        proper_types:non_empty(iolist()),
        no_null_bin(lists:flatten(V))
    ).

no_null_bin(Value) when is_list(Value) ->
    V = lists:filter(fun(N) -> N =/= 0 end, lists:flatten(Value)),
    Val = list_to_binary(V),
    case Val of
        <<>> -> <<"noname">>;
        _ -> Val
    end.

entry_type() ->
    proper_types:weighted_union([{5, data}, {1, namespace}]).

encoding(Type) ->
    case Type of
        namespace ->
            undefined;
        data ->
            binary
    end.

value(Type) ->
    case Type of
        data ->
            proper_types:weighted_union([{25, binary_data()}, {1, data_file()}]);
        namespace ->
            undefined
    end.

ns_idx() ->
    proper_types:choose(1, 254).

binary_data() ->
    ?LET(
        B,
        proper_types:non_empty(iodata()),
        iolist_to_binary(B)
    ).

data_file() ->
    Unique = integer_to_list(erlang:unique_integer([positive])),
    Basename = "_build/test/test_nvs_data" ++ Unique,
    {ok, Cwd} = file:get_cwd(),
    File = filename:join(Cwd, Basename),
    ?LET(
        Data,
        proper_types:non_empty(iodata()),
        case efile:write(File, Data, binary) of
            ok ->
                File;
            {error, Reason} ->
                error({file_write, {Reason, File}})
        end
    ).

%% --- Properties ---
prop_encode_entry() ->
    ?FORALL(
        {Key, Type, Encoding, Value, NsIdx},
        entry(),
        begin
            Bin =
                try
                    {Bin0, _NsIdx0} = nvs_entry:encode(Key, Type, Encoding, Value, NsIdx),
                    Bin0
                after
                    case filelib:is_file(Value) of
                        true ->
                            file:delete(Value);
                        false ->
                            ok
                    end
                end,
            is_binary(Bin) andalso (byte_size(Bin) rem 32) =:= 0
        end
    ).

prop_entry_crc_integrity() ->
    ?FORALL(
        {Key, Type, Encoding, Value, NsIdx},
        ?LET(
            {K, V, N},
            {nvs_key(), binary_data(), ns_idx()},
            {K, data, encoding(data), V, N}
        ),
        begin
            {Bin, _NsIdx0} = nvs_entry:encode(Key, Type, Encoding, Value, NsIdx),
            <<_NS:8, _Type:8, _Span:8, _Chunk:8, _CRC:32/little, _KeyField:16/binary,
                _ValueFieldHead:4/binary, ValCrc0:1/little-unsigned-integer-unit:32,
                _ValueRest/binary>> = Bin,
            ValCrc0 =:= erlang:crc32(16#ffffffff, Value)
        end
    ).

prop_encode_entry_type_checks() ->
    ?FORALL(
        {Key, Type, Encoding, Value, NsIdx},
        entry(),
        begin
            EncType =
                try
                    {Bin, _NsId0} = nvs_entry:encode(Key, Type, Encoding, Value, NsIdx),
                    <<_NsId:8, EncType0:1/binary, _Span:8, _Chunk:8, _CRC:32/little,
                        _KeyField:16/binary, _ValueField:8/binary, _ValueRest/binary>> = Bin,
                    EncType0
                after
                    case filelib:is_file(Value) of
                        true ->
                            file:delete(Value);
                        false ->
                            ok
                    end
                end,
            case Type of
                namespace ->
                    EncType =:= encoded_type(u8);
                _ ->
                    EncType =:= encoded_type(Encoding)
            end
        end
    ).

%% Helpers
encoded_type(E) ->
    case E of
        u8 -> <<16#01>>;
        binary -> <<16#42>>;
        bin_idx -> <<16#48>>;
        undefined -> <<16#ff>>
    end.
