#!/usr/bin/env bash

set -euo pipefail

# ----------------------------------------------------------------------
# Initialize FSL
# ----------------------------------------------------------------------

export FSLDIR=/home/jon/fsl
. "${FSLDIR}/etc/fslconf/fsl.sh"
export PATH="${FSLDIR}/share/fsl/bin:$PATH"

# ----------------------------------------------------------------------
# User options
# ----------------------------------------------------------------------

NEGATE_FIELDMAP=false

# ----------------------------------------------------------------------
# Minimal FUGUE B0 distortion correction
# ----------------------------------------------------------------------

SUBJECT="sub-00012"
BIDS_DIR="/home/jon/fmriprep/data"
OUTPUT_DIR="/home/jon/fmriprep/fugue_test"

ACQ="product"
RUN="01"

BOLD_STEM="${SUBJECT}_task-rest_acq-${ACQ}_run-${RUN}"

BOLD="${BIDS_DIR}/${SUBJECT}/func/${BOLD_STEM}_bold.nii"
BOLD_JSON="${BIDS_DIR}/${SUBJECT}/func/${BOLD_STEM}_bold.json"

FIELDMAP_HZ="${BIDS_DIR}/${SUBJECT}/fmap/${SUBJECT}_fieldmap.nii.gz"
FIELDMAP_MAGNITUDE="${BIDS_DIR}/${SUBJECT}/fmap/${SUBJECT}_magnitude.nii.gz"

mkdir -p "${OUTPUT_DIR}"

MEAN_BOLD="${OUTPUT_DIR}/${BOLD_STEM}_mean"

FIELDMAP_EPI_HZ="${OUTPUT_DIR}/${SUBJECT}_space-func_fieldmap_hz"
FIELDMAP_EPI_RADS="${OUTPUT_DIR}/${SUBJECT}_space-func_fieldmap_rads"
MAGNITUDE_EPI="${OUTPUT_DIR}/${SUBJECT}_space-func_magnitude"

VOXEL_SHIFT="${OUTPUT_DIR}/${BOLD_STEM}_voxelshift"
BOLD_CORRECTED="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0corr_bold"
MEAN_CORRECTED="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0corr_mean"

PHASE_ENCODING_DIRECTION=$(jq -er '.PhaseEncodingDirection' "${BOLD_JSON}")
TOTAL_READOUT_TIME=$(jq -er '.TotalReadoutTime' "${BOLD_JSON}")

case "${PHASE_ENCODING_DIRECTION}" in
    i)  FUGUE_DIRECTION="x"; PE_DIM=1 ;;
    i-) FUGUE_DIRECTION="x-"; PE_DIM=1 ;;
    j)  FUGUE_DIRECTION="y"; PE_DIM=2 ;;
    j-) FUGUE_DIRECTION="y-"; PE_DIM=2 ;;
    k)  FUGUE_DIRECTION="z"; PE_DIM=3 ;;
    k-) FUGUE_DIRECTION="z-"; PE_DIM=3 ;;
    *) echo "Unsupported PhaseEncodingDirection"; exit 1 ;;
esac

PE_MATRIX_SIZE=$(fslval "${BOLD}" "dim${PE_DIM}")

DWELL_TIME=$(python3 - "${TOTAL_READOUT_TIME}" "${PE_MATRIX_SIZE}" <<'PY'
import sys
print(float(sys.argv[1])/(int(sys.argv[2])-1))
PY
)

echo "Negate field map: ${NEGATE_FIELDMAP}"

fslmaths "${BOLD}" -Tmean "${MEAN_BOLD}"

flirt \
    -in "${FIELDMAP_HZ}" \
    -ref "${MEAN_BOLD}" \
    -applyxfm \
    -usesqform \
    -interp trilinear \
    -out "${FIELDMAP_EPI_HZ}"

flirt \
    -in "${FIELDMAP_MAGNITUDE}" \
    -ref "${MEAN_BOLD}" \
    -applyxfm \
    -usesqform \
    -interp trilinear \
    -out "${MAGNITUDE_EPI}"

fslmaths \
    "${FIELDMAP_EPI_HZ}" \
    -mul 6.283185307179586 \
    "${FIELDMAP_EPI_RADS}"

if ${NEGATE_FIELDMAP}; then
    fslmaths "${FIELDMAP_EPI_RADS}" -mul -1 "${FIELDMAP_EPI_RADS}"
fi

fugue \
    --in="${BOLD}" \
    --loadfmap="${FIELDMAP_EPI_RADS}" \
    --dwell="${DWELL_TIME}" \
    --unwarpdir="${FUGUE_DIRECTION}" \
    --saveshift="${VOXEL_SHIFT}" \
    --unwarp="${BOLD_CORRECTED}"

fslmaths "${BOLD_CORRECTED}" -Tmean "${MEAN_CORRECTED}"

echo "Done."
echo "View with:"
echo "fsleyes \\"
echo "  ${MAGNITUDE_EPI}.nii.gz \\"
echo "  ${MEAN_BOLD}.nii.gz \\"
echo "  ${MEAN_CORRECTED}.nii.gz"
