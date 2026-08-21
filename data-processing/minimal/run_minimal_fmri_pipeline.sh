#!/usr/bin/env bash

set -euo pipefail

# ======================================================================
# Minimal fMRI preprocessing pipeline
#
# Geometry strategy
# -----------------
# 1. Correct field-map geometry empirically:
#      fmap magnitude -> T1w using rigid + SyN (ANTs)
#    The same transform is applied to the Hz field map.
#
# 2. For Pulseq BOLD only, correct the static Pulseq geometry empirically:
#      raw Pulseq mean -> matching raw product mean using rigid + SyN (ANTs)
#    This registration is deliberately estimated BEFORE B0 correction because
#    the Pulseq and product EPI acquisitions have closely matched B0 distortion
#    by design. The transform therefore primarily captures prescription offset
#    and smooth geometric mismatch such as uncorrected gradient nonlinearity.
#
# 3. Perform B0 distortion correction and motion correction.
#
# 4. Optionally combine B0 and motion transforms so that these two corrections
#    are applied in one final interpolation.
#
# 5. Estimate mean EPI -> T1w registration for QC/display.
#
# 6. Optionally estimate T1w -> MNI152NLin2009cAsym normalization.
#
# NOTE:
# The ANTs nonlinear registrations are empirical geometry corrections. They
# are not a substitute for a calibrated gradient-nonlinearity correction.
#
# For Pulseq, the static ANTs geometry correction currently requires one
# interpolation before the combined B0+motion interpolation.
# ======================================================================

# ----------------------------------------------------------------------
# Initialize FSL
# ----------------------------------------------------------------------

export FSLDIR="${HOME}/fsl"
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

BIDS_DIR="${HOME}/bidsRoot"
DERIVATIVES_ROOT="${BIDS_DIR}/derivatives/minimal"
WORK_ROOT="${HOME}/temp/data-processing/minimal"

# B0 field-map sign convention.
NEGATE_FIELDMAP=false

# Correct fmap magnitude/fieldmap geometry using magnitude -> T1w SyN.
ALIGN_FMAP_TO_T1=true

# Correct Pulseq BOLD geometry using raw Pulseq mean -> raw product mean SyN.
# This option is ignored for ACQ=product.
CORRECT_PULSEQ_GEOMETRY=true

# Matching product run used as the fixed image for Pulseq geometry correction.
PRODUCT_REFERENCE_RUN="${RUN}"

# ANTs settings for empirical geometry corrections.
ANTS_THREADS=2
ANTS_PRECISION="f"

# Limit ITK threading for ANTs operations.
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${ANTS_THREADS}"
REGISTRATION_T1_RESOLUTION_MM=3

# EPI -> T1w registration.
# false: standard 6-DOF FLIRT
# true:  BBR using BET + FAST + epi_reg
USE_BBR=false

# B0 + motion final resampling.
APPLY_COMBINED_TRANSFORMS=true
FINAL_INTERPOLATION="spline"

# Optional nonlinear T1w -> MNI152NLin2009cAsym normalization.
REGISTER_TO_MNI=false
MNI_RESOLUTION=1

KEEP_INTERMEDIATES=true

# ----------------------------------------------------------------------
# Inputs
# ----------------------------------------------------------------------

SESSION_DIR="${BIDS_DIR}/${SUBJECT}/${SESSION}"

BOLD_STEM="${SUBJECT}_${SESSION}_task-${TASK}_acq-${ACQ}_run-${RUN}"
BOLD="${SESSION_DIR}/func/${BOLD_STEM}_bold.nii"
BOLD_JSON="${SESSION_DIR}/func/${BOLD_STEM}_bold.json"

FIELDMAP_HZ="${SESSION_DIR}/fmap/${SUBJECT}_${SESSION}_fieldmap.nii.gz"
FIELDMAP_MAGNITUDE="${SESSION_DIR}/fmap/${SUBJECT}_${SESSION}_magnitude.nii.gz"

T1="${SESSION_DIR}/anat/${SUBJECT}_${SESSION}_T1w.nii.gz"

