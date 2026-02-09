%% esp_partition functions for working with ESP32 partitions
%% This is part of eee_tools
%% Based on: https://github.com/espressif/esp-idf/blob/master/components/partition_table/gen_esp32part.py
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
%%

%%-------------------------------------------------------------------
%% @doc ESP32 partition table - Core API
%%
%% Converts partition tables to/from CSV and binary formats.
%% This module provides the main API for working with ESP32 partition
%% tables and can be used as a library in other Erlang applications.
%%
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-module(esp_partition).
-include("esp_partition.hrl").

%% API functions
-export([
    binary_to_table/1,
    table_to_binary/2,
    list/1,
    get_info/2,
    partition_at_offset/2,
    is_partition_or_table/1,
    verify_table/2
]).

%% escript entry point
-export([main/1]).

%% Type definitions
-export_type([
    partition/0,
    table/0,
    config/0,
    fs_type/0,
    fs_flags/0,
    partition_info/0
]).

-type fs_type() ::
    {firmware,
        factory
        | ota_0
        | ota_1
        | ota_2
        | ota_3
        | ota_4
        | ota_5
        | ota_6
        | ota_7
        | ota_8
        | ota_9
        | ota_10
        | ota_11
        | ota_12
        | ota_13
        | ota_14
        | ota_15
        | test
        | tee_0
        | tee_1
        | {unknown, byte()}}
    | ota_data
    | phy
    | avm_app
    | nvs
    | coredump
    | nvs_keys
    | efuse
    | undefined
    | fatfs
    | spiffs
    | littlefs
    | {data, {unknown, byte()}}
    | {bootloader, primary | ota | recovery | {unknown, byte()}}
    | {partition_table, primary | ota | {unknown, byte()}}.
%% The type `avm_app' is not an esp-idf defined type, it is recognized as type 16#00, subtype 16#aa in custom partition tables.
-type fs_flags() :: [encrypted | readonly] | [].
-type partition() :: #partition{}.
-type table() :: [partition()].
-type config() :: #partmap_config{}.
-type partition_info() :: {
    Name :: string(),
    Type :: fs_type(),
    Offset :: non_neg_integer(),
    Size :: non_neg_integer(),
    Flags :: fs_flags()
}.

%%===================================================================
%% Escript entry point
%%===================================================================

%% @hidden
-spec main(Args :: string()) -> no_return().
main(Args) ->
    esp_partition_cli:main(Args).

%%===================================================================
%% API Functions
%%===================================================================

%%-----------------------------------------------------------------------------
%% @param BinData binary data to parse table data
%% @returns {ok, table()} or rases an error
%% @doc Parse binary partition table
%%
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec binary_to_table(BinData :: binary()) -> {ok, table()}.
binary_to_table(BinData) ->
    Partitions =
        try get_partition_records(BinData, crypto:hash_init(md5), []) of
            P -> P
        catch
            _:Reason ->
                error({decode_binary_table, Reason})
        end,
    {ok, Partitions}.

%%-----------------------------------------------------------------------------
%% @param Partitions is the `table()' data to encode
%% @param Config is a #partmap_config{} for the partition table
%% @returns {ok, binary()} or raises an error
%% @doc Convert partition table() to binary().
%%
%% The output is suitable for writing to a partitions.bin or flashing to a device.
%%
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec table_to_binary(Partitions :: table(), Config :: config()) ->
    {ok, binary()}.
table_to_binary(Partitions, Config) ->
    create(lists:reverse(Partitions), <<>>, Config).

%%-----------------------------------------------------------------------------
%% @param Filepath, partition binary or `t:table/0'
%% @returns list of partitions as info tuples or raises an error
%% @doc Get a list of tuples describing the binary partitions.
%%
%% The returned list will be a list of `t:partition_info/0'
%%
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec list(PartitionTable :: string() | binary() | table()) ->
    [partition_info()].
list([P | _] = Table) when is_record(P, partition) ->
    table_to_list(Table);
