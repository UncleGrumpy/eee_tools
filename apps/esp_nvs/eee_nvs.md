<!--
 Copyright 2025 Winford <winford@object.stream>

SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
-->

# esp_nvs

An escript and library for working with ESP32 Non-Volatile Storage partitions.

This tool currently supports manipulating version 2 format NVS partitions. Encryption is not
(_yet_) supported.

## The NVS partition

The non-volatile storage partition is divided into 4096-byte sized pages, header and page state
consume 64 bytes per page. One page is always kept free for swap. AtomVM uses an NVS partition size
of 24 kilobytes, leaving 20 kilobytes free for storing key-value pairs in non-volatile storage.

## Keys and namespaces

Key-value pairs are always stored under a namespace, only one is required, but as many as 254
different namespaces may be used. Keep in mind that each namespace entry will consume 32 bytes of
non-volatile storage space. Each `key` name is limited to 15 characters, and `t:binary` `values`
are limited to 4000 bytes for version 2 NVS (the default for `f:nvs_page:init/1`), or 1984 bytes
for version 1. AtomVM users should also note that the `atomvm` namespace is reserved, it should
only be used to store the following keys (other internal keys may be added in the future):

_nvs.csv example file:_

```csv
## First row, following any comments, is the column header
key,type,encoding,value
## First entry is a namespace
atomvm,namespace,,
## keys in the atomvm namespace
dev_mode,data,binary,
boot_path,data,binary,/dev/partition/by-name/main.avm
start_module,data,binary,your_app_start_module
## optional atomvm keys for dev_mode:
sta_ssid,data,binary,`networkname`
sta_psk,data,binary,`password`
```

Notice that the first line of the nvs.csv file (you can use any filename you choose this is just
for example purposes) is the columns header. The header is not commented out, unlike some other csv
files used by the ESP-IDF. The first entry of the csv file should be a namespace, followed by keys
in that namespace. All keys in a namespace should be grouped together in the csv file, the behavior
when a namespace is used more than once in the csv file is undefined, and will likely result in
some of the keys being inaccessible at runtime.

All other keys should be in a different namespace:

<!-- markdownlint-disable-next-line MD036 -->
_nvs.csv example file (continued)_

```csv
...
network,namespace,,
credentials,file,binary,/path/to/secrets
features,namespace,,
level,data,binary,11
flopper,data,binary,enabled
flipper,data,binary,quirky_mode
logger,namespace,,
level,data,binary,info
```

To use a custom `boot_path` change the `main.avm` at the end of the path to your custom boot
partition name. The `start_module` can be any module that exposes a `start/0` function to specify
an entrypoint other than the default. The `dev_mode` option can be set to `always` to bypass any
flashed application and enter dev mode, which will open an `arepl` console on port 2323 and a web
interface on port 8080. Dev mode looks for WiFi credentials `sta_ssid` and `sta_psk` in the
`atomvm` namespace, `dev_mode` also stores several other keys in the `atomvm` namespace (if you are
curious you can read the `dev_mode` code).

Notice that the same key, in this example `level` may be used in more than one namespace. In
addition to using provided values for keys, the key can be set to the contents of an external file.
The value for the `credentials` key in the example above is set to the contents of the file
`/path/to/secrets`.

This tool (and AtomVM) currently supports only binary-encoded values, which consume a minimum of 96
bytes per entry. All entries are padded to 32-byte aligned blocks, each key that holds a binary
value uses 2 32-byte blocks for header and index (footer), if the value stored is larger than 32
bytes, more blocks will be used to store the data. The use of large values is more efficient for
NVS storage space consumption. A single byte of data will still require 96 bytes of NVS flash
space. In contrast, a large data structure of 256 bytes will consume a total of 320 bytes. This is
80% efficiency in the use of storage space vs 1.04% for a single byte. Retrieving and storing
__very__ large key values (up to 4000 bytes) will consume more RAM and take slightly longer than
smaller values that fit in a single 32-byte block, so a balance should be found that best suits the
applications needs.

Terms read from csv files are treated as binary `<<"strings">>`. Both `esp_nvs` and Espressif's
`nvs_partition_gen.py` require that there be __no whitespace after commas__ (`,`),
__or at the end of each line__. The ESP-IDF `nvs_partition_gen.py` tool also requires there be no
empty line at the end of the csv file, the `esp_nvs` tool will tolerate a newline at the end of the
file. __The first entry after the heading should always be a namespace.__

## Examples

Example csv file:

```csv
key,type,encoding,value
test,namespace,,
foo,data,binary,21
bar,data,binary,AtomVM NVS Test
```

