#!/bin/bash
#SBATCH --job-name=hrrr-extract
#SBATCH --partition=ultramem
#SBATCH --qos=highmem
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=4-00:00:00
#SBATCH --output=logs/hrrr-extract-%j.out
#SBATCH --error=logs/hrrr-extract-%j.err

# HRRR Data Extraction Job for HPC using Singularity
# This script runs the HRRR precipitation data extraction for Oso Creek basin

echo "Starting HRRR extraction job: $SLURM_JOB_ID"
echo "Node: $SLURM_NODELIST"
echo "Start time: $(date)"

# Set working directory to job submission directory
cd $SLURM_SUBMIT_DIR

module load wgrib2/gcc11/3.3.0
module load python39

pip install awscli

# Create logs directory if it doesn't exist
mkdir -p logs

# Define Singularity image and data paths
SINGULARITY_IMAGE="/work/TANN/wgrib2_latest.sif"
DATA_DIR="/work/TANN/knguyen38/data"
SCRIPTS_DIR="$(pwd)/scripts"

# Set container environment variables
export SINGULARITYENV_HRRR_BASE_PATH="/srv"
export SINGULARITYENV_HRRR_DOWNLOAD_PATH="/srv/download"
export SINGULARITYENV_HRRR_OUTPUT_PATH="/srv/output"
export SINGULARITYENV_HRRR_ARCHIVE_PATH="/srv/archive"
export SINGULARITYENV_HRRR_LOG_PATH="/srv/logs"
export SINGULARITYENV_AWS_DEFAULT_REGION="us-east-1"

# Set date range for processing
# Default: Full range (Feb 19, 2015 - Mar 6, 2021)
START_DATE=${START_DATE:-"20150419"}
END_DATE=${END_DATE:-"20150519"}

echo "Processing date range: $START_DATE to $END_DATE"
echo "Data directory: $DATA_DIR"
echo "Scripts directory: $SCRIPTS_DIR"

# Create necessary directories
mkdir -p "$DATA_DIR"/{download,output,archive,logs,analysis}

# Run the extraction using Singularity
echo "Starting HRRR extraction..."
# singularity exec \
#     --bind /work/TANN/knguyen38/data:/srv \
#     --env HRRR_BASE_PATH="/srv" \
#     --env HRRR_DOWNLOAD_PATH="/srv/download" \
#     --env HRRR_OUTPUT_PATH="/srv/output" \
#     --env HRRR_ARCHIVE_PATH="/srv/archive" \
#     --env HRRR_LOG_PATH="/srv/logs" \
#     --env AWS_DEFAULT_REGION="us-east-1" \
#     $SINGULARITY_IMAGE \
#     scripts/aws-process-hrrr.sh "$START_DATE" "$END_DATE"
export HRRR_BASE_PATH="$DATA_DIR"
export HRRR_DOWNLOAD_PATH="$DATA_DIR/download"
export HRRR_OUTPUT_PATH="$DATA_DIR/output"
export HRRR_ARCHIVE_PATH="$DATA_DIR/archive"
export HRRR_LOG_PATH="$DATA_DIR/logs"
export AWS_DEFAULT_REGION="us-east-1"

srun bash scripts/aws-process-hrrr.sh "$START_DATE" "$END_DATE"

# Check exit status
if [ $? -eq 0 ]; then
    echo "HRRR extraction completed successfully!"
    
    # Count processed files
    PROCESSED_FILES=$(find "$DATA_DIR/archive" -name "*.zip" | wc -l)
    echo "Total files processed: $PROCESSED_FILES"
    
    # Calculate total data size
    TOTAL_SIZE=$(du -sh "$DATA_DIR/archive" | cut -f1)
    echo "Total extracted data size: $TOTAL_SIZE"
    
else
    echo "HRRR extraction failed with exit code: $?"
    exit 1
fi

echo "Job completed at: $(date)"
echo "Job ID: $SLURM_JOB_ID"