list(File) when is_list(File) ->
    Partitions =
        case efile:read(File) of
            {ok, Data} ->
                Data;
            {error, enoent} ->
                error(no_file);
            {error, Reason} ->
                error({file_read, Reason})
        end,
    list(Partitions);
list(Partitions) when is_binary(Partitions) ->
    Table = get_partition_records(Partitions, crypto:hash_init(md5), []),
    table_to_list(Table).

%%-----------------------------------------------------------------------------
%% @param Name of partition to retrieve info for
%% @param Data binary/0, filepath, or table/0 to search
%% @returns `t:partition_info/0' or raises an error
%% @doc Lookup partition info by name
%%
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec get_info(Name :: string(), Partition :: string() | binary() | table()) ->
    partition_info().
get_info(Name, [P | _] = Table) when is_record(P, partition) ->
    find_partition_by_name(Name, Table);
get_info(Name, File) when is_list(File) ->
    Partitions =
        case efile:read(File) of
            {ok, Data} ->
                Data;
            {error, enoent} ->
                error(no_partition_binary);
            {error, Reason} ->
                error({file_read, {Reason, File}})
        end,
    get_info(Name, Partitions);
get_info(Name, Partitions) when is_binary(Partitions) ->
    Table = get_partition_records(Partitions, crypto:hash_init(md5), []),
    find_partition_by_name(Name, Table).

%%-----------------------------------------------------------------------------
%% @param Offset is the location of the partition to lookup its name
%% @param Data binary/0, filepath, or table/0 to search
%% @returns `t:partition_info/0' or raises an error
%% @doc Lookup partition info for a given offset.
%%
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec partition_at_offset(Offset :: non_neg_integer(), Partition :: string() | binary()) ->
    partition_info().
partition_at_offset(Offset, [P | _] = Table) when is_record(P, partition) ->
    find_partition_by_offset(Offset, Table);
partition_at_offset(Offset, File) when is_list(File) ->
    Partitions =
        case efile:read(File) of
            {ok, Data} ->
                Data;
            {error, enoent} ->
                error(no_partition_binary);
            {error, Reason} ->
                error({file_read, {Reason, File}})
        end,
    partition_at_offset(Offset, Partitions);
partition_at_offset(Offset, Partitions) when is_binary(Partitions) ->
    Table = get_partition_records(Partitions, crypto:hash_init(md5), []),
    find_partition_by_offset(Offset, Table).

%%-----------------------------------------------------------------------------
%% @param Data the filepath to binary partition table or single binary partition entry to verify
%% @returns {IsValid :: boolean(), Kind :: partition | table} | {false, invalid} or raises an error
%% @doc Verify if file or binary data is a partition, or table
%%
%% This can be used to verify if a binary represents a valid partition, or a given file is a
%% partition table. Typically the return will be `{Valid :: boolean(), partition | table}', but
%% `{false, invalid}' is returned if the `Data' is not a binary or path to a csv file. If an error
%% is encountered while opening a csv file an error will be raised.
%%
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec is_partition_or_table(Data :: string() | <<_:256>>) ->
    {boolean(), partition | table | invalid}.
