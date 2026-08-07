# Minimal fMRI preprocessing pipeline

`run_minimal_fmri_pipeline.sh` performs a lightweight fMRI preprocessing workflow using FSL.

## Processing steps

1. B0 distortion correction (`fugue`)
2. Rigid-body motion correction (`mcflirt`)
3. Mean EPI → T1 registration (FLIRT or optional BBR)

The final 4D BOLD series always remains in native functional space. The EPI→T1 transform is estimated only for quality control, overlays, and figures.

## Processing modes

### Sequential mode

Set:

```bash
APPLY_COMBINED_TRANSFORMS=false
```

Workflow:

```text
Raw BOLD
    ↓
FUGUE
    ↓
MCFLIRT
```

This is the simplest workflow and is useful for debugging. The BOLD data are resampled twice.

### Combined-transform mode (recommended)

Set:

```bash
APPLY_COMBINED_TRANSFORMS=true
```

Workflow:

```text
Estimate B0 shift map
        ↓
Provisional FUGUE correction
        ↓
Estimate motion with MCFLIRT
        ↓
Combine B0 shift map + motion matrix
        ↓
Resample each original BOLD volume once
```

The provisional FUGUE- and MCFLIRT-corrected data are used only to estimate the transforms. The retained final 4D BOLD series is created directly from the original data using one interpolation.

## User options

```bash
SUBJECT="sub-00012"
ACQ="product"
RUN="01"

NEGATE_FIELDMAP=false
USE_BBR=false

APPLY_COMBINED_TRANSFORMS=true
FINAL_INTERPOLATION="spline"

KEEP_INTERMEDIATES=true
```

- `NEGATE_FIELDMAP` flips the sign of the field map before FUGUE.
- `USE_BBR` enables BET + FAST + `epi_reg` instead of 6-DOF FLIRT.
- `APPLY_COMBINED_TRANSFORMS` selects between sequential and single-resampling output.
- `FINAL_INTERPOLATION` controls the interpolation used by `applywarp`.
- `KEEP_INTERMEDIATES` retains temporary files for debugging.

## Required inputs

```
sub-XXXX/
├── anat/
│   └── sub-XXXX_T1w.nii
├── fmap/
│   ├── sub-XXXX_fieldmap.nii.gz
│   └── sub-XXXX_magnitude.nii.gz
└── func/
    ├── sub-XXXX_task-*_bold.nii
    └── sub-XXXX_task-*_bold.json
```

The field map must be stored in Hz. The BOLD JSON must contain `PhaseEncodingDirection` and `TotalReadoutTime`.

## Main outputs

- `*_desc-b0corrMc_bold.nii.gz` — final corrected 4D BOLD series.
- `*_desc-b0corrMc_bold.par` — motion parameters.
- `*_desc-b0corrMc_bold.mat/` — one rigid transform per volume.
- `*_from-func_to-T1w.mat` — functional-to-T1 transform.
- `*_space-T1w_desc-b0corrMc_mean.nii.gz` — mean EPI in T1 space for QC.

## Quality control

**B0 correction**

```bash
fsleyes <magnitude> <raw_mean> <b0_corrected_mean>
```

**Motion correction**

```bash
fsleyes <b0_corrected_mean> <motion_corrected_mean>
```

**EPI→T1 registration**

```bash
fsleyes <T1> <registered_mean_EPI>
```

## Notes

- The combined-transform mode is recommended for production because it minimizes interpolation.
- The visual difference from sequential processing is usually modest for low-motion data but is methodologically preferable.
- The field map is assumed to be static during the run.

## Comparison with fMRIPrep

The repository includes a convenience wrapper,

```bash
./run_fmriprep.sh
```

which runs fMRIPrep with settings that closely match the scope of the lightweight preprocessing pipeline.

By default, the script:

* processes a single participant;
* disables FreeSurfer surface reconstruction (`--fs-no-reconall`);
* outputs data in native functional (`func`) and T1 (`T1w`) spaces;
* optionally performs MNI normalization;
* optionally runs the BIDS validator before preprocessing;
* saves the complete terminal output to a log file.

The output spaces are configured near the top of the script:

```bash
OUTPUT_MNI=false

OUTPUT_SPACES=(T1w func)

if ${OUTPUT_MNI}; then
    OUTPUT_SPACES+=(MNI152NLin2009cAsym)
fi
```

Setting

```bash
OUTPUT_MNI=true
```

adds MNI152NLin2009cAsym outputs in addition to the native-space outputs.

Run the script with:

```bash
source mypythonenv/bin/activate
./run_fmriprep.sh
```

The lightweight pipeline implemented in this repository intentionally performs only the core geometric preprocessing steps:

1. B₀ distortion correction
2. Rigid-body motion correction
3. EPI → T1 registration

Unlike fMRIPrep, it does **not** perform:

* slice-timing correction;
* anatomical preprocessing beyond optional BET/FAST for BBR;
* surface reconstruction;
* spatial normalization (unless requested when running fMRIPrep);
* confound estimation;
* nuisance regression;
* temporal filtering; or
* spatial smoothing.

The purpose of `run_fmriprep.sh` is therefore not to replace the lightweight pipeline, but to provide a convenient reference implementation for comparison and validation. The outputs from both pipelines can be compared to evaluate the geometric preprocessing while keeping the remainder of the processing as similar as possible.