Will yield the following key values in the `test` namespace:

<!-- tabs-open -->

### Erlang

```erlang
    Key = <<"foo">>, Value = <<"21">>.
    Key = <<"bar">>, Value = <<"AtomVM NVS Test">>.
```

### Elixir

```elixir
    key = "foo", value = "21"
    key = "bar", value = "AtomVM NVS Test"
```

<!-- tabs-close -->

Of course, integer values stored in csv files can be used as is (a binary character
representation), or turned into integers with `binary_to_integer/1,2`.

>For more details see Espressif's documentation about
>[Non-Volatile Storage](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/storage/nvs_flash.html)
>And for reference the documentation for
>[nvs_partition_gen.py](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/storage/nvs_partition_gen.html),
>Espressif's original python implementation of this tool.

## Build

From the top-level eee_tools directory:

```console
$ rebar3 escriptize -a esp_nvs
===> Verifying dependencies...
===> Analyzing applications...
===> Compiling eee_lib
===> Compiling esp_partition
===> Compiling esp_nvs
===> Compiling eee_tools
===> Building escript for esp_nvs...
```

The escript will be built in the `_build` directory in `_build/default/bin`.

## `esp_nvs` Escript Usage

After building the `esp_nvs` escript an NVS partition can be created with the following command:

```console
$ _build/default/bin/esp_nvs generate /path/to/input/nvs.csv /path/to/output/nvs.bin 0x6000
===> Wrote NVS binary to /path/to/output/nvs.bin.

```

By adding a `-v` or `--verbose` option you can increase the verbosity, this may be repeated, or
use `-vv` to get very verbose debug logging.

```console
$ _build/default/bin/esp_nvs -v generate /path/to/input/nvs.csv /path/to/output/nvs.bin
===> Using default size 0x6000
===> Read csv file...
===> NVS page initialized...
===> Entries inserted into page record
===> Generating binary data complete...
===> Wrote NVS binary to /path/to/output/nvs.bin

```

Adjust the filenames to match your needs, relative paths may be used. The AtomVM release image uses
a size of 0x6000, the minimum size is 0x3000 or 12k (12288 bytes).

To see all currently supported options use the `--help` or `-h` flag when invoking esp_nvs:

```console
$ _build/default/bin/esp_nvs -h

  Usage: esp_nvs [-q, --quiet] [-v, --verbose] COMMAND [CMD_OPTS] INPUT OUTPUT [SIZE] (default 0x6000)
        parameters in [] are optional.

  INPUT is a csv file.

  OUTPUT may be a filename, relative or absolute path for the output. If it is a bare filename it will be
        written to the current working directory or inside --outdir, if supplied.

  *SIZE option must be a multiple of 4096 bytes, if none is given the default 0x6000 will be used, this is
        the size used for AtomVM release images and default builds. The minimum partition size is 0x3000 or
        12k (12288 bytes).

  Commands:
        generate:  Generate a Non-Volatile Storage binary partition from a csv file.

                Command Options:
                --outdir:       Overrides any leading path in the output file parameter, using this path
                                with the output file basename. (Optional for ESP-IDF nvs_partition_gen.py
                                compatibility)

  Options:
        -v, --verbose:  Increase verbosity (may be repeated for debug output)
        -q, --quiet:    Suppress all non error messages (overrides verbose
                        option if present)
  Examples:
        esp_nvs -q generate nvs_data.csv output.bin
        esp_nvs generate nvs_data.csv output.bin 0x4000

```

## API Usage

Non-volatile storage entries are organized into "pages", and filled with "entries". Page size is
always 4096 bytes. The minimum NVS partition size is typically 3 pages (or 12kB), partitions with a
length of 4096 or 8192 (one or two pages) are allowed, but will be read-only and no additional keys
can be saved (or updated) at runtime. Pages are managed by the [`nvs_page`](`m:nvs_page`) module.

### Initialization

To begin constructing a partition table start by initializing the first page, using the partition
size parameter:

```erlang
PartitionSize = 16#6000,
{ok, NVSpage} = nvs_page:init(PartitionSize),
```

### Encoding key-value entries manually

Now we need some packed entries to add to the page. We will start with a namespace, and then add a
few key-value pairs. It is important to hold onto the index and pass the current index each time an
entry is added. The index returned will be incremented when new namespace entries are added, do not
manually adjust this value or the keys will end up in the wrong namespace. First let's take a look
at the function specification:

