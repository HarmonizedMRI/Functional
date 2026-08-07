#!/usr/bin/env bash

set -euo pipefail

# ======================================================================
# Minimal fMRI preprocessing pipeline
#
# Steps:
#   1. B0 distortion correction with FUGUE
#   2. Motion estimation/correction with MCFLIRT
#   3. Mean EPI -> T1 registration for QC/display
#
# Final 4D output modes:
#
#   APPLY_COMBINED_TRANSFORMS=false
#       Sequential output:
#           raw BOLD -> FUGUE -> MCFLIRT
#
#   APPLY_COMBINED_TRANSFORMS=true
#       Single-resampling output:
#           estimate B0 correction
#           estimate motion on provisional B0-corrected data
#           combine B0 shift map + volume-specific motion matrix
#           resample each original BOLD volume once
#
# The final 4D BOLD series remains in functional space.
# The EPI-to-T1 transform is used only for QC, overlays, and figures.
# ======================================================================

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

BIDS_DIR="/home/jon/fmriprep/data"
OUTPUT_ROOT="/home/jon/fmriprep/minimal_pipeline"

# false: use field map as provided
# true:  multiply field map by -1 before FUGUE
NEGATE_FIELDMAP=false

# false: standard six-DOF FLIRT registration
# true:  boundary-based registration using BET + FAST + epi_reg
USE_BBR=false

# false: sequential FUGUE then MCFLIRT resampling
# true:  combine B0 and motion transforms and resample original data once
APPLY_COMBINED_TRANSFORMS=true

# Final interpolation used only when APPLY_COMBINED_TRANSFORMS=true
FINAL_INTERPOLATION="spline"

# Retain temporary files used for transform estimation and combination
KEEP_INTERMEDIATES=true

# ----------------------------------------------------------------------
# Input files
# ----------------------------------------------------------------------

BOLD_STEM="${SUBJECT}_task-rest_acq-${ACQ}_run-${RUN}"

BOLD="${BIDS_DIR}/${SUBJECT}/func/${BOLD_STEM}_bold.nii"
BOLD_JSON="${BIDS_DIR}/${SUBJECT}/func/${BOLD_STEM}_bold.json"

FIELDMAP_HZ="${BIDS_DIR}/${SUBJECT}/fmap/${SUBJECT}_fieldmap.nii.gz"
FIELDMAP_MAGNITUDE="${BIDS_DIR}/${SUBJECT}/fmap/${SUBJECT}_magnitude.nii.gz"

T1="${BIDS_DIR}/${SUBJECT}/anat/${SUBJECT}_T1w.nii"

# ----------------------------------------------------------------------
# Output directories and filenames
# ----------------------------------------------------------------------

OUTPUT_DIR="${OUTPUT_ROOT}/${SUBJECT}/${BOLD_STEM}"
WORK_DIR="${OUTPUT_DIR}/work"

mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}"

RAW_MEAN="${OUTPUT_DIR}/${BOLD_STEM}_desc-raw_mean"

FIELDMAP_FUNC_HZ="${OUTPUT_DIR}/${SUBJECT}_space-func_fieldmap_hz"
FIELDMAP_FUNC_RADS="${OUTPUT_DIR}/${SUBJECT}_space-func_fieldmap_rads"
MAGNITUDE_FUNC="${OUTPUT_DIR}/${SUBJECT}_space-func_magnitude"

VOXEL_SHIFT="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0_voxelshift"

BOLD_B0="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0corr_bold"
BOLD_B0_MEAN="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0corr_mean"

BOLD_MC="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0corrMc_bold"
BOLD_MC_MEAN="${OUTPUT_DIR}/${BOLD_STEM}_desc-b0corrMc_mean"

PROVISIONAL_B0="${WORK_DIR}/${BOLD_STEM}_desc-b0corrProvisional_bold"
PROVISIONAL_MC="${WORK_DIR}/${BOLD_STEM}_desc-b0corrMcProvisional_bold"
PROVISIONAL_MC_MATS="${PROVISIONAL_MC}.mat"

