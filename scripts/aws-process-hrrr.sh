#!/bin/bash

shopt -s extglob    # Extended globbing (pattern matching) support

# HRRR data extraction for Oso Creek / Corpus Christi basin
# Extracts multiple meteorological variables from HRRR deterministic runs
# Time Range: February 19, 2015 through March 6, 2021
# Forecast leads: 1-15 hours
# Cycles: All cycles (00-23Z)
# Variables: PRATE, TMP, DPT, PWAT, VUCSH, VVCSH, CAPE at specified levels
# Location: Oso Creek / Corpus Christi basin (lat/lon box)
# Output: Pivoted CSV with columns: start_time,long,lat,valid_time,variable+level

# Configuration
ENABLE_CHECKPOINT=${ENABLE_CHECKPOINT:-true}  # Set to 'false' to disable checkpoint feature

# Checkpoint file to track processing progress
CHECKPOINT_FILE="$HRRR_OUTPUT_PATH/processing_checkpoint.txt"

# Function to save checkpoint
save_checkpoint() {
    if [[ "$ENABLE_CHECKPOINT" == "true" ]]; then
        local year=$1
        local doy=$2
        local hour=$3
        echo "CHECKPOINT: Saving $year,$doy,$hour to $CHECKPOINT_FILE"
        echo "$year,$doy,$hour" > "$CHECKPOINT_FILE"
        echo "CHECKPOINT: Saved checkpoint file"
    fi
}

# Function to load checkpoint
load_checkpoint() {
    if [[ "$ENABLE_CHECKPOINT" == "true" && -f "$CHECKPOINT_FILE" ]]; then
        local checkpoint=$(cat "$CHECKPOINT_FILE" | tr -d '\r')
        echo "$checkpoint"
        return 0
    else
        echo ""
        return 1
    fi
}

# Oso Creek / Corpus Christi basin coordinates
# Lat/Lon bounds: (27.588733, 27.837343, -97.729247, -97.251896)
LAT_MIN=27.588733
LAT_MAX=27.837343
LON_MIN=-97.729247
LON_MAX=-97.251896

# Convert longitude to 0-360 format for HRRR data using bash arithmetic
# Since we're dealing with known values, we can precompute them
LON_MIN_360="262.270753"  # -97.729247 + 360
LON_MAX_360="262.748104"  # -97.251896 + 360

echo "Processing Oso Creek / Corpus Christi basin:"
echo "  Latitude range: $LAT_MIN to $LAT_MAX"
echo "  Longitude range: $LON_MIN to $LON_MAX (-180 to 180)"
echo "  Longitude range: $LON_MIN_360 to $LON_MAX_360 (0 to 360)"

# Download HRRR archive files for specific date and forecast leads 1-15
download_date_prediction_leads() {
    local date=$1
    local prediction_hour=`printf "%02d" $2`
    local dl_path=$3

    # S3 path for HRRR data
    local s3_path="s3://noaa-hrrr-bdp-pds/hrrr.${date}/conus/"
    
    # Download forecast leads 01-15 (f01 through f15)
    local dl_start=`date '+%s'`
    echo " • Checking/downloading forecast leads 01-15 from $s3_path for hour $prediction_hour"
    
    local downloaded_count=0
    local skipped_count=0
    
    # Download each forecast lead individually, but check if already exists
    for lead in {01..15}; do
        local s3_obj_name="hrrr.t${prediction_hour}z.wrfsfcf${lead}.grib2"
        local local_file_path="$dl_path/$s3_obj_name"
        
        if [[ -f "$local_file_path" ]]; then
            echo "   - Skipping $s3_obj_name (already downloaded)"
            skipped_count=$((skipped_count + 1))
        else
            echo "   - Downloading $s3_obj_name"
            aws s3 cp --no-progress "${s3_path}${s3_obj_name}" "$dl_path/" --no-sign-request
            downloaded_count=$((downloaded_count + 1))
        fi
    done
    
    local dl_end=`date '+%s'`
    local dl_delta=$((dl_end - dl_start))

    # Keep track of download size and stats
    local size_mb=`du -sm "$dl_path" | cut -f1`
    echo "# Download summary: $downloaded_count new, $skipped_count existing files"
    echo "# $size_mb MB total in download path, completed in $dl_delta seconds"
    return
}

