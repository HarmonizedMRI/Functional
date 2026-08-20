#!/usr/bin/env bash
set -euo pipefail

export FSLDIR="${HOME}/fsl"
. "${FSLDIR}/etc/fslconf/fsl.sh"
export PATH="${FSLDIR}/share/fsl/bin:$PATH"

SUBJECT="sub-00007"
SESSION="ses-umichmr75020241124"
TASK="vismotor"
ACQ="product"
RUN="01"

BIDS_DIR="${HOME}/bidsRoot"
DERIVATIVES_ROOT="${BIDS_DIR}/derivatives/minimal"
WORK_ROOT="${HOME}/temp/data-processing/minimal"

NEGATE_FIELDMAP=false
USE_BBR=false
APPLY_COMBINED_TRANSFORMS=true
FINAL_INTERPOLATION="spline"

# Optional nonlinear T1w -> MNI152NLin2009cAsym normalization.
REGISTER_TO_MNI=true
MNI_RESOLUTION=1

KEEP_INTERMEDIATES=true

SESSION_DIR="${BIDS_DIR}/${SUBJECT}/${SESSION}"
BOLD_STEM="${SUBJECT}_${SESSION}_task-${TASK}_acq-${ACQ}_run-${RUN}"

BOLD="${SESSION_DIR}/func/${BOLD_STEM}_bold.nii"
BOLD_JSON="${SESSION_DIR}/func/${BOLD_STEM}_bold.json"
FIELDMAP_HZ="${SESSION_DIR}/fmap/${SUBJECT}_${SESSION}_fieldmap.nii.gz"
FIELDMAP_MAGNITUDE="${SESSION_DIR}/fmap/${SUBJECT}_${SESSION}_magnitude.nii.gz"
T1="${SESSION_DIR}/anat/${SUBJECT}_${SESSION}_T1w.nii.gz"

DERIV_SESSION_DIR="${DERIVATIVES_ROOT}/${SUBJECT}/${SESSION}"
FUNC_DIR="${DERIV_SESSION_DIR}/func"
FMAP_DIR="${DERIV_SESSION_DIR}/fmap"
ANAT_DIR="${DERIV_SESSION_DIR}/anat"
QC_DIR="${DERIV_SESSION_DIR}/qc"
WORK_DIR="${WORK_ROOT}/${SUBJECT}/${SESSION}/${BOLD_STEM}"

mkdir -p "${DERIVATIVES_ROOT}" "${FUNC_DIR}" "${FMAP_DIR}" "${ANAT_DIR}" "${QC_DIR}" "${WORK_DIR}"

DERIVATIVE_STEM="${BOLD_STEM}"

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

MNI_SPACE="MNI152NLin2009cAsym"
T1_TO_MNI_XFM="${ANAT_DIR}/${SUBJECT}_${SESSION}_from-T1w_to-${MNI_SPACE}_mode-image_xfm.h5"
MNI_TO_T1_XFM="${ANAT_DIR}/${SUBJECT}_${SESSION}_from-${MNI_SPACE}_to-T1w_mode-image_xfm.h5"
T1_IN_MNI="${ANAT_DIR}/${SUBJECT}_${SESSION}_space-${MNI_SPACE}_desc-preproc_T1w"

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

MNI_WORK_DIR="${WORK_DIR}/mni"
MNI_PREFIX="${MNI_WORK_DIR}/T1w_to_${MNI_SPACE}_"
mkdir -p "${MNI_WORK_DIR}"

cat > "${DERIVATIVES_ROOT}/dataset_description.json" <<EOF
{
  "Name": "Minimal fMRI preprocessing derivatives",
  "BIDSVersion": "1.10.0",
  "DatasetType": "derivative",
  "GeneratedBy": [
    {
      "Name": "run_minimal_fmri_pipeline.sh",
      "Description": "FSL-based B0 distortion correction, rigid-body motion correction, EPI-to-T1 registration, and optional ANTs T1-to-MNI normalization"
    },
    {
      "Name": "FSL"
    },
    {
      "Name": "ANTs",
      "Description": "Used only when REGISTER_TO_MNI=true"
    }
  ]
}
EOF

for file in "${BOLD}" "${BOLD_JSON}" "${FIELDMAP_HZ}" "${FIELDMAP_MAGNITUDE}" "${T1}"; do
    [[ -f "${file}" ]] || { echo "ERROR: Required input file not found: ${file}" >&2; exit 1; }
done

for command in fslmaths fslval flirt fugue mcflirt jq python3; do
    command -v "${command}" >/dev/null 2>&1 || { echo "ERROR: Required command not found: ${command}" >&2; exit 1; }
done

if ${APPLY_COMBINED_TRANSFORMS}; then
    for command in fslsplit fslmerge convertwarp applywarp; do
        command -v "${command}" >/dev/null 2>&1 || { echo "ERROR: Required command not found: ${command}" >&2; exit 1; }
    done
fi

if ${USE_BBR}; then
    for command in bet fast epi_reg; do
        command -v "${command}" >/dev/null 2>&1 || { echo "ERROR: Required BBR command not found: ${command}" >&2; exit 1; }
    done
