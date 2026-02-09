%% CSV parsing for NVS partition generator
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
%% @doc
%% Module to assist in decoding non-volatile storage csv files.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-module(nvs_csv).
-include("esp_nvs.hrl").

-export([
    read_file/1
]).

%%-------------------------------------------------------------------
%% @param File CSV file to be decoded
%% @doc Decode a non-volatile storage csv file
%%
%% Read a csv file and return a list of maps, describing the key-values to be stored in
%% non-volatile storage.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec read_file(file:name_all()) -> {ok, ParsedEntries :: esp_nvs:entry_list()}.
read_file(Filename) ->
    IDFheader = #{key => key, type => type, encoding => encoding, value => <<"value">>},
    case
        ecsv:decode_file(Filename, [{key, atom}, {type, atom}, {encoding, atom}, {value, binary}])
    of
        [] ->
            error({no_nvs_entries, Filename});
        [IDFheader | CsvData] ->
            {ok, CsvData};
        Data ->
            {ok, Data}
    end.
