# Development and setup notes

This document contains software installation, testing, and implementation notes for the minimal fMRI preprocessing pipeline.

For normal use of the pipeline, see [`README.md`](README.md).

## Software setup

### FSL

The minimal pipeline uses FSL for B0 distortion correction, motion correction, and EPI-to-T1 registration.

Example installation:

```bash
curl -Ls https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py \
    -o fslinstaller.py

python3 fslinstaller.py
```

If FSL is installed in `${HOME}/fsl`, configure it with:

```bash
export FSLDIR="${HOME}/fsl"
. "${FSLDIR}/etc/fslconf/fsl.sh"
export PATH="${FSLDIR}/share/fsl/bin:$PATH"
```

These lines can be added to `~/.bashrc` if desired.

Check:

```bash
command -v fugue
command -v mcflirt
command -v flirt
```

The pipeline also requires `FSLOUTPUTTYPE` to be configured by the FSL setup script.

### ANTs

ANTs is required only when:

```bash
REGISTER_TO_MNI=true
```

Download a precompiled Linux release of ANTs from the official ANTs GitHub releases page and extract it to a convenient location, for example under:

```text
${HOME}/ants/
```

Add the extracted ANTs `bin` directory to `PATH`. For example:

```bash
export ANTSDIR="${HOME}/ants/ants-2.x.x"
export PATH="${ANTSDIR}/bin:$PATH"
```

These lines can be added to `~/.bashrc`.

Check:

```bash
command -v antsRegistrationSyN.sh
command -v antsApplyTransforms
```

Both commands should return paths to the corresponding ANTs executables.

### TemplateFlow

TemplateFlow is used to retrieve the `MNI152NLin2009cAsym` T1w reference image.

Install with:

```bash
python3 -m pip install templateflow
```

Check:

```bash
python3 -c "import templateflow.api; print('TemplateFlow OK')"
```

TemplateFlow does not need to be installed in a dedicated Python environment as long as it is accessible to the `python3` command used to launch the pipeline.

### jq

The pipeline reads BIDS JSON metadata using `jq`.

On Ubuntu:

```bash
sudo apt install jq
```

Check:

```bash
command -v jq
```

## BIDS validation

The BIDS validator can be run using Docker:

```bash
docker run --rm -ti \
    -v "${HOME}/bidsRoot:/data:ro" \
    bids/validator /data
```

To suppress warnings and report errors only:

```bash
docker run --rm -ti \
    -v "${HOME}/bidsRoot:/data:ro" \
    bids/validator /data \
    --ignoreWarnings
```

## Testing individual processing stages

The individual scripts are useful for debugging and validating each stage before running the full pipeline.

### B0 distortion correction

Use:

```bash
./run_fugue.sh
```

This tests:

- BOLD mean-image creation
- field-map resampling into functional space
- magnitude-image resampling into functional space
- conversion of the field map from Hz to rad/s
- FUGUE distortion correction
- field-map sign

The BOLD JSON sidecar supplies:

```json
{
  "PhaseEncodingDirection": "j-",
  "TotalReadoutTime": 0.0522
}
```

The effective echo spacing used by FUGUE is:

```text
TotalReadoutTime / (N_PE - 1)
```

where `N_PE` is the phase-encoding matrix size.

For field-map sign testing, the field map can be multiplied by -1 and the two corrected images compared visually.

### Motion correction

Use the standalone MCFLIRT test after confirming the B0 correction.

The intended processing order is:

```text
B0 correction → motion correction
```

The full pipeline can optionally combine the final B0 and motion resampling into a single interpolation step.

### EPI-to-T1 registration

Use:

```bash
./run_epi_reg.sh
```

The default registration is six-degree-of-freedom FLIRT with normalized mutual information.

BBR can optionally be tested using BET, FAST, and `epi_reg`.

For QC, overlay the transformed mean EPI on the original high-resolution T1w image.

### T1-to-MNI registration

