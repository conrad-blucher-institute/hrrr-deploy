#!/bin/bash

# Missing Data Report Generator for HRRR Extraction
# Checks for missing hour files across specified date range
# Generates CSV report in data/report/ directory
# Usage: ./check-missing-data.sh [start_date] [end_date]
#        Dates in YYYYMMDD format (e.g., 20200101 20201231)

# Function to show usage
show_usage() {
    echo "Usage: $0 [start_date] [end_date]"
    echo "  start_date: Start date in YYYYMMDD format (e.g., 20200101)"
    echo "  end_date:   End date in YYYYMMDD format (e.g., 20201231)"
    echo "  If no dates provided, checks all available dates"
    echo ""
    echo "Examples:"
    echo "  $0                      # Check all dates"
    echo "  $0 20200101 20200131    # Check January 2020"
    echo "  $0 20191201 20200229    # Check Dec 2019 to Feb 2020"
}

# Function to validate YYYYMMDD format
validate_date_format() {
    local input_date=$1
    if [[ ${#input_date} -ne 8 ]] || [[ ! "$input_date" =~ ^[0-9]{8}$ ]]; then
        echo "Error: Date must be 8 digits in YYYYMMDD format" >&2
        return 1
    fi
    
    local yyyy=${input_date:0:4}
    local mm=${input_date:4:2}
    local dd=${input_date:6:2}
    
    # Validate year (reasonable range)
    if (( yyyy < 1900 || yyyy > 2100 )); then
        echo "Error: Invalid year: $yyyy" >&2
        return 1
    fi
    
    # Validate month
    if (( mm < 1 || mm > 12 )); then
        echo "Error: Invalid month: $mm" >&2
        return 1
    fi
    
    # Validate day (basic check)
    if (( dd < 1 || dd > 31 )); then
        echo "Error: Invalid day: $dd" >&2
        return 1
    fi
    
    return 0
}

# Function to check if date is in range
is_date_in_range() {
    local check_date=$1
    local start_date=$2
    local end_date=$3
    
    # If no range specified, include all dates
    if [[ -z "$start_date" || -z "$end_date" ]]; then
        return 0
    fi
    
    # Compare dates as integers
    if (( check_date >= start_date && check_date <= end_date )); then
        return 0
    else
        return 1
    fi
}

# Parse command line arguments
START_DATE=""
END_DATE=""

if [[ $# -eq 0 ]]; then
    echo "No date range specified - checking all available dates"
elif [[ $# -eq 2 ]]; then
    START_DATE=$1
    END_DATE=$2
    
    # Validate dates
    if ! validate_date_format "$START_DATE"; then
        echo "Error: Invalid start date format: $START_DATE"
        show_usage
        exit 1
    fi
    
    if ! validate_date_format "$END_DATE"; then
        echo "Error: Invalid end date format: $END_DATE"
        show_usage
        exit 1
    fi
    
    # Validate date range
    if (( START_DATE > END_DATE )); then
        echo "Error: Start date ($START_DATE) is after end date ($END_DATE)"
        exit 1
    fi
    
    echo "Checking date range: $START_DATE to $END_DATE"
else
    echo "Error: Invalid number of arguments"
    show_usage
    exit 1
fi

# Configuration
ARCHIVE_DIR="data/archive"
REPORT_DIR="data/report"

# Generate report filename based on date range
if [[ -n "$START_DATE" && -n "$END_DATE" ]]; then
    REPORT_FILE="$REPORT_DIR/missing_data_report_${START_DATE}_to_${END_DATE}_$(date +%Y%m%d_%H%M%S).csv"
else
    REPORT_FILE="$REPORT_DIR/missing_data_report_all_dates_$(date +%Y%m%d_%H%M%S).csv"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "HRRR Missing Data Report Generator"
echo "=================================="

if [[ -n "$START_DATE" && -n "$END_DATE" ]]; then
    echo "Date range: $START_DATE to $END_DATE (YYYYMMDD format)"
else
    echo "Checking all available dates"
fi

# Create report directory if it doesn't exist
mkdir -p "$REPORT_DIR"

# Check if archive directory exists
if [[ ! -d "$ARCHIVE_DIR" ]]; then
    echo -e "${RED}Error: Archive directory '$ARCHIVE_DIR' not found${NC}"
    exit 1
fi

# Initialize report file with header
echo "date,missing_hours,missing_hour_list" > "$REPORT_FILE"

# Initialize counters
total_dates=0
dates_with_missing=0
total_missing_hours=0

echo "Scanning archive directory: $ARCHIVE_DIR"
echo ""

# Process each date directory
for date_dir in "$ARCHIVE_DIR"/*/; do
    if [[ -d "$date_dir" ]]; then
        date_name=$(basename "$date_dir")
        
        # Skip if not a date format (YYYYMMDD)
        if [[ ! "$date_name" =~ ^[0-9]{8}$ ]]; then
            continue
        fi
        
        # Check if date is in specified range
        if ! is_date_in_range "$date_name" "$START_DATE" "$END_DATE"; then
            continue
        fi
        
        total_dates=$((total_dates + 1))
        
        # Expected hours: 00 through 23 (24 total)
        expected_hours=($(seq -f "%02g" 0 23))
        missing_hours=()
        found_hours=0
        
        # Check for each expected hour file
        for hour in "${expected_hours[@]}"; do
            hour_file="$date_dir/${hour}-hrrr-raw.csv"
            if [[ -f "$hour_file" ]]; then
                found_hours=$((found_hours + 1))
            else
                missing_hours+=("$hour")
            fi
        done
        
        # Calculate missing count
        missing_count=${#missing_hours[@]}
        total_missing_hours=$((total_missing_hours + missing_count))
        
        # Create comma-separated list of missing hours
        missing_list=""
        if [[ $missing_count -gt 0 ]]; then
            dates_with_missing=$((dates_with_missing + 1))
            missing_list=$(IFS=';'; echo "${missing_hours[*]}")
            
            # Color output for missing data
            echo -e "${RED}$date_name: Missing $missing_count hours [$missing_list]${NC}"
        else
            echo -e "${GREEN}$date_name: Complete (24/24 hours)${NC}"
        fi
        
        # Write to CSV report
        echo "$date_name,$missing_count,\"$missing_list\"" >> "$REPORT_FILE"
    fi
done

echo ""
echo "Report Summary:"
echo "==============="
echo "Total dates processed: $total_dates"
echo "Dates with missing data: $dates_with_missing"
echo "Total missing hours: $total_missing_hours"

if [[ $dates_with_missing -gt 0 ]]; then
    echo -e "${YELLOW}Warning: $dates_with_missing dates have missing hour files${NC}"
    completion_rate=$(( (total_dates * 24 - total_missing_hours) * 100 / (total_dates * 24) ))
    echo "Data completion rate: ${completion_rate}%"
else
    echo -e "${GREEN}All dates are complete!${NC}"
fi

echo ""
echo "Detailed report saved to: $REPORT_FILE"

# Return appropriate exit code
if [[ $dates_with_missing -gt 0 ]]; then
    exit 1  # Missing data found
else
    exit 0  # All data complete
fi