is_partition_or_table(Data) when is_binary(Data) ->
    case {binary:part(Data, {0, 2}) =:= <<16#aa, 16#50>>, byte_size(Data)} of
        {false, _} ->
            {false, invalid};
        {true, 32} ->
            {true, partition};
        {true, TableSize} when TableSize =:= ?PARTITION_TABLE_MAX ->
            {true, table};
        {true, _} ->
            {false, invalid}
    end;
is_partition_or_table(FilePath) when is_list(FilePath) ->
    case file:read_file(FilePath) of
        {ok, Data} ->
            {byte_size(Data) >= 32 andalso binary:part(Data, {0, 2}) =:= <<16#aa, 16#50>>, table};
        {error, Reason} ->
            error({csv_file_access, Reason})
    end;
is_partition_or_table(_Data) ->
    {false, invalid}.

%%-----------------------------------------------------------------------------
%% @param Partitions is the `t:table()' data to verify
%% @returns ok | {error, Reason}
%% @doc Verify partition table integrity
%%
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec verify_table(Partitions :: table(), Config :: config()) -> ok | {error, Reason :: any()}.
verify_table(Partitions, Config) when is_list(Partitions) ->
    try
        lists:foreach(fun(P) -> verify_record(P, Config) end, Partitions),
        check_duplicate_names(Partitions),
        check_overlaps(Partitions, Config),
        check_otadata(Partitions),
        ok
    catch
        _:Error -> {error, Error}
    end;
verify_table(Partitions, _Config) ->
    {error, {invalid_partition_table, {not_records_list, Partitions}}}.

%%===================================================================
%% Internal Functions
%%===================================================================

-spec create(Partitions :: table(), TableData :: binary(), Config :: config()) ->
    {ok, binary()}.
create([], TableData, Config) ->
    case Config#partmap_config.md5sum of
        true ->
            Md5 = crypto:hash(md5, TableData),
            ChecksumRecord =
                <<16#eb, 16#eb, 16#ff, 16#ff, 16#ff, 16#ff, 16#ff, 16#ff, 16#ff, 16#ff, 16#ff,
                    16#ff, 16#ff, 16#ff, 16#ff, 16#ff, Md5/binary>>,
            Table = <<TableData/binary, ChecksumRecord/binary>>,
            PaddingSize = ?PARTITION_TABLE_MAX - byte_size(Table),
            case PaddingSize of
                Size when Size > 0 ->
                    {ok, <<Table/binary, (binary:copy(<<16#ff>>, PaddingSize))/binary>>};
                0 ->
                    {ok, <<Table/binary>>};
                _ ->
                    error({partition_table_overflow, {entry_size, byte_size(Table)}})
            end;
        false ->
            PaddingSize = ?PARTITION_TABLE_MAX - byte_size(TableData),
            case PaddingSize of
                Size when Size > 0 ->
                    {ok, <<TableData/binary, (binary:copy(<<16#ff>>, PaddingSize))/binary>>};
                0 ->
                    {ok, <<TableData/binary>>};
                _ ->
                    error({partition_table_overflow, {entry_size, byte_size(TableData)}})
            end
    end;
create([P | Partitions], TableData, Config) ->
    Part = partition_to_binary(P, Config),
    create(Partitions, <<Part:32/binary, TableData/binary>>, Config).

get_partition_records(<<>>, _Md5, _Acc) ->
    error({decode_error, "Partition table is missing an end-of-table marker"});
get_partition_records(BinData, _Md5, _Acc) when byte_size(BinData) < 32 ->
    error({decode_error, "Partition table length must be a multiple of 32 bytes"});
get_partition_records(<<Data:32/binary, Rest/binary>>, Md5, Acc) ->
    case is_end_marker(Data) of
        true ->
            lists:reverse(Acc);
        false ->
            case is_md5_record(Data) of
                true ->
                    StoredMd5 = binary:part(Data, {16, 16}),
                    ComputedMd5 = crypto:hash_final(Md5),
                    case StoredMd5 of
                        ComputedMd5 ->
                            get_partition_records(Rest, crypto:hash_init(md5), Acc);
                        _ ->
                            error(
                                {md5_mismatch, to_hex_string(ComputedMd5), to_hex_string(StoredMd5)}
                            )
                    end;
                false ->
                    NewMd5 = crypto:hash_update(Md5, Data),
                    Partition = record_from_partition_bin(Data, length(Acc) + 1),
                    get_partition_records(Rest, NewMd5, [Partition | Acc])
            end
    end.

-spec is_end_marker(Data :: binary()) -> boolean().
is_end_marker(Data) ->
    Data =:= binary:copy(<<16#ff>>, 32).

is_md5_record(
    <<16#eb, 16#eb, 16#ff, 16#ff, 16#ff, 16#ff, 16#ff, 16#ff, 16#ff, 16#ff, 16#ff, 16#ff, 16#ff,
        16#ff, 16#ff, 16#ff, _Checksum:16/binary>>
) ->
    true;
is_md5_record(_) ->
    false.

-spec record_from_partition_bin(Binary :: <<_:256>>, LineNo :: 1..255) -> Partition :: partition().
record_from_partition_bin(Binary, LineNo) ->
    Partition =
        case Binary of
            <<16#aa, 16#50, Type:1/binary, SubType:1/binary, Offset:4/binary, Size:4/binary,
                NameBin:16/binary, Flags:4/binary>> ->
                Name = binary_to_list(binary:part(NameBin, {0, find_null_terminator(NameBin, 0)})),
                Flags0 = binary:decode_unsigned(Flags, little),
                #partition{
                    name = Name,
                    type = binary:decode_unsigned(Type, little),
                    subtype = binary:decode_unsigned(SubType, little),
                    offset = binary:decode_unsigned(Offset, little),
                    size = binary:decode_unsigned(Size, little),
                    encrypted = (Flags0 band (1 bsl 0)) =/= 0,
                    readonly = (Flags0 band (1 bsl 1)) =/= 0,
                    entry_num = LineNo
                };
            _ ->
                error({invalid_partition_data, Binary})
        end,
    Partition.

-spec partition_to_binary(P :: #partition{}, Config :: config()) -> <<_:256>>.
partition_to_binary(#partition{} = P, Config) ->
    NameBin = list_to_binary(P#partition.name),
    %% Partition names are limited to 16 bytes, including a NULL byte.
    Size = byte_size(NameBin),
    case Size > 15 of
        true -> error({"Partition name length limit 15 exceeded", P#partition.name});
        false -> ok
    end,
    Padding = binary:copy(<<0>>, 16 - Size),
    PaddedNameBin =
        <<NameBin:Size/binary, Padding/binary>>,
    FlagsInt =
        (case P#partition.encrypted of
            true -> 1 bsl 0;
            false -> 0
        end) bor
            (case P#partition.readonly of
                true -> 1 bsl 1;
                false -> 0
            end),
    Type = P#partition.type,
    Subtype = P#partition.subtype,
    Offset = P#partition.offset,
    PartSize = P#partition.size,
    NewEnd = Offset + PartSize,
    case NewEnd =< Config#partmap_config.flash_size of
        false ->
            error({flash_overflow, {NewEnd, Config#partmap_config.flash_size}});
        true ->
            <<16#aa50:16, Type:1/little-unsigned-integer-unit:8,
                Subtype:1/little-unsigned-integer-unit:8, Offset:4/little-unsigned-integer-unit:8,
                PartSize:4/little-unsigned-integer-unit:8, PaddedNameBin:16/binary,
                FlagsInt:4/little-unsigned-integer-unit:8>>
    end.

-spec table_to_list(Table :: table()) -> Partitions :: [partition_info()].
table_to_list(Table) ->
    table_to_list(Table, []).

-spec table_to_list(Table :: table(), Acc :: [partition_info()] | []) ->
    Partitions :: [partition_info()].
table_to_list([], Acc) ->
    lists:reverse(Acc);
table_to_list([Partition | Table], Acc) ->
    table_to_list(Table, [get_partition_info(Partition) | Acc]).

-spec get_partition_info(Partition :: partition()) -> partition_info().
get_partition_info(Partition) ->
    {
        Partition#partition.name,
        decode_partition_type(Partition),
        Partition#partition.offset,
        Partition#partition.size,
        flags_from_record(Partition)
    }.

-spec find_partition_by_offset(Offset :: non_neg_integer(), TableData :: table() | []) ->
    partition_info().
find_partition_by_offset(Offset, []) ->
    error({no_partition, {offset, Offset}});
find_partition_by_offset(Offset, [#partition{offset = Address} = Partition | TableData]) ->
    case Address of
        Offset ->
            get_partition_info(Partition);
        _ ->
            find_partition_by_offset(Offset, TableData)
    end.

-spec find_partition_by_name(Name :: string(), TableData :: table() | []) -> partition_info().
find_partition_by_name(Name, []) ->
    error({no_partition, {name, Name}});
find_partition_by_name(FindName, [#partition{name = Name} = Partition | TableData]) ->
    case Name of
        FindName ->
            get_partition_info(Partition);
        _ ->
            find_partition_by_name(FindName, TableData)
    end.

% @hidden
-spec decode_partition_type(PartitionRecord :: partition()) -> fs_type().
decode_partition_type(#partition{type = 16#00, subtype = SubType} = _PartitionRecord) ->
    case SubType of
        16#00 -> {firmware, factory};
        16#10 -> {firmware, ota_0};
        16#11 -> {firmware, ota_1};
        16#12 -> {firmware, ota_2};
        16#13 -> {firmware, ota_3};
        16#14 -> {firmware, ota_4};
        16#15 -> {firmware, ota_5};
        16#16 -> {firmware, ota_6};
        16#17 -> {firmware, ota_7};
        16#18 -> {firmware, ota_8};
        16#19 -> {firmware, ota_9};
        16#1a -> {firmware, ota_10};
        16#1b -> {firmware, ota_11};
        16#1c -> {firmware, ota_12};
        16#1d -> {firmware, ota_13};
        16#1e -> {firmware, ota_14};
        16#1f -> {firmware, ota_15};
        16#20 -> {firmware, test};
        16#30 -> {firmware, tee_0};
        16#31 -> {firmware, tee_1};
        Byte -> {firmware, {unknown, Byte}}
    end;
decode_partition_type(#partition{type = 16#01, subtype = SubType} = _PartitionRecord) ->
    case SubType of
        16#00 -> ota_data;
        16#01 -> phy;
        16#aa -> avm_app;
        16#02 -> nvs;
        16#03 -> coredump;
        16#04 -> nvs_keys;
        16#05 -> efuse;
        16#06 -> undefined;
        16#81 -> fatfs;
        16#82 -> spiffs;
        16#83 -> littlefs;
        Byte -> {data, {unknown, Byte}}
    end;
decode_partition_type(#partition{type = 16#02, subtype = SubType} = _PartitionRecord) ->
    case SubType of
        16#00 -> {bootloader, primary};
        16#01 -> {bootloader, ota};
        16#02 -> {bootloader, recovery};
        Byte -> {bootloader, {unknown, Byte}}
    end;
decode_partition_type(#partition{type = 16#03, subtype = SubType} = _PartitionRecord) ->
    case SubType of
        16#00 -> {partition_table, primary};
        16#01 -> {partition_table, ota};
        Byte -> {partition_table, {unknown, Byte}}
    end.

-spec flags_from_record(Partition :: partition()) -> [encrypted | readonly] | [].
flags_from_record(Partition) ->
    Flag0 =
        case Partition#partition.encrypted of
            true -> [encrypted];
            false -> []
        end,
    case Partition#partition.readonly of
        true -> lists:flatten([readonly | Flag0]);
        false -> Flag0
    end.

find_null_terminator(Bin, Index) when Index >= byte_size(Bin) ->
    Index;
find_null_terminator(Bin, Index) ->
    case binary:at(Bin, Index) of
        0 -> Index;
        _ -> find_null_terminator(Bin, Index + 1)
    end.

verify_record(#partition{} = P, Config) ->
    case P#partition.type of
        undefined -> error({validation_error, P#partition.name, "Type field is not set"});
        _ -> ok
    end,
    case P#partition.subtype of
        undefined -> error({validation_error, P#partition.name, "Subtype field is not set"});
        _ -> ok
    end,
    case P#partition.offset of
        undefined -> error({validation_error, P#partition.name, "Offset field is not set"});
        _ -> ok
    end,
    case P#partition.size of
        undefined -> error({validation_error, P#partition.name, "Size field is not set"});
        _ -> ok
    end,

    OffsetAlign = get_alignment_offset(P#partition.type),
    case P#partition.offset rem OffsetAlign of
        0 ->
            ok;
        _ ->
            error(
                {validation_error, P#partition.name,
                    io_lib:format(
                        "Offset 0x~.16B is not aligned to 0x~.16B",
                        [P#partition.offset, OffsetAlign]
                    )}
            )
    end,

    case P#partition.type of
        16#00 ->
            SizeAlign = get_alignment_size(P#partition.type, Config),
            case P#partition.size rem SizeAlign of
                0 ->
                    ok;
                _ ->
                    error(
                        {validation_error, P#partition.name,
                            io_lib:format(
                                "Size 0x~.16B is not aligned to 0x~.16B",
                                [P#partition.size, SizeAlign]
                            )}
                    )
            end;
        _ ->
            ok
    end;
verify_record(BadArg, _Config) ->
    error({validation_error, bad_record, BadArg}).

check_duplicate_names(Partitions) ->
    Names = [P#partition.name || P <- Partitions],
    case length(Names) =:= length(lists:usort(Names)) of
        true ->
            ok;
        false ->
            Duplicates = Names -- lists:usort(Names),
            error({duplicate_partition_names, lists:usort(Duplicates)})
    end.

check_overlaps(Partitions, Config) ->
    Sorted = lists:sort(fun(A, B) -> A#partition.offset < B#partition.offset end, Partitions),
    check_overlaps(Sorted, Config, undefined).

check_overlaps([], _Config, _LastPartition) ->
    ok;
check_overlaps([P | Rest], Config, LastPartition) ->
    case P#partition.offset + P#partition.size > Config#partmap_config.flash_size of
        true -> error({flash_overflow, {P#partition.name, P#partition.offset + P#partition.size}});
        false -> ok
    end,
    PartTableEnd = Config#partmap_config.table_offset + ?PARTITION_TABLE_MAX,
    case P#partition.offset < PartTableEnd of
        true ->
            IsPrimaryBootloader =
                P#partition.type =:= 16#02 andalso P#partition.subtype =:= 16#00,
            IsPrimaryPartTable =
                P#partition.type =:= 16#03 andalso P#partition.subtype =:= 16#00,
            case IsPrimaryBootloader or IsPrimaryPartTable of
                false ->
                    error(
                        {partition_offset_below_table, P#partition.name, P#partition.offset,
                            PartTableEnd}
                    );
                true ->
                    ok
            end;
        false ->
            ok
    end,

    case LastPartition of
        undefined ->
            ok;
        _ when
            P#partition.offset <
                (LastPartition#partition.offset + LastPartition#partition.size)
        ->
            error(
                {partition_overlap, P#partition.name, P#partition.offset,
                    LastPartition#partition.name, LastPartition#partition.offset,
                    LastPartition#partition.offset + LastPartition#partition.size - 1}
            );
        _ ->
            ok
    end,

    check_overlaps(Rest, Config, P).

check_otadata(Partitions) ->
    OtaDataPartitions = [
        P
     || P <- Partitions,
        P#partition.type =:= 16#01 andalso P#partition.subtype =:= 16#00
    ],
    case length(OtaDataPartitions) > 1 of
        true ->
            error({multiple_otadata_partitions});
        false ->
            ok
    end,

    case OtaDataPartitions of
        [P] when P#partition.size =/= 16#2000 ->
            error({invalid_otadata_size, P#partition.name, P#partition.size});
        _ ->
            ok
    end.

get_alignment_offset(Type) ->
    case Type of
        16#00 -> 16#10000;
        16#01 -> 16#1000;
        16#02 -> 16#1000;
        16#03 -> 16#1000;
        _ -> 16#1000
    end.

get_alignment_size(Type, Config) ->
    case Type of
        16#00 ->
            case Config#partmap_config.secure of
                v1 -> 16#10000;
                v2 -> 16#1000;
                _ -> 16#1000
            end;
        _ ->
            16#1000
    end.

to_hex_string(Bin) ->
    lists:flatten([io_lib:format("~2.16.0b", [B]) || <<B>> <= Bin]).
