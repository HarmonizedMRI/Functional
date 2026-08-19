# Session utilities

MATLAB utilities for reading HarmonizedMRI session configuration files and locating the corresponding imaging data.

The configuration format is defined in:

```text
../../data-config/
```

See `data-config/README.md` for the organization and format of `sessions.txt`, `sessions/`, and `scans.txt`.

## Files

```text
session/
├── README.md
├── loadSession.m
├── readScans.m
└── getScanFiles.m
```

- `loadSession.m` reads session-level metadata and scan configurations.
- `readScans.m` reads individual `scans.txt` files and resolves their data directories relative to the local imaging-data location.
- `getScanFiles.m` returns full paths to the configured scan files for convenient use by reconstruction and other processing code.

## Usage

Configuration files and imaging data can reside in different locations.

Specify:

```matlab
configRoot = '/path/to/Functional/data-config';
dataRoot = '/path/to/imaging/data';
```

and load a session using its session ID:

```matlab
sessionID = 'sub00012-umich-mr750-20250115-1';

S = loadSession(configRoot, dataRoot, sessionID);
```

`configRoot` is the directory containing:

```text
sessions.txt
sessions/
```

`dataRoot` is the root directory containing the actual imaging data.

## Returned session structure

`loadSession` returns session-level information such as:

```matlab
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

```matlab
S.scans.pulseq
S.scans.product
```

For example:

```matlab
S.scans.pulseq.datadir
S.scans.pulseq.cal
S.scans.pulseq.cal2d
S.scans.pulseq.rest
```

The scan type `2d` in `scans.txt` is represented as `cal2d`, since MATLAB structure field names cannot begin with a number.

## Get full scan filenames

`getScanFiles` converts the scan inventory into full paths that can be passed directly to reconstruction or other processing code.

For example:

```matlab
S = loadSession(configRoot, dataRoot, sessionID);
F = getScanFiles(S, 'pulseq');
```

The returned structure contains full paths:

```matlab
F.cal
F.cal2d
F.rest
```

For example, these can be passed to an SMS-EPI reconstruction:

```matlab
calfile   = F.cal;
cal2dfile = F.cal2d;
restfile  = F.rest;
```

If more than one scan of a given type is configured, the corresponding field is returned as a cell array of filenames.

The same interface can be used for scanner product acquisitions:

```matlab
F = getScanFiles(S, 'product');
```

This keeps downstream processing code independent of the details of `sessions.txt`, `scans.txt`, vendor-specific file naming, and local data storage.

## Data path resolution

`readScans` replaces the machine-specific portion of the data path stored in `scans.txt` with the supplied `dataRoot`.

For example, a configured path containing:

```text
/mnt/storage/HarmonizedMRI/fMRI/sub00012-umich-mr750-20250115-1/raw/Exam15678/
```

with:

```text
dataRoot = /data/HarmonizedMRI/fMRI
```

is resolved as:

```text
/data/HarmonizedMRI/fMRI/sub00012-umich-mr750-20250115-1/raw/Exam15678/
```

Everything beginning with the session ID is preserved, allowing arbitrary directory structures below the session directory.

## Missing imaging data

Session configuration can be loaded even when some or all of the corresponding imaging data are unavailable locally.

Missing raw-data directories or files generate warnings rather than errors. This allows the same configuration repository to be used by users who have access to different subsets or locations of the imaging data.