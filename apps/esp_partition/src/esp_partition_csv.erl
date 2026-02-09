%% esp_partition_csv this module provides functions for encoding and decoding csv partition data.
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
%% SPDX-FileCopyrightText: 2025 Winford (Uncle Grumpy) <winford@object.stream>
%% SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later

%%-------------------------------------------------------------------
%% @doc ESP32 partition table - CSV APIs
%%
%% Converts partition tables to/from CSV and binary formats.
%% This module provides the main API for working with ESP32 partition
%% tables and can be used as a library in other Erlang applications.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-module(esp_partition_csv).
-include("esp_partition.hrl").

-export([
    table_from_csv_file/2,
    table_from_csv_data/2,
    encode_csv_table/1
]).

-type row() :: #{
    name => Name :: string(),
    type => Type :: string(),
    subtype => Subtype :: string(),
    offset => Offset :: string(),
    size => Size :: string(),
    flags => Flags :: string()
}.

%%===================================================================
%% API Functions
%%===================================================================

%%-----------------------------------------------------------------------------
%% @param FilePath file to read csv data from
%% @param Config
%% @returns {ok, Partitions}
%% @doc Read partition `t:esp_partition:table/0' from file (CSV or binary)
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec table_from_csv_file(FilePath :: file:name_all(), Config :: esp_partition:config()) ->
    {ok, Data :: esp_partition:table()}.
table_from_csv_file(FilePath, Config) ->
    try
        Lines = ecsv:decode_file(FilePath, [name, type, subtype, offset, size, flags]),
        case Lines of
            [] ->
                error(no_csv_data);
            _ ->
                table_from_csv_data(Lines, Config)
        end
    catch
        _:Error ->
            error({csv_file_error, Error})
    end.

%%-----------------------------------------------------------------------------
%% @param CsvData data string to parse table data
%% @returns {ok, [#partition{}]}
%% @doc Parse CSV content
%%
%% The returned `Partitions' is a list of `#partition{}' records.
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec table_from_csv_data(Lines :: [row()], Config :: esp_partition:config()) ->
    {ok, Lines :: esp_partition:table()}.
table_from_csv_data(Lines, Config) ->
    try
        case encode_csv_lines(Lines, []) of
            no_data ->
                error(no_data);
            Partitions0 ->
                Partitions1 = align_partition_offsets(Partitions0, Config),
                {ok, Partitions1}
        end
    catch
        _:Error -> error({csv_parse_error, Error})
    end.

%%-----------------------------------------------------------------------------
%% @param Partitions is the table() data to encode
%% @returns {ok, CsvString}
%% @doc Convert partition table to CSV format
%%
%%
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec encode_csv_table(Partitions :: esp_partition:table()) -> {ok, string()}.
encode_csv_table(Partitions) ->
    try
        Header =
            "# ESP-IDF Partition Table generated with eee_tools\n" ++
                "# Name, Type, SubType, Offset, Size, Flags\n",
        Rows = [partition_to_csv_string(P) || P <- Partitions],
        Csv = Header ++ string:join(Rows, "\n"),
        {ok, Csv}
    catch
        _:Error -> error({csv_encode_error, Error})
    end.

%%===================================================================
%% Internal Functions
%%===================================================================

%% Used to decode subtype from maps, maps are named as their decoded types
-define(SUBTYPES, #{
    %% bootloader subtypes
    16#02 => #{
        "primary" => 16#00,
        "recovery" => 16#02
    },
    %% partition table subtypes
    16#03 => #{
        "primary" => 16#00,
        "ota" => 16#01
    },
    %% app subtypes
    16#00 => #{
        "factory" => 16#00,
        "ota_0" => 16#10,
        "ota_1" => 16#11,
        "ota_2" => 16#12,
        "ota_3" => 16#13,
        "ota_4" => 16#14,
        "ota_5" => 16#15,
        "ota_6" => 16#16,
        "ota_7" => 16#17,
        "ota_8" => 16#18,
        "ota_9" => 16#19,
        "ota_10" => 16#1a,
        "ota_11" => 16#1b,
        "ota_12" => 16#1c,
        "ota_13" => 16#1d,
        "ota_14" => 16#1e,
        "ota_15" => 16#1f,
        "test" => 16#20
    },
    %% data subtypes
    16#01 => #{
        "ota" => 16#00,
        "phy" => 16#01,
        "nvs" => 16#02,
        "coredump" => 16#03,
        "nvs_keys" => 16#04,
        "efuse" => 16#05,
        "undefined" => 16#06,
        "esphttpd" => 16#80,
        "fat" => 16#81,
        "spiffs" => 16#82,
        "littlefs" => 16#83,
        "tee_ota" => 16#90,
        "atomvm_app" => 16#aa
    }
}).

