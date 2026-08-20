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
#       Sequential:
#           raw BOLD -> FUGUE -> MCFLIRT
#
#   APPLY_COMBINED_TRANSFORMS=true
#       Combined:
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

SUBJECT="sub-00007"
SESSION="ses-umichmr75020241124"

TASK="vismotor"
ACQ="product"
RUN="01"

# Root of the BIDS dataset created by buildBIDS.
BIDS_DIR="/home/jon/bidsRoot"

# Public-facing derivatives.
DERIVATIVES_ROOT="${BIDS_DIR}/derivatives/minimal"

# Temporary/intermediate files.
WORK_ROOT="/home/jon/temp/data-processing/minimal"

# false: use field map as provided
# true:  multiply field map by -1 before FUGUE
NEGATE_FIELDMAP=false

# false: standard 6-DOF FLIRT registration
# true:  boundary-based registration using BET + FAST + epi_reg
USE_BBR=false

# false: sequential FUGUE -> MCFLIRT resampling
# true:  combine B0 and motion transforms and resample original data once
APPLY_COMBINED_TRANSFORMS=true

# Used only when APPLY_COMBINED_TRANSFORMS=true
FINAL_INTERPOLATION="spline"

# Keep temporary files used for transform estimation/debugging.
KEEP_INTERMEDIATES=true

# ----------------------------------------------------------------------
# Input filenames
# ----------------------------------------------------------------------

SESSION_DIR="${BIDS_DIR}/${SUBJECT}/${SESSION}"

BOLD_STEM="${SUBJECT}_${SESSION}_task-${TASK}_acq-${ACQ}_run-${RUN}"

BOLD="${SESSION_DIR}/func/${BOLD_STEM}_bold.nii"
BOLD_JSON="${SESSION_DIR}/func/${BOLD_STEM}_bold.json"

FIELDMAP_HZ="${SESSION_DIR}/fmap/${SUBJECT}_${SESSION}_fieldmap.nii.gz"
FIELDMAP_MAGNITUDE="${SESSION_DIR}/fmap/${SUBJECT}_${SESSION}_magnitude.nii.gz"

T1="${SESSION_DIR}/anat/${SUBJECT}_${SESSION}_T1w.nii.gz"

# ----------------------------------------------------------------------
# Public derivative directories
# ----------------------------------------------------------------------

DERIV_SESSION_DIR="${DERIVATIVES_ROOT}/${SUBJECT}/${SESSION}"

FUNC_DIR="${DERIV_SESSION_DIR}/func"
FMAP_DIR="${DERIV_SESSION_DIR}/fmap"
ANAT_DIR="${DERIV_SESSION_DIR}/anat"
QC_DIR="${DERIV_SESSION_DIR}/qc"

WORK_DIR="${WORK_ROOT}/${SUBJECT}/${SESSION}/${BOLD_STEM}"

mkdir -p \
    "${DERIVATIVES_ROOT}" \
    "${FUNC_DIR}" \
    "${FMAP_DIR}" \
    "${ANAT_DIR}" \
    "${QC_DIR}" \
    "${WORK_DIR}"

DERIVATIVE_STEM="${BOLD_STEM}"

# ----------------------------------------------------------------------
# Public-facing outputs
# ----------------------------------------------------------------------

RAW_MEAN="${QC_DIR}/${DERIVATIVE_STEM}_desc-raw_mean"

FIELDMAP_FUNC_HZ="${FMAP_DIR}/${SUBJECT}_${SESSION}_space-func_desc-resampled_fieldmap"
FIELDMAP_FUNC_RADS="${WORK_DIR}/${SUBJECT}_${SESSION}_space-func_fieldmap_rads"

MAGNITUDE_FUNC="${FMAP_DIR}/${SUBJECT}_${SESSION}_space-func_desc-resampled_magnitude"

VOXEL_SHIFT="${FMAP_DIR}/${DERIVATIVE_STEM}_desc-b0_voxelshift"

BOLD_B0_MEAN="${QC_DIR}/${DERIVATIVE_STEM}_desc-b0corr_mean"