RAW_SPLIT_DIR="${WORK_DIR}/raw_volumes"
WARP_DIR="${WORK_DIR}/combined_warps"
CORRECTED_SPLIT_DIR="${WORK_DIR}/corrected_volumes"

FUNC_TO_T1_PREFIX="${OUTPUT_DIR}/${BOLD_STEM}_from-func_to-T1w"
FUNC_TO_T1_MATRIX="${FUNC_TO_T1_PREFIX}.mat"
MEAN_IN_T1="${OUTPUT_DIR}/${BOLD_STEM}_space-T1w_desc-b0corrMc_mean"

T1_BRAIN="${OUTPUT_DIR}/${SUBJECT}_desc-brain_T1w"
T1_FAST_PREFIX="${OUTPUT_DIR}/${SUBJECT}_fast"
WM_SEG="${T1_FAST_PREFIX}_wmseg"

# ----------------------------------------------------------------------
# Validate inputs and commands
# ----------------------------------------------------------------------

for file in \
    "${BOLD}" \
    "${BOLD_JSON}" \
    "${FIELDMAP_HZ}" \
    "${FIELDMAP_MAGNITUDE}" \
    "${T1}"
do
    if [[ ! -f "${file}" ]]; then
        echo "ERROR: Required input file not found:" >&2
        echo "  ${file}" >&2
        exit 1
    fi
done

for command in \
    fslmaths \
    fslval \
    flirt \
    fugue \
    mcflirt \
    jq \
    python3
do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: ${command}" >&2
        exit 1
    fi
done

if ${APPLY_COMBINED_TRANSFORMS}; then
    for command in fslsplit fslmerge convertwarp applywarp; do
        if ! command -v "${command}" >/dev/null 2>&1; then
            echo "ERROR: Required combined-transform command not found: ${command}" >&2
            exit 1
        fi
    done
fi

if ${USE_BBR}; then
    for command in bet fast epi_reg; do
        if ! command -v "${command}" >/dev/null 2>&1; then
            echo "ERROR: Required BBR command not found: ${command}" >&2
            exit 1
        fi
    done
fi

# ----------------------------------------------------------------------
# Read BIDS metadata
# ----------------------------------------------------------------------

PHASE_ENCODING_DIRECTION=$(jq -er '.PhaseEncodingDirection' "${BOLD_JSON}")
TOTAL_READOUT_TIME=$(jq -er '.TotalReadoutTime' "${BOLD_JSON}")

case "${PHASE_ENCODING_DIRECTION}" in
    i)  FUGUE_DIRECTION="x";  PE_DIM=1 ;;
    i-) FUGUE_DIRECTION="x-"; PE_DIM=1 ;;
    j)  FUGUE_DIRECTION="y";  PE_DIM=2 ;;
    j-) FUGUE_DIRECTION="y-"; PE_DIM=2 ;;
    k)  FUGUE_DIRECTION="z";  PE_DIM=3 ;;
    k-) FUGUE_DIRECTION="z-"; PE_DIM=3 ;;
    *)
        echo "ERROR: Unsupported PhaseEncodingDirection:" >&2
        echo "  ${PHASE_ENCODING_DIRECTION}" >&2
        exit 1
        ;;
esac

PE_MATRIX_SIZE=$(fslval "${BOLD}" "dim${PE_DIM}")
N_VOLUMES=$(fslval "${BOLD}" dim4)

if [[ "${PE_MATRIX_SIZE}" -le 1 ]]; then
    echo "ERROR: Invalid phase-encoding matrix size: ${PE_MATRIX_SIZE}" >&2
    exit 1
fi

DWELL_TIME=$(python3 - "${TOTAL_READOUT_TIME}" "${PE_MATRIX_SIZE}" <<'PY'
import sys
total_readout_time = float(sys.argv[1])
pe_matrix_size = int(sys.argv[2])
print(f"{total_readout_time / (pe_matrix_size - 1):.12g}")
PY
)