-spec encode_csv_lines(Lines :: list(row()), Acc :: list(esp_partition:partition()) | []) ->
    EncodedCSV :: esp_partition:table() | no_data.
encode_csv_lines([], Acc) ->
    case Acc of
        [] ->
            no_data;
        _ ->
            lists:reverse(Acc)
    end;
encode_csv_lines([Line | Rest], Acc) ->
    Partition = encode_csv_line(Line, length(Acc) + 1),
    encode_csv_lines(Rest, [Partition | Acc]).

-spec encode_csv_line(Line :: row(), LineNo :: non_neg_integer()) -> esp_partition:partition().
encode_csv_line(Line, LineNo) ->
    {Encrypted, Readonly} = parse_flags(maps:get(flags, Line)),
    EncodedType = encode_partition_type(maps:get(type, Line)),
    EncodedSubType = encode_partition_subtype(maps:get(subtype, Line), EncodedType),
    EncodedOffset = encode_address(maps:get(offset, Line), EncodedType),
    EncodedSize = encode_size(maps:get(size, Line), EncodedType),

    #partition{
        name = maps:get(name, Line),
        type = EncodedType,
        subtype = EncodedSubType,
        offset = EncodedOffset,
        size = EncodedSize,
        encrypted = Encrypted,
        readonly = Readonly,
        entry_num = LineNo
    }.

