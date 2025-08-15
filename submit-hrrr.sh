#!/bin/bash

# HRRR Extraction Job Submission Script for HPC
# This script helps submit and monitor HRRR extraction jobs on SLURM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
  test                    Submit test job (single day)
  single                  Submit single job (full dataset)
  array                   Submit array job (parallel processing)
  status                  Check job status
  resume                  Show resume status (existing files)
  cancel [JOB_ID]         Cancel job(s)
  logs [JOB_ID]           Show job logs
  clean                   Clean up old log files
  setup                   Initial setup and validation

Options for test:
  --date YYYYMMDD         Test date (default: 20200101)

Options for single:
  --start YYYYMMDD        Start date (default: 20150219)
  --end YYYYMMDD          End date (default: 20210306)

Options for array:
  --tasks N               Number of parallel tasks (default: 12)

Examples:
  $0 setup                           # Initial setup
  $0 test --date 20200101           # Test with specific date
  $0 single --start 20200101 --end 20200131  # Single job for January 2020
  $0 array --tasks 6                # Array job with 6 parallel tasks
  $0 status                         # Check all HRRR job status
  $0 logs 12345                     # Show logs for job 12345

EOF
}

setup_environment() {
    echo "Setting up HRRR extraction environment..."
    
    # Create necessary directories
    mkdir -p logs data/{download,output,archive,logs,analysis}
    
    # Make scripts executable
    chmod +x scripts/*.sh
    chmod +x *.slurm
    
    echo "Setup complete!"
    echo "Directory structure:"
    tree -L 2 data/ || ls -la data/
}

submit_test() {
    local test_date="20200101"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --date)
                test_date="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    echo "Submitting test job for date: $test_date"
    
    # Submit job with environment variable
    JOB_ID=$(sbatch --export=TEST_DATE="$test_date" hrrr-test.slurm | awk '{print $NF}')
    
    if [ $? -eq 0 ]; then
        echo "Test job submitted with ID: $JOB_ID"
        echo "Monitor with: $0 logs $JOB_ID"
    else
        echo "Failed to submit test job"
        exit 1
    fi
}

submit_single() {
    local start_date="20150219"
    local end_date="20210306"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --start)
                start_date="$2"
                shift 2
                ;;
            --end)
                end_date="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    echo "Submitting single job for date range: $start_date to $end_date"
    
    # Submit job with environment variables
    JOB_ID=$(sbatch --export=START_DATE="$start_date",END_DATE="$end_date" hrrr-extract.slurm | awk '{print $NF}')
    
    if [ $? -eq 0 ]; then
        echo "Single job submitted with ID: $JOB_ID"
        echo "Estimated completion time: ~2-4 weeks"
        echo "Monitor with: $0 logs $JOB_ID"
    else
        echo "Failed to submit single job"
        exit 1
    fi
}

submit_array() {
    local max_tasks="12"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --tasks)
                max_tasks="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    echo "Submitting array job with up to $max_tasks parallel tasks"
    
    # Modify the array job script to use the specified max tasks
    sed -i "s/#SBATCH --array=1-72%[0-9]*/#SBATCH --array=1-72%${max_tasks}/" hrrr-extract-array.slurm
    
    # Submit array job
    JOB_ID=$(sbatch hrrr-extract-array.slurm | awk '{print $NF}')
    
    if [ $? -eq 0 ]; then
        echo "Array job submitted with ID: $JOB_ID"
        echo "Processing 72 monthly chunks with up to $max_tasks parallel tasks"
        echo "Estimated completion time: ~1-2 weeks"
        echo "Monitor with: $0 status"
    else
        echo "Failed to submit array job"
        exit 1
    fi
}

show_status() {
    echo "HRRR Job Status:"
    echo "================"
    
    # Show jobs for current user with HRRR in the name
    squeue -u $USER --name=hrrr* --format="%.10i %.15j %.8u %.8T %.10M %.6D %R" || \
    squeue -u $USER | grep -E "(hrrr|HRRR)"
    
    echo ""
    echo "Recent completed jobs:"
    sacct -u $USER --name=hrrr* --starttime=$(date -d '7 days ago' +%Y-%m-%d) \
          --format="JobID,JobName,State,ExitCode,Start,End" 2>/dev/null || \
    echo "Use 'sacct' command to check completed jobs"
}

cancel_jobs() {
    if [ -z "$1" ]; then
        echo "Cancelling all HRRR jobs for user $USER..."
        scancel -u $USER --name=hrrr*
    else
        echo "Cancelling job $1..."
        scancel "$1"
    fi
}