BOLD_MC="${FUNC_DIR}/${DERIVATIVE_STEM}_desc-b0corrMc_bold"
BOLD_MC_MEAN="${FUNC_DIR}/${DERIVATIVE_STEM}_desc-b0corrMc_mean"

FUNC_TO_T1_PREFIX="${ANAT_DIR}/${DERIVATIVE_STEM}_from-func_to-T1w_mode-image_xfm"
FUNC_TO_T1_MATRIX="${FUNC_TO_T1_PREFIX}.mat"

MEAN_IN_T1="${FUNC_DIR}/${DERIVATIVE_STEM}_space-T1w_desc-b0corrMc_mean"

# ----------------------------------------------------------------------
# Working files
# ----------------------------------------------------------------------

BOLD_B0="${WORK_DIR}/${BOLD_STEM}_desc-b0corr_bold"

PROVISIONAL_B0="${WORK_DIR}/${BOLD_STEM}_desc-b0corrProvisional_bold"
PROVISIONAL_MC="${WORK_DIR}/${BOLD_STEM}_desc-b0corrMcProvisional_bold"
PROVISIONAL_MC_MATS="${PROVISIONAL_MC}.mat"

RAW_SPLIT_DIR="${WORK_DIR}/raw_volumes"
WARP_DIR="${WORK_DIR}/combined_warps"
CORRECTED_SPLIT_DIR="${WORK_DIR}/corrected_volumes"

T1_BRAIN="${WORK_DIR}/${SUBJECT}_${SESSION}_desc-brain_T1w"
T1_FAST_PREFIX="${WORK_DIR}/${SUBJECT}_${SESSION}_fast"
WM_SEG="${T1_FAST_PREFIX}_wmseg"

# ----------------------------------------------------------------------
# Create derivatives dataset_description.json
# ----------------------------------------------------------------------

cat > "${DERIVATIVES_ROOT}/dataset_description.json" <<EOF
{
  "Name": "Minimal fMRI preprocessing derivatives",
  "BIDSVersion": "1.10.0",
  "DatasetType": "derivative",
  "GeneratedBy": [
    {
      "Name": "run_minimal_fmri_pipeline.sh",
      "Description": "FSL-based B0 distortion correction, rigid-body motion correction, and EPI-to-T1 registration"
    },
    {
      "Name": "FSL"
    }
  ]
}
EOF

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
    i)
        FUGUE_DIRECTION="x"
        PE_DIM=1
        ;;
    i-)
        FUGUE_DIRECTION="x-"
        PE_DIM=1
        ;;
    j)
        FUGUE_DIRECTION="y"
        PE_DIM=2
        ;;
    j-)
        FUGUE_DIRECTION="y-"
        PE_DIM=2
        ;;
    k)
        FUGUE_DIRECTION="z"
        PE_DIM=3
        ;;
    k-)
        FUGUE_DIRECTION="z-"
        PE_DIM=3
        ;;
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
echo "Session:                       ${SESSION}"
echo "Acquisition:                   ${ACQ}"
echo "BOLD volumes:                  ${N_VOLUMES}"
echo "BIDS directory:                ${BIDS_DIR}"
echo "Derivatives root:              ${DERIVATIVES_ROOT}"
echo "PhaseEncodingDirection:        ${PHASE_ENCODING_DIRECTION}"
echo "FUGUE direction:               ${FUGUE_DIRECTION}"
echo "TotalReadoutTime:              ${TOTAL_READOUT_TIME} s"
echo "Effective echo spacing:        ${DWELL_TIME} s"
echo "Negate field map:              ${NEGATE_FIELDMAP}"
echo "Use BBR:                       ${USE_BBR}"
echo "Apply combined transforms:     ${APPLY_COMBINED_TRANSFORMS}"
echo

# ======================================================================
# Step 1: B0 distortion correction
# ======================================================================

echo "Step 1/3: B0 distortion correction"

fslmaths \
    "${BOLD}" \
    -Tmean \
    "${RAW_MEAN}"