# Matching product BOLD reference for Pulseq geometry correction.
PRODUCT_REFERENCE_STEM="${SUBJECT}_${SESSION}_task-${TASK}_acq-product_run-${PRODUCT_REFERENCE_RUN}"
PRODUCT_REFERENCE_BOLD="${SESSION_DIR}/func/${PRODUCT_REFERENCE_STEM}_bold.nii"

# ----------------------------------------------------------------------
# Output directories
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
# Mean/reference images
# ----------------------------------------------------------------------

RAW_MEAN="${QC_DIR}/${DERIVATIVE_STEM}_desc-raw_mean"

# The image that enters FUGUE. For product data this is the original BOLD.
# For Pulseq data it may be the static geometry-corrected BOLD.
PROCESSING_BOLD="${BOLD}"
PROCESSING_MEAN="${RAW_MEAN}"

# Pulseq geometry-correction outputs.
PULSEQ_GEOM_WORK_DIR="${WORK_DIR}/pulseq_geometry"
PULSEQ_GEOM_PREFIX="${PULSEQ_GEOM_WORK_DIR}/pulseq_to_product_"
PULSEQ_GEOM_SPLIT_DIR="${PULSEQ_GEOM_WORK_DIR}/raw_volumes"
PULSEQ_GEOM_CORRECTED_DIR="${PULSEQ_GEOM_WORK_DIR}/corrected_volumes"

PRODUCT_REFERENCE_MEAN="${PULSEQ_GEOM_WORK_DIR}/${PRODUCT_REFERENCE_STEM}_mean"

PULSEQ_GEOM_BOLD="${WORK_DIR}/${BOLD_STEM}_desc-geomcorr_bold"
PULSEQ_GEOM_MEAN="${QC_DIR}/${DERIVATIVE_STEM}_desc-geomcorr_mean"

PULSEQ_TO_PRODUCT_XFM="${FUNC_DIR}/${SUBJECT}_${SESSION}_task-${TASK}_run-${RUN}_from-pulseq_to-product_mode-image_xfm.h5"
PRODUCT_TO_PULSEQ_XFM="${FUNC_DIR}/${SUBJECT}_${SESSION}_task-${TASK}_run-${RUN}_from-product_to-pulseq_mode-image_xfm.h5"

# ----------------------------------------------------------------------
# Field-map geometry outputs
# ----------------------------------------------------------------------

FMAP_GEOM_WORK_DIR="${WORK_DIR}/fmap_geometry"
FMAP_GEOM_PREFIX="${FMAP_GEOM_WORK_DIR}/fmap_to_T1w_"
T1_REGISTRATION_REFERENCE="${FMAP_GEOM_WORK_DIR}/T1w_${REGISTRATION_T1_RESOLUTION_MM}mm.nii.gz"

FMAP_TO_T1_XFM="${FMAP_DIR}/${SUBJECT}_${SESSION}_from-fmap_to-T1w_mode-image_xfm.h5"
T1_TO_FMAP_XFM="${FMAP_DIR}/${SUBJECT}_${SESSION}_from-T1w_to-fmap_mode-image_xfm.h5"

MAGNITUDE_IN_T1="${QC_DIR}/${SUBJECT}_${SESSION}_space-T1w_desc-fmapMagnitude.nii.gz"

FIELDMAP_FUNC_HZ="${FMAP_DIR}/${SUBJECT}_${SESSION}_space-func_desc-resampled_fieldmap"
FIELDMAP_FUNC_RADS="${WORK_DIR}/${SUBJECT}_${SESSION}_space-func_fieldmap_rads"
MAGNITUDE_FUNC="${FMAP_DIR}/${SUBJECT}_${SESSION}_space-func_desc-resampled_magnitude"

VOXEL_SHIFT="${FMAP_DIR}/${DERIVATIVE_STEM}_desc-b0_voxelshift"
BOLD_B0_MEAN="${QC_DIR}/${DERIVATIVE_STEM}_desc-b0corr_mean"

# ----------------------------------------------------------------------
# Motion/B0 outputs
# ----------------------------------------------------------------------

