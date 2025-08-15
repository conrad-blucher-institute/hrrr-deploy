#!/bin/bash
#SBATCH --job-name=hrrr-array
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=24:00:00
#SBATCH --array=1-72%12
#SBATCH --output=logs/hrrr-array-%A_%a.out
#SBATCH --error=logs/hrrr-array-%A_%a.err
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=your.email@example.com

# HRRR Data Extraction Array Job for HPC using Singularity
# This script processes the date range in parallel chunks for faster processing
# Array indices 1-72 represent monthly chunks from Feb 2015 to Mar 2021

echo "Starting HRRR array job: $SLURM_JOB_ID, array task: $SLURM_ARRAY_TASK_ID"
echo "Node: $SLURM_NODELIST"
echo "Start time: $(date)"

# Load required modules
module load singularity

# Set working directory
cd $SLURM_SUBMIT_DIR

# Create logs directory
mkdir -p logs

# Define date ranges for each array task (monthly chunks)
# Calculate start and end dates based on array task ID
START_YEAR=2015
START_MONTH=2  # February 2015

# Calculate year and month for this task
MONTHS_FROM_START=$((SLURM_ARRAY_TASK_ID - 1))
YEAR=$((START_YEAR + (START_MONTH + MONTHS_FROM_START - 1) / 12))
MONTH=$(((START_MONTH + MONTHS_FROM_START - 1) % 12 + 1))

# Format month with leading zero
MONTH_STR=$(printf "%02d" $MONTH)

# Calculate start and end dates for this month
if [ $MONTH -eq 2 ] && [ $YEAR -eq 2015 ]; then
    # Special case for first month (starts on Feb 19)
    START_DATE="${YEAR}0219"
elif [ $MONTH -eq 3 ] && [ $YEAR -eq 2021 ]; then
    # Special case for last month (ends on Mar 6)
    END_DATE="20210306"
    START_DATE="${YEAR}${MONTH_STR}01"
else
    # Regular month processing
    START_DATE="${YEAR}${MONTH_STR}01"
    # Calculate last day of month
    if [ $MONTH -eq 12 ]; then
        NEXT_YEAR=$((YEAR + 1))
        NEXT_MONTH="01"
    else
        NEXT_YEAR=$YEAR
        NEXT_MONTH=$(printf "%02d" $((MONTH + 1)))
    fi
    # Get last day of current month
    LAST_DAY=$(date -d "${NEXT_YEAR}-${NEXT_MONTH}-01 -1 day" +%d)
    END_DATE="${YEAR}${MONTH_STR}${LAST_DAY}"
fi

# Handle special end date for March 2021
if [ $YEAR -eq 2021 ] && [ $MONTH -eq 3 ]; then
    END_DATE="20210306"
fi

echo "Processing array task $SLURM_ARRAY_TASK_ID: $START_DATE to $END_DATE"

# Singularity setup
SINGULARITY_IMAGE="docker://sondngyn/wgrib2:latest"
DATA_DIR="$(pwd)/data"
SCRIPTS_DIR="$(pwd)/scripts"

# Create task-specific subdirectories to avoid conflicts
TASK_DATA_DIR="$DATA_DIR/task_${SLURM_ARRAY_TASK_ID}"
mkdir -p "$TASK_DATA_DIR"/{download,output,archive,logs}

echo "Task data directory: $TASK_DATA_DIR"

# Run extraction for this date range
singularity exec \
    --bind "$SCRIPTS_DIR:/opt:ro" \
    --bind "$TASK_DATA_DIR:/srv" \
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
    echo "Array task $SLURM_ARRAY_TASK_ID completed successfully!"
    
    # Move results to main archive directory
    mkdir -p "$DATA_DIR/archive"
    if [ -d "$TASK_DATA_DIR/archive" ]; then
        mv "$TASK_DATA_DIR/archive"/* "$DATA_DIR/archive/" 2>/dev/null || true
    fi
    
    # Move logs to main logs directory
    mkdir -p "$DATA_DIR/logs"
    if [ -d "$TASK_DATA_DIR/logs" ]; then
        mv "$TASK_DATA_DIR/logs"/* "$DATA_DIR/logs/" 2>/dev/null || true
    fi
    
    # Clean up task directory
    rm -rf "$TASK_DATA_DIR"
    
    # Count files processed by this task
    PROCESSED_FILES=$(find "$DATA_DIR/archive" -name "*${START_DATE:0:6}*" -o -name "*${END_DATE:0:6}*" | wc -l)
    echo "Files processed by task $SLURM_ARRAY_TASK_ID: $PROCESSED_FILES"
    
else
    echo "Array task $SLURM_ARRAY_TASK_ID failed with exit code: $?"
    exit 1
fi

echo "Array task $SLURM_ARRAY_TASK_ID completed at: $(date)"