# Extract multiple meteorological variables for the Oso Creek basin lat/lon box
extract_hrrr_basin_data() {
    local path2gribs=$1
    local output_file=$2

    # Define variables and their levels
    declare -A variables_levels=(
        ["PRATE"]="surface"
        ["TMP"]="2 m above ground"
        ["DPT"]="2 m above ground" 
        ["PWAT"]="entire atmosphere (considered as a single layer)"
        ["VUCSH"]="0-6000 m above ground"
        ["VVCSH"]="0-6000 m above ground"
        ["CAPE"]="90-0 mb above ground"
    )

    # Create header with variable+level columns
    local header="start_time,long,lat,valid_time"
    for variable in PRATE TMP DPT PWAT VUCSH VVCSH CAPE; do
        local level="${variables_levels[$variable]}"
        header="${header},${variable}_${level}"
    done
    echo "$header" > "$output_file"

    # Use associative arrays to store data by location+time
    declare -A data_matrix
    declare -A locations_times

    for grib_file in $path2gribs/*.grib2; do
        # In case of no files
        [[ ! -e "$grib_file" ]] && continue
        
        local filename=$(basename "$grib_file")
        echo " • Processing $filename" 1>&2
        
        # Extract each variable at its specified level
        for variable in "${!variables_levels[@]}"; do
            local level="${variables_levels[$variable]}"
            echo "   - Extracting $variable at $level" 1>&2
            
            # Escape parentheses in level string for regex matching
            local escaped_level="${level//\(/\\(}"
            escaped_level="${escaped_level//\)/\\)}"
            
            # Use wgrib2 to extract variable at specific level within the bounding box
            wgrib2 "$grib_file" -match ":$variable:$escaped_level:" -small_grib ${LON_MIN_360}:${LON_MAX_360} ${LAT_MIN}:${LAT_MAX} /tmp/subset_${variable}.grib2 >/dev/null 2>&1
            
            if [[ -f /tmp/subset_${variable}.grib2 ]]; then
                # Extract data in CSV format
                wgrib2 /tmp/subset_${variable}.grib2 -csv /tmp/${variable}_data.csv >/dev/null 2>&1
                
                if [[ -f /tmp/${variable}_data.csv ]]; then
                    # Read the CSV data and store in matrix
                    while IFS=',' read -r start_time valid_time var_name level_name longitude latitude value; do
                        # Skip header line if present
                        [[ "$start_time" == "start_time" ]] && continue
                        
                        # Create unique key for this location and time
                        local key="${start_time}_${valid_time}_${longitude}_${latitude}"
                        locations_times["$key"]="$start_time,$longitude,$latitude,$valid_time"
                        
                        # Store the value for this variable at this location/time
                        data_matrix["${key}_${variable}"]="$value"
                    done < /tmp/${variable}_data.csv
                    
                    rm -f /tmp/${variable}_data.csv
                fi
                
                rm -f /tmp/subset_${variable}.grib2
            fi
        done
        
        PROCESS_COUNT=$((PROCESS_COUNT + 1))
    done
    
    # Write out the pivoted data
    for key in "${!locations_times[@]}"; do
        local location_time="${locations_times[$key]}"
        local row="$location_time"
        
        # Add each variable value in the specified order
        for variable in PRATE TMP DPT PWAT VUCSH VVCSH CAPE; do
            local value="${data_matrix[${key}_${variable}]}"
            # Use empty string if value not found
            [[ -z "$value" ]] && value=""
            row="${row},${value}"
        done
        
        echo "$row" >> "$output_file"
    done
}

# Process HRRR grib files for specific date and prediction hour
process_hrrr_prate() {
    local pred_date=$1
    local prediction_hour=`printf "%02d" $2`

    local now=`date -u '+%Y-%m-%dT%H:%M:%SZ'`
    echo "# Starting HRRR prate processing (date $pred_date, prediction hour $prediction_hour) at $now" >>$LOG_FILE

    # Create date-specific download directory
    local date_download_path="$HRRR_DOWNLOAD_PATH/hrrr.$pred_date"
    mkdir -p "$date_download_path"

    # Create date-specific output directory
    local date_output_dir="$HRRR_OUTPUT_PATH/$pred_date"
    mkdir -p "$date_output_dir"

    download_date_prediction_leads $pred_date $prediction_hour "$date_download_path" >>$LOG_FILE 2>&1
    
    local output_file="$prediction_hour-hrrr-raw.csv"
    extract_hrrr_basin_data "$date_download_path" "$date_output_dir/$output_file" 2>>$LOG_FILE
    
    echo " • Removing downloaded grib2 files" >>$LOG_FILE
    rm -rf "$date_download_path" >>$LOG_FILE 2>&1

    local now=`date -u '+%Y-%m-%dT%H:%M:%SZ'`
    echo "# Finished processing ($pred_date, prediction hour $prediction_hour) at $now" >>$LOG_FILE
}

# Archive results locally (no S3 upload)
archive_results() {
    local output_path=$1

    # Move completed daily directories to archive
    for day_dir in $output_path/*/; do
        [[ ! -d "$day_dir" ]] && continue
        local day_name=$(basename "$day_dir")
        echo " • Archiving daily directory $day_name"
        mv "$day_dir" "$HRRR_ARCHIVE_PATH/" \
            && echo "   ... Successfully archived $day_name to $HRRR_ARCHIVE_PATH"
    done
}