BOLD_MC="${FUNC_DIR}/${DERIVATIVE_STEM}_desc-b0corrMc_bold"
BOLD_MC_MEAN="${FUNC_DIR}/${DERIVATIVE_STEM}_desc-b0corrMc_mean"

BOLD_B0="${WORK_DIR}/${BOLD_STEM}_desc-b0corr_bold"

PROVISIONAL_B0="${WORK_DIR}/${BOLD_STEM}_desc-b0corrProvisional_bold"
PROVISIONAL_MC="${WORK_DIR}/${BOLD_STEM}_desc-b0corrMcProvisional_bold"
PROVISIONAL_MC_MATS="${PROVISIONAL_MC}.mat"

RAW_SPLIT_DIR="${WORK_DIR}/raw_volumes"
WARP_DIR="${WORK_DIR}/combined_warps"
CORRECTED_SPLIT_DIR="${WORK_DIR}/corrected_volumes"

# ----------------------------------------------------------------------
# EPI -> T1 outputs
# ----------------------------------------------------------------------

FUNC_TO_T1_PREFIX="${ANAT_DIR}/${DERIVATIVE_STEM}_from-func_to-T1w_mode-image_xfm"
FUNC_TO_T1_MATRIX="${FUNC_TO_T1_PREFIX}.mat"
MEAN_IN_T1="${FUNC_DIR}/${DERIVATIVE_STEM}_space-T1w_desc-b0corrMc_mean"

T1_BRAIN="${WORK_DIR}/${SUBJECT}_${SESSION}_desc-brain_T1w"
T1_FAST_PREFIX="${WORK_DIR}/${SUBJECT}_${SESSION}_fast"
WM_SEG="${T1_FAST_PREFIX}_wmseg"

# ----------------------------------------------------------------------
# T1 -> MNI outputs
# ----------------------------------------------------------------------

MNI_SPACE="MNI152NLin2009cAsym"

T1_TO_MNI_XFM="${ANAT_DIR}/${SUBJECT}_${SESSION}_from-T1w_to-${MNI_SPACE}_mode-image_xfm.h5"
MNI_TO_T1_XFM="${ANAT_DIR}/${SUBJECT}_${SESSION}_from-${MNI_SPACE}_to-T1w_mode-image_xfm.h5"
T1_IN_MNI="${ANAT_DIR}/${SUBJECT}_${SESSION}_space-${MNI_SPACE}_desc-preproc_T1w"

MNI_WORK_DIR="${WORK_DIR}/mni"
MNI_PREFIX="${MNI_WORK_DIR}/T1w_to_${MNI_SPACE}_"

mkdir -p \
    "${PULSEQ_GEOM_WORK_DIR}" \
    "${FMAP_GEOM_WORK_DIR}" \
    "${MNI_WORK_DIR}"

# ----------------------------------------------------------------------
# Derivatives dataset metadata
# ----------------------------------------------------------------------

