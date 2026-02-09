%% esp_nvs application entrypoint
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
%% Command-line interface entry point for esp_nvs escript and common
%% type definitions.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-module(esp_nvs).
-include("esp_nvs.hrl").

-export([main/1]).

-export_type([
    encoding/0,
    encoded_type/0,
    entry_key/0,
    entry_type/0,
    entry_value/0,
    entry_list/0,
    entry_map/0,
    version/0
]).

%% TODO: add support for all types, not just AtomVM supported ones.
-type encoding() ::
    u8 | binary | bin_idx | undefined.
-type encoded_type() :: 16#01 | 16#42 | 16#48 | 16#ff.
-type entry_key() :: atom() | binary().
-type entry_type() :: data | file | namespace.
-type entry_value() :: binary() | undefined.
-type version() :: <<_:8>>.
%% The version number is represented by: Version = 256 - VersionNumber.
%% Version `1' is encoded as `<<16#ff>>', version `2' as `<<16#fe>>'.

-type entry_list() :: [entry_map()].
-type entry_map() :: #{
    key => Key :: esp_nvs:entry_key(),
    type => Type :: esp_nvs:entry_type(),
    encoding => Encoding :: esp_nvs:encoding(),
    value => Value :: esp_nvs:entry_value()
}.
-spec main(Args :: [string()]) -> no_return().
main(Args) ->
    nvs_cli:main(Args).
