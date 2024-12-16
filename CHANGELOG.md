# Changelog

All notable changes to this project will be documented in this file.

## Release 0.1.1

Remove file accidentally included in previous release.

## Release 0.1.0

Initial release including fully functional deploy plan originally from
[Nest](https://github.com/jameslikeslinux/puppet-nest). Parameter names have
been changed to be a little more generic, and the code has been significantly
refactored for public consumption. Added tests and documentation.

**Features**

* Deploy charts with custom resources, values, and patches.
* Integrate into your own project with parameters to customize lookups.
* Automatically generate Helm chart to manage bare resources.
* Manage multiple charts as one release with subcharts.

**Bugfixes**

* Build intermediate files in separate directories to avoid conflicts.

**Known Issues**

* This project does not currently run on Windows.
