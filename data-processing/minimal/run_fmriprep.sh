#!/usr/bin/env bash

set -euo pipefail

# ======================================================================
# Run fMRIPrep on one participant
#
# This configuration:
#   - processes one BIDS participant
#   - disables FreeSurfer surface reconstruction
#   - writes outputs in native functional and T1w spaces
#   - does not request MNI normalization
#   - saves a complete terminal log
# ======================================================================

# ----------------------------------------------------------------------
# User settings
# ----------------------------------------------------------------------

BIDS_DIR="/home/jon/fmriprep/data"
OUTPUT_DIR="/home/jon/fmriprep/derivatives"
WORK_DIR="/home/jon/fmriprep/work"

PARTICIPANT_LABEL="00012"

FS_LICENSE_FILE="${HOME}/.freesurfer/license.txt"

# Also write outputs in MNI152NLin2009cAsym space.
OUTPUT_MNI=false

# Build output spaces.
OUTPUT_SPACES=(T1w func)
if ${OUTPUT_MNI}; then
    OUTPUT_SPACES+=(MNI152NLin2009cAsym)
fi

NPROCS=10
OMP_NTHREADS=4
MEM_MB=24000

# Run the BIDS validator before fMRIPrep.
RUN_BIDS_VALIDATOR=false

# Suppress validator warnings and report errors only.
VALIDATOR_ERRORS_ONLY=true

LOG_FILE="/home/jon/fmriprep/fmriprep_${PARTICIPANT_LABEL}.log"

# ----------------------------------------------------------------------
# Check requirements
# ----------------------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker was not found." >&2
    exit 1
fi

if ! command -v fmriprep-docker >/dev/null 2>&1; then
    echo "ERROR: fmriprep-docker was not found." >&2
    echo "Activate the Python environment containing fmriprep-docker." >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not running or this user cannot access it." >&2
    exit 1
fi

if [[ ! -d "${BIDS_DIR}" ]]; then
    echo "ERROR: BIDS directory not found:" >&2
    echo "  ${BIDS_DIR}" >&2
    exit 1
fi

if [[ ! -d "${BIDS_DIR}/sub-${PARTICIPANT_LABEL}" ]]; then
    echo "ERROR: Participant directory not found:" >&2
    echo "  ${BIDS_DIR}/sub-${PARTICIPANT_LABEL}" >&2
    exit 1
fi

if [[ ! -f "${BIDS_DIR}/dataset_description.json" ]]; then
    echo "ERROR: Missing BIDS dataset description:" >&2
    echo "  ${BIDS_DIR}/dataset_description.json" >&2
    exit 1
fi

if [[ ! -f "${FS_LICENSE_FILE}" ]]; then
    echo "ERROR: FreeSurfer license file not found:" >&2
    echo "  ${FS_LICENSE_FILE}" >&2
    exit 1
fi

mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}"

# ----------------------------------------------------------------------
# Optional BIDS validation
# ----------------------------------------------------------------------

if ${RUN_BIDS_VALIDATOR}; then
    echo "Validating BIDS dataset..."

    VALIDATOR_ARGS=()

    if ${VALIDATOR_ERRORS_ONLY}; then
        VALIDATOR_ARGS+=(--ignoreWarnings)
    fi

    docker run --rm -ti \
        -v "${BIDS_DIR}:/data:ro" \
        bids/validator \
        /data \
        "${VALIDATOR_ARGS[@]}"
fi

# ----------------------------------------------------------------------
# Run fMRIPrep
# ----------------------------------------------------------------------

echo
echo "Running fMRIPrep"
echo "  BIDS directory:       ${BIDS_DIR}"
echo "  Output directory:     ${OUTPUT_DIR}"
echo "  Work directory:       ${WORK_DIR}"
echo "  Participant:          ${PARTICIPANT_LABEL}"
echo "  Processes:            ${NPROCS}"
echo "  OpenMP threads:       ${OMP_NTHREADS}"
echo "  Memory limit:         ${MEM_MB} MB"
echo "  MNI normalization:    ${OUTPUT_MNI}"
echo "  Log file:             ${LOG_FILE}"
echo

fmriprep-docker \
    "${BIDS_DIR}" \
    "${OUTPUT_DIR}" \
    participant \
    --participant-label "${PARTICIPANT_LABEL}" \
    --fs-no-reconall \
    --fs-license-file "${FS_LICENSE_FILE}" \
    --output-spaces "${OUTPUT_SPACES[@]}" \
    --nprocs "${NPROCS}" \
    --omp-nthreads "${OMP_NTHREADS}" \
    --mem-mb "${MEM_MB}" \
    -w "${WORK_DIR}" \
    2>&1 | tee "${LOG_FILE}"

echo
echo "fMRIPrep completed."
echo
echo "Participant report:"
echo "  ${OUTPUT_DIR}/sub-${PARTICIPANT_LABEL}.html"
echo
echo "Log:"
echo "  ${LOG_FILE}"