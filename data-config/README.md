# Data configuration

This directory contains configuration files describing the imaging sessions used by the HarmonizedMRI Functional project.

The configuration is stored separately from the imaging data themselves. This allows the configuration to be maintained in Git while the imaging data reside on a local disk, institutional server, or other storage system.

No imaging data are stored in this directory.

## Organization

```text id="xixvgk"
data-config/
├── README.md
├── sessions.txt
├── readout.mod
└── sessions/
    └── sub00012-umich-mr750-20250115-1/
        ├── pulseq/
        │   └── scans.txt
        └── product/
            └── scans.txt
```

Each session has a unique identifier of the form

```text id="9ny1yq"
<subject>-<site>-<scanner>-<date>-<session>
```

for example:

```text id="v8i8io"
sub00012-umich-mr750-20250115-1
```

## `sessions.txt`

`sessions.txt` contains session-level information.

For example:

```text id="l5j1cd"
subject     site    scanner    date        session    vendor    kspace_delay    readout_trajectory_file
sub00012    umich   mr750      20250115    1          GE        -1.5            ./readout.mod
```

The session identifier is constructed from the first five columns.

Other columns contain acquisition- or scanner-specific information shared by scans within the session.

## Session scan configuration

Scan information for each session is stored under

```text id="5sjv95"
sessions/<sessionID>/
```

Pulseq and scanner product/built-in acquisitions are kept separately:

```text id="tt14xa"
sessions/<sessionID>/
├── pulseq/
│   └── scans.txt
└── product/
    └── scans.txt
```

This makes it possible to associate vendor-neutral Pulseq acquisitions and corresponding scanner product acquisitions with the same imaging session.

Additional scan types can be added as needed.

## `scans.txt`

The first line of `scans.txt` identifies the directory containing the scan data. Subsequent lines associate scan types with files or directories.

For example:

```text id="d9p8k6"
/mnt/storage/HarmonizedMRI/fMRI/sub00012-umich-mr750-20250115-1/raw/Exam15678/
cal     Series15
2d      Series14
rest    Series16
```

The exact interpretation of a scan entry may be vendor dependent. For example, for GE raw data, `Series15` identifies a Series directory containing the corresponding ScanArchive file.

## Portable data paths

The paths recorded in `scans.txt` may contain machine-specific parent directories. These do not need to be manually edited when the configuration is used on another system.

The session-loading utilities preserve the portion of the path beginning with the session ID and replace everything before it with a user-specified `dataRoot`.

For example:

```text id="v08gdn"
/mnt/storage/jfnielse/HarmonizedMRI/fMRI/
    sub00012-umich-mr750-20250115-1/raw/Exam15678/
```

with

```text id="v3ss81"
dataRoot = /data/HarmonizedMRI/fMRI
```

is resolved as

```text id="19fdnm"
/data/HarmonizedMRI/fMRI/
    sub00012-umich-mr750-20250115-1/raw/Exam15678/
```

Everything beginning with the session ID is preserved, allowing arbitrary directory structures below the session directory.

## Using the configuration

MATLAB utilities for reading these files are provided in:

```text id="j8glwi"
../data-processing/session/
```

See the README in that directory for usage instructions.