show_logs() {
    local job_id="$1"
    
    if [ -z "$job_id" ]; then
        echo "Recent log files:"
        ls -lt logs/hrrr-* | head -10
        return
    fi
    
    echo "Showing logs for job $job_id:"
    echo "============================="
    
    # Show SLURM output
    if [ -f "logs/hrrr-extract-${job_id}.out" ]; then
        echo "=== SLURM Output ==="
        tail -50 "logs/hrrr-extract-${job_id}.out"
    elif [ -f "logs/hrrr-test-${job_id}.out" ]; then
        echo "=== SLURM Output ==="
        tail -50 "logs/hrrr-test-${job_id}.out"
    elif [ -f "logs/hrrr-array-${job_id}_"*.out ]; then
        echo "=== Array Job Output (showing first task) ==="
        tail -50 logs/hrrr-array-${job_id}_*.out | head -50
    fi
    
    # Show application log
    echo ""
    echo "=== Application Logs ==="
    if [ -f "data/logs/hrrr-prate-oso-creek-$(date +%Y%m%d).log" ]; then
        tail -30 "data/logs/hrrr-prate-oso-creek-$(date +%Y%m%d).log"
    else
        echo "No application logs found for today"
        ls -t data/logs/*.log | head -3 | xargs tail -10
    fi
}

clean_logs() {
    echo "Cleaning old log files..."
    
    # Remove logs older than 30 days
    find logs/ -name "*.out" -o -name "*.err" -mtime +30 -delete
    find data/logs/ -name "*.log" -mtime +30 -delete
    
    echo "Old log files cleaned"
}

show_resume_status() {
    echo "=== HRRR Extraction Resume Status ==="
    echo
    
    # Check data directories
    if [ ! -d "data" ]; then
        echo "No data directory found. Run '$0 setup' first."
        return 1
    fi
    
    # Count existing files
    archived_count=$(find data/archive -name "*-prate-raw.zip" 2>/dev/null | wc -l)
    output_count=$(find data/output -name "*-prate-raw.zip" 2>/dev/null | wc -l)
    total_existing=$((archived_count + output_count))
    
    echo "Existing files:"
    echo "  Archived: $archived_count files"
    echo "  In output: $output_count files"
    echo "  Total: $total_existing files"
    
    if [ $total_existing -eq 0 ]; then
        echo "  Status: Fresh start - no existing files"
        echo "  Resume: Not applicable"
        return 0
    fi
    
    # Calculate total expected files for full dataset (Feb 19, 2015 - Mar 6, 2021)
    # This is approximately 6 years * 365 days * 24 hours = ~53,000 files
    start_date="20150219"
    end_date="20210306"
    
    # Simple calculation: days between dates * 24 hours
    start_epoch=$(date -d "$start_date" +%s)
    end_epoch=$(date -d "$end_date" +%s)
    total_days=$(( (end_epoch - start_epoch) / 86400 + 1 ))
    total_expected=$((total_days * 24))
    
    echo "  Expected total: $total_expected files"
    
    if [ $total_expected -gt 0 ]; then
        completion_percent=$((total_existing * 100 / total_expected))
        echo "  Progress: $completion_percent% complete"
        remaining=$((total_expected - total_existing))
        echo "  Remaining: $remaining files to process"
    fi
    
    # Show date range of existing files
    if [ $total_existing -gt 0 ]; then
        echo
        echo "Date range analysis:"
        
        # Find earliest and latest dates
        earliest_file=$(find data/archive data/output -name "*-prate-raw.zip" 2>/dev/null | sort | head -1)
        latest_file=$(find data/archive data/output -name "*-prate-raw.zip" 2>/dev/null | sort | tail -1)
        
        if [ -n "$earliest_file" ]; then
            earliest_date=$(basename "$earliest_file" | cut -d'-' -f1)
            latest_date=$(basename "$latest_file" | cut -d'-' -f1)
            echo "  Earliest: $earliest_date"
            echo "  Latest: $latest_date"
        fi
        
        # Show files by month to identify gaps
        echo
        echo "Files by month (recent):"
        find data/archive data/output -name "*-prate-raw.zip" 2>/dev/null | \
            xargs basename -a 2>/dev/null | \
            cut -c1-6 | sort | uniq -c | tail -10 | \
            while read count month; do
                echo "  $month: $count files"
            done
    fi
    
    echo
    echo "Resume capability: Enabled"
    echo "When you restart processing, existing files will be automatically skipped."
}

# Main script logic
case "$1" in
    setup)
        setup_environment
        ;;
    test)
        shift
        submit_test "$@"
        ;;
    single)
        shift
        submit_single "$@"
        ;;
    array)
        shift
        submit_array "$@"
        ;;
    status)
        show_status
        ;;
    resume)
        show_resume_status
        ;;
    cancel)
        cancel_jobs "$2"
        ;;
    logs)
        show_logs "$2"
        ;;
    clean)
        clean_logs
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