align_partition_offsets(Partitions, Config) ->
    PartTableEnd = Config#partmap_config.table_offset + 16#1000,
    {Aligned, _LastEnd} = lists:foldl(
        fun(P, {Acc, LastEnd}) ->
            case P#partition.size of
                undefined ->
                    error({invalid_partition_size, P#partition.name});
                _ ->
                    ok
            end,
            P1 = align_partition_offset(P, LastEnd, Config),
            case P1#partition.offset of
                undefined -> error({invalid_partition_offset, P1#partition.name});
                _ -> ok
            end,
            {[P1 | Acc], P1#partition.offset + P1#partition.size}
        end,
        {[], PartTableEnd},
        Partitions
    ),
    lists:reverse(Aligned).

align_partition_offset(
    #partition{type = Type, offset = Offset, size = Size} = P, LastEnd, _Config
) ->
    IsBootloader =
        Type =:= 16#02,
    IsPartTable =
        Type =:= 16#03,

    case IsBootloader orelse IsPartTable of
        true ->
            % Don't modify bootloader or partition table.
            % By default these do not appear in the partitions.csv file, only for builds with
            % custom bootloaders that may require configuring these partitions in the csv file, in
            % which case we need the offsets and sizes explicitly set.
            case undefined =:= Size orelse undefined =:= Offset of
                true ->
                    error("Size and offset required for bootloader or partition table");
                false ->
                    P
            end;
        false ->
            NewOffset =
                case Offset of
                    undefined ->
                        BlockEnd = get_alignment_size(Type),
                        case LastEnd rem BlockEnd of
                            0 -> LastEnd;
                            Pad -> LastEnd + (BlockEnd - Pad)
                        end;
                    _ ->
                        Offset
                end,

            P#partition{offset = NewOffset}
    end.

partition_to_csv_string(#partition{} = P) ->
    TypeStr = lookup_type_keyword(P#partition.type),
    SubTypeStr = lookup_subtype_keyword(P#partition.subtype, P#partition.type),
    OffsetStr = format_address(P#partition.offset),
    SizeStr = format_address(P#partition.size),
    FlagsStr = format_flags(P#partition.encrypted, P#partition.readonly),

    string:join(
        [
            P#partition.name,
            TypeStr,
            SubTypeStr,
            OffsetStr,
            SizeStr,
            FlagsStr
        ],
        ","
    ).

format_address(Addr) when is_integer(Addr) ->
    "0x" ++ integer_to_list(Addr, 16);
format_address(undefined) ->
    "".

-spec format_flags(Encrypted :: boolean(), Readonly :: boolean()) -> string().
format_flags(Encrypted, Readonly) ->
    Flags = [],
    Flags1 =
        case Encrypted of
            true -> ["encrypted" | Flags];
            false -> Flags
        end,
    Flags2 =
        case Readonly of
            true -> ["readonly" | Flags1];
            false -> Flags1
        end,
    case Flags2 of
        [] ->
            "";
        _ ->
            string:join(lists:reverse(Flags2), ":")
    end.

encode_partition_type(Type) ->
    case string:lowercase(Type) of
        "bootloader" ->
            16#02;
        "partition_table" ->
            16#03;
        "app" ->
            16#00;
        "data" ->
            16#01;
        _ ->
            case eee_lib:parse_int_string(Type) of
                {ok, Int} -> Int;
                {error, _} -> error({invalid_partition_type, Type})
            end
    end.

-spec encode_partition_subtype(SubType :: string(), Type :: non_neg_integer()) ->
    EncodedSubType :: non_neg_integer().
encode_partition_subtype(SubType, Type) ->
    case string:lowercase(SubType) of
        "" when Type =:= 16#00 ->
            error({parse_error, "App partition cannot have an empty subtype"});
        "" when Type =:= 16#01 ->
            % undefined
            16#06;
        "" ->
            error({parse_error, "Partition subtype is required for this type"});
        S ->
            try get_subtype_value(S, Type) of
                Found when is_integer(Found) ->
                    Found;
                {error, Reason} ->
                    case eee_lib:parse_int_string(S) of
                        {ok, Int} -> Int;
                        {error, _} -> error({encode_error, Reason})
                    end
            catch
                _:Exception ->
                    error({encode_error, Exception})
            end
    end.

-spec encode_address(Addr :: string(), Type :: non_neg_integer()) ->
    Address :: non_neg_integer() | undefined.
encode_address(Addr, Type) when Addr =:= "" ->
    case Type of
        16#02 -> undefined;
        % default offset
        16#03 -> 16#8000;
        _ -> undefined
    end;
encode_address(Addr, _Type) ->
    case eee_lib:parse_int_string(Addr) of
        {ok, Addr0} ->
            Addr0;
        {error, no_integer} ->
            undefined;
        {error, Reason} ->
            error({invalid_offset, {Addr, Reason}})
    end.

-spec encode_size(SizeStr :: string(), Type :: non_neg_integer()) ->
    Size :: non_neg_integer() | undefined.
encode_size(SizeStr, Type) when SizeStr =:= "" ->
    case Type of
        16#02 -> 16#1000;
        16#03 -> 16#1000;
        _ -> undefined
    end;
encode_size(SizeStr, _Type) ->
    case eee_lib:parse_int_string(SizeStr) of
        {ok, Size} ->
            Size;
        {error, Reason} ->
            error({invalid_size, {SizeStr, Reason}})
    end.

-spec parse_flags(FlagStr :: string()) -> Flags :: {Encrypted :: boolean(), ReadOnly :: boolean()}.
parse_flags(FlagStr) ->
    case FlagStr of
        undefined ->
            {false, false};
        FlagStr when is_list(FlagStr) ->
            Flags = string:split(FlagStr, ":", all),
            {lists:member("encrypted", Flags), lists:member("readonly", Flags)};
        _ ->
            error({unrecognized_flag, FlagStr})
    end.

-spec get_subtype_value(SubType :: string(), Type :: non_neg_integer()) ->
    EncodedSubtype :: non_neg_integer() | {error, Reason :: term()}.
get_subtype_value(SubType, Type) ->
    SubTypes = ?SUBTYPES,
    case maps:get(Type, SubTypes, undefined) of
        undefined ->
            {error, {invalid_type, Type}};
        SubTypeMap ->
            maps:get(SubType, SubTypeMap, {error, {invalid_subtype, SubType}})
    end.

-spec lookup_type_keyword(Type :: byte()) -> TypeKeyword :: string().
lookup_type_keyword(Type) ->
    case Type of
        16#02 -> "bootloader";
        16#03 -> "partition_table";
        16#00 -> "app";
        16#01 -> "data";
        _ -> integer_to_list(Type)
    end.

lookup_subtype_keyword(SubType, Type) ->
    SubTypes = ?SUBTYPES,
    SubTypeMap = maps:get(Type, SubTypes, #{}),
    case lists:keyfind(SubType, 2, maps:to_list(SubTypeMap)) of
        {Name, _} -> Name;
        false -> integer_to_list(SubType)
    end.

-spec get_alignment_size('undefined' | byte()) -> Alignment :: 16#10000 | 16#1000.
get_alignment_size(Type) ->
    case Type of
        16#00 -> 16#10000;
        16#01 -> 16#1000;
        16#02 -> 16#1000;
        16#03 -> 16#1000;
        _ -> 16#1000
    end.