echo
echo "Subject:                       ${SUBJECT}"
echo "Acquisition:                   ${ACQ}"
echo "BOLD volumes:                  ${N_VOLUMES}"
echo "PhaseEncodingDirection:        ${PHASE_ENCODING_DIRECTION}"
echo "FUGUE direction:               ${FUGUE_DIRECTION}"
echo "TotalReadoutTime:              ${TOTAL_READOUT_TIME} s"
echo "Effective echo spacing:        ${DWELL_TIME} s"
echo "Negate field map:              ${NEGATE_FIELDMAP}"
echo "Use BBR:                       ${USE_BBR}"
echo "Apply combined transforms:     ${APPLY_COMBINED_TRANSFORMS}"
echo

# ======================================================================
# Step 1: Prepare field map and estimate B0 correction
# ======================================================================

echo "Step 1/3: B0 distortion correction setup"

fslmaths \
    "${BOLD}" \
    -Tmean \
    "${RAW_MEAN}"

flirt \
    -in "${FIELDMAP_HZ}" \
    -ref "${RAW_MEAN}" \
    -applyxfm \
    -usesqform \
    -interp trilinear \
    -out "${FIELDMAP_FUNC_HZ}"

flirt \
    -in "${FIELDMAP_MAGNITUDE}" \
    -ref "${RAW_MEAN}" \
    -applyxfm \
    -usesqform \
    -interp trilinear \
    -out "${MAGNITUDE_FUNC}"

fslmaths \
    "${FIELDMAP_FUNC_HZ}" \
    -mul 6.283185307179586 \
    "${FIELDMAP_FUNC_RADS}"

if ${NEGATE_FIELDMAP}; then
    echo "Negating field map."
    fslmaths \
        "${FIELDMAP_FUNC_RADS}" \
        -mul -1 \
        "${FIELDMAP_FUNC_RADS}"
fi

if ${APPLY_COMBINED_TRANSFORMS}; then
    B0_ESTIMATION_OUTPUT="${PROVISIONAL_B0}"
else
    B0_ESTIMATION_OUTPUT="${BOLD_B0}"
fi

fugue \
    --in="${BOLD}" \
    --loadfmap="${FIELDMAP_FUNC_RADS}" \
    --dwell="${DWELL_TIME}" \
    --unwarpdir="${FUGUE_DIRECTION}" \
    --saveshift="${VOXEL_SHIFT}" \
    --unwarp="${B0_ESTIMATION_OUTPUT}"

fslmaths \
    "${B0_ESTIMATION_OUTPUT}" \
    -Tmean \
    "${BOLD_B0_MEAN}"

# ======================================================================
# Step 2: Motion estimation and final functional-space output
# ======================================================================

echo "Step 2/3: Motion correction"