fi

if ${REGISTER_TO_MNI}; then
    for command in antsRegistrationSyN.sh antsApplyTransforms; do
        command -v "${command}" >/dev/null 2>&1 || { echo "ERROR: MNI registration requested but command not found: ${command}" >&2; exit 1; }
    done
    if ! python3 -c "import templateflow.api" >/dev/null 2>&1; then
        echo "ERROR: REGISTER_TO_MNI=true requires the Python package 'templateflow'." >&2
        echo "Install with: python3 -m pip install templateflow" >&2
        exit 1
    fi
fi

PHASE_ENCODING_DIRECTION=$(jq -er '.PhaseEncodingDirection' "${BOLD_JSON}")
TOTAL_READOUT_TIME=$(jq -er '.TotalReadoutTime' "${BOLD_JSON}")

case "${PHASE_ENCODING_DIRECTION}" in
    i)  FUGUE_DIRECTION="x";  PE_DIM=1 ;;
    i-) FUGUE_DIRECTION="x-"; PE_DIM=1 ;;
    j)  FUGUE_DIRECTION="y";  PE_DIM=2 ;;
    j-) FUGUE_DIRECTION="y-"; PE_DIM=2 ;;
    k)  FUGUE_DIRECTION="z";  PE_DIM=3 ;;
    k-) FUGUE_DIRECTION="z-"; PE_DIM=3 ;;
    *) echo "ERROR: Unsupported PhaseEncodingDirection: ${PHASE_ENCODING_DIRECTION}" >&2; exit 1 ;;
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
echo "Apply combined transforms:     ${APPLY_COMBINED_TRANSFORMS}"
echo "Register T1 to MNI:            ${REGISTER_TO_MNI}"
echo

echo "Step 1/4: B0 distortion correction"

fslmaths "${BOLD}" -Tmean "${RAW_MEAN}"

flirt -in "${FIELDMAP_HZ}" -ref "${RAW_MEAN}" -applyxfm -usesqform -interp trilinear -out "${FIELDMAP_FUNC_HZ}"
flirt -in "${FIELDMAP_MAGNITUDE}" -ref "${RAW_MEAN}" -applyxfm -usesqform -interp trilinear -out "${MAGNITUDE_FUNC}"

fslmaths "${FIELDMAP_FUNC_HZ}" -mul 6.283185307179586 "${FIELDMAP_FUNC_RADS}"

if ${NEGATE_FIELDMAP}; then
    fslmaths "${FIELDMAP_FUNC_RADS}" -mul -1 "${FIELDMAP_FUNC_RADS}"
fi

if ${APPLY_COMBINED_TRANSFORMS}; then
    B0_ESTIMATION_OUTPUT="${PROVISIONAL_B0}"
else
    B0_ESTIMATION_OUTPUT="${BOLD_B0}"
fi

fugue --in="${BOLD}"       --loadfmap="${FIELDMAP_FUNC_RADS}"       --dwell="${DWELL_TIME}"       --unwarpdir="${FUGUE_DIRECTION}"       --saveshift="${VOXEL_SHIFT}"       --unwarp="${B0_ESTIMATION_OUTPUT}"

fslmaths "${B0_ESTIMATION_OUTPUT}" -Tmean "${BOLD_B0_MEAN}"

echo "Step 2/4: Motion correction"

if ${APPLY_COMBINED_TRANSFORMS}; then
    mcflirt -in "${PROVISIONAL_B0}" -out "${PROVISIONAL_MC}" -plots -mats -rmsrel -rmsabs -spline_final

    mkdir -p "${RAW_SPLIT_DIR}" "${WARP_DIR}" "${CORRECTED_SPLIT_DIR}"
    rm -f "${RAW_SPLIT_DIR}"/vol*.nii.gz "${WARP_DIR}"/warp*.nii.gz "${CORRECTED_SPLIT_DIR}"/vol*.nii.gz

    fslsplit "${BOLD}" "${RAW_SPLIT_DIR}/vol" -t

    for ((index=0; index<N_VOLUMES; index++)); do
        printf -v volume_id "%04d" "${index}"

        RAW_VOLUME="${RAW_SPLIT_DIR}/vol${volume_id}.nii.gz"
        MOTION_MATRIX="${PROVISIONAL_MC_MATS}/MAT_${volume_id}"
        COMBINED_WARP="${WARP_DIR}/warp${volume_id}"
        CORRECTED_VOLUME="${CORRECTED_SPLIT_DIR}/vol${volume_id}"

        convertwarp --ref="${RAW_MEAN}"                     --shiftmap="${VOXEL_SHIFT}"                     --shiftdir="${FUGUE_DIRECTION}"                     --premat="${MOTION_MATRIX}"                     --out="${COMBINED_WARP}"                     --relout

        applywarp --ref="${RAW_MEAN}"                   --in="${RAW_VOLUME}"                   --warp="${COMBINED_WARP}"                   --rel                   --interp="${FINAL_INTERPOLATION}"                   --out="${CORRECTED_VOLUME}"
    done

    fslmerge -t "${BOLD_MC}" "${CORRECTED_SPLIT_DIR}"/vol*.nii.gz

    cp "${PROVISIONAL_MC}.par" "${QC_DIR}/${DERIVATIVE_STEM}_desc-motion_parameters.tsv"
    cp "${PROVISIONAL_MC}_rel.rms" "${QC_DIR}/${DERIVATIVE_STEM}_desc-relativeMotion_rms.tsv"
    cp "${PROVISIONAL_MC}_abs.rms" "${QC_DIR}/${DERIVATIVE_STEM}_desc-absoluteMotion_rms.tsv"

    rm -rf "${QC_DIR}/${DERIVATIVE_STEM}_desc-motion_matrices"
    cp -r "${PROVISIONAL_MC_MATS}" "${QC_DIR}/${DERIVATIVE_STEM}_desc-motion_matrices"
