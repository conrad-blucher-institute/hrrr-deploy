#!/bin/bash
#SBATCH --job-name=hrrr-extract
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=72:00:00
#SBATCH --output=logs/hrrr-extract-%j.out
#SBATCH --error=logs/hrrr-extract-%j.err
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=your.email@example.com

# HRRR Data Extraction Job for HPC using Singularity
# This script runs the HRRR precipitation data extraction for Oso Creek basin

echo "Starting HRRR extraction job: $SLURM_JOB_ID"
echo "Node: $SLURM_NODELIST"
echo "Start time: $(date)"

# Load required modules (adjust for your HPC system)
module load singularity

# Set working directory to job submission directory
cd $SLURM_SUBMIT_DIR

# Create logs directory if it doesn't exist
mkdir -p logs

# Define Singularity image and data paths
SINGULARITY_IMAGE="docker://sondngyn/wgrib2:latest"
DATA_DIR="$(pwd)/data"
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
START_DATE=${START_DATE:-"20150219"}
END_DATE=${END_DATE:-"20210306"}

echo "Processing date range: $START_DATE to $END_DATE"
echo "Data directory: $DATA_DIR"
echo "Scripts directory: $SCRIPTS_DIR"

# Create necessary directories
mkdir -p "$DATA_DIR"/{download,output,archive,logs,analysis}

# Run the extraction using Singularity
echo "Starting HRRR extraction..."
singularity exec \
    --bind "$SCRIPTS_DIR:/opt:ro" \
    --bind "$DATA_DIR:/srv" \
    --env HRRR_BASE_PATH="/srv" \
    --env HRRR_DOWNLOAD_PATH="/srv/download" \
    --env HRRR_OUTPUT_PATH="/srv/output" \
    --env HRRR_ARCHIVE_PATH="/srv/archive" \
    --env HRRR_LOG_PATH="/srv/logs" \
    --env AWS_DEFAULT_REGION="us-east-1" \
    "$SINGULARITY_IMAGE" \
    /opt/aws-process-hrrr.sh "$START_DATE" "$END_DATE"

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
