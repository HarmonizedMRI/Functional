#!/usr/bin/env bash

set -euo pipefail

# ----------------------------------------------------------------------
# User settings
# ----------------------------------------------------------------------

SUBJECT="sub-00007"
SESSION="ses-umichmr75020241124"

BIDS_DIR="/home/jon/bidsRoot"

OUTPUT_DIR="${BIDS_DIR}/derivatives/minimal/${SUBJECT}/${SESSION}/anat"
WORK_DIR="/home/jon/fmriprep/work/mni_test/${SUBJECT}/${SESSION}"

MNI_SPACE="MNI152NLin2009cAsym"
MNI_RESOLUTION=1

mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}"

# ----------------------------------------------------------------------
# Input
# ----------------------------------------------------------------------

T1="${BIDS_DIR}/${SUBJECT}/${SESSION}/anat/${SUBJECT}_${SESSION}_T1w.nii.gz"

if [[ ! -f "${T1}" ]]; then
    echo "ERROR: T1 not found:"
    echo "  ${T1}"
    exit 1
fi

# ----------------------------------------------------------------------
# Check requirements
# ----------------------------------------------------------------------

for command in antsRegistrationSyN.sh antsApplyTransforms python3; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: ${command}"
        exit 1
    fi
done

if ! python3 -c "import templateflow.api" >/dev/null 2>&1; then
    echo "ERROR: Python package 'templateflow' is not installed."
    echo
    echo "Install with:"
    echo "  python3 -m pip install templateflow"
    exit 1
fi

# ----------------------------------------------------------------------
# Get MNI template
# ----------------------------------------------------------------------

echo "Locating TemplateFlow MNI template..."

MNI_TEMPLATE=$(python3 - "${MNI_RESOLUTION}" <<'PY'
import sys
from templateflow.api import get

resolution = int(sys.argv[1])

path = get(
    "MNI152NLin2009cAsym",
    resolution=resolution,
    suffix="T1w",
    extension=".nii.gz",
)

if isinstance(path, (list, tuple)):
    path = path[0]

print(path)
PY
)

if [[ ! -f "${MNI_TEMPLATE}" ]]; then
    echo "ERROR: MNI template not found:"
    echo "  ${MNI_TEMPLATE}"
    exit 1
fi

echo
echo "T1:"
echo "  ${T1}"
echo
echo "MNI template:"
echo "  ${MNI_TEMPLATE}"
echo

# ----------------------------------------------------------------------
# ANTs nonlinear registration
# ----------------------------------------------------------------------

PREFIX="${WORK_DIR}/T1w_to_${MNI_SPACE}_"

echo "Running ANTs nonlinear registration..."

antsRegistrationSyN.sh \
    -d 3 \
    -f "${MNI_TEMPLATE}" \
    -m "${T1}" \
    -o "${PREFIX}" \
    -t s

# ----------------------------------------------------------------------
# Public outputs
# ----------------------------------------------------------------------

T1_IN_MNI="${OUTPUT_DIR}/${SUBJECT}_${SESSION}_space-${MNI_SPACE}_desc-preproc_T1w.nii.gz"

T1_TO_MNI_XFM="${OUTPUT_DIR}/${SUBJECT}_${SESSION}_from-T1w_to-${MNI_SPACE}_mode-image_xfm.h5"

MNI_TO_T1_XFM="${OUTPUT_DIR}/${SUBJECT}_${SESSION}_from-${MNI_SPACE}_to-T1w_mode-image_xfm.h5"

cp \
    "${PREFIX}Warped.nii.gz" \
    "${T1_IN_MNI}"

# Forward composite transform: T1 -> MNI
antsApplyTransforms \
    -d 3 \
    -r "${MNI_TEMPLATE}" \
    -o "[${T1_TO_MNI_XFM},1]" \
    -t "${PREFIX}1Warp.nii.gz" \
    -t "${PREFIX}0GenericAffine.mat"

# Inverse composite transform: MNI -> T1
antsApplyTransforms \
    -d 3 \
    -r "${T1}" \
    -o "[${MNI_TO_T1_XFM},1]" \
    -t "[${PREFIX}0GenericAffine.mat,1]" \
    -t "${PREFIX}1InverseWarp.nii.gz"

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------

echo
echo "Done."
echo
echo "T1 in MNI space:"
echo "  ${T1_IN_MNI}"
echo
echo "T1 -> MNI transform:"
echo "  ${T1_TO_MNI_XFM}"
echo
echo "MNI -> T1 transform:"
echo "  ${MNI_TO_T1_XFM}"
echo
echo "QC:"
echo "  fsleyes ${MNI_TEMPLATE} ${T1_IN_MNI}"