A standalone MNI test script can be used to validate ANTs and TemplateFlow before enabling MNI normalization in the full pipeline.

The registration is:

```text
T1w → MNI152NLin2009cAsym
```

using ANTs nonlinear SyN registration.

Check the result by overlaying the transformed T1w image on the TemplateFlow MNI reference. Inspect:

- overall brain outline
- cortical boundaries
- ventricles
- cerebellum
- inferior brain regions

The full pipeline saves both forward and inverse composite transforms.

## Combined B0 and motion resampling

The recommended full-pipeline setting is:

```bash
APPLY_COMBINED_TRANSFORMS=true
```

The workflow is conceptually:

```text
Raw BOLD
   │
   ├─ FUGUE → provisional B0-corrected BOLD
   │              │
   │              └─ MCFLIRT → motion matrices
   │
   └─ original volumes
          │
          └─ combine B0 shift + volume-specific motion transform
                         │
                         └─ one final interpolation
```

This avoids applying separate final interpolation steps for FUGUE and MCFLIRT.

With:

```bash
APPLY_COMBINED_TRANSFORMS=false
```

the simpler sequential workflow is used:

```text
Raw BOLD → FUGUE → MCFLIRT
```

## fMRIPrep comparison

`run_fmriprep.sh` provides a comparison against fMRIPrep.

The intent is not to reproduce all fMRIPrep processing. Instead, fMRIPrep provides an established reference workflow against which the geometric preprocessing from the minimal pipeline can be evaluated.

The fMRIPrep wrapper can be configured to:

- disable FreeSurfer surface reconstruction
- output native functional and T1w-space data
- optionally output `MNI152NLin2009cAsym`

Example output-space construction:

```bash
OUTPUT_MNI=false

OUTPUT_SPACES=(T1w func)

if ${OUTPUT_MNI}; then
    OUTPUT_SPACES+=(MNI152NLin2009cAsym)
fi
```

and:

```bash
--output-spaces "${OUTPUT_SPACES[@]}"
```

## Docker permissions for fMRIPrep

If:

```bash
docker info
```

reports:

```text
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

the user needs permission to access the Docker daemon.

After adding the user to the Docker group, log out and back in (or otherwise refresh group membership) before retrying:

```bash
docker info
```

## FreeSurfer license

fMRIPrep may require a FreeSurfer license even when surface reconstruction is disabled.

The license can be supplied with the fMRIPrep `--fs-license-file` option or through the `FS_LICENSE` environment variable.

## Notes on native-space outputs

The minimal pipeline deliberately keeps the final 4D BOLD data in functional space.

It estimates and saves:

```text
functional → T1w
T1w → MNI152NLin2009cAsym
```

transforms rather than automatically resampling the full time series into anatomical or standard space.

This keeps the main BOLD derivative close to the acquired resolution and permits later functional derivatives, such as activation maps, to be transformed as needed.

## Empirical geometry correction for Pulseq acquisitions

The current minimal pipeline includes two ANTs-based geometry-correction steps for Pulseq-derived images.

These are **empirical image-registration corrections**, not calibrated gradient-nonlinearity (GNL) corrections.

### Field-map magnitude and field map

The Pulseq B0-map acquisition is not currently corrected using a scanner-specific GNL model. The field-map magnitude can therefore show spatial mismatch relative to the T1w image.

The pipeline estimates:

```text
fmap magnitude → T1w
```

using ANTs rigid + SyN registration:

```bash
antsRegistrationSyN.sh \
    -d 3 \
    -f <T1-registration-reference> \
    -m <fmap-magnitude> \
    -o <prefix> \
    -t sr \
    -p f \
    -n 2
```

The same transform is then applied to the Hz field map.

Because the expected geometric mismatch is smooth, and full-resolution SyN can use substantial memory, the T1w image is resampled to 3 mm only for **transform estimation**:

```bash
ResampleImage \
    3 \
    "${T1}" \
    "${T1_REGISTRATION_REFERENCE}" \
    3x3x3