# Convert from julian/ordinal day to YYYYMMDD
jul2ymd() {
    date -d "$1-01-01 +$2 days -1 day" "+%Y%m%d"
}

# Print usage and die
usage() {
    local zero=`basename $0`
    cat <<EndOfUsage 1>&2
Usage:  $zero [start_date] [end_date]

Extract HRRR meteorological data for Oso Creek / Corpus Christi basin
Time Range: February 19, 2015 through March 6, 2021 (default)
Forecast leads: 1-15 hours
Cycles: All cycles (00-23Z)
Variables: PRATE (surface), TMP (2m), DPT (2m), PWAT (entire_atmosphere), 
          VUCSH (0-6000m), VVCSH (0-6000m), CAPE (90-0 mb)

<start_date> and <end_date> must be in the format YYYYMMDD
If no dates provided, will process the full default range

Examples:
---------
Process full default range (Feb 19, 2015 - Mar 6, 2021):
    $zero

Process specific date range:
    $zero 20150219 20150228

Process single day:
    $zero 20150219 20150219

EndOfUsage
    exit 1
}

# Parse command line arguments
START_DATE=${1:-"20150219"}  # Default: February 19, 2015
END_DATE=${2:-"20210306"}    # Default: March 6, 2021

# Validate date format
if [[ ! "$START_DATE" =~ ^[0-9]{8}$ ]] || [[ ! "$END_DATE" =~ ^[0-9]{8}$ ]]; then
    echo "Error: Dates must be in YYYYMMDD format" 1>&2
    usage
fi

echo "Processing HRRR meteorological data for Oso Creek / Corpus Christi basin"
echo "Date range: $START_DATE to $END_DATE"
echo "Forecast leads: 1-15 hours"
echo "Cycles: All cycles (00-23Z)"
echo "Variables: PRATE, TMP, DPT, PWAT, VUCSH, VVCSH, CAPE"

# Ensure directory infrastructure exists
mkdir -p $HRRR_DOWNLOAD_PATH $HRRR_OUTPUT_PATH $HRRR_ARCHIVE_PATH $HRRR_LOG_PATH

# Log file
TODAY=`date -u '+%Y%m%d'`
LOG_FILE="$HRRR_LOG_PATH/hrrr-multi-vars-oso-creek-$TODAY.log"

# Put machine-specific metadata at start of logfile
if [[ ! -e "$LOG_FILE" ]]; then
    cat > "$LOG_FILE" << EOF
# HRRR Multi-Variable Extraction for Oso Creek / Corpus Christi Basin
# Hostname: $(hostname)
# $(uname -ar)
# wgrib2 version: $(wgrib2 -version 2>/dev/null || echo "wgrib2 not found")
# Processing range: $START_DATE to $END_DATE
# Basin coordinates: Lat($LAT_MIN, $LAT_MAX), Lon($LON_MIN, $LON_MAX)
# Forecast leads: 1-15 hours
# Cycles: All cycles (00-23Z)
# Variables: PRATE (surface), TMP (2m), DPT (2m), PWAT (entire_atmosphere),
#           VUCSH (0-6000m), VVCSH (0-6000m), CAPE (90-0 mb)
# Units: Raw values (no conversion)
EOF
fi

# Check for required tools
for tool in wgrib2 aws; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: Required tool '$tool' not found" 1>&2
        echo "Please ensure wgrib2 and aws-cli are installed" 1>&2
        exit 1
    fi
done

# Number of total grib2 files processed
PROCESS_COUNT=0

# Start timer
START_TIME=`date '+%s'`
echo "" >>$LOG_FILE

# Convert dates to julian format for iteration
read year1 doy1 <<< $(date -d "$START_DATE" "+%Y %j")
read year2 doy2 <<< $(date -d "$END_DATE" "+%Y %j")

