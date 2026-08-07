# Development notes

This document describes the development environment used for the lightweight fMRI preprocessing pipeline, how to reproduce the reference **fMRIPrep** workflow, and how to validate each individual processing step using native FSL tools.

---

# 1. Development environment

## Python environment

```bash
python3 -m venv mypythonenv
source mypythonenv/bin/activate
python3 -m pip install fmriprep-docker
```

## Install Docker

```bash
# Remove potentially conflicting apt packages
sudo apt remove -y docker.io docker-compose docker-compose-v2 \
    docker-doc podman-docker containerd runc

# Add Docker's official signing key
sudo apt update
sudo apt install -y ca-certificates curl

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker's apt repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
```

Test:

```bash
sudo docker run --rm hello-world
```

Give your user permission to run Docker without `sudo`:

```bash
sudo usermod -aG docker "$USER"
```

Log out and back in, then verify:

```bash
fmriprep
```

The first run downloads the required Docker images.

---

## Install FSL

```bash
curl -Ls https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py \
    -o fslinstaller.py

python3 fslinstaller.py
```

Add to `.bashrc`:

```bash
export FSLDIR=/home/jon/fsl
. "${FSLDIR}/etc/fslconf/fsl.sh"
export PATH="${FSLDIR}/share/fsl/bin:$PATH"
```

A native FSL installation is useful for testing individual preprocessing steps.

---

# 2. Reference workflow using fMRIPrep

## Validate the BIDS dataset

```bash
docker run --rm -ti \
    -v /home/jon/fmriprep/data:/data:ro \
    bids/validator /data
```

Ignore warnings:

```bash
docker run --rm -ti \
    -v /home/jon/fmriprep/data:/data:ro \
    bids/validator /data \
    --ignoreWarnings
```

---

## Run fMRIPrep

This configuration:

* keeps the data in native space
* skips FreeSurfer surface reconstruction

```bash
fmriprep-docker \
    /home/jon/fmriprep/data \
    /home/jon/fmriprep/derivatives \
    participant \
    --participant-label 00012 \
    --fs-no-reconall \
    --fs-license-file "$HOME/.freesurfer/license.txt" \
    --output-spaces T1w func \
    --nprocs 8 \
    --omp-nthreads 4 \
    --mem-mb 12000 \
    -w /home/jon/fmriprep/work \
    2>&1 | tee /home/jon/fmriprep/fmriprep.log
```

---

# 3. Developing and validating the lightweight pipeline

The lightweight pipeline intentionally implements only:

1. B₀ distortion correction
2. Motion correction
3. EPI → T1 registration

No slice timing correction, spatial normalization, nuisance regression, temporal filtering, smoothing, or surface reconstruction is performed.

Each stage was first validated independently before being integrated into the complete pipeline.

## Overall processing sequence

```text
Raw BOLD
      │
      ├── B0 distortion correction (FUGUE)
      │
      ├── Motion correction (MCFLIRT)
      │
      ├── Mean corrected BOLD
      │
      └── EPI → T1 registration (FLIRT or optional BBR)
```

The integrated script is:

```bash
./run_minimal_fmri_pipeline.sh
```

It supports two processing modes.

### Sequential mode

```bash
APPLY_COMBINED_TRANSFORMS=false
```

```text
Raw BOLD
      ↓
FUGUE
      ↓
MCFLIRT
```

The BOLD data are interpolated twice.

### Combined-transform mode (recommended)

```bash
APPLY_COMBINED_TRANSFORMS=true
```

```text
Estimate B0 shift map
        ↓
Provisional FUGUE correction
        ↓
Estimate motion (MCFLIRT)
        ↓
Combine B0 shift map
+ volume-specific motion matrices
        ↓
Single interpolation of original data
```

Only one interpolation is applied to the final retained BOLD series.

---

## Validate B₀ distortion correction

```bash
./run_fugue.sh
```

Inspect:

```bash
fsleyes \
    /home/jon/fmriprep/fugue_test/sub-00012_space-func_magnitude.nii.gz \
    /home/jon/fmriprep/fugue_test/sub-00012_task-rest_acq-product_run-01_mean.nii.gz \
    /home/jon/fmriprep/fugue_test/sub-00012_task-rest_acq-product_run-01_desc-b0corr_mean.nii.gz
```

Use the resampled magnitude image as the anatomical reference and toggle between the original and corrected EPI.

---

## Validate motion correction

```bash
./run_mcflirt.sh
```

Creates

```text
/home/jon/fmriprep/mcflirt_test/sub-00012_task-rest_acq-product_run-01_desc-b0corrMc_bold.nii.gz
```

Inspect the motion-corrected mean image together with the B₀-corrected mean image and review the motion parameter files.

---

## Validate EPI → T1 registration

```bash
./run_epi_reg.sh
```

The script:

* defaults to 6-DOF FLIRT;
* optionally uses boundary-based registration (BBR);
* estimates the functional-to-T1 transform;
* optionally estimates a T1-to-functional transform;
* provides registered images for visual inspection;
* leaves the full 4D BOLD series in functional space.

### BBR option

BBR uses:

```text
motion-corrected BOLD
        ↓
mean BOLD
        ↓
brain extraction
        ↓
white-matter segmentation
        ↓
epi_reg
```

Since the EPI has already been corrected with FUGUE, the field map is **not** supplied again during registration.

---

# 4. Implementation notes

## Relationship to fMRIPrep

The lightweight pipeline implements only the early preprocessing steps:

* B₀ distortion correction
* rigid-body motion correction
* EPI → T1 registration

Compared with fMRIPrep, it intentionally omits:

* slice-timing correction
* anatomical preprocessing beyond optional BET/FAST
* surface reconstruction
* spatial normalization
* confound estimation
* nuisance regression
* temporal filtering
* spatial smoothing

The goal is a transparent reference implementation suitable for validating vendor-neutral fMRI acquisitions while remaining broadly consistent with the initial stages of the fMRIPrep workflow.

## Combined transforms

The pipeline optionally combines the B₀ distortion warp with the MCFLIRT rigid-body transforms before the final resampling.

Compared with sequential FUGUE → MCFLIRT processing, this reduces interpolation of the retained BOLD data from two resampling steps to one. Although the visual differences are typically small for low-motion datasets, the combined-transform approach is methodologically preferable for production analyses.

## Legacy validation scripts

The individual scripts

```text
run_fugue.sh
run_mcflirt.sh
run_epi_reg.sh
```

were developed to validate each processing stage independently before integrating them into the full preprocessing pipeline. They remain useful for debugging individual components.

