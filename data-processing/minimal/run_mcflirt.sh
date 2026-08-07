#!/usr/bin/env bash

set -euo pipefail

# ----------------------------------------------------------------------
# Initialize FSL
# ----------------------------------------------------------------------

export FSLDIR=/home/jon/fsl
. "${FSLDIR}/etc/fslconf/fsl.sh"
export PATH="${FSLDIR}/share/fsl/bin:$PATH"

# ----------------------------------------------------------------------
# User settings
# ----------------------------------------------------------------------

SUBJECT="sub-00012"
ACQ="product"
RUN="01"

FUGUE_DIR="/home/jon/fmriprep/fugue_test"
OUTPUT_DIR="/home/jon/fmriprep/mcflirt_test"

mkdir -p "${OUTPUT_DIR}"

BOLD_STEM="${SUBJECT}_task-rest_acq-${ACQ}_run-${RUN}"

INPUT_BOLD="${FUGUE_DIR}/${BOLD_STEM}_desc-b0corr_bold.nii.gz"

OUTPUT_BOLD="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0corrMc_bold"
INPUT_MEAN="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0corr_mean"
OUTPUT_MEAN="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0corrMc_mean"
TEMPORAL_SD_BEFORE="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0corr_stdev"
TEMPORAL_SD_AFTER="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0corrMc_stdev"

# ----------------------------------------------------------------------
# Check input
# ----------------------------------------------------------------------

if [[ ! -f "${INPUT_BOLD}" ]]; then
    echo "ERROR: Input BOLD image not found:"
    echo "  ${INPUT_BOLD}"
    exit 1
fi

echo
echo "Input BOLD:"
echo "  ${INPUT_BOLD}"
echo
echo "Output BOLD:"
echo "  ${OUTPUT_BOLD}.nii.gz"
echo

# ----------------------------------------------------------------------
# Create pre-motion-correction QC images
# ----------------------------------------------------------------------

echo "Creating pre-MCFLIRT mean and temporal SD images..."

fslmaths \
    "${INPUT_BOLD}" \
    -Tmean \
    "${INPUT_MEAN}"

fslmaths \
    "${INPUT_BOLD}" \
    -Tstd \
    "${TEMPORAL_SD_BEFORE}"

# ----------------------------------------------------------------------
# Run MCFLIRT
#
# -plots         Save six rigid-body motion parameters
# -mats          Save one transformation matrix per volume
# -rmsrel        Save relative RMS displacement
# -rmsabs        Save absolute RMS displacement
# -spline_final  Use spline interpolation for final resampling
# ----------------------------------------------------------------------

echo "Running MCFLIRT..."

mcflirt \
    -in "${INPUT_BOLD}" \
    -out "${OUTPUT_BOLD}" \
    -plots \
    -mats \
    -rmsrel \
    -rmsabs \
    -spline_final

# ----------------------------------------------------------------------
# Create post-motion-correction QC images
# ----------------------------------------------------------------------

echo "Creating post-MCFLIRT mean and temporal SD images..."

fslmaths \
    "${OUTPUT_BOLD}" \
    -Tmean \
    "${OUTPUT_MEAN}"

fslmaths \
    "${OUTPUT_BOLD}" \
    -Tstd \
    "${TEMPORAL_SD_AFTER}"

echo
echo "MCFLIRT completed."
echo
echo "Corrected time series:"
echo "  ${OUTPUT_BOLD}.nii.gz"
echo
echo "Motion parameters:"
echo "  ${OUTPUT_BOLD}.par"
echo
echo "Transformation matrices:"
echo "  ${OUTPUT_BOLD}.mat/"
echo
echo "Relative RMS displacement:"
echo "  ${OUTPUT_BOLD}_rel.rms"
echo
echo "Absolute RMS displacement:"
echo "  ${OUTPUT_BOLD}_abs.rms"
echo
echo "Inspect mean and temporal-SD images with:"
echo
echo "fsleyes \\"
echo "  ${INPUT_MEAN}.nii.gz \\"
echo "  ${OUTPUT_MEAN}.nii.gz \\"
echo "  ${TEMPORAL_SD_BEFORE}.nii.gz \\"
echo "  ${TEMPORAL_SD_AFTER}.nii.gz"

