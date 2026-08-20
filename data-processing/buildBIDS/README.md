# buildBIDS

Utilities for converting the internal HarmonizedMRI data organization into a BIDS-compatible dataset for sharing with collaborators.

## Purpose

The scripts in this folder build the primary BIDS dataset from the internal HarmonizedMRI directory structure.

The primary BIDS dataset currently includes:

- T1-weighted anatomical images
- Product and Pulseq BOLD fMRI
- Canonical B0 field maps
- Magnitude images associated with the field maps

Selected derived calibration products, currently BART coil sensitivity maps, are copied under `derivatives/calibration/`.

Additional preprocessing pipelines such as the minimal fMRI pipeline and fMRIPrep are maintained separately under `Functional/data-processing/`.

## Overall organization

```text
srcRoot/
└── sub00012-umich-mr750-20250115/
    ├── anat/
    ├── fmap/
    ├── product/
    └── pulseq/

        │
        ▼

    buildBIDS

        │
        ▼

bidsRoot/
├── dataset_description.json
│
├── sub-00012/
│   └── ses-umichmr75020250115/
│       ├── anat/
│       │   ├── sub-00012_ses-umichmr75020250115_T1w.nii.gz
│       │   └── sub-00012_ses-umichmr75020250115_T1w.json
│       │
│       ├── fmap/
│       │   ├── sub-00012_ses-umichmr75020250115_fieldmap.nii.gz
│       │   ├── sub-00012_ses-umichmr75020250115_fieldmap.json
│       │   ├── sub-00012_ses-umichmr75020250115_magnitude.nii.gz
│       │   └── sub-00012_ses-umichmr75020250115_magnitude.json
│       │
│       └── func/
│           ├── sub-00012_ses-umichmr75020250115_task-vismotor_acq-product_run-01_bold.nii
│           ├── sub-00012_ses-umichmr75020250115_task-vismotor_acq-product_run-01_bold.json
│           ├── sub-00012_ses-umichmr75020250115_task-vismotor_acq-pulseq_run-01_bold.nii
│           ├── sub-00012_ses-umichmr75020250115_task-vismotor_acq-pulseq_run-01_bold.json
│           ├── sub-00012_ses-umichmr75020250115_task-rest_acq-product_run-01_bold.nii
│           ├── sub-00012_ses-umichmr75020250115_task-rest_acq-product_run-01_bold.json
│           ├── sub-00012_ses-umichmr75020250115_task-rest_acq-pulseq_run-01_bold.nii
│           └── sub-00012_ses-umichmr75020250115_task-rest_acq-pulseq_run-01_bold.json
│
└── derivatives/
    └── calibration/
        ├── dataset_description.json
        └── sub-00012/
            └── ses-umichmr75020250115/
                └── fmap/
                    ├── sub-00012_ses-umichmr75020250115_desc-bart_sensitivity.mat
                    └── sub-00012_ses-umichmr75020250115_desc-bart_sensitivity.json
```

## Internal source organization

Each session is expected to have a directory name of the form

```text
sub00012-umich-mr750-20250115
```

and a layout such as:

```text
sub00012-umich-mr750-20250115/
├── anat/
│   ├── T1w.nii.gz
│   └── T1w.json
│
├── fmap/
│   ├── fieldmap.nii.gz
│   ├── fieldmap.json
│   ├── magnitude.nii.gz
│   ├── magnitude.json
│   ├── sens.mat
│   └── sens.json
│
├── product/
│   ├── task_run1.nii
│   ├── task_run2.nii
│   ├── rest_run1.nii
│   └── ...
│
└── pulseq/
    ├── task_run1.nii
    ├── task_run2.nii
    ├── rest_run1.nii
    └── ...
```

The BOLD source filename determines the BIDS task label:

```text
task_run*.nii  -> task-vismotor
rest_run*.nii  -> task-rest
```

Product and Pulseq BOLD files are discovered and processed independently.

## Current functionality

`buildBIDS.m` currently:

- creates dataset-level `dataset_description.json` files;
- copies T1-weighted anatomical images;
- copies the canonical field map and associated magnitude image;
- copies product BOLD runs;
- processes and copies Pulseq BOLD runs;
- creates or copies BOLD JSON sidecars;
- copies BART sensitivity maps into `derivatives/calibration`;
- converts internal session names into BIDS subject/session labels;
- skips existing output files by default.

## BOLD metadata

`copyBOLD.m` supports the following optional arguments:

```matlab
copyBOLD(info, ...
    PhaseEncodingDirection="j-", ...
    TotalReadoutTime=0.0522);
```

The current defaults for the HarmonizedMRI BOLD acquisition are:

```json
{
  "PhaseEncodingDirection": "j-",
  "TotalReadoutTime": 0.0522
}
```

For Pulseq BOLD runs, a JSON sidecar is generated because the reconstructed NIfTI files generally do not have one.

For product BOLD runs:

- if a source JSON sidecar exists, it is copied unchanged;
- supplied phase-encoding/readout-time values are not used in that case;
- if no source JSON exists, a minimal sidecar is generated using the supplied values.

## Pulseq BOLD processing

Pulseq reconstructions are modified before being written to the BIDS dataset:

- use the corresponding product run as the spatial-header reference;
- preserve the Pulseq image dimensions;
- set voxel size to 2.4 × 2.4 × 2.4 mm;
- set TR to 0.8 s;
- flip the first image dimension to match the product orientation;
- scale the image and save as `int16`.

The matching product run is required as the geometry reference for this step.

## Usage

```matlab
srcRoot  = '/path/to/srcRoot';
bidsRoot = '/path/to/bidsRoot';

buildBIDS(srcRoot, bidsRoot);
```

`buildBIDS` discovers session directories under `srcRoot`, creates the corresponding BIDS subject/session hierarchy, and copies the supported source and calibration data into `bidsRoot`.

## Related processing

Field-map reconstruction is performed separately using the tools in the `HarmonizedMRI/B0shimming` repository. The canonical outputs handed to `buildBIDS` are:

```text
fmap/
├── fieldmap.nii.gz
├── fieldmap.json
├── magnitude.nii.gz
├── magnitude.json
├── sens.mat
└── sens.json
```

Functional preprocessing is also separate from `buildBIDS`:

```text
Functional/data-processing/
├── buildBIDS/
├── minimal/
└── fmriprep/
```

The minimal pipeline uses the BOLD phase-encoding direction and total readout time for B0 distortion correction.

## Future work

Potential future additions include:

- generation of `participants.tsv`;
- copying raw ISMRMRD data into `sourcedata/`;
- additional calibration derivatives such as alternative field-map or sensitivity-map estimates;
- optional BIDS validation.