cat > "${DERIVATIVES_ROOT}/dataset_description.json" <<EOF
{
  "Name": "Minimal fMRI preprocessing derivatives",
  "BIDSVersion": "1.10.0",
  "DatasetType": "derivative",
  "GeneratedBy": [
    {
      "Name": "run_minimal_fmri_pipeline.sh",
      "Description": "Minimal geometric fMRI preprocessing with FSL and ANTs"
    },
    {
      "Name": "FSL"
    },
    {
      "Name": "ANTs",
      "Description": "Empirical field-map/Pulseq geometry correction and optional MNI normalization"
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

if ${ALIGN_FMAP_TO_T1} || { [[ "${ACQ}" == "pulseq" ]] && ${CORRECT_PULSEQ_GEOMETRY}; } || ${REGISTER_TO_MNI}; then
    for command in \
        antsRegistrationSyN.sh \
        antsApplyTransforms \
        ResampleImage
    do
        if ! command -v "${command}" >/dev/null 2>&1; then
            echo "ERROR: Required ANTs command not found: ${command}" >&2
            exit 1
        fi
    done
fi

if ${APPLY_COMBINED_TRANSFORMS} || { [[ "${ACQ}" == "pulseq" ]] && ${CORRECT_PULSEQ_GEOMETRY}; }; then
    for command in fslsplit fslmerge; do
        if ! command -v "${command}" >/dev/null 2>&1; then
            echo "ERROR: Required command not found: ${command}" >&2
            exit 1
        fi
    done
fi

if ${APPLY_COMBINED_TRANSFORMS}; then
    for command in convertwarp applywarp; do
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

if ${REGISTER_TO_MNI}; then
    if ! python3 -c "import templateflow.api" >/dev/null 2>&1; then
        echo "ERROR: REGISTER_TO_MNI=true requires Python package 'templateflow'." >&2
        echo "Install with: python3 -m pip install templateflow" >&2
        exit 1
    fi
fi

# Pulseq geometry correction requires a matching product reference.
if [[ "${ACQ}" == "pulseq" ]] && ${CORRECT_PULSEQ_GEOMETRY}; then
    if [[ ! -f "${PRODUCT_REFERENCE_BOLD}" ]]; then
        echo "ERROR: Matching product reference BOLD not found:" >&2
        echo "  ${PRODUCT_REFERENCE_BOLD}" >&2
        exit 1
    fi
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
        echo "ERROR: Unsupported PhaseEncodingDirection: ${PHASE_ENCODING_DIRECTION}" >&2
        exit 1
        ;;
esac

PE_MATRIX_SIZE=$(fslval "${BOLD}" "dim${PE_DIM}")
N_VOLUMES=$(fslval "${BOLD}" dim4)

DWELL_TIME=$(python3 - "${TOTAL_READOUT_TIME}" "${PE_MATRIX_SIZE}" <<'PY'
import sys
print(f"{float(sys.argv[1])/(int(sys.argv[2])-1):.12g}")
PY
)

echo
echo "Subject:                       ${SUBJECT}"
echo "Session:                       ${SESSION}"
echo "Task:                          ${TASK}"
echo "Acquisition:                   ${ACQ}"
echo "Align fmap to T1:              ${ALIGN_FMAP_TO_T1}"
echo "Correct Pulseq geometry:       ${CORRECT_PULSEQ_GEOMETRY}"
echo "Apply combined B0+MC:          ${APPLY_COMBINED_TRANSFORMS}"
echo "Register T1 to MNI:            ${REGISTER_TO_MNI}"
echo

# ======================================================================
# Step 1: Create raw mean and optionally correct static Pulseq geometry
# ======================================================================

echo "Step 1/5: Preparing functional geometry"

fslmaths "${BOLD}" -Tmean "${RAW_MEAN}"

if [[ "${ACQ}" == "pulseq" ]] && ${CORRECT_PULSEQ_GEOMETRY}; then

    echo "Estimating raw Pulseq -> raw product geometry transform."
    echo "B0 correction is intentionally NOT applied before this registration."

    fslmaths \
        "${PRODUCT_REFERENCE_BOLD}" \
        -Tmean \
        "${PRODUCT_REFERENCE_MEAN}"

    antsRegistrationSyN.sh \
        -d 3 \
        -f "${PRODUCT_REFERENCE_MEAN}.nii.gz" \
        -m "${RAW_MEAN}.nii.gz" \
        -o "${PULSEQ_GEOM_PREFIX}" \
        -t sr \
        -p "${ANTS_PRECISION}" \
        -n "${ANTS_THREADS}"

    # Save composite forward and inverse transforms.
    antsApplyTransforms \
        -d 3 \
        -r "${PRODUCT_REFERENCE_MEAN}.nii.gz" \
        -o "[${PULSEQ_TO_PRODUCT_XFM},1]" \
        -t "${PULSEQ_GEOM_PREFIX}1Warp.nii.gz" \
        -t "${PULSEQ_GEOM_PREFIX}0GenericAffine.mat"

    antsApplyTransforms \
        -d 3 \
        -r "${RAW_MEAN}.nii.gz" \
        -o "[${PRODUCT_TO_PULSEQ_XFM},1]" \
        -t "[${PULSEQ_GEOM_PREFIX}0GenericAffine.mat,1]" \
        -t "${PULSEQ_GEOM_PREFIX}1InverseWarp.nii.gz"

    # Apply the static 3D transform to the Pulseq series one volume at a
    # time. Applying a nonlinear transform to the entire 4D time series in
    # one antsApplyTransforms call can require excessive memory.
    mkdir -p \
        "${PULSEQ_GEOM_SPLIT_DIR}" \
        "${PULSEQ_GEOM_CORRECTED_DIR}"

    rm -f \
        "${PULSEQ_GEOM_SPLIT_DIR}"/vol*.nii.gz \
        "${PULSEQ_GEOM_CORRECTED_DIR}"/vol*.nii.gz

    fslsplit \
        "${BOLD}" \
        "${PULSEQ_GEOM_SPLIT_DIR}/vol" \
        -t

    PULSEQ_N_VOLUMES=$(fslval "${BOLD}" dim4)

    echo "Applying Pulseq geometry correction to ${PULSEQ_N_VOLUMES} volumes..."

    for ((index=0; index<PULSEQ_N_VOLUMES; index++)); do

        printf -v volume_id "%04d" "${index}"

        INPUT_VOLUME="${PULSEQ_GEOM_SPLIT_DIR}/vol${volume_id}.nii.gz"
        OUTPUT_VOLUME="${PULSEQ_GEOM_CORRECTED_DIR}/vol${volume_id}.nii.gz"

        antsApplyTransforms \
            -d 3 \
            -i "${INPUT_VOLUME}" \
            -r "${PRODUCT_REFERENCE_MEAN}.nii.gz" \
            -o "${OUTPUT_VOLUME}" \
            -n Linear \
            -t "${PULSEQ_TO_PRODUCT_XFM}"

    done

    fslmerge \
        -t "${PULSEQ_GEOM_BOLD}" \
        "${PULSEQ_GEOM_CORRECTED_DIR}"/vol*.nii.gz

    fslmaths \
        "${PULSEQ_GEOM_BOLD}.nii.gz" \
        -Tmean \
        "${PULSEQ_GEOM_MEAN}"

    PROCESSING_BOLD="${PULSEQ_GEOM_BOLD}.nii.gz"
    PROCESSING_MEAN="${PULSEQ_GEOM_MEAN}"

    echo "Pulseq data will continue on the product functional grid."

else

    PROCESSING_BOLD="${BOLD}"
    PROCESSING_MEAN="${RAW_MEAN}"

fi

# ======================================================================
# Step 2: Correct field-map geometry and resample to functional grid
# ======================================================================

echo "Step 2/5: Preparing field map"

if ${ALIGN_FMAP_TO_T1}; then

    echo "Estimating fmap magnitude -> T1w geometry transform."

    # Use a lower-resolution T1 only to estimate the nonlinear transform.
    ResampleImage \
        3 \
        "${T1}" \
        "${T1_REGISTRATION_REFERENCE}" \
        "${REGISTRATION_T1_RESOLUTION_MM}x${REGISTRATION_T1_RESOLUTION_MM}x${REGISTRATION_T1_RESOLUTION_MM}"

    antsRegistrationSyN.sh \
        -d 3 \
        -f "${T1_REGISTRATION_REFERENCE}" \
        -m "${FIELDMAP_MAGNITUDE}" \
        -o "${FMAP_GEOM_PREFIX}" \
        -t sr \
        -p "${ANTS_PRECISION}" \
        -n "${ANTS_THREADS}"

    antsApplyTransforms \
        -d 3 \
        -r "${T1}" \
        -o "[${FMAP_TO_T1_XFM},1]" \
        -t "${FMAP_GEOM_PREFIX}1Warp.nii.gz" \
        -t "${FMAP_GEOM_PREFIX}0GenericAffine.mat"

    antsApplyTransforms \
        -d 3 \
        -r "${FIELDMAP_MAGNITUDE}" \
        -o "[${T1_TO_FMAP_XFM},1]" \
        -t "[${FMAP_GEOM_PREFIX}0GenericAffine.mat,1]" \
        -t "${FMAP_GEOM_PREFIX}1InverseWarp.nii.gz"

    # High-resolution T1-space magnitude for QC.
    antsApplyTransforms \
        -d 3 \
        -i "${FIELDMAP_MAGNITUDE}" \
        -r "${T1}" \
        -o "${MAGNITUDE_IN_T1}" \
        -n Linear \
        -t "${FMAP_TO_T1_XFM}"

    # Apply the same transform to magnitude and Hz field map, but sample
    # directly onto the functional processing grid.
    antsApplyTransforms \
        -d 3 \
        -i "${FIELDMAP_MAGNITUDE}" \
        -r "${PROCESSING_MEAN}.nii.gz" \
        -o "${MAGNITUDE_FUNC}.nii.gz" \
        -n Linear \
        -t "${FMAP_TO_T1_XFM}"

    antsApplyTransforms \
        -d 3 \
        -i "${FIELDMAP_HZ}" \
        -r "${PROCESSING_MEAN}.nii.gz" \
        -o "${FIELDMAP_FUNC_HZ}.nii.gz" \
        -n Linear \
        -t "${FMAP_TO_T1_XFM}"

else

    # Legacy header-based resampling.
    flirt \
        -in "${FIELDMAP_HZ}" \
        -ref "${PROCESSING_MEAN}" \
        -applyxfm \
        -usesqform \
        -interp trilinear \
        -out "${FIELDMAP_FUNC_HZ}"

    flirt \
        -in "${FIELDMAP_MAGNITUDE}" \
        -ref "${PROCESSING_MEAN}" \
        -applyxfm \
        -usesqform \
        -interp trilinear \
        -out "${MAGNITUDE_FUNC}"

fi

# FUGUE expects the field map in rad/s.
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

# Re-read PE matrix size on the actual processing grid.
PE_MATRIX_SIZE=$(fslval "${PROCESSING_BOLD}" "dim${PE_DIM}")

DWELL_TIME=$(python3 - "${TOTAL_READOUT_TIME}" "${PE_MATRIX_SIZE}" <<'PY'
import sys
print(f"{float(sys.argv[1])/(int(sys.argv[2])-1):.12g}")
PY
)

# ======================================================================
# Step 3: B0 correction + motion correction
# ======================================================================

echo "Step 3/5: B0 distortion and motion correction"

if ${APPLY_COMBINED_TRANSFORMS}; then
    B0_ESTIMATION_OUTPUT="${PROVISIONAL_B0}"
else
    B0_ESTIMATION_OUTPUT="${BOLD_B0}"
fi

fugue \
    --in="${PROCESSING_BOLD}" \
    --loadfmap="${FIELDMAP_FUNC_RADS}" \
    --dwell="${DWELL_TIME}" \
    --unwarpdir="${FUGUE_DIRECTION}" \
    --saveshift="${VOXEL_SHIFT}" \
    --unwarp="${B0_ESTIMATION_OUTPUT}"

fslmaths \
    "${B0_ESTIMATION_OUTPUT}" \
    -Tmean \
    "${BOLD_B0_MEAN}"

if ${APPLY_COMBINED_TRANSFORMS}; then

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

    rm -f \
        "${RAW_SPLIT_DIR}"/vol*.nii.gz \
        "${WARP_DIR}"/warp*.nii.gz \
        "${CORRECTED_SPLIT_DIR}"/vol*.nii.gz

    fslsplit \
        "${PROCESSING_BOLD}" \
        "${RAW_SPLIT_DIR}/vol" \
        -t

    N_VOLUMES=$(fslval "${PROCESSING_BOLD}" dim4)

    for ((index=0; index<N_VOLUMES; index++)); do

        printf -v volume_id "%04d" "${index}"

        RAW_VOLUME="${RAW_SPLIT_DIR}/vol${volume_id}.nii.gz"
        MOTION_MATRIX="${PROVISIONAL_MC_MATS}/MAT_${volume_id}"
        COMBINED_WARP="${WARP_DIR}/warp${volume_id}"
        CORRECTED_VOLUME="${CORRECTED_SPLIT_DIR}/vol${volume_id}"

        convertwarp \
            --ref="${PROCESSING_MEAN}" \
            --shiftmap="${VOXEL_SHIFT}" \
            --shiftdir="${FUGUE_DIRECTION}" \
            --premat="${MOTION_MATRIX}" \
            --out="${COMBINED_WARP}" \
            --relout

        applywarp \
            --ref="${PROCESSING_MEAN}" \
            --in="${RAW_VOLUME}" \
            --warp="${COMBINED_WARP}" \
            --rel \
            --interp="${FINAL_INTERPOLATION}" \
            --out="${CORRECTED_VOLUME}"

    done

    fslmerge \
        -t "${BOLD_MC}" \
        "${CORRECTED_SPLIT_DIR}"/vol*.nii.gz

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

PULSEQ_GEOMETRY_CORRECTED=false
if [[ "${ACQ}" == "pulseq" ]] && ${CORRECT_PULSEQ_GEOMETRY}; then
    PULSEQ_GEOMETRY_CORRECTED=true
fi

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
  "FieldMapGeometryCorrection": "ANTs rigid+SyN magnitude-to-T1w registration",
  "PulseqGeometryCorrected": ${PULSEQ_GEOMETRY_CORRECTED},
  "CombinedB0MotionResampling": ${APPLY_COMBINED_TRANSFORMS},
  "Interpolation": "${FINAL_INTERPOLATION}",
  "MotionCorrection": "MCFLIRT",
  "DistortionCorrection": "FUGUE"
}
EOF

# ======================================================================
# Step 4: Mean EPI -> T1w registration
# ======================================================================

echo "Step 4/5: Mean EPI-to-T1w registration"

if ${USE_BBR}; then

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

# ======================================================================
# Step 5: Optional T1w -> MNI152NLin2009cAsym
# ======================================================================

if ${REGISTER_TO_MNI}; then

    echo "Step 5/5: T1w-to-${MNI_SPACE} nonlinear registration"

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
        echo "ERROR: MNI template not found: ${MNI_TEMPLATE}" >&2
        exit 1
    fi

    antsRegistrationSyN.sh \
        -d 3 \
        -f "${MNI_TEMPLATE}" \
        -m "${T1}" \
        -o "${MNI_PREFIX}" \
        -t s \
        -p "${ANTS_PRECISION}" \
        -n "${ANTS_THREADS}"

    cp \
        "${MNI_PREFIX}Warped.nii.gz" \
        "${T1_IN_MNI}.nii.gz"

    antsApplyTransforms \
        -d 3 \
        -r "${MNI_TEMPLATE}" \
        -o "[${T1_TO_MNI_XFM},1]" \
        -t "${MNI_PREFIX}1Warp.nii.gz" \
        -t "${MNI_PREFIX}0GenericAffine.mat"

    antsApplyTransforms \
        -d 3 \
        -r "${T1}" \
        -o "[${MNI_TO_T1_XFM},1]" \
        -t "[${MNI_PREFIX}0GenericAffine.mat,1]" \
        -t "${MNI_PREFIX}1InverseWarp.nii.gz"

else

    echo "Step 5/5: T1w-to-MNI registration skipped."

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
echo "Final BOLD:"
echo "  ${BOLD_MC}.nii.gz"
echo
echo "Field-map magnitude in T1w space:"
echo "  ${MAGNITUDE_IN_T1}"
echo
echo "EPI-to-T1w transform:"
echo "  ${FUNC_TO_T1_MATRIX}"

if [[ "${ACQ}" == "pulseq" ]] && ${CORRECT_PULSEQ_GEOMETRY}; then
    echo
    echo "Pulseq-to-product geometry transform:"
    echo "  ${PULSEQ_TO_PRODUCT_XFM}"
fi

if ${REGISTER_TO_MNI}; then
    echo
    echo "T1w-to-MNI transform:"
    echo "  ${T1_TO_MNI_XFM}"
    echo "MNI-to-T1w transform:"
    echo "  ${MNI_TO_T1_XFM}"
    echo "T1w in MNI space:"
    echo "  ${T1_IN_MNI}.nii.gz"
fi