```

The field-map magnitude can remain at its native resolution (for example, 2.4 mm). The fixed and moving images do not need matching voxel sizes.

The final transform is applied using the original high-resolution T1w or functional image as the reference grid, so the output resolution is not limited to 3 mm.

The current default is therefore:

```bash
REGISTRATION_T1_RESOLUTION_MM=3
```

This is intentional. Reducing it to 2.4 mm is not expected to provide a meaningful benefit for the smooth deformation being estimated and increases memory use.

### Pulseq BOLD geometry

Pulseq and product BOLD acquisitions are designed to have very closely matched EPI susceptibility distortion.

For this reason, the static Pulseq-to-product geometry correction is estimated **before B0 correction**:

```text
raw Pulseq mean → raw product mean
```

using rigid + SyN registration.

This preserves the common B0 distortion in both images and asks the nonlinear registration to primarily account for:

- prescription offset;
- smooth geometry differences associated with missing GNL correction.

The product BOLD run with the matching run number is used as the fixed reference by default.

This assumption should be revisited if Pulseq and product acquisition parameters differ substantially in phase-encoding direction, echo spacing, readout duration, or other parameters that affect EPI distortion.

### Memory use when applying the Pulseq geometry transform

Applying the nonlinear transform to the entire 4D Pulseq BOLD series using:

```bash
antsApplyTransforms -e 3 ...
```

can require substantial memory and may be killed by the operating system.

The current implementation therefore:

1. splits the 4D Pulseq BOLD into individual 3D volumes with `fslsplit`;
2. applies the same static ANTs transform to each volume independently;
3. merges the corrected volumes with `fslmerge`.

Conceptually:

```text
4D Pulseq BOLD
      ↓
fslsplit
      ↓
3D volume 0000 ─┐
3D volume 0001 ─┼─ antsApplyTransforms
3D volume 0002 ─┤
       ...       │
                 ↓
             fslmerge
                 ↓
geometry-corrected 4D Pulseq BOLD
```

This substantially reduces peak memory use.

ANTs threading is also limited with:

```bash
ANTS_THREADS=2
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${ANTS_THREADS}"
```

and the registrations use single precision:

```bash
-p f
```

to reduce memory requirements.

## Interpolation strategy

For product BOLD, the pipeline can combine B0 distortion and MCFLIRT motion transforms and apply them in one final interpolation:

```bash
APPLY_COMBINED_TRANSFORMS=true
```

For Pulseq BOLD, the current implementation performs:

```text
raw Pulseq BOLD
      ↓
static Pulseq→product ANTs geometry correction
      ↓
combined B0 + motion correction
```

Therefore, Pulseq currently undergoes two interpolation stages:

1. static ANTs geometry correction;
2. combined FUGUE + MCFLIRT resampling.

A future improvement could attempt to compose the ANTs nonlinear geometry transform with the FSL B0/motion transforms so that all geometric corrections are applied in a single final interpolation. This is more complicated because it requires careful conversion/composition of transforms across ANTs and FSL conventions.

## QC for the geometry corrections

### Field-map geometry

Compare:

```text
T1w
fmap magnitude transformed to T1w space
```

For example:

```bash
fsleyes \
    <T1w> \
    <fmap-magnitude-in-T1w-space>
```

Check whole-brain shape, ventricles, cortex, cerebellum, and inferior brain regions.

### Pulseq geometry

Compare the raw product mean with the geometry-corrected Pulseq mean:

```bash
fsleyes \
    <raw-product-mean> \
    <pulseq-geometry-corrected-mean>
```

This comparison should be made before evaluating B0 correction, since the static Pulseq geometry transform is intentionally estimated on un-B0-corrected images.

## Interpretation caveat

The ANTs-based nonlinear registrations are practical corrections for geometry mismatch in the current data-processing workflow. They should not be described as true GNL correction.

A calibrated GNL correction based on scanner gradient-coil coefficients would remain preferable when available.
