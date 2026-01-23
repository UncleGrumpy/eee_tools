<!--
 Copyright 2025 Winford <winford@object.stream>

SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
-->

# Contributing

Before contributing, please read carefully our [Code of Conduct](CODE_OF_CONDUCT.md) and
the following contribution guidelines.

Please, also make sure to understand the [Apache 2.0 license](./LICENSES/Apache-2.0.txt) and the
[Developer Certificate of Origin](https://developercertificate.org/).

## Git Recommended Practices

* Commit messages should have a [summary and a description](https://github.com/erlang/otp/wiki/writing-good-commit-messages)
  - The first word of the brief summary should be capitalized and no end punctuation
  - Description should focus on the reason for the changes
* `--signoff` on all commits ([DCO](https://github.com/apps/dco))
* Avoid trailing white spaces
* Always `git pull --rebase`
* [Clean up your branch history](https://git-scm.com/book/id/v2/Git-Tools-Rewriting-History)
with `git rebase -i`
* All your intermediate commits should build

## Code Checks, Style and Tests

* All functions should have a `spec`, and if exported include documentation
* [Run the test suite](#running-the-full-test-suite) to make sure there is no regression
* Include tests for new functions or features
* Check changes with dialyzer [(see below)](#scanning-code-for-errors-and-formatting)
* Use [`erlfmt` formatter](#erlfmt) enforced style

### Rebar3 `test` profile for contributors

Several rebar3 aliases are configured to simplify running tests as well as formatting and spec
checks. These should all be used under the `test` profile; this is done to keep the extra deps
(`proper`), and plugins (`erlfmt` and `rebar3_proper`) out of the default and prod profiles used by
regular consumers of the app. An extra dependency `eavmlib` is also pulled from a sub-directory of
the AtomVM repository to allow testing the cross-compatibility of modules that allow running some
tools and APIs on AtomVM or OTP's `BEAM`.

#### Running the full test suite

To run all tests use the alias:

>`rebar3 as test test`

This will run all of the eunit, PropEr, and ct tests with coverage.

#### Scanning code for errors and formatting

To run all of the configured code checking tools use the alias:

>`rebar3 as test check`

This will run xref and dialyzer to catch any obvious bugs or problems with the code, and use erlfmt
to check formatting.

##### erlfmt

If you run `rebar3 fmt -c` in the `test` profile it will not check the `project_app_dirs`. To check
the formatting of __all__ files with [erlfmt](https://github.com/WhatsApp/erlfmt) use the alias:

>`rebar3 as test erlfmt`

If you need to fix formatting errors, __all__ of the project's files can be fixed using the alias:
>`rebar3 as test format`

#### Run all tests and checks

To run all of the tests and code scanning tools use the alias:

>`rebar3 as test tests`

### Build the documentation

The documentation should be built using the `doc` profile. This profile includes the
`rebar3_ex_doc` plugin dependency.

To compile the documentation use the alias:

>`rebar3 as doc ex_doc`

#### Documentation style

The project is using old `edoc` style documentation at least until OTP-29 is released, at that
point the documentation will be updated to OTP-27 style triple-quoted (`"""`) doc string. The delay
is to support compiling on older OTP releases that AtomVM still supports. Even if AtomVM does not
drop support for OTP-26 right away after the release of OTP-29, OTP-26 support will likely be
dropped by this toolset.