else
    mcflirt -in "${BOLD_B0}" -out "${BOLD_MC}" -plots -mats -rmsrel -rmsabs -spline_final

    cp "${BOLD_MC}.par" "${QC_DIR}/${DERIVATIVE_STEM}_desc-motion_parameters.tsv"
    cp "${BOLD_MC}_rel.rms" "${QC_DIR}/${DERIVATIVE_STEM}_desc-relativeMotion_rms.tsv"
    cp "${BOLD_MC}_abs.rms" "${QC_DIR}/${DERIVATIVE_STEM}_desc-absoluteMotion_rms.tsv"

    rm -rf "${QC_DIR}/${DERIVATIVE_STEM}_desc-motion_matrices"
    cp -r "${BOLD_MC}.mat" "${QC_DIR}/${DERIVATIVE_STEM}_desc-motion_matrices"
fi

fslmaths "${BOLD_MC}" -Tmean "${BOLD_MC_MEAN}"

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

echo "Step 3/4: Mean EPI-to-T1 registration"

if ${USE_BBR}; then
    bet "${T1}" "${T1_BRAIN}" -R -f 0.30 -m
    fast -t 1 -n 3 -o "${T1_FAST_PREFIX}" "${T1_BRAIN}"
    fslmaths "${T1_FAST_PREFIX}_pve_2" -thr 0.5 -bin "${WM_SEG}"

    epi_reg --epi="${BOLD_MC_MEAN}"             --t1="${T1}"             --t1brain="${T1_BRAIN}"             --wmseg="${WM_SEG}"             --out="${FUNC_TO_T1_PREFIX}"

    cp "${FUNC_TO_T1_PREFIX}.nii.gz" "${MEAN_IN_T1}.nii.gz"
else
    flirt -in "${BOLD_MC_MEAN}"           -ref "${T1}"           -out "${MEAN_IN_T1}"           -omat "${FUNC_TO_T1_MATRIX}"           -dof 6           -cost normmi           -searchrx -90 90           -searchry -90 90           -searchrz -90 90           -interp trilinear
fi

if ${REGISTER_TO_MNI}; then
    echo "Step 4/4: T1-to-${MNI_SPACE} nonlinear registration"

    MNI_TEMPLATE=$(python3 - "${MNI_RESOLUTION}" <<'PY'
import sys
from templateflow.api import get
resolution = int(sys.argv[1])
path = get("MNI152NLin2009cAsym", resolution=resolution, suffix="T1w", extension=".nii.gz")
if isinstance(path, (list, tuple)):
    path = path[0]
print(path)
PY
)

    [[ -f "${MNI_TEMPLATE}" ]] || { echo "ERROR: MNI template not found: ${MNI_TEMPLATE}" >&2; exit 1; }

    antsRegistrationSyN.sh         -d 3         -f "${MNI_TEMPLATE}"         -m "${T1}"         -o "${MNI_PREFIX}"         -t s

    cp "${MNI_PREFIX}Warped.nii.gz" "${T1_IN_MNI}.nii.gz"

    antsApplyTransforms         -d 3         -r "${MNI_TEMPLATE}"         -o "[${T1_TO_MNI_XFM},1]"         -t "${MNI_PREFIX}1Warp.nii.gz"         -t "${MNI_PREFIX}0GenericAffine.mat"

    antsApplyTransforms         -d 3         -r "${T1}"         -o "[${MNI_TO_T1_XFM},1]"         -t "[${MNI_PREFIX}0GenericAffine.mat,1]"         -t "${MNI_PREFIX}1InverseWarp.nii.gz"
else
    echo "Step 4/4: T1-to-MNI registration skipped."
fi

if ! ${KEEP_INTERMEDIATES}; then
    rm -rf "${WORK_DIR}"
fi

echo
echo "Pipeline completed."
echo "Final BOLD: ${BOLD_MC}.nii.gz"
echo "EPI-to-T1 transform: ${FUNC_TO_T1_MATRIX}"

if ${REGISTER_TO_MNI}; then
    echo "T1-to-MNI transform: ${T1_TO_MNI_XFM}"
    echo "MNI-to-T1 transform: ${MNI_TO_T1_XFM}"
    echo "T1 in MNI space: ${T1_IN_MNI}.nii.gz"
fi
