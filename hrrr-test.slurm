#!/bin/bash
#SBATCH --job-name=hrrr-test
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=02:00:00
#SBATCH --output=logs/hrrr-test-%j.out
#SBATCH --error=logs/hrrr-test-%j.err

# HRRR Single Day Test Job using Singularity
# This script tests the HRRR extraction setup with a single day

echo "Starting HRRR test job: $SLURM_JOB_ID"
echo "Node: $SLURM_NODELIST"
echo "Start time: $(date)"

# Load required modules
module load singularity

# Set working directory
cd $SLURM_SUBMIT_DIR

# Create logs directory
mkdir -p logs

# Test date (default: January 1, 2020)
TEST_DATE=${TEST_DATE:-"20200101"}

echo "Testing with date: $TEST_DATE"

# Singularity setup
SINGULARITY_IMAGE="docker://sondngyn/wgrib2:latest"
DATA_DIR="$(pwd)/data"
SCRIPTS_DIR="$(pwd)/scripts"

# Create test directories
mkdir -p "$DATA_DIR"/{download,output,archive,logs}


echo "Running single day extraction test..."

# Run single day test
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
    /opt/aws-process-hrrr.sh "$TEST_DATE" "$TEST_DATE"

# Check results
if [ $? -eq 0 ]; then
    echo "Test completed successfully!"
    
    # Show results
    echo "Files created:"
    find "$DATA_DIR" -name "*.zip" -o -name "*.csv" | head -10
    
    # Show first few lines of a CSV file if available
    CSV_FILE=$(find "$DATA_DIR" -name "*.csv" | head -1)
    if [ -n "$CSV_FILE" ]; then
        echo "Sample data from $CSV_FILE:"
        head -5 "$CSV_FILE"
    fi
    
else
    echo "Test failed with exit code: $?"
    exit 1
fi

echo "Test job completed at: $(date)"
