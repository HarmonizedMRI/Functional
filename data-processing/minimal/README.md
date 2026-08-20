# Minimal fMRI preprocessing pipeline

`run_minimal_fmri_pipeline.sh` implements a lightweight preprocessing pipeline for the harmonized fMRI data.

The pipeline performs:

1. B0 distortion correction using FSL `fugue`
2. Rigid-body motion correction using FSL `mcflirt`
3. Registration of the mean corrected EPI to the T1-weighted image
4. Optional nonlinear T1w → MNI152NLin2009cAsym registration using ANTs

The final 4D BOLD series remains in native functional space. Spatial transforms are retained for overlays, figures, and downstream analyses.

The pipeline intentionally does **not** perform spatial smoothing, slice-timing correction, nuisance regression, temporal filtering, or surface reconstruction.

## Processing workflow

```mermaid
flowchart TD
    A[Raw BOLD] --> B[B0 correction<br/>FUGUE]
    B --> C[Motion estimation<br/>MCFLIRT]
    C --> D[Corrected BOLD<br/>functional space]

    D --> E[Mean corrected EPI]
    E --> F[EPI to T1 registration<br/>FLIRT or BBR]
    G[T1w] --> F

    G --> H{REGISTER_TO_MNI?}
    H -- true --> I[ANTs nonlinear registration]
    I --> J[MNI152NLin2009cAsym]

    F --> K[func to T1 transform]
    I --> L[T1 to MNI transform]
```

## Requirements

The basic pipeline requires:

- FSL
- `jq`
- Python 3
- BIDS-organized input data

Optional MNI normalization additionally requires:

- ANTs
- TemplateFlow

See [`DEVELOPMENT.md`](DEVELOPMENT.md) for installation and setup notes.

## Expected BIDS input

For example:

```text
bidsRoot/
└── sub-00007/
    └── ses-umichmr75020241124/
        ├── anat/
        │   ├── sub-00007_ses-umichmr75020241124_T1w.nii.gz
        │   └── sub-00007_ses-umichmr75020241124_T1w.json
        ├── fmap/
        │   ├── sub-00007_ses-umichmr75020241124_fieldmap.nii.gz
        │   ├── sub-00007_ses-umichmr75020241124_fieldmap.json
        │   ├── sub-00007_ses-umichmr75020241124_magnitude.nii.gz
        │   └── sub-00007_ses-umichmr75020241124_magnitude.json
        └── func/
            ├── sub-00007_ses-umichmr75020241124_task-vismotor_acq-product_run-01_bold.nii
            └── sub-00007_ses-umichmr75020241124_task-vismotor_acq-product_run-01_bold.json
```

The field map must be expressed in Hz.

The BOLD JSON sidecar must contain:

```json
{
  "PhaseEncodingDirection": "j-",
  "TotalReadoutTime": 0.0522
}
```

The pipeline determines the FUGUE unwarp direction from `PhaseEncodingDirection` and calculates the effective echo spacing from `TotalReadoutTime` and the phase-encoding matrix size.

## Configuration

Edit the user settings near the top of `run_minimal_fmri_pipeline.sh`.

For example:

```bash
SUBJECT="sub-00007"
SESSION="ses-umichmr75020241124"

TASK="vismotor"
ACQ="product"
RUN="01"

BIDS_DIR="${HOME}/bidsRoot"
```

To process a Pulseq acquisition instead:

```bash
ACQ="pulseq"
```

To select another run:

```bash
RUN="02"
```

### Field-map sign

```bash
NEGATE_FIELDMAP=false
```

Set to `true` to multiply the field map by -1 before distortion correction. This is primarily useful for testing field-map sign conventions.

### EPI-to-T1 registration

```bash
USE_BBR=false
```

The default uses six-degree-of-freedom FLIRT registration with normalized mutual information.

Set:

```bash
USE_BBR=true
```

to use boundary-based registration (BBR) with BET, FAST, and `epi_reg`.

### Combined B0 and motion resampling

```bash
APPLY_COMBINED_TRANSFORMS=true
```

This is the recommended mode.

Motion is estimated from provisionally B0-corrected data, but the B0 and volume-specific motion transformations are combined before generating the final BOLD series. Each original BOLD volume is therefore interpolated only once.

Set:

```bash
APPLY_COMBINED_TRANSFORMS=false
```

to use the simpler sequential workflow:

```text
Raw BOLD → FUGUE → MCFLIRT
```

### MNI normalization

MNI normalization is optional:

```bash
REGISTER_TO_MNI=false
```

Set:

```bash
REGISTER_TO_MNI=true
```

to perform nonlinear T1w registration to `MNI152NLin2009cAsym` using ANTs and a TemplateFlow reference image.

The pipeline saves the T1w→MNI and MNI→T1w transforms and an MNI-space T1w image.

The full 4D BOLD series is **not** automatically resampled into MNI space. Instead, the pipeline retains:

```text
functional → T1w
T1w → MNI152NLin2009cAsym
```

transforms for later use. Functional derivatives such as activation maps can therefore be transformed to MNI space later without requiring the preprocessed 4D BOLD data to be stored in MNI space.

## Run

Make the script executable:

```bash
chmod +x run_minimal_fmri_pipeline.sh
```

Then run:

```bash
./run_minimal_fmri_pipeline.sh
```

## Output

Public-facing outputs are written as a BIDS derivatives dataset:

```text
bidsRoot/
└── derivatives/
    └── minimal/
        ├── dataset_description.json
        └── sub-00007/
            └── ses-umichmr75020241124/
                ├── func/
                ├── fmap/
                ├── anat/
                └── qc/
```

### `func/`

Contains the final B0- and motion-corrected BOLD series and mean EPI registration products.

The principal output is:

```text
*_desc-b0corrMc_bold.nii.gz
```

### `fmap/`

Contains field-map-related derivatives in functional space, including the resampled field map, magnitude image, and voxel-shift map.

### `anat/`

Contains spatial transformations, including the functional→T1w transform.

When `REGISTER_TO_MNI=true`, this directory additionally contains:

```text
*_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
*_from-MNI152NLin2009cAsym_to-T1w_mode-image_xfm.h5
*_space-MNI152NLin2009cAsym_desc-preproc_T1w.nii.gz
```

### `qc/`

Contains intermediate mean images and motion parameters useful for quality control.

## Quality control

### B0 correction

Overlay the raw and corrected mean EPI on the field-map magnitude image:

```bash
fsleyes \
    <magnitude-in-functional-space> \
    <raw-mean-EPI> \
    <B0-corrected-mean-EPI>
```

### EPI-to-T1 registration

```bash
fsleyes \
    <T1w> \
    <mean-EPI-in-T1w-space>
```

### MNI registration

When MNI normalization is enabled:

```bash
fsleyes \
    <MNI152NLin2009cAsym-template> \
    <T1w-in-MNI-space>
```

Inspect the overall brain outline, cortical boundaries, ventricles, cerebellum, and inferior brain regions.

## Relationship to fMRIPrep

This pipeline is intentionally much more limited than fMRIPrep. It is designed as a transparent minimal preprocessing workflow for the harmonized fMRI data rather than as a replacement for a full fMRI preprocessing pipeline.

The repository also includes:

```bash
./run_fmriprep.sh
```

for comparison with fMRIPrep processing.

See [`DEVELOPMENT.md`](DEVELOPMENT.md) for installation and testing notes, individual-stage validation scripts, BIDS validation, and the fMRIPrep comparison workflow.
