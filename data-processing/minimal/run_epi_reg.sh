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

# false: standard rigid-body FLIRT registration
# true:  boundary-based registration using BET + FAST + epi_reg
USE_BBR=false

BIDS_DIR="/home/jon/fmriprep/data"
MCFLIRT_DIR="/home/jon/fmriprep/mcflirt_test"
OUTPUT_DIR="/home/jon/fmriprep/bold_to_t1_test"

mkdir -p "${OUTPUT_DIR}"

BOLD_STEM="${SUBJECT}_task-rest_acq-${ACQ}_run-${RUN}"

T1="${BIDS_DIR}/${SUBJECT}/anat/${SUBJECT}_T1w.nii"

BOLD_MC="${MCFLIRT_DIR}/${BOLD_STEM}_desc-b0corrMc_bold.nii.gz"
BOLD_MEAN="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0corrMc_mean"

FUNC_TO_T1_PREFIX="${OUTPUT_DIR}/${BOLD_STEM}_from-func_to-T1w"
FUNC_TO_T1_MATRIX="${FUNC_TO_T1_PREFIX}.mat"
REGISTERED_MEAN="${FUNC_TO_T1_PREFIX}.nii.gz"

T1_TO_FUNC_MATRIX="${OUTPUT_DIR}/${BOLD_STEM}_from-T1w_to-func.mat"
T1_IN_FUNC="${OUTPUT_DIR}/${SUBJECT}_space-func_T1w"

T1_BRAIN="${OUTPUT_DIR}/${SUBJECT}_desc-brain_T1w"
T1_FAST_PREFIX="${OUTPUT_DIR}/${SUBJECT}_fast"
WM_SEG="${T1_FAST_PREFIX}_wmseg"

# ----------------------------------------------------------------------
# Check inputs and commands
# ----------------------------------------------------------------------

for file in "${T1}" "${BOLD_MC}"; do
    if [[ ! -f "${file}" ]]; then
        echo "ERROR: Input file not found:"
        echo "  ${file}"
        exit 1
    fi
done

for command in fslmaths flirt convert_xfm; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: ${command}" >&2
        exit 1
    fi
done

if ${USE_BBR}; then
    for command in bet fast epi_reg; do
        if ! command -v "${command}" >/dev/null 2>&1; then
            echo "ERROR: Required BBR command not found: ${command}" >&2
            exit 1
        fi
    done
fi

# ----------------------------------------------------------------------
# Create mean motion-corrected EPI
# ----------------------------------------------------------------------

echo "Creating mean motion-corrected EPI..."

fslmaths \
    "${BOLD_MC}" \
    -Tmean \
    "${BOLD_MEAN}"

# ----------------------------------------------------------------------
# Estimate functional-to-T1 registration
# ----------------------------------------------------------------------

if ${USE_BBR}; then

    echo "Registration method: BBR"

    bet \
        "${T1}" \
        "${T1_BRAIN}" \
        -R \
        -f 0.30 \
        -m

    fast \
        -t 1 \
        -n 3 \
        -o "${T1_FAST_PREFIX}" \
        "${T1_BRAIN}"

    fslmaths \
        "${T1_FAST_PREFIX}_pve_2" \
        -thr 0.5 \
        -bin \
        "${WM_SEG}"

    epi_reg \
        --epi="${BOLD_MEAN}" \
        --t1="${T1}" \
        --t1brain="${T1_BRAIN}" \
        --wmseg="${WM_SEG}" \
        --out="${FUNC_TO_T1_PREFIX}"

else

    echo "Registration method: 6-DOF FLIRT"

    flirt \
        -in "${BOLD_MEAN}" \
        -ref "${T1}" \
        -out "${REGISTERED_MEAN}" \
        -omat "${FUNC_TO_T1_MATRIX}" \
        -dof 6 \
        -cost normmi \
        -searchrx -90 90 \
        -searchry -90 90 \
        -searchrz -90 90 \
        -interp trilinear

fi

# ----------------------------------------------------------------------
# Invert the transform and bring T1 into functional space
# ----------------------------------------------------------------------

echo "Inverting transform..."

convert_xfm \
    -omat "${T1_TO_FUNC_MATRIX}" \
    -inverse "${FUNC_TO_T1_MATRIX}"

echo "Resampling T1 into functional space..."

flirt \
    -in "${T1}" \
    -ref "${BOLD_MEAN}" \
    -applyxfm \
    -init "${T1_TO_FUNC_MATRIX}" \
    -interp trilinear \
    -out "${T1_IN_FUNC}"

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------

echo
echo "Registration completed."
echo
echo "Use BBR:"
echo "  ${USE_BBR}"
echo
echo "Functional-to-T1 matrix:"
echo "  ${FUNC_TO_T1_MATRIX}"
echo
echo "T1-to-functional matrix:"
echo "  ${T1_TO_FUNC_MATRIX}"
echo
echo "Mean BOLD:"
echo "  ${BOLD_MEAN}.nii.gz"
echo
echo "T1 in functional space:"
echo "  ${T1_IN_FUNC}.nii.gz"
echo
echo "Inspect with:"
echo
echo "fsleyes \\"
echo "  ${BOLD_MEAN}.nii.gz \\"
echo "  ${T1_IN_FUNC}.nii.gz"