# Resample field map and magnitude to functional grid using NIfTI
# world-coordinate information.
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

# FUGUE expects rad/s.
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
# Step 2: Motion correction
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

    mkdir -p \
        "${RAW_SPLIT_DIR}" \
        "${WARP_DIR}" \
        "${CORRECTED_SPLIT_DIR}"

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

    # Preserve motion diagnostics.
    cp \
        "${PROVISIONAL_MC}.par" \
        "${QC_DIR}/${DERIVATIVE_STEM}_desc-motion_parameters.tsv"

    cp \
        "${PROVISIONAL_MC}_rel.rms" \
        "${QC_DIR}/${DERIVATIVE_STEM}_desc-relativeMotion_rms.tsv"

    cp \
        "${PROVISIONAL_MC}_abs.rms" \
        "${QC_DIR}/${DERIVATIVE_STEM}_desc-absoluteMotion_rms.tsv"

    rm -rf \
        "${QC_DIR}/${DERIVATIVE_STEM}_desc-motion_matrices"

    cp -r \
        "${PROVISIONAL_MC_MATS}" \
        "${QC_DIR}/${DERIVATIVE_STEM}_desc-motion_matrices"

else

    echo "Using sequential FUGUE -> MCFLIRT resampling."

    mcflirt \
        -in "${BOLD_B0}" \
        -out "${BOLD_MC}" \
        -plots \
        -mats \
        -rmsrel \
        -rmsabs \
        -spline_final

    cp \
        "${BOLD_MC}.par" \
        "${QC_DIR}/${DERIVATIVE_STEM}_desc-motion_parameters.tsv"

    cp \
        "${BOLD_MC}_rel.rms" \
        "${QC_DIR}/${DERIVATIVE_STEM}_desc-relativeMotion_rms.tsv"

    cp \
        "${BOLD_MC}_abs.rms" \
        "${QC_DIR}/${DERIVATIVE_STEM}_desc-absoluteMotion_rms.tsv"

    rm -rf \
        "${QC_DIR}/${DERIVATIVE_STEM}_desc-motion_matrices"

    cp -r \
        "${BOLD_MC}.mat" \
        "${QC_DIR}/${DERIVATIVE_STEM}_desc-motion_matrices"

fi

fslmaths \
    "${BOLD_MC}" \
    -Tmean \
    "${BOLD_MC_MEAN}"

# ----------------------------------------------------------------------
# JSON sidecar for final BOLD derivative
# ----------------------------------------------------------------------

cat > "${BOLD_MC}.json" <<EOF
{
  "Description": "BOLD series corrected for static B0 distortion and rigid-body head motion",
  "Sources": [
    "bids::${SUBJECT}/${SESSION}/func/${BOLD_STEM}_bold.nii",
    "bids::${SUBJECT}/${SESSION}/fmap/${SUBJECT}_${SESSION}_fieldmap.nii.gz"
  ],
  "PhaseEncodingDirection": "${PHASE_ENCODING_DIRECTION}",
  "TotalReadoutTime": ${TOTAL_READOUT_TIME},
  "B0FieldMapUnits": "Hz",
  "B0FieldMapNegated": ${NEGATE_FIELDMAP},
  "CombinedTransformResampling": ${APPLY_COMBINED_TRANSFORMS},
  "Interpolation": "${FINAL_INTERPOLATION}",
  "MotionCorrection": "MCFLIRT",
  "DistortionCorrection": "FUGUE"
}
EOF

# ======================================================================
# Step 3: Mean EPI -> T1 registration
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

    echo "Registration method: 6-DOF FLIRT"

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
echo "Public derivative dataset:"
echo "  ${DERIVATIVES_ROOT}"
echo
echo "Final B0- and motion-corrected BOLD:"
echo "  ${BOLD_MC}.nii.gz"
echo
echo "Final BOLD sidecar:"
echo "  ${BOLD_MC}.json"
echo
echo "Motion/QC files:"
echo "  ${QC_DIR}"
echo
echo "Resampled field-map products:"
echo "  ${FMAP_DIR}"
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
