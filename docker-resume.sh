#!/bin/bash

# HRRR Docker Resume Helper Script
# Shows resume status and helps restart Docker processing

echo "=== HRRR Docker Resume Status ==="
echo

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo "Error: Run this script from the hrrr-deploy project root directory"
    exit 1
fi

# Check data directory
if [ ! -d "data" ]; then
    echo "No data directory found. Run 'docker compose up' to create it."
    exit 1
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
    echo
    echo "Status: Fresh start - no existing files found"
    echo "Resume: Not applicable"
    echo
    echo "To start processing:"
    echo "  docker compose up"
else
    # Calculate progress
    start_date="20150219"
    end_date="20210306"
    start_epoch=$(date -d "$start_date" +%s)
    end_epoch=$(date -d "$end_date" +%s)
    total_days=$(( (end_epoch - start_epoch) / 86400 + 1 ))
    total_expected=$((total_days * 24))
    
    completion_percent=$((total_existing * 100 / total_expected))
    remaining=$((total_expected - total_existing))
    
    echo "  Expected total: $total_expected files"
    echo "  Progress: $completion_percent% complete"
    echo "  Remaining: $remaining files"
    
    # Find date range
    if [ $total_existing -gt 0 ]; then
        echo
        echo "Date range of existing files:"
        earliest_file=$(find data/archive data/output -name "*-prate-raw.zip" 2>/dev/null | sort | head -1)
        latest_file=$(find data/archive data/output -name "*-prate-raw.zip" 2>/dev/null | sort | tail -1)
        
        if [ -n "$earliest_file" ]; then
            earliest_date=$(basename "$earliest_file" | cut -d'-' -f1)
            latest_date=$(basename "$latest_file" | cut -d'-' -f1)
            echo "  From: $earliest_date"
            echo "  To: $latest_date"
        fi
    fi
    
    echo
    echo "Resume capability: ✓ Enabled"
    echo "Existing files will be automatically skipped when you restart."
    echo
    echo "To resume processing:"
    echo "  docker compose up"
    echo
    echo "To run in background:"
    echo "  docker compose up -d"
    echo
    echo "To check logs:"
    echo "  docker compose logs -f"
fi

# Show recent activity from logs
if [ -d "data/logs" ]; then
    latest_log=$(find data/logs -name "*.log" -type f -exec ls -t {} + | head -1)
    if [ -n "$latest_log" ]; then
        echo
        echo "Recent activity (from $latest_log):"
        tail -5 "$latest_log" | grep -E "(Processing|Finished|Skipped)" | tail -3
    fi
fi

echo
echo "For detailed resume status:"
echo "  ./submit-hrrr.sh resume  (if using HPC)"
echo "  ./docker-resume.sh       (this script)"