if ${APPLY_COMBINED_TRANSFORMS}; then

    echo "Estimating motion on provisional B0-corrected data."

    mcflirt \
        -in "${PROVISIONAL_B0}" \
        -out "${PROVISIONAL_MC}" \
        -plots \
        -mats \
        -rmsrel \
        -rmsabs \
        -spline_final

    mkdir -p "${RAW_SPLIT_DIR}" "${WARP_DIR}" "${CORRECTED_SPLIT_DIR}"

    rm -f "${RAW_SPLIT_DIR}"/vol*.nii.gz
    rm -f "${WARP_DIR}"/warp*.nii.gz
    rm -f "${CORRECTED_SPLIT_DIR}"/vol*.nii.gz

    fslsplit \
        "${BOLD}" \
        "${RAW_SPLIT_DIR}/vol" \
        -t

    for ((index=0; index<N_VOLUMES; index++)); do
        printf -v volume_id "%04d" "${index}"

        RAW_VOLUME="${RAW_SPLIT_DIR}/vol${volume_id}.nii.gz"
        MOTION_MATRIX="${PROVISIONAL_MC_MATS}/MAT_${volume_id}"
        COMBINED_WARP="${WARP_DIR}/warp${volume_id}"
        CORRECTED_VOLUME="${CORRECTED_SPLIT_DIR}/vol${volume_id}"

        if [[ ! -f "${MOTION_MATRIX}" ]]; then
            echo "ERROR: Missing MCFLIRT matrix:" >&2
            echo "  ${MOTION_MATRIX}" >&2
            exit 1
        fi

        convertwarp \
            --ref="${RAW_MEAN}" \
            --shiftmap="${VOXEL_SHIFT}" \
            --shiftdir="${FUGUE_DIRECTION}" \
            --premat="${MOTION_MATRIX}" \
            --out="${COMBINED_WARP}" \
            --relout

        applywarp \
            --ref="${RAW_MEAN}" \
            --in="${RAW_VOLUME}" \
            --warp="${COMBINED_WARP}" \
            --rel \
            --interp="${FINAL_INTERPOLATION}" \
            --out="${CORRECTED_VOLUME}"
    done

    fslmerge \
        -t "${BOLD_MC}" \
        "${CORRECTED_SPLIT_DIR}"/vol*.nii.gz

    cp "${PROVISIONAL_MC}.par" "${BOLD_MC}.par"
    cp "${PROVISIONAL_MC}_rel.rms" "${BOLD_MC}_rel.rms"
    cp "${PROVISIONAL_MC}_abs.rms" "${BOLD_MC}_abs.rms"

    rm -rf "${BOLD_MC}.mat"
    cp -r "${PROVISIONAL_MC_MATS}" "${BOLD_MC}.mat"

else

    echo "Using sequential FUGUE then MCFLIRT resampling."

    mcflirt \
        -in "${BOLD_B0}" \
        -out "${BOLD_MC}" \
        -plots \
        -mats \
        -rmsrel \
        -rmsabs \
        -spline_final

fi

fslmaths \
    "${BOLD_MC}" \
    -Tmean \
    "${BOLD_MC_MEAN}"

# ======================================================================
# Step 3: Mean EPI to T1 registration for display/QC
# ======================================================================

echo "Step 3/3: Mean EPI-to-T1 registration"

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
        --epi="${BOLD_MC_MEAN}" \
        --t1="${T1}" \
        --t1brain="${T1_BRAIN}" \
        --wmseg="${WM_SEG}" \
        --out="${FUNC_TO_T1_PREFIX}"

    cp \
        "${FUNC_TO_T1_PREFIX}.nii.gz" \
        "${MEAN_IN_T1}.nii.gz"

else

    echo "Registration method: six-DOF FLIRT"

    flirt \
        -in "${BOLD_MC_MEAN}" \
        -ref "${T1}" \
        -out "${MEAN_IN_T1}" \
        -omat "${FUNC_TO_T1_MATRIX}" \
        -dof 6 \
        -cost normmi \
        -searchrx -90 90 \
        -searchry -90 90 \
        -searchrz -90 90 \
        -interp trilinear

fi

# ----------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------

if ! ${KEEP_INTERMEDIATES}; then
    rm -rf "${WORK_DIR}"
fi

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------

echo
echo "Pipeline completed."
echo
echo "Final B0- and motion-corrected BOLD:"
echo "  ${BOLD_MC}.nii.gz"
echo
echo "Motion parameters:"
echo "  ${BOLD_MC}.par"
echo
echo "Motion matrices:"
echo "  ${BOLD_MC}.mat/"
echo
echo "EPI-to-T1 matrix:"
echo "  ${FUNC_TO_T1_MATRIX}"
echo
echo "Mean EPI in T1 space:"
echo "  ${MEAN_IN_T1}.nii.gz"
echo
echo "B0 QC:"
echo "  fsleyes ${MAGNITUDE_FUNC}.nii.gz ${RAW_MEAN}.nii.gz ${BOLD_B0_MEAN}.nii.gz"
echo
echo "EPI-to-T1 QC:"
echo "  fsleyes ${T1} ${MEAN_IN_T1}.nii.gz"
