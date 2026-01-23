%% esp_device_flash.erl
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
%% @doc This module relies on an installed `esptool.py' to dump partition tables and arbitrary
%% ranges from flash.
%%
%% This is hopefully a temporary workaround until pure Erlang modules can replace the `read_flash'
%% functionality provided by `esptool.py'.
%%
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-module(esp_device_flash).

-export([get_partition_table/4, read/6]).

%%-----------------------------------------------------------------------------
%% @param Esptool the full path to esptool.py
%% @param Port device port of attached esp32
%% @param TempFile location to save binary data
%% @param LogFile File to log esptool.py output to.
%% @returns Binary partition data
%% @doc Dump device partition table
%%
%% Dumps the partition table binary from the ESP32 device attached to `Port'
%% to the specified file. Output from `Esptool' is logged to `LogFile'.
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec get_partition_table(
    Esptool :: file:name_all(),
    Port :: file:name_all(),
    TempFile :: file:name_all(),
    LogFile :: file:name_all()
) ->
    PartitionData :: binary().
get_partition_table(Esptool, Port, TempFile, LogFile) ->
    read("0x8000", "0xC00", Esptool, Port, TempFile, LogFile).

%%-----------------------------------------------------------------------------
%% @param Begin Flash address to begin reading from
%% @param Size Size of flash partition to be read
%% @param Esptool the full path to esptool.py
%% @param Port device port of attached esp32
%% @param TempFile location to save binary data
%% @param LogFile File to log esptool.py output to.
%% @returns Binary partition data
%% @doc Read arbitrary device flash ranges
%%
%% Dumps the partition binary data of size 'Size' starting at address `Begin' from the ESP32 device
%% attached to `Port' to the specified `TempFile'. Output from `Esptool' is logged to `LogFile'.
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec read(
    Begin :: string() | non_neg_integer(),
    Size :: string() | non_neg_integer(),
    Esptool :: file:name_all(),
    Port :: file:name_all(),
    TempFile :: file:name_all(),
    LogFile :: file:name_all()
) ->
    PartitionData :: binary().
read(Begin, _Size, _Esptool, _Port, _TempFile, _LogFile) when is_integer(Begin) andalso Begin < 0 ->
    error({invalid_flash_address, Begin});
read(Begin, Size, Esptool, Port, TempFile, LogFile) when is_integer(Begin) ->
    read(integer_to_list(Begin), Size, Esptool, Port, TempFile, LogFile);
read(_Begin, Size, _Esptool, _Port, _TempFile, _LogFile) when is_integer(Size) andalso Size < 0 ->
    error({invalid_size, Size});
read(Begin, Size, Esptool, Port, TempFile, LogFile) when is_integer(Size) ->
    read(Begin, integer_to_list(Size), Esptool, Port, TempFile, LogFile);
read(Begin, Size, Esptool, Port, TempFile, LogFile) ->
    Offset =
        case eee_lib:parse_int_string(Begin) of
            {ok, Offset0} when Offset0 < 0 ->
                error({invalid_flash_address, Begin});
            {ok, Offset0} ->
                integer_to_list(Offset0);
            {error, Reason} ->
                error({invalid_flash_address, Reason})
        end,
    Length =
        case eee_lib:parse_int_string(Size) of
            {ok, Len} when Len < 0 ->
                error({invalid_size, Size});
            {ok, Len} ->
                integer_to_list(Len);
            {error, Reason0} ->
                error({invalid_size, Reason0})
        end,
    BaseArgs = ["read_flash", Offset, Length, TempFile],
    Args =
        case Port of
            "auto" ->
                BaseArgs;
            _ ->
                ["--port", Port | BaseArgs]
        end,

    try eee_lib:port_execute_log(Esptool, Args, LogFile) of
        ok -> ok;
        {ok, _} -> ok
    catch
        _:Reason1 -> error({esptool_failed, Reason1, {log_location, LogFile}})
    end,

    PartitionData =
        try efile:read(TempFile) of
            {ok, Data} ->
                Data;
            {error, Reason2} ->
                {error, Reason2}
        catch
            _:Error ->
                error({file_read, Error, {log_location, LogFile}})
        end,
    case PartitionData of
        {error, enoent} ->
            error({no_data_from_device, {log_location, LogFile}});
        {error, Reason3} ->
            error({file_read, Reason3, {log_location, LogFile}});
        PartitionData when is_binary(PartitionData) ->
            PartitionData
    end.