# Force decimal context
doy1=$((10#$doy1))
doy2=$((10#$doy2))

echo "Processing HRRR prate data from $START_DATE [$year1 $doy1] to $END_DATE [$year2 $doy2]" >>$LOG_FILE

day_count=0
y=$year1
d=$doy1
start_hour=0

# Check for existing checkpoint to resume processing
echo "Checkpoint feature: $([[ "$ENABLE_CHECKPOINT" == "true" ]] && echo "ENABLED" || echo "DISABLED")"
checkpoint=$(load_checkpoint)
if [[ -n "$checkpoint" ]]; then
    IFS=',' read -r checkpoint_year checkpoint_doy checkpoint_hour <<< "$checkpoint"
    echo "Found checkpoint: Year $checkpoint_year, Day $checkpoint_doy, Hour $checkpoint_hour"
    echo "Resuming from checkpoint..." >>$LOG_FILE
    
    # Resume from checkpoint if it's within our processing range
    if (( checkpoint_year >= year1 && checkpoint_year <= year2 )); then
        if (( checkpoint_year < year2 )) || (( checkpoint_year == year2 && checkpoint_doy <= doy2 )); then
            y=$checkpoint_year
            d=$checkpoint_doy
            start_hour=$((10#$checkpoint_hour))
            echo "Resuming processing from $y/$d hour $start_hour"
        else
            echo "Checkpoint is beyond processing range, starting from beginning"
        fi
    else
        echo "Checkpoint is outside processing range, starting from beginning"
    fi
else
    if [[ "$ENABLE_CHECKPOINT" == "true" ]]; then
        echo "No checkpoint found, starting from beginning"
    else
        echo "Checkpoint disabled, starting from beginning"
    fi
fi

# Main processing loop
while (( y < year2 )) || (( y == year2 && d <= doy2 )); do
    when=`jul2ymd "$y" "$d"`
    
    # Skip invalid dates (e.g., Feb 29 in non-leap years)
    if [[ ${when:0:4} -eq "$y" ]]; then
        echo "Processing date: $when"
        
        # Process all prediction hours (start_hour-23) for each day
        for ph in $(seq -f "%02g" $start_hour 23); do
            echo "  Processing prediction hour: $ph"
            process_hrrr_prate $when $ph
            
            # Calculate next position to save in checkpoint
            next_hour=$((10#$ph + 1))
            if (( next_hour <= 23 )); then
                # Save next hour of same day
                save_checkpoint $y $d $(printf "%02d" $next_hour)
            else
                # Save first hour of next day
                next_d=$((d + 1))
                next_y=$y
                
                # Handle year rollover for day 366 (or 365 in non-leap years)
                if (( (next_y % 4 == 0 && (next_y % 100 != 0 || next_y % 400 == 0)) && next_d > 366 )) || 
                   (( (next_y % 4 != 0 || (next_y % 100 == 0 && next_y % 400 != 0)) && next_d > 365 )); then
                    next_d=1
                    next_y=$((next_y + 1))
                fi
                save_checkpoint $next_y $next_d "00"
            fi
        done
        
        # Reset start_hour for next day
        start_hour=0
        
        # Archive results for this day (no S3 upload)
        archive_results "$HRRR_OUTPUT_PATH" >>$LOG_FILE 2>&1
    fi

    d=$((d + 1))
    day_count=$((day_count + 1))

    # Handle day overflow (366 for leap years)
    if (( d > 366 )); then
        d=1
        y=$((y + 1))
    fi

    # Progress reporting
    END_TIME=`date '+%s'`
    DELTA=$((END_TIME - START_TIME))
    echo "# [Day $day_count] Processed $PROCESS_COUNT HRRR grib2 files in $DELTA seconds" >>$LOG_FILE
    echo "Progress: Day $day_count completed ($when)"
done

# Final statistics
END_TIME=`date '+%s'`
DELTA=$((END_TIME - START_TIME))
echo "# [Final] Processed $PROCESS_COUNT HRRR grib2 files in $DELTA seconds" >>$LOG_FILE
echo "Processing complete. Total time: $DELTA seconds, Files processed: $PROCESS_COUNT"

# Remove checkpoint file on successful completion
if [[ -f "$CHECKPOINT_FILE" ]]; then
    rm -f "$CHECKPOINT_FILE"
    echo "Checkpoint file removed - processing completed successfully"
fi

# Estimate total runs processed
total_days=$day_count
total_prediction_hours=$((total_days * 24))
total_forecast_leads=$((total_prediction_hours * 15))
echo "# Statistics: $total_days days, $total_prediction_hours prediction hours, $total_forecast_leads forecast leads" >>$LOG_FILE
echo "Estimated total forecast files processed: $total_forecast_leads"
