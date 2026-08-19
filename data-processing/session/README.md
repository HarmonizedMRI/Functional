# Session utilities

MATLAB utilities for reading HarmonizedMRI session configuration files and locating the corresponding imaging data.

The configuration format is defined in:

```text id="cj00lp"
../../data-config/
```

See `data-config/README.md` for the organization and format of `sessions.txt`, `sessions/`, and `scans.txt`.

## Files

```text id="ryx4r6"
session/
├── README.md
├── loadSession.m
└── readScans.m
```

- `loadSession.m` reads session-level metadata and scan configurations.
- `readScans.m` reads individual `scans.txt` files and resolves their entries against the local imaging-data location.

## Usage

Configuration files and imaging data can reside in different locations.

Specify:

```matlab id="skkntq"
configRoot = '/path/to/Functional/data-config';
dataRoot = '/path/to/imaging/data';
```

and load a session using its session ID:

```matlab id="gn3o0i"
sessionID = 'sub00012-umich-mr750-20250115-1';

S = loadSession(configRoot, dataRoot, sessionID);
```

`configRoot` is the directory containing:

```text id="xdgqse"
sessions.txt
sessions/
```

`dataRoot` is the root directory containing the actual imaging data.

## Returned session structure

`loadSession` returns session-level information such as:

```matlab id="zfcgl6"
S.id
S.subject
S.site
S.scanner
S.date
S.session
S.vendor

S.kspace_delay
S.readout_trajectory_file
S.configdir
```

Scan information is organized by acquisition implementation:

```matlab id="xjfl6g"
S.scans.pulseq
S.scans.product
```

For example:

```matlab id="5rw10y"
S.scans.pulseq.datadir
S.scans.pulseq.cal
S.scans.pulseq.cal2d
S.scans.pulseq.rest
```

The scan type `2d` in `scans.txt` is represented as `cal2d`, since MATLAB structure field names cannot begin with a number.

## Data path resolution

`readScans` replaces the machine-specific portion of the path stored in `scans.txt` with the supplied `dataRoot`.

For example, a configured path ending in

```text id="h99e4m"
sub00012-umich-mr750-20250115-1/raw/Exam15678/
```

is resolved under the specified `dataRoot`, regardless of the original parent directory recorded in `scans.txt`.

## Missing imaging data

Session configuration can be loaded even when some or all of the corresponding imaging data are unavailable locally.

Missing raw-data directories or files generate warnings rather than errors. This allows the same configuration repository to be used by users who have access to different subsets or locations of the imaging data.