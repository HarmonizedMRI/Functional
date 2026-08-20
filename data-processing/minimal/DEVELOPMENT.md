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