```erlang
-spec encode(
    Key :: esp_nvs:entry_key(),     %% atom()
    Type :: esp_nvs:entry_type(),   %% data | file | namespace
    Encoding :: esp_nvs:encoding(), %% binary | undefined
    Value :: esp_nvs:entry_value(), %% binary() | file:name_all() | undefined
    NsIdx :: ns_idx()               %% 0..255
) -> {PackedEntry :: packed_kv(), NameSpace :: ns_idx()}.
```

Now we can encode the entries:

```erlang
%% The first namespace entry should start with a 0 index. This will return a tuple with the packed
%% entry and the current namespace index.
{Namespace1, NsIdx} = nvs_entry:encode(example, namespace, undefined, undefined, 0),
{Entry1, NsIdx1} = nvs_entry:encode(foo, data, binary, term_to_binary(bar), NsIdx),
{Entry2, NsIdx2} = nvs_entry:encode(bar, data, binary, <<"some binary data">>, NsIdx1)
{Namespace2, NsIdx3} = nvs_entry:encode(icons, namespace, undefined, undefined, NsIdx2),
{Entry3, NsIdx4} = nvs_entry:encode(logo, file, binary, "/path/to/icon.png", NsIdx3)
```

Before we add these entries to our `page#{}` that was returned from the `init/1` function let us
assume that the `icon.png` file in the third entry has a size of 3714 bytes. This will not fit on
the first page. The page metadata consumes 64 bytes, and each namespace consumes 32 bytes. Both
the `foo` and `bar` key entries will consume 96 bytes each (remember a 32-byte header and 32-byte
footer is added to each binary entry). This brings out current page offset (before we add the
`icon`) to 320 bytes. Because 3714 bytes does not align with the entry block size of 32-bytes it
will be padded to 3744 bytes, and with the add 64-bytes of metadata the entry will require 3808
bytes of storage space, added to the current offset of 320 this puts us just past the end of the
page. This will result in the logo being placed on the second page, and the first page will be
marked as full. We will end up losing most of the storage space in page 1. This can be avoided by
some careful planning. If we were to move the `icons` namespace and the `logo` key to the first
entries, followed by the `example` namespace and its keys then all of our entries will fit on the
first page, except for the `bar` key, which will be the first entry written to page 2, still
leaving the rest of the page available to add more key during runtime. This is admittedly a bit of
a contrived example, but it should illustrate the importance of considering the order that
namespaces and keys are added to the NVS partition.

When packing entries using `f:nvs_entry:encode/5`, values that are not given as `t:binary/0` will
be converted using `f:term_to_binary/1`. The stored values can be decoded after retrieval with
`f:binary_to_term/1`. The results would be the same if the `foo` key above were written as:

```erlang
{Entry1, NsIdx1} = nvs_entry:encode(foo, data, binary, bar, NsIdx),
```

### Adding entries to page records

Enough of that! Let's get back to adding our encoded entries to the page we prepared with the
`nvs_page:init/1` function. For the sake of this demonstration we will not worry about the wasted
NVS space discussed above. With an NVS partition of size 24k, minus the 4k swap page, there is
still just short of 16k free for the application to add more entries at run-time.

```erlang
PageRecords = nvs_page:insert_entries(Entries, NVSpage, 1, []),
```

These page records can now be used to generate the NVS partition binary:

### Generating an NVS partition binary

```erlang
BinaryPartition = nvs_page:build_partition(PageRecords, PartitionSize),
```

#### Saving the binary to disk

The generated binary can be written to disk (for later flashing to a device) using `efile:write/3`
available in [`eee_lib`](../eee_lib/eee_lib.md). This function will work both on OTP's BEAM and AtomVM, here is
the spec:

```erlang
-spec write(
    Path :: file_path() | stdout, Content :: binary() | string(), Modes :: binary | text | [mode()]
) ->
    ok | {error, Reason :: any()}.
```

You can use the same mode() options as OTP `m:file` functions, and when running on AtomVM they will
be translated to the appropriate `atomvm:posix_open/3` options, and any permissions will be parsed
from the `mode()` (`Flags`, `posix_open` parameter 2) and passed as the correct `posix_open/3`
permission `Mode` (parameter 3). Also note that if the application targets only AtomVM any of the
standard posix `o_*` options are also accepted, but this will result in a crash on the BEAM if the
application is used there. For maximum compatibility stick to the `m:file` module options used by
OTP.

### Complete esp_nvs API documentation

For detailed API documentation see the individual module docs:
* `m:nvs_page`
* `m:nvs_entry`
* `m:nvs_csv`
* `m:esp_nvs`
